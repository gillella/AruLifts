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

    /// Activity the live session was configured with. `HKWorkoutSession` fixes
    /// its activity type at creation, so changing it means ending this session
    /// and starting another.
    private(set) var currentActivityKind: PhaseActivityKind?

    /// Starts the live session. Failures are logged, never fatal — the
    /// workout itself proceeds regardless of Health availability.
    func start(
        sessionID: UUID = UUID(),
        configuration: HKWorkoutConfiguration? = nil,
        activityKind: PhaseActivityKind? = nil,
        phaseName: String? = nil
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
            // One gym visit can produce several workouts (one per phase
            // activity). Every phase of a visit shares the app's session id, so
            // that doubles as the grouping key, while each fragment keeps a
            // distinct external id so Health sees them as separate entries.
            var metadata: [String: Any] = [
                HKMetadataKeyExternalUUID: "\(sessionID.uuidString)-\(phaseName ?? "session")",
                Self.visitGroupingMetadataKey: sessionID.uuidString
            ]
            if let phaseName {
                metadata[Self.phaseNameMetadataKey] = phaseName
                metadata[HKMetadataKeyWorkoutBrandName] = phaseName
            }
            try await newBuilder.addMetadata(metadata)
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
            currentActivityKind = activityKind
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
        currentActivityKind = nil
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
        currentActivityKind = nil
        heartRateBPM = nil
        liveSession.end()
        liveBuilder.discardWorkout()
        if let activeSessionID {
            startGate.release(activeSessionID)
        }
    }
}

extension PhaseActivityKind {
    /// The HealthKit activity this phase should be recorded as.
    var hkActivityType: HKWorkoutActivityType {
        switch self {
        case .stairClimbing: return .stairClimbing
        case .elliptical: return .elliptical
        case .running: return .running
        case .cycling: return .cycling
        case .rowing: return .rowing
        case .mixedCardio: return .mixedCardio
        case .traditionalStrengthTraining: return .traditionalStrengthTraining
        case .flexibility: return .flexibility
        case .coreTraining: return .coreTraining
        case .preparationAndRecovery: return .preparationAndRecovery
        }
    }
}

extension WatchWorkoutSession {
    /// Custom metadata key tying one gym visit's per-phase workouts together.
    static let visitGroupingMetadataKey = "com.arulifts.gymVisitID"
    static let phaseNameMetadataKey = "com.arulifts.phaseName"

    /// Switches the live HealthKit session to the activity a new phase needs.
    ///
    /// `HKWorkoutSession.activityType` is immutable, so this saves the current
    /// workout and opens a new one. That is the accepted cost of per-phase
    /// accuracy: one gym visit appears in Health as several workouts, sharing a
    /// grouping id in metadata, with a short heart-rate gap at each boundary.
    /// No-ops when the activity is unchanged, so consecutive phases of the same
    /// kind (sauna then steam) stay one continuous session.
    func switchActivity(
        to kind: PhaseActivityKind,
        phaseName: String,
        sessionID: UUID
    ) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard currentActivityKind != kind else { return }
        guard isRunning else {
            // Nothing live yet (start may have failed or been skipped); begin
            // one for this phase rather than silently tracking nothing.
            await start(sessionID: sessionID, activityKind: kind, phaseName: phaseName)
            return
        }
        logger.info(
            "Switching Health activity to \(kind.rawValue, privacy: .public) for phase \(phaseName, privacy: .public)"
        )
        _ = await finish()
        await start(sessionID: sessionID, activityKind: kind, phaseName: phaseName)
    }

    /// Starts a live session already configured for a specific phase.
    func start(
        sessionID: UUID,
        activityKind: PhaseActivityKind,
        phaseName: String
    ) async {
        let config = HKWorkoutConfiguration()
        config.activityType = activityKind.hkActivityType
        config.locationType = .indoor
        await start(
            sessionID: sessionID,
            configuration: config,
            activityKind: activityKind,
            phaseName: phaseName
        )
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
