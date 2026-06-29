import SwiftUI

@main
struct AruLiftsApp: App {
    @StateObject private var store = WorkoutStore()
    @StateObject private var active = ActiveWorkoutManager()

    init() {
        RestTimerManager.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(active)
                .tint(.orange)
                .onAppear {
                    // Persist finished sessions to history.
                    active.onFinish = { session in
                        store.recordSession(session)
                    }
                }
        }
    }
}
