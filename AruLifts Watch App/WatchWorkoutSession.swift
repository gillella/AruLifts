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

    /// Latest heart-rate reading from the live session, in beats per minute.
    /// nil when there's no running session, no data yet, or permission was
    /// denied — views hide the HR chip in that case.
    @Published private(set) var heartRateBPM: Double?

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
            newBuilder.delegate = self

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

    /// Ends the live session and saves the workout to Health. Collected
    /// samples (heart rate, active energy) are persisted with the HKWorkout,
    /// so average HR and calories appear in the Fitness app automatically.
    func finish() async {
        guard let liveSession = session, let liveBuilder = builder else { return }
        session = nil
        builder = nil
        heartRateBPM = nil
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
        heartRateBPM = nil
        liveSession.end()
        liveBuilder.discardWorkout()
    }
}

extension WatchWorkoutSession: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hrType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hrType),
              let stats = workoutBuilder.statistics(for: hrType),
              let latest = stats.mostRecentQuantity() else { return }
        let bpm = latest.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        Task { @MainActor in self.heartRateBPM = bpm }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
