import Foundation

/// One exercise whose working weight was bumped after a successful session.
struct ProgressionChange: Identifiable, Equatable {
    var id: UUID { exerciseID }
    let exerciseID: UUID
    let name: String
    let fromWeight: Double
    let toWeight: Double
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

    /// True when the logged exercise hit every target rep in every set.
    static func isSuccessful(_ logged: SessionExercise, targetReps: Int) -> Bool {
        guard !logged.sets.isEmpty else { return false }
        return logged.sets.allSatisfy { $0.isCompleted && $0.reps >= targetReps }
    }

    /// Applies progression from a finished session to its template.
    /// Returns the updated template plus the list of bumps (empty when the
    /// session doesn't belong to this template or nothing succeeded).
    static func apply(
        session: WorkoutSession,
        to template: WorkoutTemplate,
        units: AppSettings.Units
    ) -> (template: WorkoutTemplate, changes: [ProgressionChange]) {
        guard session.templateID == template.id else { return (template, []) }

        var updated = template
        var changes: [ProgressionChange] = []

        for (index, te) in template.exercises.enumerated() {
            guard te.progressionEnabled else { continue }
            guard let logged = session.exercises.first(where: { $0.exerciseID == te.exerciseID }) else { continue }
            guard logged.usesWeight else { continue }
            guard isSuccessful(logged, targetReps: te.targetReps) else { continue }

            let increment = te.progressionIncrement
                ?? defaultIncrement(exerciseName: te.name, units: units)
            let newWeight = te.weight + increment
            updated.exercises[index].weight = newWeight
            changes.append(ProgressionChange(
                exerciseID: te.exerciseID,
                name: te.name,
                fromWeight: te.weight,
                toWeight: newWeight
            ))
        }
        return (updated, changes)
    }
}
