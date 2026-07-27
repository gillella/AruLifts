import Foundation
import HealthKit
import OSLog

/// Runs a real HKWorkoutSession while a workout is active on the watch.
/// This keeps the app alive through rest periods (so the rest-over haptic
/// always fires) and earns workout/activity-ring credit. The Watch records
/// both Watch-started workouts and iPhone starts whose ownership is handed to
/// the Watch; the finalization `healthSaved` flag prevents the phone from
/// writing a duplicate Health entry.
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
    private var startGate = WatchWorkoutStartGate()
    private let logger = Logger(
        subsystem: "com.arulifts.app.watchkitapp",
        category: "WorkoutSession"
    )

    /// Latest heart-rate reading from the live session, in beats per minute.
    /// nil when there's no running session, no data yet, or permission was
    /// denied — views hide the HR chip in that case.
    @Published private(set) var heartRateBPM: Double?

    var isRunning: Bool { session != nil }

    /// Starts the live session. Failures are logged, never fatal — the
    /// workout itself proceeds regardless of Health availability.
    func start(
        sessionID: UUID = UUID(),
        configuration: HKWorkoutConfiguration? = nil
    ) async {
        guard startGate.claim(sessionID) else {
            logger.info(
                "Ignoring duplicate workout start \(sessionID.uuidString, privacy: .public)"
            )
            return
        }
        guard session == nil, startingSessionID == nil,
              HKHealthStore.isHealthDataAvailable() else {
            startGate.release(sessionID)
            return
        }
        startingSessionID = sessionID
        var pendingSession: HKWorkoutSession?
        var pendingBuilder: HKLiveWorkoutBuilder?
        do {
            try await HealthKitManager.shared.requestAuthorization()

            let config = configuration ?? HKWorkoutConfiguration()
            if configuration == nil {
                config.activityType = .traditionalStrengthTraining
                config.locationType = .indoor
            }

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
                startGate.release(sessionID)
                return
            }
            session = newSession
            builder = newBuilder
            workoutSessionID = sessionID
            startingSessionID = nil
            pendingSession = nil
            pendingBuilder = nil
            logger.info(
                "Started HealthKit workout \(sessionID.uuidString, privacy: .public)"
            )
        } catch {
            pendingSession?.end()
            pendingBuilder?.discardWorkout()
            logger.error(
                "HealthKit workout start failed for \(sessionID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            if startingSessionID == sessionID {
                startingSessionID = nil
            }
            startGate.release(sessionID)
        }
    }

    /// Ends the live session and saves the workout to Health. Collected
    /// samples (heart rate, active energy) are persisted with the HKWorkout,
    /// so average HR and calories appear in the Fitness app automatically.
    func finish() async -> HealthSaveResult {
        // If authorization/collection is still pending, invalidate that start
        // before reporting there is no live workout to finish.
        let pendingSessionID = startingSessionID
        startingSessionID = nil
        if let pendingSessionID {
            startGate.release(pendingSessionID)
        }
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
        defer { startGate.release(appSessionID) }
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
            logger.error(
                "HealthKit workout finish failed for \(appSessionID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return .failed(sessionID: appSessionID, error: error)
        }
    }

    /// Ends the live session without saving — the workout was cancelled, or
    /// the phone finished it and owns the Health entry.
    func discard() {
        let pendingSessionID = startingSessionID
        startingSessionID = nil
        if let pendingSessionID {
            startGate.release(pendingSessionID)
        }
        guard let liveSession = session, let liveBuilder = builder else { return }
        let activeSessionID = workoutSessionID
        session = nil
        builder = nil
        workoutSessionID = nil
        heartRateBPM = nil
        liveSession.end()
        liveBuilder.discardWorkout()
        if let activeSessionID {
            startGate.release(activeSessionID)
        }
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
