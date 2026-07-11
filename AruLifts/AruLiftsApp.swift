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
                    active.onFinish = { session, healthAlreadySaved in
                        store.recordSession(session)
                        // Skip the Health save when the watch's live session
                        // already produced the HKWorkout entry.
                        guard !healthAlreadySaved else { return }
                        var finished = session
                        if finished.finishedAt == nil { finished.finishedAt = Date() }
                        Task { await HealthKitManager.shared.saveWorkout(finished) }
                    }
                }
        }
    }
}
