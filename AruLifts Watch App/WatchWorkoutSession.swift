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
    private var workoutSessionID: UUID?
    /// Set before authorization starts, so cancel/finish can invalidate an
    /// in-flight start that has not yet created an HKWorkoutSession.
    private var startingSessionID: UUID?

    /// Latest heart-rate reading from the live session, in beats per minute.
    /// nil when there's no running session, no data yet, or permission was
    /// denied — views hide the HR chip in that case.
    @Published private(set) var heartRateBPM: Double?

    var isRunning: Bool { session != nil }

    /// Starts the live session. Failures are logged, never fatal — the
    /// workout itself proceeds regardless of Health availability.
    func start(sessionID: UUID = UUID()) async {
        guard session == nil, startingSessionID == nil,
              HKHealthStore.isHealthDataAvailable() else { return }
        startingSessionID = sessionID
        var pendingSession: HKWorkoutSession?
        var pendingBuilder: HKLiveWorkoutBuilder?
        do {
            try await HealthKitManager.shared.requestAuthorization()

            let config = HKWorkoutConfiguration()
            config.activityType = .traditionalStrengthTraining
            config.locationType = .indoor

            let newSession = try HKWorkoutSession(healthStore: store, configuration: config)
            let newBuilder = newSession.associatedWorkoutBuilder()
            pendingSession = newSession
            pendingBuilder = newBuilder
            newBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            newBuilder.delegate = self

            let startDate = Date()
            newSession.startActivity(with: startDate)
            try await newBuilder.beginCollection(at: startDate)
            try await newBuilder.addMetadata([
                HKMetadataKeyExternalUUID: sessionID.uuidString
            ])
            // Cancellation may have happened while Health authorization or
            // collection setup was awaiting. Do not leak a live session.
            guard startingSessionID == sessionID else {
                newSession.end()
                newBuilder.discardWorkout()
                return
            }
            session = newSession
            builder = newBuilder
            workoutSessionID = sessionID
            startingSessionID = nil
            pendingSession = nil
            pendingBuilder = nil
        } catch {
            pendingSession?.end()
            pendingBuilder?.discardWorkout()
            print("WatchWorkoutSession: start failed: \(error.localizedDescription)")
            if startingSessionID == sessionID {
                startingSessionID = nil
            }
        }
    }

    /// Ends the live session and saves the workout to Health. Collected
    /// samples (heart rate, active energy) are persisted with the HKWorkout,
    /// so average HR and calories appear in the Fitness app automatically.
    func finish() async -> HealthSaveResult {
        // If authorization/collection is still pending, invalidate that start
        // before reporting there is no live workout to finish.
        startingSessionID = nil
        guard let liveSession = session,
              let liveBuilder = builder,
              let appSessionID = workoutSessionID else {
            return .failed(
                sessionID: workoutSessionID ?? UUID(),
                description: "No live HealthKit workout session to finish"
            )
        }
        session = nil
        builder = nil
        workoutSessionID = nil
        heartRateBPM = nil
        liveSession.end()
        do {
            try await liveBuilder.endCollection(at: Date())
            guard let workout = try await liveBuilder.finishWorkout() else {
                return .failed(
                    sessionID: appSessionID,
                    description: "HealthKit finished without returning a saved workout"
                )
            }
            return .saved(sessionID: appSessionID, healthWorkoutID: workout.uuid)
        } catch {
            print("WatchWorkoutSession: finish failed: \(error.localizedDescription)")
            return .failed(sessionID: appSessionID, error: error)
        }
    }

    /// Ends the live session without saving — the workout was cancelled, or
    /// the phone finished it and owns the Health entry.
    func discard() {
        startingSessionID = nil
        guard let liveSession = session, let liveBuilder = builder else { return }
        session = nil
        builder = nil
        workoutSessionID = nil
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
