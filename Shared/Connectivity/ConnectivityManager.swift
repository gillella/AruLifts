import Foundation
import Combine

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Signals the counterpart ended a session. `finished` distinguishes a
/// completed workout (save to history) from a cancelled one (discard).
struct EndEvent {
    let id: UUID
    let finished: Bool
    /// The sender already saved this workout to Apple Health (watch live
    /// session), so the receiver must not write a duplicate HKWorkout.
    let healthSaved: Bool
    /// The sender's final session snapshot at the moment it ended, if it could
    /// be encoded. Carried alongside "end" so the receiver saves/discards the
    /// state the sender actually saw, not whatever local copy it happens to
    /// have — the last "sync" application-context push and this "end" message
    /// travel on different transports with no ordering guarantee between them,
    /// so a final edit (e.g. a last-second rep count) could otherwise race
    /// past its own "end" event and never make it into the receiver's copy.
    let session: WorkoutSession?
    /// Makes each delivery distinct so `@Published` always emits.
    let nonce = UUID()
}

extension EndEvent: Equatable {
    /// Equality here is really identity, not value equality: two `EndEvent`s
    /// are only ever "the same" if they are literally the same delivery. The
    /// `nonce` (fresh `UUID` per init) is sufficient and avoids requiring
    /// `WorkoutSession` equality semantics to carry meaning they don't have here.
    static func == (lhs: EndEvent, rhs: EndEvent) -> Bool {
        lhs.nonce == rhs.nonce
    }
}

/// Bridges the iPhone and Apple Watch using `WCSession`. The phone starts a
/// session and pushes it to the watch; both sides then push full-session state
/// (start/sync) via `updateApplicationContext` as the user logs sets, so either
/// device converges on the latest state regardless of message ordering. Discrete
/// lifecycle events ("end") use the reliable `sendMessage`/`transferUserInfo`
/// path instead, since they must never be coalesced away or lost.
final class ConnectivityManager: NSObject, ObservableObject {
    static let shared = ConnectivityManager()

    /// Latest session received from the counterpart device.
    @Published var receivedSession: WorkoutSession?
    @Published var receivedExerciseIndex: Int?
    @Published var receivedRestTimerEndDate: Date?
    @Published var receivedRestTimerTotalSeconds: Int?
    /// Atomic v2 protocol delivery. The envelope payload remains opaque until
    /// the coordinator validates ownership and ordering.
    @Published var receivedWorkoutEnvelope: WorkoutMessageEnvelope?
    /// The counterpart asked to end the session (finish or cancel).
    @Published var endEvent: EndEvent?
    /// Whether the counterpart device is currently reachable.
    @Published var isReachable: Bool = false
    /// Whether a watch app is installed/paired (meaningful on iOS only).
    @Published var isCounterpartAvailable: Bool = false

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Incoming session snapshots older than this are ignored. Application
    /// context is sticky and survives app termination, so an app killed
    /// mid-workout leaves its last "sync" in the context; without this guard a
    /// cold launch days later would replay that snapshot and resurrect the
    /// finished-in-spirit workout (observed: a 6-day-old session reappearing
    /// on launch). No real gym session runs longer than this, so a snapshot
    /// older than the window is always stale, never a live workout to resume.
    private let maxSessionAge: TimeInterval = 6 * 60 * 60
    /// Changes after WCSession activation, even when the counterpart is not
    /// foreground-reachable. Durable outbox items must then be flushed via
    /// `transferUserInfo`, not wait for a reachability transition.
    @Published private(set) var activationGeneration = 0

    private override init() {
        super.init()
        activate()
    }

    // MARK: - Public API

    func activate() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        #endif
    }

    /// Sends one v2 envelope. Reliable items use the queued-delta path (with an
    /// immediate reachable attempt); context is reserved for explicitly
    /// coalescible latest-state bootstrap messages.
    func send(
        _ envelope: WorkoutMessageEnvelope,
        transport: WorkoutMessageTransport
    ) {
        guard let data = try? encoder.encode(envelope) else { return }
        let payload: [String: Any] = [
            "type": "workoutSyncV2",
            "envelope": data
        ]
        switch transport {
        case .context:
            writeContext(payload)
        case .reliable:
            // Checkpoints/offers are also the atomically published latest
            // application context for cold-start convergence. The same stable
            // message ID then travels as a queued delta, so cross-transport
            // duplicates are harmless and revision gaps can still be repaired.
            if envelope.kind == .checkpoint ||
                envelope.kind == .ownershipOffer {
                writeContext(payload)
            }
            transmit(payload)
        }
    }

    /// Phone -> Watch: begin mirroring this session. Routed through application
    /// context (see `sendSync`) so the session is waiting for the watch app as
    /// soon as it activates, even if it wasn't running when the phone started it.
    func sendStart(_ session: WorkoutSession, currentExerciseIndex: Int, restTimerEndDate: Date?, restTimerTotalSeconds: Int?) {
        sendContext(type: "start", session: session, currentExerciseIndex: currentExerciseIndex, restTimerEndDate: restTimerEndDate, restTimerTotalSeconds: restTimerTotalSeconds)
    }

    /// Either direction: push the current full state.
    ///
    /// Full-session snapshots ("start"/"sync") go through
    /// `WCSession.updateApplicationContext`, not `sendMessage`/`transferUserInfo`.
    /// Application context holds at most one pending dictionary per direction and
    /// always reflects the most recent call, so it coalesces rapid-fire edits (e.g.
    /// two quick "+1 rep" taps on the watch) into "deliver the latest state" rather
    /// than racing two independent transports. The previous implementation mixed an
    /// immediate `sendMessage` with a queued `transferUserInfo` fallback per edit;
    /// because those two paths have no ordering guarantee relative to each other, a
    /// stale snapshot could arrive after a newer one and silently overwrite it
    /// (lost-update bug). A single coalescing channel makes that reordering
    /// impossible by construction.
    func sendSync(_ session: WorkoutSession, currentExerciseIndex: Int, restTimerEndDate: Date?, restTimerTotalSeconds: Int?) {
        sendContext(type: "sync", session: session, currentExerciseIndex: currentExerciseIndex, restTimerEndDate: restTimerEndDate, restTimerTotalSeconds: restTimerTotalSeconds)
    }

    /// Either direction: the session has finished (save) or been cancelled.
    ///
    /// Carries the full final `WorkoutSession` snapshot, not just its id: "end"
    /// travels on the reliable message/userInfo transport while "sync" travels on
    /// application context, and those two transports have no ordering guarantee
    /// relative to each other. If the sender made one last edit right before
    /// ending (e.g. a final rep-count tap before tapping Finish), the "end"
    /// message can beat the last "sync" context across the wire, and a receiver
    /// that only trusted its own locally-applied session would save/discard a
    /// copy missing that edit. Embedding the snapshot in "end" makes it
    /// self-contained: the receiver always finalizes exactly what the sender saw.
    func sendEnd(_ session: WorkoutSession, finished: Bool, healthSaved: Bool = false) {
        var payload: [String: Any] = [
            "type": "end",
            "id": session.id.uuidString,
            "finished": finished,
            "healthSaved": healthSaved,
        ]
        // Best-effort: if encoding fails (shouldn't happen for a value we just
        // held in memory), fall back to id-only and let the receiver use its
        // own local copy, same as before this fix.
        if let data = try? encoder.encode(session) {
            payload["session"] = data
        }
        transmit(payload)
        // Also clear the sticky application context (see clearActiveContext).
        // The context is the "latest full-session state" channel and it persists
        // across launches; if it still held the just-ended session, a counterpart
        // that cold-launches later would read that stale snapshot out of
        // `receivedApplicationContext` and resurrect a finished workout.
        clearActiveContext(session.id)
    }

    /// Overwrites the application context with an inert marker so no active-session
    /// snapshot is left lingering in it. Call whenever this device's session goes
    /// away (locally finished/cancelled, sent an end, OR received a remote end)
    /// so a cold-launching counterpart never resurrects it from a stale context.
    /// Both sides of a session must tombstone their own outgoing context:
    /// the sender does it in `sendEnd`, and the receiver must do it too (see
    /// `ActiveWorkoutManager.handleRemoteEnd`), because each direction of
    /// `WCSession.applicationContext` is independent — clearing the context you
    /// send does nothing to the context your counterpart is sending back to you.
    func clearActiveContext(_ id: UUID) {
        // Deliberately NOT type "end". `didReceiveApplicationContext` fires for
        // this write exactly as it would for a real push, and this write races
        // the actual "end" (sent separately via `transmit`, a different
        // transport with no ordering guarantee against this one). If this used
        // type "end" with no "finished"/"session" data, an out-of-order arrival
        // here would decode as `finished: false` (see `handle`'s defaults) and
        // could be misread as a cancel, discarding a session that was actually
        // finished. An unrecognized type is a safe no-op in `handle` (falls to
        // `default: break`) whether read live or via the cold-launch bootstrap
        // in `activationDidCompleteWith` — in both cases "do nothing" is exactly
        // right, since this write's only job is to keep a stale session
        // snapshot out of the sticky, persisted application context.
        writeContext(["type": "contextCleared", "id": id.uuidString])
    }

    // MARK: - Sending helpers

    /// Sends a full-session snapshot ("start"/"sync") via application context.
    /// `updateApplicationContext` only ever keeps the latest call pending, so
    /// this is the "keep the counterpart's view current" channel; it is not used
    /// for discrete events like "end" which must not be coalesced or dropped.
    private func sendContext(type: String, session: WorkoutSession, currentExerciseIndex: Int, restTimerEndDate: Date?, restTimerTotalSeconds: Int?) {
        guard let data = try? encoder.encode(session) else { return }
        var payload: [String: Any] = [
            "type": type,
            "session": data,
            "currentExerciseIndex": currentExerciseIndex
        ]
        if let restTimerEndDate {
            payload["restTimerEndDate"] = restTimerEndDate
        }
        if let restTimerTotalSeconds {
            payload["restTimerTotalSeconds"] = restTimerTotalSeconds
        }
        writeContext(payload)
    }

    /// Shared low-level call into `updateApplicationContext`. Used both for
    /// full-session snapshots (`sendContext`) and for the "end" tombstone
    /// (`clearActiveContext`) so there is exactly one place that talks to the
    /// sticky application-context channel.
    private func writeContext(_ payload: [String: Any]) {
        #if canImport(WatchConnectivity)
        let wcSession = WCSession.default
        guard wcSession.activationState == .activated else { return }
        do {
            try wcSession.updateApplicationContext(payload)
        } catch {
            // Throws if WatchConnectivity is unavailable/not activated on this
            // device. No fallback transport here on purpose: mixing in
            // sendMessage/transferUserInfo would reintroduce the same
            // cross-transport reordering this path exists to avoid. The next
            // edit (or the periodic context updates from further set changes)
            // will retry naturally.
        }
        #endif
    }

    private func transmit(_ payload: [String: Any]) {
        #if canImport(WatchConnectivity)
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            // Live message for immediate delivery.
            session.sendMessage(payload, replyHandler: nil, errorHandler: { [weak self] _ in
                self?.queue(payload)
            })
        } else {
            queue(payload)
        }
        #endif
    }

    /// Falls back to a guaranteed-delivery transfer when not reachable.
    private func queue(_ payload: [String: Any]) {
        #if canImport(WatchConnectivity)
        WCSession.default.transferUserInfo(payload)
        #endif
    }

    // MARK: - Receiving

    private func handle(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String else { return }
        switch type {
        case "workoutSyncV2":
            guard let data = payload["envelope"] as? Data,
                  let envelope = try? decoder.decode(
                    WorkoutMessageEnvelope.self,
                    from: data
                  ) else { return }
            DispatchQueue.main.async {
                self.receivedWorkoutEnvelope = envelope
            }
        case "start", "sync":
            if let data = payload["session"] as? Data,
               let session = try? decoder.decode(WorkoutSession.self, from: data) {
                // Drop stale snapshots (see maxSessionAge): the sticky context
                // can hand us a session from a long-dead run on cold launch.
                guard Date().timeIntervalSince(session.startedAt) <= maxSessionAge else { return }
                let index = payload["currentExerciseIndex"] as? Int
                let endDate = payload["restTimerEndDate"] as? Date
                let totalSeconds = payload["restTimerTotalSeconds"] as? Int
                DispatchQueue.main.async {
                    self.receivedRestTimerEndDate = endDate
                    self.receivedRestTimerTotalSeconds = totalSeconds
                    self.receivedExerciseIndex = index
                    self.receivedSession = session
                }
            }
        case "end":
            if let idString = payload["id"] as? String, let id = UUID(uuidString: idString) {
                let finished = (payload["finished"] as? Bool) ?? false
                let healthSaved = (payload["healthSaved"] as? Bool) ?? false
                // Defensive: the snapshot is best-effort (see sendEnd) — encoding
                // could fail, or a legacy/foreign payload might omit it — so a
                // missing/undecodable snapshot is an expected, not exceptional,
                // path. Fall back to nil and let the receiver use its own local
                // session (see ActiveWorkoutManager.handleRemoteEnd).
                let snapshot = (payload["session"] as? Data).flatMap {
                    try? self.decoder.decode(WorkoutSession.self, from: $0)
                }
                DispatchQueue.main.async {
                    self.endEvent = EndEvent(id: id, finished: finished, healthSaved: healthSaved, session: snapshot)
                }
            }
        default:
            break
        }
    }
}

#if canImport(WatchConnectivity)
extension ConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.refreshAvailability(session)
            self.activationGeneration &+= 1
        }
        // The counterpart may have pushed a session via updateApplicationContext
        // while this side was not running. That context does NOT arrive through
        // didReceiveApplicationContext on launch — the system only stashes it in
        // receivedApplicationContext — so pick it up here so a phone-started
        // workout is waiting when the watch app activates (and vice versa).
        let pending = session.receivedApplicationContext
        if !pending.isEmpty { handle(pending) }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.refreshAvailability(session) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo)
    }

    /// Delivered for `updateApplicationContext` pushes ("start"/"sync"). Same
    /// `["type", "session"]` shape as messages/userInfo, so it reuses `handle`.
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext)
    }

    private func refreshAvailability(_ session: WCSession) {
        isReachable = session.isReachable
        #if os(iOS)
        isCounterpartAvailable = session.isPaired && session.isWatchAppInstalled
        #else
        isCounterpartAvailable = session.isCompanionAppInstalled
        #endif
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate for switching between paired watches.
        WCSession.default.activate()
    }
    #endif
}
#endif
