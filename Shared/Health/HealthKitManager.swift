import Foundation
import HealthKit

/// The durable outcome of attempting to save one app workout to HealthKit.
/// `saved` and `alreadySaved` are the only states that verify an HKWorkout
/// exists in the Health store.
struct HealthSaveResult: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case saved
        case alreadySaved
        case unavailable
        case invalidSession
        case failed
    }

    let state: State
    let sessionID: UUID
    let healthWorkoutID: UUID?
    let errorDescription: String?

    var isVerifiedSaved: Bool {
        state == .saved || state == .alreadySaved
    }

    static func saved(sessionID: UUID, healthWorkoutID: UUID) -> Self {
        Self(state: .saved, sessionID: sessionID, healthWorkoutID: healthWorkoutID, errorDescription: nil)
    }

    static func alreadySaved(sessionID: UUID, healthWorkoutID: UUID) -> Self {
        Self(state: .alreadySaved, sessionID: sessionID, healthWorkoutID: healthWorkoutID, errorDescription: nil)
    }

    static func unavailable(sessionID: UUID) -> Self {
        Self(state: .unavailable, sessionID: sessionID, healthWorkoutID: nil, errorDescription: nil)
    }

    static func invalidSession(sessionID: UUID) -> Self {
        Self(state: .invalidSession, sessionID: sessionID, healthWorkoutID: nil, errorDescription: nil)
    }

    static func failed(sessionID: UUID, error: Error) -> Self {
        Self(
            state: .failed,
            sessionID: sessionID,
            healthWorkoutID: nil,
            errorDescription: error.localizedDescription
        )
    }

    static func failed(sessionID: UUID, description: String) -> Self {
        Self(state: .failed, sessionID: sessionID, healthWorkoutID: nil, errorDescription: description)
    }
}

/// Saves finished workouts to Apple Health.
@MainActor
final class HealthKitManager {
    static let shared = HealthKitManager()
    private let store = HKHealthStore()
    #if os(iOS)
    /// Coalesces duplicate finish callbacks that arrive before the first
    /// HealthKit query/save has completed.
    private var workoutSaveTasks: [UUID: Task<HealthSaveResult, Never>] = [:]
    #endif
    private init() {}

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Everything we ever write: workouts, their energy, and body weight
    /// (weight logging itself lands with issue #9, but we ask once up front).
    private var shareTypes: Set<HKSampleType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.bodyMass),
        ]
    }

    /// Presents the Health permission sheet on first call; no-op afterwards.
    /// Read access to active energy and heart rate lets the watch's
    /// HKLiveWorkoutBuilder collect those samples during a live session.
    func requestAuthorization() async throws {
        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
            HKQuantityType(.bodyMass),
        ]
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    #if os(iOS)
    /// Saves the finished session as a strength-training workout with estimated
    /// active energy. Repeated calls for the same app session return the
    /// existing Health workout instead of creating another one.
    ///
    /// Deliberately never throws: a Health denial or write failure must not
    /// interfere with finishing and recording the workout in app history.
    func saveWorkout(_ session: WorkoutSession) async -> HealthSaveResult {
        if let existingTask = workoutSaveTasks[session.id] {
            return await existingTask.value
        }

        let task = Task<HealthSaveResult, Never> { [weak self] in
            guard let self else {
                return HealthSaveResult.failed(
                    sessionID: session.id,
                    description: "HealthKit manager was released"
                )
            }
            return await self.performSaveWorkout(session)
        }
        workoutSaveTasks[session.id] = task
        let result = await task.value
        workoutSaveTasks[session.id] = nil
        return result
    }

    private func performSaveWorkout(_ session: WorkoutSession) async -> HealthSaveResult {
        guard isAvailable else { return .unavailable(sessionID: session.id) }
        guard let end = session.finishedAt, end > session.startedAt else {
            return .invalidSession(sessionID: session.id)
        }
        let start = session.startedAt
        var activeBuilder: HKWorkoutBuilder?

        do {
            try await requestAuthorization()

            if let existing = try await workout(externalUUID: session.id) {
                return .alreadySaved(sessionID: session.id, healthWorkoutID: existing.uuid)
            }

            let config = HKWorkoutConfiguration()
            config.activityType = .traditionalStrengthTraining
            config.locationType = .indoor

            let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
            activeBuilder = builder
            try await builder.beginCollection(at: start)
            try await builder.addMetadata([
                HKMetadataKeyExternalUUID: session.id.uuidString
            ])

            let kcal = Self.estimatedActiveEnergyKcal(start: start, end: end)
            if kcal > 0 {
                let sample = HKQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                    start: start,
                    end: end
                )
                try await builder.addSamples([sample])
            }

            try await builder.endCollection(at: end)
            guard let workout = try await builder.finishWorkout() else {
                return .failed(
                    sessionID: session.id,
                    description: "HealthKit finished without returning a saved workout"
                )
            }
            activeBuilder = nil
            return .saved(sessionID: session.id, healthWorkoutID: workout.uuid)
        } catch {
            activeBuilder?.discardWorkout()
            // Permission denied or Health write failure — log and move on.
            print("HealthKit: workout save failed: \(error.localizedDescription)")
            return .failed(sessionID: session.id, error: error)
        }
    }

    /// Finds a previously saved workout carrying the app session's stable ID.
    private func workout(externalUUID: UUID) async throws -> HKWorkout? {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            operatorType: .equalTo,
            value: externalUUID.uuidString
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples?.first as? HKWorkout)
                }
            }
            store.execute(query)
        }
    }

    /// MET-based estimate (strength training ≈ 3.5 METs) with a fixed 75 kg
    /// body weight until body-weight tracking (issue #9) provides a real one.
    static func estimatedActiveEnergyKcal(start: Date, end: Date) -> Double {
        let hours = end.timeIntervalSince(start) / 3600
        return 3.5 * 75.0 * hours
    }

    /// Writes a body-mass sample. Errors logged, never thrown — logging a
    /// weight in the app must not fail because Health declined.
    func saveBodyMass(kg: Double, date: Date) async {
        guard isAvailable, kg > 0 else { return }
        do {
            try await requestAuthorization()
            let sample = HKQuantitySample(
                type: HKQuantityType(.bodyMass),
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
                start: date,
                end: date
            )
            try await store.save(sample)
        } catch {
            print("HealthKit: body mass save failed: \(error.localizedDescription)")
        }
    }

    /// Most recent body-mass sample in Health (any source), in kilograms.
    /// nil when unavailable, unauthorized, or no data.
    func latestBodyMassKg() async -> Double? {
        guard isAvailable else { return nil }
        try? await requestAuthorization()
        let type = HKQuantityType(.bodyMass)
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let kg = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: kg)
            }
            store.execute(query)
        }
    }
    #endif
}
