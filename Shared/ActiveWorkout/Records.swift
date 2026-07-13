import Foundation

/// Per-exercise personal records computed from history. Completed work sets
/// only — warmups never count. Pure and testable.
struct ExerciseRecords: Identifiable, Equatable {
    var id: UUID { exerciseID }
    let exerciseID: UUID
    let name: String
    /// Heaviest completed work set (ties broken by reps).
    let maxWeight: Double
    let repsAtMaxWeight: Int
    /// Best Epley-estimated one-rep max across all sets.
    let best1RM: Double
    /// Highest single-session volume for this exercise.
    let maxSessionVolume: Double
}

/// Which records a just-finished session broke, for the celebration UI.
struct PRHighlight: Identifiable, Equatable {
    var id: UUID { exerciseID }
    let exerciseID: UUID
    let name: String
    /// Human-readable record kinds, e.g. ["Weight", "1RM"].
    let kinds: [String]
}

enum Records {
    /// Epley formula. Reps ≤ 1 returns the weight itself.
    static func epley1RM(weight: Double, reps: Int) -> Double {
        guard reps > 1 else { return weight }
        return weight * (1 + Double(reps) / 30)
    }

    /// All-time records per exercise, sorted by name.
    static func all(history: [WorkoutSession]) -> [ExerciseRecords] {
        var byExercise: [UUID: ExerciseRecords] = [:]

        for session in history where session.isFinished {
            for ex in session.exercises where ex.usesWeight {
                let workSets = ex.sets.filter { $0.isCompleted && !$0.isWarmup && $0.weight > 0 }
                guard !workSets.isEmpty else { continue }

                let bestSet = workSets.max {
                    ($0.weight, $0.reps) < ($1.weight, $1.reps)
                }!
                let best1RM = workSets.map { epley1RM(weight: $0.weight, reps: $0.reps) }.max()!
                let sessionVolume = workSets.reduce(0) { $0 + Double($1.reps) * $1.weight }

                if let existing = byExercise[ex.exerciseID] {
                    byExercise[ex.exerciseID] = ExerciseRecords(
                        exerciseID: ex.exerciseID,
                        name: ex.name,
                        maxWeight: max(existing.maxWeight, bestSet.weight),
                        repsAtMaxWeight: bestSet.weight > existing.maxWeight ? bestSet.reps
                            : (bestSet.weight == existing.maxWeight ? max(existing.repsAtMaxWeight, bestSet.reps) : existing.repsAtMaxWeight),
                        best1RM: max(existing.best1RM, best1RM),
                        maxSessionVolume: max(existing.maxSessionVolume, sessionVolume)
                    )
                } else {
                    byExercise[ex.exerciseID] = ExerciseRecords(
                        exerciseID: ex.exerciseID,
                        name: ex.name,
                        maxWeight: bestSet.weight,
                        repsAtMaxWeight: bestSet.reps,
                        best1RM: best1RM,
                        maxSessionVolume: sessionVolume
                    )
                }
            }
        }
        return byExercise.values.sorted { $0.name < $1.name }
    }

    /// Records this session broke relative to PRIOR history (pass history
    /// without the session itself). Empty when nothing was beaten.
    static func newPRs(session: WorkoutSession, priorHistory: [WorkoutSession]) -> [PRHighlight] {
        let before = Dictionary(uniqueKeysWithValues: all(history: priorHistory).map { ($0.exerciseID, $0) })
        let after = all(history: priorHistory + [session])

        var highlights: [PRHighlight] = []
        for record in after {
            guard session.exercises.contains(where: { $0.exerciseID == record.exerciseID }) else { continue }
            var kinds: [String] = []
            if let old = before[record.exerciseID] {
                if record.maxWeight > old.maxWeight { kinds.append("Weight") }
                if record.best1RM > old.best1RM + 0.001 { kinds.append("1RM") }
                if record.maxSessionVolume > old.maxSessionVolume + 0.001 { kinds.append("Volume") }
            } else if record.maxWeight > 0 {
                kinds = ["First"]
            }
            if !kinds.isEmpty {
                highlights.append(PRHighlight(exerciseID: record.exerciseID, name: record.name, kinds: kinds))
            }
        }
        return highlights.sorted { $0.name < $1.name }
    }
}
