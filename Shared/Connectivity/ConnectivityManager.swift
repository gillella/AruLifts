import Foundation
import Combine

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Signals the counterpart ended a session. `finished` distinguishes a
/// completed workout (save to history) from a cancelled one (discard).
struct EndEvent: Equatable {
    let id: UUID
    let finished: Bool
    /// Makes each delivery distinct so `@Published` always emits.
    let nonce = UUID()
}

/// Bridges the iPhone and Apple Watch using `WCSession`. The phone starts a
/// session and pushes it to the watch; both sides then send full-session syncs
/// as the user logs sets, so either device stays current.
final class ConnectivityManager: NSObject, ObservableObject {
    static let shared = ConnectivityManager()

    /// Latest session received from the counterpart device.
    @Published var receivedSession: WorkoutSession?
    /// The counterpart asked to end the session (finish or cancel).
    @Published var endEvent: EndEvent?
    /// Whether the counterpart device is currently reachable.
    @Published var isReachable: Bool = false
    /// Whether a watch app is installed/paired (meaningful on iOS only).
    @Published var isCounterpartAvailable: Bool = false

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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

    /// Phone -> Watch: begin mirroring this session.
    func sendStart(_ session: WorkoutSession) {
        send(type: "start", session: session)
    }

    /// Either direction: push the current full state.
    func sendSync(_ session: WorkoutSession) {
        send(type: "sync", session: session)
    }

    /// Either direction: the session has finished (save) or been cancelled.
    func sendEnd(_ id: UUID, finished: Bool) {
        let payload: [String: Any] = ["type": "end", "id": id.uuidString, "finished": finished]
        transmit(payload)
    }

    // MARK: - Sending helpers

    private func send(type: String, session: WorkoutSession) {
        guard let data = try? encoder.encode(session) else { return }
        let payload: [String: Any] = ["type": type, "session": data]
        transmit(payload)
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
        case "start", "sync":
            if let data = payload["session"] as? Data,
               let session = try? decoder.decode(WorkoutSession.self, from: data) {
                DispatchQueue.main.async { self.receivedSession = session }
            }
        case "end":
            if let idString = payload["id"] as? String, let id = UUID(uuidString: idString) {
                let finished = (payload["finished"] as? Bool) ?? false
                DispatchQueue.main.async { self.endEvent = EndEvent(id: id, finished: finished) }
            }
        default:
            break
        }
    }
}

#if canImport(WatchConnectivity)
extension ConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.refreshAvailability(session) }
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
