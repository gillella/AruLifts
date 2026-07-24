import SwiftUI

@main
struct AruLiftsApp: App {
    @StateObject private var store: WorkoutStore
    @StateObject private var active: ActiveWorkoutManager

    init() {
        // A Watch tombstone can wake the phone before any SwiftUI scene has
        // appeared. Bind this at object construction rather than RootView's
        // `onAppear`, otherwise that one durable finish event is consumed
        // before history/Health have a receiver.
        let store = WorkoutStore()
        let active = ActiveWorkoutManager()
        active.onFinish = { session, healthAlreadySaved in
            store.recordSession(session)
            // Skip the Health save when the Watch's live session already
            // produced the HKWorkout entry.
            guard !healthAlreadySaved else { return }
            var finished = session
            if finished.finishedAt == nil { finished.finishedAt = Date() }
            Task { await HealthKitManager.shared.saveWorkout(finished) }
        }
        _store = StateObject(wrappedValue: store)
        _active = StateObject(wrappedValue: active)
        RestTimerManager.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(active)
                .tint(.orange)
                .onAppear {
                    updateWatchPlanCache()
                }
                .onChange(of: store.templates) { _, _ in updateWatchPlanCache() }
                .onChange(of: store.customExercises) { _, _ in updateWatchPlanCache() }
                .onChange(of: store.settings) { _, _ in updateWatchPlanCache() }
        }
    }

    private func updateWatchPlanCache() {
        active.updateWatchPlanCache(
            templates: store.templates,
            library: store.exerciseIndex,
            settings: store.settings
        )
    }
}
