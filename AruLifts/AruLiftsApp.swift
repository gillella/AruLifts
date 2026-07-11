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
                    // Persist finished sessions to history and Apple Health.
                    active.onFinish = { session in
                        store.recordSession(session)
                        var finished = session
                        if finished.finishedAt == nil { finished.finishedAt = Date() }
                        Task { await HealthKitManager.shared.saveWorkout(finished) }
                    }
                }
        }
    }
}
