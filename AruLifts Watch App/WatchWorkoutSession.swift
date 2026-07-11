import Foundation
import HealthKit

/// Runs a real HKWorkoutSession while a workout is active on the watch.
/// This keeps the app alive through rest periods (so the rest-over haptic
/// always fires) and earns workout/activity-ring credit. Watch-initiated
/// workouts only: phone-run workouts are saved to Health by the phone
/// (`HealthKitManager`), and the `EndEvent.healthSaved` flag keeps the two
/// devices from writing duplicate Health entries.
@MainActor
final class WatchWorkoutSession: NSObject, ObservableObject {
    static let shared = WatchWorkoutSession()

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    var isRunning: Bool { session != nil }

    /// Starts the live session. Failures are logged, never fatal — the
    /// workout itself proceeds regardless of Health availability.
    func start() async {
        guard session == nil, HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await HealthKitManager.shared.requestAuthorization()

            let config = HKWorkoutConfiguration()
            config.activityType = .traditionalStrengthTraining
            config.locationType = .indoor

            let newSession = try HKWorkoutSession(healthStore: store, configuration: config)
            let newBuilder = newSession.associatedWorkoutBuilder()
            newBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)

            newSession.startActivity(with: Date())
            try await newBuilder.beginCollection(at: Date())
            session = newSession
            builder = newBuilder
        } catch {
            print("WatchWorkoutSession: start failed: \(error.localizedDescription)")
            session = nil
            builder = nil
        }
    }

    /// Ends the live session and saves the workout to Health.
    func finish() async {
        guard let liveSession = session, let liveBuilder = builder else { return }
        session = nil
        builder = nil
        liveSession.end()
        do {
            try await liveBuilder.endCollection(at: Date())
            try await liveBuilder.finishWorkout()
        } catch {
            print("WatchWorkoutSession: finish failed: \(error.localizedDescription)")
        }
    }

    /// Ends the live session without saving — the workout was cancelled, or
    /// the phone finished it and owns the Health entry.
    func discard() {
        guard let liveSession = session, let liveBuilder = builder else { return }
        session = nil
        builder = nil
        liveSession.end()
        liveBuilder.discardWorkout()
    }
}
