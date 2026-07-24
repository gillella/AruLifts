import Foundation

/// Persistence-first state machine for single-writer workout replication.
final class WorkoutSyncCoordinator {
    enum ReceiveResult: Equatable {
        case applied, duplicate, stale, gap, ignored, invalid
    }

    private(set) var state: WorkoutRuntimeState
    let localDevice: WorkoutDevice
    var onStateChange: ((WorkoutRuntimeState) -> Void)?
    var transmit: ((WorkoutMessageEnvelope, WorkoutMessageTransport) -> Void)?

    private let repository: ActiveWorkoutRepository
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let processedIDLimit = 256

    init(
        localDevice: WorkoutDevice,
        repository: ActiveWorkoutRepository = ActiveWorkoutRepository(),
        transmit: ((WorkoutMessageEnvelope, WorkoutMessageTransport) -> Void)? = nil
    ) {
        self.localDevice = localDevice
        self.repository = repository
        self.transmit = transmit
        state = repository.load()
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
        isWorkoutPaused: Bool
    ) -> Bool {
        guard var replica = state.activeReplica, canEdit,
              replica.session.id == session.id else { return false }
        replica.session = session
        replica.currentExerciseIndex = currentExerciseIndex
        replica.restTimer = restTimer
        replica.isWorkoutPaused = isWorkoutPaused
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
        if let current = state.activeReplica {
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
        if let current = state.activeReplica {
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
            guard checkpoint.replica.version == .initial else { return .gap }
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
        guard let current = state.activeReplica,
              current.session.id == finalization.tombstone.sessionID,
              current.owner == envelope.sender,
              finalization.tombstone.finalVersion >= current.version else { return .stale }
        var next = state
        next.activeReplica = nil
        next.authorityState = nil
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
