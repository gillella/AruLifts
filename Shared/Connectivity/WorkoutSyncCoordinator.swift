import Foundation

/// Persistence-first state machine for single-writer workout replication.
final class WorkoutSyncCoordinator {
    enum ReceiveResult: Equatable {
        case applied, duplicate, stale, ignored, invalid
    }

    private(set) var state: WorkoutRuntimeState
    let localDevice: WorkoutDevice
    /// Set when launch-time recovery discarded an abandoned active replica.
    /// The manager uses this to clear the matching sticky application context.
    private(set) var discardedStaleSessionID: UUID?
    var onStateChange: ((WorkoutRuntimeState) -> Void)?
    var transmit: ((WorkoutMessageEnvelope, WorkoutMessageTransport) -> Void)?

    private let repository: ActiveWorkoutRepository
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let processedIDLimit = 256
    /// Oldest workout a device with no local replica will adopt from an
    /// incoming checkpoint. No real gym session runs this long, so anything
    /// older is a stale snapshot retained in the sticky application context,
    /// never a live workout worth joining. Injectable so tests can exercise
    /// the boundary without waiting.
    private let maxAdoptableSessionAge: TimeInterval
    /// Clock seam for tests; production always reads the real clock.
    private let now: () -> Date

    init(
        localDevice: WorkoutDevice,
        repository: ActiveWorkoutRepository = ActiveWorkoutRepository(),
        maxAdoptableSessionAge: TimeInterval = 6 * 60 * 60,
        now: @escaping () -> Date = Date.init,
        transmit: ((WorkoutMessageEnvelope, WorkoutMessageTransport) -> Void)? = nil
    ) {
        self.localDevice = localDevice
        self.repository = repository
        self.maxAdoptableSessionAge = maxAdoptableSessionAge
        self.now = now
        self.transmit = transmit
        let restored = repository.load()
        if let replica = restored.activeReplica,
           now().timeIntervalSince(replica.session.startedAt) >
             maxAdoptableSessionAge {
            var recovered = restored
            let sessionID = replica.session.id
            recovered.activeReplica = nil
            recovered.authorityState = nil
            recovered.syncStatus = .localOnly
            recovered.terminalSessions[sessionID] = WorkoutTombstone(
                sessionID: sessionID,
                finalVersion: replica.version,
                finished: false,
                createdAt: now()
            )
            let decoder = JSONDecoder()
            recovered.outbox.removeAll { pending in
                guard let queued = try? decoder.decode(
                    WorkoutMessageEnvelope.self,
                    from: pending.payload
                ) else { return false }
                return queued.sessionID == sessionID
            }
            state = recovered
            discardedStaleSessionID = sessionID
            _ = repository.save(recovered)
        } else {
            state = restored
        }
    }

    var replica: WorkoutReplica? { state.activeReplica }
    var watchPlanCache: WatchPlanCache? { state.watchPlanCache }
    var owner: WorkoutDevice? { state.activeReplica?.owner }
    var canEdit: Bool {
        owner == localDevice &&
            (state.authorityState == .authoritative ||
             state.authorityState == .offeringTransfer)
    }

    @discardableResult
    func start(_ session: WorkoutSession, currentExerciseIndex: Int = 0) -> Bool {
        let replica = WorkoutReplica(
            session: session,
            owner: localDevice,
            currentExerciseIndex: currentExerciseIndex,
            healthRecorder: localDevice == .watch ? .watch : nil
        )
        var next = WorkoutRuntimeState(
            activeReplica: replica,
            authorityState: localDevice == .phone ? .offeringTransfer : .authoritative,
            syncStatus: localDevice == .phone ? .waitingForWatch : .waitingForPhone,
            outbox: state.outbox,
            processedMessageIDs: state.processedMessageIDs,
            terminalSessions: state.terminalSessions,
            watchPlanCache: state.watchPlanCache
        )
        do {
            let envelope: WorkoutMessageEnvelope
            if localDevice == .phone {
                envelope = try WorkoutMessageEnvelope(
                    kind: .ownershipOffer,
                    sender: localDevice,
                    sessionID: session.id,
                    payload: WorkoutOwnershipOffer(replica: replica)
                )
            } else {
                envelope = try WorkoutMessageEnvelope(
                    kind: .checkpoint,
                    sender: localDevice,
                    sessionID: session.id,
                    payload: WorkoutCheckpoint(replica: replica)
                )
            }
            append(envelope, to: &next)
            return commit(next, flush: true)
        } catch { return false }
    }

    @discardableResult
    func mutate(
        session: WorkoutSession,
        currentExerciseIndex: Int,
        restTimer: RestTimerSnapshot?,
        isWorkoutPaused: Bool,
        phaseTimer: PhaseTimerSnapshot? = nil,
        exerciseTimer: ExerciseTimerSnapshot? = nil
    ) -> Bool {
        guard var replica = state.activeReplica, canEdit,
              replica.session.id == session.id else { return false }
        replica.session = session
        replica.currentExerciseIndex = currentExerciseIndex
        replica.restTimer = restTimer
        replica.isWorkoutPaused = isWorkoutPaused
        replica.phaseTimer = phaseTimer
        replica.exerciseTimer = exerciseTimer
        replica.version = replica.version.advanced()
        do {
            let stillOffering = state.authorityState == .offeringTransfer
            let envelope = try WorkoutMessageEnvelope(
                kind: stillOffering ? .ownershipOffer : .checkpoint,
                sender: localDevice,
                sessionID: session.id,
                payload: stillOffering
                    ? WorkoutWirePayload.offer(replica)
                    : WorkoutWirePayload.checkpoint(replica)
            )
            var next = state
            next.activeReplica = replica
            next.syncStatus = localDevice == .watch ? .waitingForPhone : .waitingForWatch
            append(envelope, to: &next)
            return commit(next, flush: true)
        } catch { return false }
    }

    @discardableResult
    func requestTakeover() -> Bool {
        guard let replica = state.activeReplica, replica.owner != localDevice else { return false }
        do {
            let envelope = try WorkoutMessageEnvelope(
                kind: .takeoverRequest,
                sender: localDevice,
                sessionID: replica.session.id,
                payload: WorkoutTakeoverRequest(
                    requester: localDevice,
                    knownVersion: replica.version
                )
            )
            var next = state
            next.authorityState = .requestingTakeover
            next.syncStatus = localDevice == .phone ? .waitingForWatch : .waitingForPhone
            append(envelope, to: &next)
            return commit(next, flush: true)
        } catch { return false }
    }

    /// Returns a timed-out takeover to a stable mirror state and removes its
    /// now-invalid requests so a later retry starts one fresh handshake.
    @discardableResult
    func cancelTakeoverRequest() -> Bool {
        guard let replica = state.activeReplica,
              replica.owner != localDevice,
              state.authorityState == .requestingTakeover else { return false }
        var next = state
        next.authorityState = .mirror
        next.syncStatus = .synced
        next.outbox.removeAll { pending in
            guard let queued = try? decoder.decode(
                WorkoutMessageEnvelope.self,
                from: pending.payload
            ) else { return false }
            return queued.kind == .takeoverRequest &&
                queued.sessionID == replica.session.id
        }
        return commit(next, flush: false)
    }

    /// Locally retires a workout this device mirrors but does not own.
    ///
    /// This is the escape hatch behind the failed-takeover message. Without it
    /// the phone is stranded: `cancel`/`finalize` both require ownership, so a
    /// mirror whose counterpart has reinstalled, been force-quit, or otherwise
    /// forgotten the session can neither take it over nor put it down, and the
    /// stale replica then blocks the next workout until the six-hour
    /// launch-recovery window expires.
    ///
    /// Deliberately local-only: no tombstone is broadcast. A non-owner must not
    /// be able to end a workout that is still live on the counterpart, and
    /// `receiveFinalization` rejects tombstones from non-owners anyway.
    @discardableResult
    func abandonMirroredSession() -> Bool {
        guard let current = state.activeReplica,
              current.owner != localDevice else { return false }
        var next = state
        retireHeldSession(in: &next)
        next.syncStatus = .localOnly
        return commit(next, flush: false)
    }

    /// True when an incoming replica describes a strictly newer workout than
    /// the one held locally. Only one workout can be live across the pair, so a
    /// counterpart reporting a later `startedAt` means the held one was
    /// abandoned rather than finished.
    private func supersedesHeldSession(_ incoming: WorkoutReplica) -> Bool {
        guard let current = state.activeReplica,
              current.session.id != incoming.session.id else { return false }
        return incoming.session.startedAt > current.session.startedAt
    }

    /// Drops the locally held session so a strictly newer one can take its
    /// place. Mirrors launch-time recovery: tombstone it as unfinished and
    /// purge its queued messages so nothing can resurrect it afterwards.
    private func retireHeldSession(in next: inout WorkoutRuntimeState) {
        guard let current = next.activeReplica else { return }
        let sessionID = current.session.id
        next.terminalSessions[sessionID] = WorkoutTombstone(
            sessionID: sessionID,
            finalVersion: current.version,
            finished: false,
            createdAt: now()
        )
        next.outbox.removeAll { pending in
            guard let queued = try? decoder.decode(
                WorkoutMessageEnvelope.self,
                from: pending.payload
            ) else { return false }
            return queued.sessionID == sessionID
        }
        next.activeReplica = nil
        next.authorityState = nil
    }

    /// Publishes a compact, self-contained plan cache. The Watch accepts only
    /// newer revisions and writes it before exposing offline starts.
    @discardableResult
    func updateWatchPlanCache(_ cache: WatchPlanCache) -> Bool {
        guard localDevice == .phone,
              cache.revision > (state.watchPlanCache?.revision ?? UInt64.min) else {
            return false
        }
        do {
            let envelope = try WorkoutMessageEnvelope(
                kind: .planCache,
                sender: localDevice,
                sessionID: nil,
                payload: cache
            )
            var next = state
            next.watchPlanCache = cache
            append(envelope, to: &next)
            return commit(next, flush: true)
        } catch { return false }
    }

    @discardableResult
    func finalize(session: WorkoutSession, finished: Bool, healthSaved: Bool) -> Bool {
        guard let replica = state.activeReplica,
              replica.session.id == session.id,
              replica.owner == localDevice else { return false }
        let tombstone = WorkoutTombstone(
            sessionID: session.id,
            finalVersion: replica.version,
            finished: finished,
            createdAt: Date()
        )
        do {
            let envelope = try WorkoutMessageEnvelope(
                kind: .tombstone,
                sender: localDevice,
                sessionID: session.id,
                payload: WorkoutFinalization(
                    tombstone: tombstone,
                    finalSession: session,
                    healthSaved: healthSaved
                )
            )
            var next = state
            next.activeReplica = nil
            next.authorityState = nil
            next.syncStatus = .synced
            next.terminalSessions[session.id] = tombstone
            append(envelope, to: &next)
            return commit(next, flush: true)
        } catch { return false }
    }

    func flushOutbox() {
        for pending in state.outbox {
            guard let envelope = try? decoder.decode(
                WorkoutMessageEnvelope.self, from: pending.payload
            ) else { continue }
            transmit?(envelope, pending.transport)
        }
    }

    @discardableResult
    func receive(_ envelope: WorkoutMessageEnvelope) -> ReceiveResult {
        guard envelope.schemaVersion == WorkoutMessageEnvelope.currentSchemaVersion,
              envelope.sender != localDevice else { return .ignored }
        if envelope.kind == .acknowledgment {
            guard let ack = try? envelope.decodePayload(WorkoutAcknowledgment.self) else {
                return .invalid
            }
            var next = state
            let before = next.outbox.count
            let ids = Set(ack.messageIDs)
            let completedLocalTransfer = next.outbox.contains { pending in
                guard ids.contains(pending.id),
                      let queued = try? decoder.decode(
                        WorkoutMessageEnvelope.self, from: pending.payload
                      ),
                      queued.kind == .ownershipCommit,
                      let commit = try? queued.decodePayload(
                        WorkoutOwnershipCommit.self
                      ) else { return false }
                return commit.replica.owner == localDevice
            }
            next.outbox.removeAll { ids.contains($0.id) }
            if completedLocalTransfer {
                next.authorityState = .authoritative
            }
            guard next.outbox.count != before else { return .duplicate }
            if next.outbox.isEmpty { next.syncStatus = .synced }
            return commit(next, flush: false) ? .applied : .invalid
        }
        if state.processedMessageIDs.contains(envelope.id) {
            sendAcknowledgment(for: envelope)
            return .duplicate
        }
        switch envelope.kind {
        case .ownershipOffer: return receiveOffer(envelope)
        case .ownershipAcceptance: return receiveAcceptance(envelope)
        case .ownershipCommit: return receiveCommit(envelope)
        case .takeoverRequest: return receiveTakeoverRequest(envelope)
        case .checkpoint: return receiveCheckpoint(envelope)
        case .planCache: return receivePlanCache(envelope)
        case .tombstone: return receiveFinalization(envelope)
        default: return .ignored
        }
    }

    private func receiveOffer(_ envelope: WorkoutMessageEnvelope) -> ReceiveResult {
        guard localDevice == .watch, envelope.sender == .phone,
              let offer = try? envelope.decodePayload(WorkoutOwnershipOffer.self),
              envelope.sessionID == offer.replica.session.id,
              offer.replica.owner == .phone,
              state.terminalSessions[offer.replica.session.id] == nil else { return .invalid }
        // A held replica for an *older* workout must not block this one. The
        // phone only offers a session it just started, so a strictly later
        // `startedAt` means the workout still on this wrist was abandoned.
        let supersedesHeld = supersedesHeldSession(offer.replica)
        if let current = state.activeReplica, !supersedesHeld {
            guard current.session.id == offer.replica.session.id,
                  current.version < offer.replica.version else { return .stale }
        }
        var accepted = offer.replica
        accepted.owner = .watch
        accepted.version = offer.replica.version.transferred()
        accepted.healthRecorder = .watch
        do {
            let receipt = try WorkoutMessageEnvelope(
                kind: .ownershipAcceptance,
                sender: localDevice,
                sessionID: accepted.session.id,
                payload: WorkoutOwnershipAcceptance(
                    replica: accepted, acceptedMessageID: envelope.id
                )
            )
            var next = state
            if supersedesHeld { retireHeldSession(in: &next) }
            // Persist the offered phone-owned replica and the acceptance
            // receipt atomically, but do not enable Watch editing until the
            // phone commits after becoming read-only.
            next.activeReplica = offer.replica
            next.authorityState = .mirror
            next.syncStatus = .waitingForPhone
            markProcessed(envelope.id, in: &next)
            append(receipt, to: &next)
            return commit(next, flush: true) ? .applied : .invalid
        } catch { return .invalid }
    }

    private func receiveAcceptance(_ envelope: WorkoutMessageEnvelope) -> ReceiveResult {
        guard let acceptance = try? envelope.decodePayload(WorkoutOwnershipAcceptance.self),
              envelope.sessionID == acceptance.replica.session.id,
              state.terminalSessions[acceptance.replica.session.id] == nil,
              let current = state.activeReplica,
              current.session.id == acceptance.replica.session.id,
              acceptance.replica.version == current.version.transferred() else { return .stale }
        let acceptingOffer =
            state.authorityState == .offeringTransfer &&
            current.owner == localDevice &&
            acceptance.replica.owner == envelope.sender
        let acceptingTakeover =
            state.authorityState == .requestingTakeover &&
            current.owner == envelope.sender &&
            acceptance.replica.owner == localDevice
        guard acceptingOffer || acceptingTakeover else { return .stale }
        var committedReplica = acceptance.replica
        if acceptingOffer {
            // Include every phone edit made before the acceptance receipt was
            // observed. The Watch has not enabled editing yet, so this merge
            // cannot conflict with a Watch mutation.
            committedReplica.session = current.session
            committedReplica.currentExerciseIndex = current.currentExerciseIndex
            committedReplica.restTimer = current.restTimer
            committedReplica.isWorkoutPaused = current.isWorkoutPaused
            committedReplica.phaseTimer = current.phaseTimer
            committedReplica.exerciseTimer = current.exerciseTimer
        }

        do {
            let transferCommit = try WorkoutMessageEnvelope(
                kind: .ownershipCommit,
                sender: localDevice,
                sessionID: committedReplica.session.id,
                payload: WorkoutOwnershipCommit(
                    replica: committedReplica,
                    acceptedMessageID: envelope.id
                )
            )
            var next = state
            next.activeReplica = committedReplica
            // New owner remains read-only until the former owner commits and
            // acknowledges; former owner is read-only immediately.
            next.authorityState = committedReplica.owner == localDevice
                ? .requestingTakeover
                : .mirror
            next.syncStatus = committedReplica.owner == .watch
                ? .waitingForWatch
                : .waitingForPhone
            next.outbox.removeAll { pending in
                if pending.id == acceptance.acceptedMessageID { return true }
                guard let queued = try? decoder.decode(
                    WorkoutMessageEnvelope.self,
                    from: pending.payload
                ) else { return false }
                return queued.sessionID == committedReplica.session.id &&
                    (queued.kind == .ownershipOffer ||
                     queued.kind == .takeoverRequest ||
                     queued.kind == .checkpoint)
            }
            markProcessed(envelope.id, in: &next)
            append(transferCommit, to: &next)
            return commit(next, flush: true) ? .applied : .invalid
        } catch { return .invalid }
    }

    private func receiveCommit(_ envelope: WorkoutMessageEnvelope) -> ReceiveResult {
        guard let transfer = try? envelope.decodePayload(WorkoutOwnershipCommit.self),
              envelope.sessionID == transfer.replica.session.id,
              let current = state.activeReplica,
              current.session.id == transfer.replica.session.id,
              transfer.replica.version == current.version.transferred() else {
            return .stale
        }
        let matchingAcceptance = state.outbox.contains { pending in
            guard pending.id == transfer.acceptedMessageID,
                  let queued = try? decoder.decode(
                    WorkoutMessageEnvelope.self, from: pending.payload
                  ),
                  queued.kind == .ownershipAcceptance,
                  let acceptance = try? queued.decodePayload(
                    WorkoutOwnershipAcceptance.self
                  ) else { return false }
            return acceptance.replica.session.id == transfer.replica.session.id &&
                acceptance.replica.owner == transfer.replica.owner &&
                acceptance.replica.version == transfer.replica.version
        }
        guard matchingAcceptance else { return .stale }

        var next = state
        next.activeReplica = transfer.replica
        next.authorityState = transfer.replica.owner == localDevice
            ? .authoritative
            : .mirror
        next.syncStatus = .synced
        next.outbox.removeAll { $0.id == transfer.acceptedMessageID }
        markProcessed(envelope.id, in: &next)
        guard commit(next, flush: false) else { return .invalid }
        sendAcknowledgment(for: envelope)
        return .applied
    }

    private func receiveTakeoverRequest(_ envelope: WorkoutMessageEnvelope) -> ReceiveResult {
        guard let request = try? envelope.decodePayload(WorkoutTakeoverRequest.self),
              request.requester == envelope.sender,
              let current = state.activeReplica,
              envelope.sessionID == current.session.id,
              current.owner == localDevice,
              state.authorityState == .authoritative,
              request.knownVersion.ownershipEpoch == current.version.ownershipEpoch,
              request.knownVersion <= current.version else { return .stale }
        var transferred = current
        transferred.owner = request.requester
        transferred.version = current.version.transferred()
        do {
            let acceptance = try WorkoutMessageEnvelope(
                kind: .ownershipAcceptance,
                sender: localDevice,
                sessionID: current.session.id,
                payload: WorkoutOwnershipAcceptance(
                    replica: transferred, acceptedMessageID: envelope.id
                )
            )
            var next = state
            // The current owner keeps editing until the requester receives
            // this acceptance and sends the commit.
            next.activeReplica = current
            next.authorityState = .finalizing
            next.syncStatus = localDevice == .watch ? .waitingForPhone : .waitingForWatch
            markProcessed(envelope.id, in: &next)
            append(acceptance, to: &next)
            return commit(next, flush: true) ? .applied : .invalid
        } catch { return .invalid }
    }

    private func receiveCheckpoint(_ envelope: WorkoutMessageEnvelope) -> ReceiveResult {
        guard let checkpoint = try? envelope.decodePayload(WorkoutCheckpoint.self),
              checkpoint.replica.owner == envelope.sender,
              checkpoint.replica.session.id == envelope.sessionID,
              state.terminalSessions[checkpoint.replica.session.id] == nil else { return .invalid }
        var next = state
        // Same rule as `receiveOffer`: a stale replica for an older workout
        // cannot veto the workout the counterpart is actually running now.
        // Retiring it here drops through to the age-checked adoption branch
        // below, so the newer session still has to be plausibly live.
        if supersedesHeldSession(checkpoint.replica) {
            retireHeldSession(in: &next)
        }
        if let current = next.activeReplica {
            guard current.session.id == checkpoint.replica.session.id,
                  checkpoint.replica.owner == current.owner else { return .stale }
            if checkpoint.replica.version <= current.version {
                if checkpoint.replica.version == current.version {
                    sendAcknowledgment(for: envelope)
                    return .duplicate
                }
                return .stale
            }
            // Checkpoints are complete snapshots, not deltas. A later revision
            // is therefore sufficient to converge after WatchConnectivity
            // reorders or coalesces a delivery; rejecting it would leave the
            // mirror stale with no guaranteed replay trigger.
            guard checkpoint.replica.version.ownershipEpoch == current.version.ownershipEpoch else {
                return .stale
            }
        } else {
            // A checkpoint is a complete snapshot, not a delta, so a device
            // holding no replica can adopt any revision. This is the path a
            // device takes to (re)join a workout already in progress: freshly
            // installed, force-quit and relaunched, or simply not running when
            // the counterpart started logging.
            //
            // This previously required `version == .initial` and returned
            // `.gap` otherwise. Nothing ever handled `.gap` — there is no
            // resync request in the protocol — so a device that missed the
            // first checkpoint rejected every subsequent one and stayed blank
            // for the rest of the workout, permanently.
            //
            // The age check is what `.initial` was implicitly buying: the
            // application context is sticky and survives termination, so
            // without it a cold launch could adopt a long-dead workout out of
            // the retained context. Keep this aligned with the six-hour
            // cold-start adoption window described by the transport layer.
            guard now().timeIntervalSince(checkpoint.replica.session.startedAt)
                    <= maxAdoptableSessionAge else { return .stale }
        }
        next.activeReplica = checkpoint.replica
        next.authorityState = .mirror
        next.syncStatus = .synced
        markProcessed(envelope.id, in: &next)
        guard commit(next, flush: false) else { return .invalid }
        sendAcknowledgment(for: envelope)
        return .applied
    }

    private func receivePlanCache(_ envelope: WorkoutMessageEnvelope) -> ReceiveResult {
        guard envelope.sender == .phone,
              let cache = try? envelope.decodePayload(WatchPlanCache.self) else {
            return .invalid
        }
        if let current = state.watchPlanCache, cache.revision <= current.revision {
            sendAcknowledgment(for: envelope)
            return .duplicate
        }
        var next = state
        next.watchPlanCache = cache
        markProcessed(envelope.id, in: &next)
        guard commit(next, flush: false) else { return .invalid }
        sendAcknowledgment(for: envelope)
        return .applied
    }

    private func receiveFinalization(_ envelope: WorkoutMessageEnvelope) -> ReceiveResult {
        guard let finalization = try? envelope.decodePayload(WorkoutFinalization.self),
              finalization.tombstone.sessionID == envelope.sessionID,
              finalization.finalSession.id == envelope.sessionID else { return .invalid }
        if state.terminalSessions[finalization.tombstone.sessionID] != nil {
            sendAcknowledgment(for: envelope)
            return .duplicate
        }
        // A device that is not tracking this session still records the
        // tombstone. It has nothing to tear down, but the tombstone is what
        // stops `receiveCheckpoint` from later adopting the finished workout:
        // the tombstone and any trailing checkpoint travel on transports with
        // no ordering guarantee, and `transferUserInfo` is a durable FIFO
        // queue that can deliver a backlog after a reinstall. Dropping it here
        // (the old behaviour) was safe only while adoption required
        // `version == .initial`; now that a replica-less device adopts any
        // revision, discarding the tombstone would resurrect finished work.
        let tracksSession =
            state.activeReplica?.session.id == finalization.tombstone.sessionID
        if tracksSession, let current = state.activeReplica {
            guard current.owner == envelope.sender,
                  finalization.tombstone.finalVersion >= current.version else { return .stale }
        }
        var next = state
        if tracksSession {
            next.activeReplica = nil
            next.authorityState = nil
        }
        next.syncStatus = .synced
        next.terminalSessions[finalization.tombstone.sessionID] = finalization.tombstone
        markProcessed(envelope.id, in: &next)
        guard commit(next, flush: false) else { return .invalid }
        sendAcknowledgment(for: envelope)
        return .applied
    }

    private func sendAcknowledgment(for envelope: WorkoutMessageEnvelope) {
        guard let ack = try? WorkoutMessageEnvelope(
            kind: .acknowledgment,
            sender: localDevice,
            sessionID: envelope.sessionID,
            payload: WorkoutAcknowledgment(messageIDs: [envelope.id])
        ) else { return }
        transmit?(ack, .reliable)
    }

    private func append(_ envelope: WorkoutMessageEnvelope, to state: inout WorkoutRuntimeState) {
        guard let data = try? encoder.encode(envelope) else { return }
        // Checkpoints and offers carry the complete replica, while a takeover
        // request carries the requester's latest known version. A newer one
        // fully supersedes any still-pending older one for the same session.
        // Without this collapse every logged set appended a fresh entry while
        // `commit(flush: true)` re-transmitted the entire outbox, making
        // delivery volume quadratic in the number of sets (30 sets produced
        // ~500 sends) and flooding the finite, persistent `transferUserInfo`
        // queue whenever the counterpart was unreachable.
        //
        // Deliberately same-kind only. An `ownershipOffer` is what drives the
        // Watch to accept ownership, so a `checkpoint` must never stand in for
        // one. Transfer-handshake receipts (acceptance/commit) and tombstones
        // are never collapsed either — `receiveCommit` and the
        // acknowledgment path match them by id out of this outbox, and a
        // dropped tombstone would strand a finished workout.
        if envelope.kind == .checkpoint ||
            envelope.kind == .ownershipOffer ||
            envelope.kind == .takeoverRequest {
            state.outbox.removeAll { pending in
                guard let queued = try? decoder.decode(
                    WorkoutMessageEnvelope.self, from: pending.payload
                ) else { return false }
                return queued.kind == envelope.kind &&
                    queued.sessionID == envelope.sessionID
            }
        }
        state.outbox.append(PendingWorkoutMessage(id: envelope.id, payload: data))
    }

    /// A small enum allows `mutate` to choose an offer or checkpoint while
    /// still using the envelope's single generic initializer.
    private enum WorkoutWirePayload: Codable {
        case offer(WorkoutReplica)
        case checkpoint(WorkoutReplica)

        private enum CodingKeys: String, CodingKey { case replica }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self = .checkpoint(try c.decode(WorkoutReplica.self, forKey: .replica))
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .offer(let replica), .checkpoint(let replica):
                try c.encode(replica, forKey: .replica)
            }
        }
    }

    private func markProcessed(_ id: UUID, in state: inout WorkoutRuntimeState) {
        state.processedMessageIDs.append(id)
        if state.processedMessageIDs.count > processedIDLimit {
            state.processedMessageIDs.removeFirst(
                state.processedMessageIDs.count - processedIDLimit
            )
        }
    }

    @discardableResult
    private func commit(_ next: WorkoutRuntimeState, flush: Bool) -> Bool {
        guard repository.save(next) else { return false }
        state = next
        onStateChange?(next)
        if flush { flushOutbox() }
        return true
    }
}
