import Foundation

/// A single logged set within a session.
struct SetEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var reps: Int
    /// The planned repetitions. `reps` may be adjusted to record an actual
    /// partial set while this remains the reference for adaptive recovery.
    var targetReps: Int
    var weight: Double
    var isCompleted: Bool
    var isWarmup: Bool

    init(
        id: UUID = UUID(),
        reps: Int,
        targetReps: Int? = nil,
        weight: Double,
        isCompleted: Bool = false,
        isWarmup: Bool = false
    ) {
        self.id = id
        self.reps = reps
        self.targetReps = targetReps ?? reps
        self.weight = weight
        self.isCompleted = isCompleted
        self.isWarmup = isWarmup
    }

    private enum CodingKeys: String, CodingKey {
        case id, reps, targetReps, weight, isCompleted, isWarmup
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        reps = try c.decode(Int.self, forKey: .reps)
        targetReps = try c.decodeIfPresent(Int.self, forKey: .targetReps) ?? reps
        weight = try c.decode(Double.self, forKey: .weight)
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        isWarmup = try c.decodeIfPresent(Bool.self, forKey: .isWarmup) ?? false
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
    /// Captured at workout start so editors on both devices use the same
    /// wording and behavior without needing to look up the exercise library.
    var loadingMode: LoadingMode

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        name: String,
        sets: [SetEntry],
        restSeconds: Int = 180,
        usesWeight: Bool = true,
        loadingMode: LoadingMode = .direct
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.name = name
        self.sets = sets
        self.restSeconds = restSeconds
        self.usesWeight = usesWeight
        self.loadingMode = loadingMode
    }

    private enum CodingKeys: String, CodingKey {
        case id, exerciseID, name, sets, restSeconds, usesWeight, loadingMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        exerciseID = try c.decode(UUID.self, forKey: .exerciseID)
        name = try c.decode(String.self, forKey: .name)
        sets = try c.decode([SetEntry].self, forKey: .sets)
        restSeconds = try c.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 180
        usesWeight = try c.decodeIfPresent(Bool.self, forKey: .usesWeight) ?? true
        loadingMode = try c.decodeIfPresent(LoadingMode.self, forKey: .loadingMode) ?? .direct
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
    /// Free-text session note ("felt heavy", "new gym"…).
    var notes: String

    init(
        id: UUID = UUID(),
        templateID: UUID? = nil,
        name: String,
        category: WorkoutCategory = .custom,
        exercises: [SessionExercise] = [],
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.templateID = templateID
        self.name = name
        self.category = category
        self.exercises = exercises
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.notes = notes
    }

    // Manual decode so history saved before notes existed still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        templateID = try c.decodeIfPresent(UUID.self, forKey: .templateID)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(WorkoutCategory.self, forKey: .category)
        exercises = try c.decode([SessionExercise].self, forKey: .exercises)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
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
            // Timed entries (cardio/stretch) are a single checkable block, no
            // weight and no warmup ramp. Rich duration tracking is handled in
            // the tracking flow; here they just need to start without breaking.
            if te.isTimed {
                return SessionExercise(
                    exerciseID: te.exerciseID,
                    name: te.name,
                    sets: [SetEntry(reps: 0, weight: 0)],
                    restSeconds: 0,
                    usesWeight: false,
                    loadingMode: .direct
                )
            }
            let loadingMode = library[te.exerciseID]?.loadingMode ?? .direct
            let usesWeight = loadingMode == .bodyweight
                ? te.tracksAddedBodyweight
                : (library[te.exerciseID]?.usesWeight ?? true)
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
                SetEntry(
                    reps: te.targetReps,
                    weight: loadingMode == .bodyweight && !te.tracksAddedBodyweight ? 0 : te.weight
                )
            }
            return SessionExercise(
                exerciseID: te.exerciseID,
                name: te.name,
                sets: sets,
                restSeconds: te.restSeconds,
                usesWeight: usesWeight,
                loadingMode: loadingMode
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
