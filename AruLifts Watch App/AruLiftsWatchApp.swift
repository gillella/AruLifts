import SwiftUI
import HealthKit
import OSLog
import WatchKit

/// Carries the HealthKit wake configuration until the matching durable
/// WatchConnectivity workout arrives. No anonymous Health workout is started.
@MainActor
final class WatchLaunchContext {
    static let shared = WatchLaunchContext()
    private(set) var configuration: HKWorkoutConfiguration?

    private init() {}

    func receive(_ configuration: HKWorkoutConfiguration) {
        self.configuration = configuration
    }

    func consumeConfiguration() -> HKWorkoutConfiguration? {
        defer { configuration = nil }
        return configuration
    }
}

@MainActor
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    private let logger = Logger(
        subsystem: "com.arulifts.app.watchkitapp",
        category: "WatchLaunch"
    )

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        logger.info("Received HealthKit companion workout launch")
        WatchLaunchContext.shared.receive(workoutConfiguration)
        ConnectivityManager.shared.activate()
    }
}

@main
struct AruLiftsWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @StateObject private var active = ActiveWorkoutManager()

    init() {
        // Ensure the WCSession is up so the phone can push sessions.
        _ = ConnectivityManager.shared
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(active)
                .tint(.orange)
        }
    }
}
