import Foundation
import Combine
import OSLog

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Bridges the iPhone and Apple Watch using `WCSession`.
///
/// The v2 coordinator supplies durable, versioned envelopes. Complete
/// checkpoints are also published as application context for cold-start
/// convergence; handshake and finalization events use the reliable queued
/// path so they cannot be coalesced away.
/// Main-actor isolation makes every published connectivity state transition
/// deterministic. WatchConnectivity invokes its delegate from arbitrary
/// background queues; the nonisolated delegate methods below explicitly hop
/// back here before touching state.
@MainActor
final class ConnectivityManager: NSObject, ObservableObject {
    static let shared = ConnectivityManager()

    /// Atomic v2 protocol delivery. The envelope payload remains opaque until
    /// the coordinator validates ownership and ordering.
    @Published var receivedWorkoutEnvelope: WorkoutMessageEnvelope?
    /// Whether the counterpart device is currently reachable.
    @Published var isReachable: Bool = false
    /// Whether a watch app is installed/paired (meaningful on iOS only).
    @Published var isCounterpartAvailable: Bool = false

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(
        subsystem: "com.arulifts.app",
        category: "WatchConnectivity"
    )

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
        guard let data = try? encoder.encode(envelope) else {
            logger.error(
                "Failed to encode \(envelope.kind.rawValue, privacy: .public)"
            )
            return
        }
        logger.info(
            "Sending \(envelope.kind.rawValue, privacy: .public) for \(envelope.sessionID?.uuidString ?? "none", privacy: .public) via \(transport.rawValue, privacy: .public)"
        )
        var payload: [String: Any] = [
            "type": "workoutSyncV2",
            "envelope": data,
            "messageID": envelope.id.uuidString,
            "messageKind": envelope.kind.rawValue
        ]
        if let sessionID = envelope.sessionID {
            payload["sessionID"] = sessionID.uuidString
        }
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

    /// Overwrites application context with an inert marker so no active
    /// checkpoint lingers after finalization. Each direction of application
    /// context is independent, so both devices clear their own outgoing copy
    /// when they apply the tombstone.
    func clearActiveContext(_ id: UUID) {
        // The clear marker and reliable tombstone can arrive in either order.
        // Keeping the marker inert leaves the tombstone as the only authority
        // for whether the workout finished or was cancelled.
        writeContext(["type": "contextCleared", "id": id.uuidString])
    }

    // MARK: - Sending helpers

    /// Shared low-level call into the sticky application-context channel.
    /// Used for complete v2 checkpoints/offers and the inert clear marker.
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
            logger.error(
                "Application context update failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        #endif
    }

    private func transmit(_ payload: [String: Any]) {
        #if canImport(WatchConnectivity)
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            // Live message for immediate delivery.
            session.sendMessage(payload, replyHandler: nil, errorHandler: { [weak self] error in
                let queuedPayload = ReceivedPayload(payload)
                let description = error.localizedDescription
                Task { @MainActor [weak self] in
                    self?.logger.error(
                        "Immediate WatchConnectivity message failed: \(description, privacy: .public); queueing"
                    )
                    self?.queue(queuedPayload.values)
                }
            })
        } else {
            queue(payload)
        }
        #endif
    }

    /// Falls back to a guaranteed-delivery transfer when not reachable.
    private func queue(_ payload: [String: Any]) {
        #if canImport(WatchConnectivity)
        let session = WCSession.default
        let messageID = payload["messageID"] as? String

        // A durable outbox flush can run at startup, activation, reachability,
        // and after every local edit. Do not create multiple system transfers
        // for the same stable envelope while one is already pending.
        if let messageID,
           session.outstandingUserInfoTransfers.contains(where: {
               $0.userInfo["messageID"] as? String == messageID
           }) {
            logger.info(
                "Skipping duplicate queued transfer \(messageID, privacy: .public)"
            )
            return
        }

        // Checkpoints and ownership offers are complete snapshots. The
        // coordinator already collapses superseded copies in its own outbox;
        // mirror that rule in WatchConnectivity's persistent system queue so
        // stale snapshots do not accumulate while the counterpart is offline.
        if let kind = payload["messageKind"] as? String,
           kind == WorkoutMessageKind.checkpoint.rawValue ||
             kind == WorkoutMessageKind.ownershipOffer.rawValue,
           let sessionID = payload["sessionID"] as? String {
            for transfer in session.outstandingUserInfoTransfers where
                transfer.userInfo["messageKind"] as? String == kind &&
                transfer.userInfo["sessionID"] as? String == sessionID {
                transfer.cancel()
            }
        }

        session.transferUserInfo(payload)
        logger.info(
            "Queued WatchConnectivity transfer \(messageID ?? "unidentified", privacy: .public); outstanding=\(session.outstandingUserInfoTransfers.count)"
        )
        #endif
    }

    // MARK: - Receiving

    /// Stops a tombstoned session from crossing an asynchronous delivery
    /// boundary after its terminal event has been received. Durable ordering is
    /// still owned by `WorkoutSyncCoordinator`; this only closes the in-process
    /// WatchConnectivity dispatch race.
    private let terminalSessionGate = TerminalSessionGate()

    private func handle(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String else { return }
        switch type {
        case "workoutSyncV2":
            guard let data = payload["envelope"] as? Data,
                  let envelope = try? decoder.decode(
                    WorkoutMessageEnvelope.self,
                    from: data
                  ) else { return }

            if envelope.kind == .tombstone,
               let finalization = try? envelope.decodePayload(WorkoutFinalization.self),
               finalization.tombstone.sessionID == envelope.sessionID {
                terminalSessionGate.markTerminal(finalization.tombstone.sessionID)
            }
            DispatchQueue.main.async {
                if envelope.kind != .tombstone,
                   let sessionID = envelope.sessionID,
                   self.terminalSessionGate.isTerminal(sessionID) {
                    return
                }
                self.receivedWorkoutEnvelope = envelope
            }
        default:
            break
        }
    }
}

#if canImport(WatchConnectivity)
extension ConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let availability = SessionAvailability(session: session)
        let activationRawValue = activationState.rawValue
        let activationError = error?.localizedDescription
        // The counterpart may have pushed a session via updateApplicationContext
        // while this side was not running. That context does NOT arrive through
        // didReceiveApplicationContext on launch — the system only stashes it in
        // receivedApplicationContext — so pick it up here so a phone-started
        // workout is waiting when the watch app activates (and vice versa).
        let pending = ReceivedPayload(session.receivedApplicationContext)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let activationError {
                self.logger.error(
                    "WCSession activation failed: \(activationError, privacy: .public)"
                )
            } else {
                self.logger.info(
                    "WCSession activated state=\(activationRawValue) reachable=\(availability.isReachable)"
                )
            }
            self.refreshAvailability(availability)
            self.activationGeneration &+= 1
            if !pending.values.isEmpty { self.handle(pending.values) }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let availability = SessionAvailability(session: session)
        Task { @MainActor [weak self] in
            self?.refreshAvailability(availability)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let payload = ReceivedPayload(message)
        Task { @MainActor [weak self] in
            self?.handle(payload.values)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let payload = ReceivedPayload(userInfo)
        Task { @MainActor [weak self] in
            self?.handle(payload.values)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish userInfoTransfer: WCSessionUserInfoTransfer,
        error: Error?
    ) {
        let messageID =
            userInfoTransfer.userInfo["messageID"] as? String ?? "unidentified"
        let transferError = error?.localizedDescription
        let outstandingCount = session.outstandingUserInfoTransfers.count
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let transferError {
                self.logger.error(
                    "Queued transfer \(messageID, privacy: .public) failed: \(transferError, privacy: .public); outstanding=\(outstandingCount)"
                )
            } else {
                self.logger.info(
                    "Queued transfer \(messageID, privacy: .public) delivered; outstanding=\(outstandingCount)"
                )
            }
        }
    }

    /// Delivers the latest complete v2 checkpoint/offer published through
    /// application context. It uses the same envelope shape as other channels.
    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let payload = ReceivedPayload(applicationContext)
        Task { @MainActor [weak self] in
            self?.handle(payload.values)
        }
    }

    private func refreshAvailability(_ availability: SessionAvailability) {
        isReachable = availability.isReachable
        isCounterpartAvailable = availability.isCounterpartAvailable
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate for switching between paired watches.
        Task { @MainActor [weak self] in
            self?.activate()
        }
    }
    #endif
}

private struct SessionAvailability: Sendable {
    let isReachable: Bool
    let isCounterpartAvailable: Bool

    nonisolated init(session: WCSession) {
        isReachable = session.isReachable
        #if os(iOS)
        isCounterpartAvailable = session.isPaired && session.isWatchAppInstalled
        #else
        isCounterpartAvailable = session.isCompanionAppInstalled
        #endif
    }
}

/// `WCSessionDelegate` vends Foundation dictionaries containing `Any`, which
/// cannot be expressed as `Sendable`. They are copied at the callback boundary
/// and only decoded after the main-actor hop; WatchConnectivity does not mutate
/// a delivered payload after invoking its delegate.
private struct ReceivedPayload: @unchecked Sendable {
    let values: [String: Any]

    init(_ values: [String: Any]) {
        self.values = values
    }
}
#endif
