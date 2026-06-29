import SwiftUI

@main
struct AruLiftsWatchApp: App {
    @StateObject private var active = ActiveWorkoutManager()

    init() {
        RestTimerManager.requestAuthorization()
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
