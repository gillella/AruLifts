import Foundation
import HealthKit

/// Saves finished workouts to Apple Health. Phone-side save only for now —
/// the watch gets a live HKWorkoutSession in roadmap issue #2.
final class HealthKitManager {
    static let shared = HealthKitManager()
    private let store = HKHealthStore()
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
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
            HKQuantityType(.bodyMass),
        ]
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    #if os(iOS)
    /// Saves the finished session as a strength-training workout with estimated
    /// active energy. Deliberately never throws: a Health denial or write
    /// failure must not interfere with finishing and recording a workout.
    func saveWorkout(_ session: WorkoutSession) async {
        guard isAvailable else { return }
        guard let end = session.finishedAt, end > session.startedAt else { return }
        let start = session.startedAt

        do {
            try await requestAuthorization()

            let config = HKWorkoutConfiguration()
            config.activityType = .traditionalStrengthTraining
            config.locationType = .indoor

            let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
            try await builder.beginCollection(at: start)

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
            try await builder.finishWorkout()
        } catch {
            // Permission denied or Health write failure — log and move on.
            print("HealthKit: workout save failed: \(error.localizedDescription)")
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
