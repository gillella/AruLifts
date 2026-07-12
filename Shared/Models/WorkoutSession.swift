import Foundation

/// A single logged set within a session.
struct SetEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var reps: Int
    var weight: Double
    var isCompleted: Bool
    var isWarmup: Bool

    init(
        id: UUID = UUID(),
        reps: Int,
        weight: Double,
        isCompleted: Bool = false,
        isWarmup: Bool = false
    ) {
        self.id = id
        self.reps = reps
        self.weight = weight
        self.isCompleted = isCompleted
        self.isWarmup = isWarmup
    }
}

/// An exercise instance inside an active or completed session, with its sets.
struct SessionExercise: Identifiable, Codable, Hashable {
    var id: UUID
    var exerciseID: UUID
    var name: String
    var sets: [SetEntry]
    var restSeconds: Int
    var usesWeight: Bool

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        name: String,
        sets: [SetEntry],
        restSeconds: Int = 180,
        usesWeight: Bool = true
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.name = name
        self.sets = sets
        self.restSeconds = restSeconds
        self.usesWeight = usesWeight
    }

    var completedSets: Int { sets.filter { $0.isCompleted }.count }
    var isComplete: Bool { !sets.isEmpty && sets.allSatisfy { $0.isCompleted } }
    /// Work sets only — warmups don't count toward training volume.
    var volume: Double {
        sets.filter { $0.isCompleted && !$0.isWarmup }
            .reduce(0) { $0 + Double($1.reps) * $1.weight }
    }
}

/// A workout in progress or finished. The phone owns history; both phone and
/// watch mutate the live copy and keep it in sync via `ConnectivityManager`.
struct WorkoutSession: Identifiable, Codable, Hashable {
    var id: UUID
    var templateID: UUID?
    var name: String
    var category: WorkoutCategory
    var exercises: [SessionExercise]
    var startedAt: Date
    var finishedAt: Date?

    init(
        id: UUID = UUID(),
        templateID: UUID? = nil,
        name: String,
        category: WorkoutCategory = .custom,
        exercises: [SessionExercise] = [],
        startedAt: Date = Date(),
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.templateID = templateID
        self.name = name
        self.category = category
        self.exercises = exercises
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    var isFinished: Bool { finishedAt != nil }

    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }
    var completedSets: Int { exercises.reduce(0) { $0 + $1.completedSets } }
    var totalVolume: Double { exercises.reduce(0) { $0 + $1.volume } }

    var durationSeconds: TimeInterval {
        (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var progress: Double {
        guard totalSets > 0 else { return 0 }
        return Double(completedSets) / Double(totalSets)
    }

    /// Builds a fresh session from a template, pre-populating each set.
    /// Pass `settings` to prepend generated warmup sets (when enabled) for
    /// weighted exercises.
    static func from(
        template: WorkoutTemplate,
        library: [UUID: Exercise],
        settings: AppSettings? = nil
    ) -> WorkoutSession {
        let exercises = template.exercises.map { te -> SessionExercise in
            let usesWeight = library[te.exerciseID]?.usesWeight ?? true
            var sets: [SetEntry] = []
            if let settings, settings.warmupsEnabled, usesWeight {
                sets = Warmup.sets(
                    workingWeight: te.weight,
                    units: settings.units,
                    barWeight: settings.barWeight,
                    roundTo: settings.weightIncrement
                )
            }
            sets += (0..<max(1, te.targetSets)).map { _ in
                SetEntry(reps: te.targetReps, weight: te.weight)
            }
            return SessionExercise(
                exerciseID: te.exerciseID,
                name: te.name,
                sets: sets,
                restSeconds: te.restSeconds,
                usesWeight: usesWeight
            )
        }
        return WorkoutSession(
            templateID: template.id,
            name: template.name,
            category: template.category,
            exercises: exercises
        )
    }
}
