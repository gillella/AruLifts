import Foundation

/// Phone settings needed while the Watch owns a workout. This travels with the
/// cached plans so the Watch never guesses units, plates, or rest behavior.
struct WatchExecutionSettings: Codable, Hashable {
    var units: AppSettings.Units
    var barWeight: Double
    var availablePlates: [Double]
    var autoStartRest: Bool
    var restAlertsEnabled: Bool
    var adaptiveRestEnabled: Bool
    var failedSetRestMultiplier: Double

    init(settings: AppSettings = AppSettings()) {
        units = settings.units
        barWeight = settings.barWeight ?? Warmup.defaultBarWeight(units: settings.units)
        availablePlates = settings.plateSet ?? PlateCalculator.defaultPlates(units: settings.units)
        autoStartRest = settings.autoStartRest
        restAlertsEnabled = settings.restAlertsEnabled
        adaptiveRestEnabled = settings.adaptiveRestEnabled
        failedSetRestMultiplier = settings.failedSetRestMultiplier
    }
}

/// A set stored in the Watch's offline plan cache.
///
/// Cached identifiers are useful for rendering stable lists, but are never
/// reused by `makeFreshSession(at:)`.
struct WatchStartableSet: Identifiable, Codable, Hashable {
    var id: UUID
    var reps: Int
    var weight: Double
    var isWarmup: Bool

    init(
        id: UUID = UUID(),
        reps: Int,
        weight: Double,
        isWarmup: Bool = false
    ) {
        self.id = id
        self.reps = reps
        self.weight = weight
        self.isWarmup = isWarmup
    }
}

/// An exercise stored in a startable Watch plan.
struct WatchStartableExercise: Identifiable, Codable, Hashable {
    var id: UUID
    var exerciseID: UUID
    var name: String
    var sets: [WatchStartableSet]
    var restSeconds: Int
    var usesWeight: Bool
    /// Target duration for cardio and mobility entries. Zero means set/rep
    /// tracking; a positive value represents one checkable timed block.
    var durationSeconds: Int

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        name: String,
        sets: [WatchStartableSet],
        restSeconds: Int,
        usesWeight: Bool,
        durationSeconds: Int = 0
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.name = name
        self.sets = sets
        self.restSeconds = restSeconds
        self.usesWeight = usesWeight
        self.durationSeconds = durationSeconds
    }

    var isTimed: Bool { durationSeconds > 0 }
}

/// A complete workout that the Watch can start without consulting the phone.
///
/// The template identifier remains stable so a finished session can still be
/// associated with (and progress) its originating phone template.
struct WatchStartableWorkout: Identifiable, Codable, Hashable {
    var templateID: UUID
    var name: String
    var category: WorkoutCategory
    var exercises: [WatchStartableExercise]
    var notes: String

    var id: UUID { templateID }

    init(
        templateID: UUID,
        name: String,
        category: WorkoutCategory,
        exercises: [WatchStartableExercise],
        notes: String = ""
    ) {
        self.templateID = templateID
        self.name = name
        self.category = category
        self.exercises = exercises
        self.notes = notes
    }

    /// Snapshots a template and every setting needed to start it offline.
    init(
        template: WorkoutTemplate,
        library: [UUID: Exercise],
        settings: AppSettings
    ) {
        templateID = template.id
        name = template.name
        category = template.category
        notes = template.notes
        exercises = template.exercises.map { templateExercise in
            if templateExercise.isTimed {
                return WatchStartableExercise(
                    exerciseID: templateExercise.exerciseID,
                    name: templateExercise.name,
                    sets: [WatchStartableSet(reps: 0, weight: 0)],
                    restSeconds: 0,
                    usesWeight: false,
                    durationSeconds: templateExercise.durationSeconds
                )
            }

            let usesWeight = library[templateExercise.exerciseID]?.usesWeight ?? true
            var sets: [WatchStartableSet] = []

            if settings.warmupsEnabled, usesWeight {
                sets = Warmup.sets(
                    workingWeight: templateExercise.weight,
                    units: settings.units,
                    barWeight: settings.barWeight,
                    roundTo: settings.weightIncrement
                ).map {
                    WatchStartableSet(
                        id: $0.id,
                        reps: $0.reps,
                        weight: $0.weight,
                        isWarmup: $0.isWarmup
                    )
                }
            }

            sets += (0..<max(1, templateExercise.targetSets)).map { _ in
                WatchStartableSet(
                    reps: templateExercise.targetReps,
                    weight: templateExercise.weight
                )
            }

            return WatchStartableExercise(
                exerciseID: templateExercise.exerciseID,
                name: templateExercise.name,
                sets: sets,
                restSeconds: templateExercise.restSeconds,
                usesWeight: usesWeight
            )
        }
    }

    static func from(
        template: WorkoutTemplate,
        library: [UUID: Exercise],
        settings: AppSettings
    ) -> WatchStartableWorkout {
        WatchStartableWorkout(
            template: template,
            library: library,
            settings: settings
        )
    }

    /// Creates a distinct workout attempt from the cached plan.
    ///
    /// All transient identifiers are regenerated so starting the same cached
    /// plan twice cannot collide in history or live-workout replication.
    func makeFreshSession(at startedAt: Date = Date()) -> WorkoutSession {
        WorkoutSession(
            id: UUID(),
            templateID: templateID,
            name: name,
            category: category,
            exercises: exercises.map { cachedExercise in
                SessionExercise(
                    id: UUID(),
                    exerciseID: cachedExercise.exerciseID,
                    name: cachedExercise.name,
                    sets: cachedExercise.sets.map { cachedSet in
                        SetEntry(
                            id: UUID(),
                            reps: cachedSet.reps,
                            weight: cachedSet.weight,
                            isCompleted: false,
                            isWarmup: cachedSet.isWarmup
                        )
                    },
                    restSeconds: cachedExercise.restSeconds,
                    usesWeight: cachedExercise.usesWeight
                )
            },
            startedAt: startedAt,
            finishedAt: nil,
            notes: ""
        )
    }
}

/// Versioned snapshot of the plans available for offline Watch starts.
///
/// Revisions are assigned by the phone and only move forward. Receivers can
/// compare caches directly or inspect `revision` to reject stale deliveries.
struct WatchPlanCache: Codable, Hashable, Comparable {
    var revision: UInt64
    var workouts: [WatchStartableWorkout]
    var executionSettings: WatchExecutionSettings
    var updatedAt: Date

    /// Alias for callers that describe the cached workouts as plans.
    var plans: [WatchStartableWorkout] {
        get { workouts }
        set { workouts = newValue }
    }

    init(
        revision: UInt64 = 0,
        workouts: [WatchStartableWorkout] = [],
        executionSettings: WatchExecutionSettings = WatchExecutionSettings(),
        updatedAt: Date = Date()
    ) {
        self.revision = revision
        self.workouts = workouts
        self.executionSettings = executionSettings
        self.updatedAt = updatedAt
    }

    init(
        revision: UInt64,
        plans: [WatchStartableWorkout],
        executionSettings: WatchExecutionSettings = WatchExecutionSettings(),
        updatedAt: Date = Date()
    ) {
        self.init(
            revision: revision, workouts: plans,
            executionSettings: executionSettings, updatedAt: updatedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case revision, workouts, executionSettings, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        revision = try c.decodeIfPresent(UInt64.self, forKey: .revision) ?? 0
        workouts = try c.decodeIfPresent([WatchStartableWorkout].self, forKey: .workouts) ?? []
        executionSettings = try c.decodeIfPresent(
            WatchExecutionSettings.self, forKey: .executionSettings
        ) ?? WatchExecutionSettings()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    static func < (lhs: WatchPlanCache, rhs: WatchPlanCache) -> Bool {
        lhs.revision < rhs.revision
    }

    func isNewer(than other: WatchPlanCache) -> Bool {
        revision > other.revision
    }

    /// Returns the next cache snapshot without allowing integer wraparound to
    /// make a newer cache appear older.
    func advanced(
        workouts: [WatchStartableWorkout],
        executionSettings: WatchExecutionSettings,
        at date: Date = Date()
    ) -> WatchPlanCache {
        WatchPlanCache(
            revision: revision == .max ? .max : revision + 1,
            workouts: workouts,
            executionSettings: executionSettings,
            updatedAt: date
        )
    }
}
