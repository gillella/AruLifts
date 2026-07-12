import Foundation

/// One exercise whose working weight changed after a session — bumped up on
/// success, or deloaded after repeated failures.
struct ProgressionChange: Identifiable, Equatable {
    enum Kind: Equatable { case increase, deload }
    var id: UUID { exerciseID }
    let exerciseID: UUID
    let name: String
    let fromWeight: Double
    let toWeight: Double
    let kind: Kind
}

/// StrongLifts-style linear progression: complete every target rep in every
/// set of an exercise and its template weight goes up next session.
/// Pure functions — no store or UI dependencies — so the rules are testable.
enum Progression {
    /// Default increment when the template doesn't set one. Deadlift-style
    /// pulls progress twice as fast, per StrongLifts convention.
    static func defaultIncrement(exerciseName: String, units: AppSettings.Units) -> Double {
        let isDeadlift = exerciseName.localizedCaseInsensitiveContains("deadlift")
        switch units {
        case .kg: return isDeadlift ? 5.0 : 2.5
        case .lb: return isDeadlift ? 10.0 : 5.0
        }
    }

    /// True when the logged exercise hit every target rep in every work set.
    /// Warmup sets never affect progression.
    static func isSuccessful(_ logged: SessionExercise, targetReps: Int) -> Bool {
        let workSets = logged.sets.filter { !$0.isWarmup }
        guard !workSets.isEmpty else { return false }
        return workSets.allSatisfy { $0.isCompleted && $0.reps >= targetReps }
    }

    /// Deload target: weight minus `percent`, rounded to the nearest multiple
    /// of the exercise's increment so the result stays plate-loadable.
    static func deloadedWeight(_ weight: Double, percent: Double, roundTo quantum: Double) -> Double {
        let reduced = weight * (1 - percent / 100)
        guard quantum > 0 else { return max(0, reduced) }
        return max(0, (reduced / quantum).rounded() * quantum)
    }

    /// Applies progression and deload from a finished session to its template.
    /// Success bumps the weight and clears the failure counter; failure
    /// increments it, and hitting `failureThreshold` deloads by
    /// `deloadPercent` and resets the counter. Exercises not attempted in the
    /// session are untouched. Returns the updated template plus the changes.
    static func apply(
        session: WorkoutSession,
        to template: WorkoutTemplate,
        units: AppSettings.Units,
        failureThreshold: Int = 3,
        deloadPercent: Double = 10
    ) -> (template: WorkoutTemplate, changes: [ProgressionChange]) {
        guard session.templateID == template.id else { return (template, []) }

        var updated = template
        var changes: [ProgressionChange] = []

        for (index, te) in template.exercises.enumerated() {
            guard te.progressionEnabled else { continue }
            guard let logged = session.exercises.first(where: { $0.exerciseID == te.exerciseID }) else { continue }
            guard logged.usesWeight else { continue }

            let increment = te.progressionIncrement
                ?? defaultIncrement(exerciseName: te.name, units: units)

            if isSuccessful(logged, targetReps: te.targetReps) {
                let newWeight = te.weight + increment
                updated.exercises[index].weight = newWeight
                updated.exercises[index].failureCount = 0
                changes.append(ProgressionChange(
                    exerciseID: te.exerciseID,
                    name: te.name,
                    fromWeight: te.weight,
                    toWeight: newWeight,
                    kind: .increase
                ))
            } else {
                let failures = te.failureCount + 1
                if failures >= max(1, failureThreshold) {
                    let newWeight = deloadedWeight(te.weight, percent: deloadPercent, roundTo: increment)
                    updated.exercises[index].weight = newWeight
                    updated.exercises[index].failureCount = 0
                    changes.append(ProgressionChange(
                        exerciseID: te.exerciseID,
                        name: te.name,
                        fromWeight: te.weight,
                        toWeight: newWeight,
                        kind: .deload
                    ))
                } else {
                    updated.exercises[index].failureCount = failures
                }
            }
        }
        return (updated, changes)
    }
}
