import Foundation

/// Phone settings needed while the Watch owns a workout. This travels with the
/// cached plans so the Watch never guesses units, plates, or rest behavior.
struct WatchExecutionSettings: Codable, Hashable {
    var units: AppSettings.Units
    var barWeight: Double
    var availablePlates: [Double]
    var weightIncrement: Double
    var autoStartRest: Bool
    var restAlertsEnabled: Bool
    var restAlertStyle: RestAlertStyle
    var earlyRestCueEnabled: Bool
    var earlyRestCueLeadSeconds: Int
    var phaseCueEnabled: Bool
    var phaseCueLeadSeconds: Int
    var adaptiveRestEnabled: Bool
    var failedSetRestMultiplier: Double

    init(settings: AppSettings = AppSettings()) {
        units = settings.units
        barWeight = settings.barWeight ?? Warmup.defaultBarWeight(units: settings.units)
        availablePlates = settings.plateSet ?? PlateCalculator.defaultPlates(units: settings.units)
        weightIncrement = settings.weightIncrement
        autoStartRest = settings.autoStartRest
        restAlertsEnabled = settings.restAlertsEnabled
        restAlertStyle = settings.restAlertStyle
        earlyRestCueEnabled = settings.earlyRestCueEnabled
        earlyRestCueLeadSeconds = settings.earlyRestCueLeadSeconds
        phaseCueEnabled = settings.phaseCueEnabled
        phaseCueLeadSeconds = settings.phaseCueLeadSeconds
        adaptiveRestEnabled = settings.adaptiveRestEnabled
        failedSetRestMultiplier = settings.failedSetRestMultiplier
    }

    private enum CodingKeys: String, CodingKey {
        case units, barWeight, availablePlates, weightIncrement, autoStartRest, restAlertsEnabled
        case restAlertStyle, earlyRestCueEnabled, earlyRestCueLeadSeconds
        case phaseCueEnabled, phaseCueLeadSeconds
        case adaptiveRestEnabled, failedSetRestMultiplier
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        units = try c.decodeIfPresent(AppSettings.Units.self, forKey: .units) ?? .kg
        barWeight = try c.decodeIfPresent(Double.self, forKey: .barWeight) ?? Warmup.defaultBarWeight(units: units)
        availablePlates = try c.decodeIfPresent([Double].self, forKey: .availablePlates) ?? PlateCalculator.defaultPlates(units: units)
        weightIncrement = try c.decodeIfPresent(Double.self, forKey: .weightIncrement) ?? 2.5
        autoStartRest = try c.decodeIfPresent(Bool.self, forKey: .autoStartRest) ?? true
        restAlertsEnabled = try c.decodeIfPresent(Bool.self, forKey: .restAlertsEnabled) ?? true
        restAlertStyle = try c.decodeIfPresent(RestAlertStyle.self, forKey: .restAlertStyle) ?? .soundAndHaptic
        earlyRestCueEnabled = try c.decodeIfPresent(Bool.self, forKey: .earlyRestCueEnabled) ?? true
        earlyRestCueLeadSeconds = try c.decodeIfPresent(Int.self, forKey: .earlyRestCueLeadSeconds) ?? 10
        phaseCueEnabled = try c.decodeIfPresent(Bool.self, forKey: .phaseCueEnabled) ?? true
        phaseCueLeadSeconds = try c.decodeIfPresent(Int.self, forKey: .phaseCueLeadSeconds) ?? 30
        adaptiveRestEnabled = try c.decodeIfPresent(Bool.self, forKey: .adaptiveRestEnabled) ?? true
        failedSetRestMultiplier = try c.decodeIfPresent(Double.self, forKey: .failedSetRestMultiplier) ?? 1.5
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
    var durationSeconds: Int
    var isWarmup: Bool

    init(
        id: UUID = UUID(),
        reps: Int,
        weight: Double,
        durationSeconds: Int = 0,
        isWarmup: Bool = false
    ) {
        self.id = id
        self.reps = reps
        self.weight = weight
        self.durationSeconds = max(0, durationSeconds)
        self.isWarmup = isWarmup
    }

    private enum CodingKeys: String, CodingKey {
        case id, reps, weight, durationSeconds, isWarmup
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        reps = try c.decode(Int.self, forKey: .reps)
        weight = try c.decode(Double.self, forKey: .weight)
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0
        isWarmup = try c.decodeIfPresent(Bool.self, forKey: .isWarmup) ?? false
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
    var loadingMode: LoadingMode
    /// Target duration for cardio and mobility entries. Zero means set/rep
    /// tracking; a positive value represents one checkable timed block.
    var durationSeconds: Int
    /// Phase this exercise belongs to, preserved so an offline Watch start
    /// reproduces the same phase scoping the phone would have produced.
    var phaseIndex: Int?

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        name: String,
        sets: [WatchStartableSet],
        restSeconds: Int,
        usesWeight: Bool,
        loadingMode: LoadingMode = .direct,
        durationSeconds: Int = 0,
        phaseIndex: Int? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.name = name
        self.sets = sets
        self.restSeconds = restSeconds
        self.usesWeight = usesWeight
        self.loadingMode = loadingMode
        self.durationSeconds = durationSeconds
        self.phaseIndex = phaseIndex
    }

    var isTimed: Bool { durationSeconds > 0 }

    private enum CodingKeys: String, CodingKey {
        case id, exerciseID, name, sets, restSeconds, usesWeight, loadingMode, durationSeconds, phaseIndex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        exerciseID = try c.decode(UUID.self, forKey: .exerciseID)
        name = try c.decode(String.self, forKey: .name)
        sets = try c.decode([WatchStartableSet].self, forKey: .sets)
        restSeconds = try c.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 180
        usesWeight = try c.decodeIfPresent(Bool.self, forKey: .usesWeight) ?? true
        loadingMode = try c.decodeIfPresent(LoadingMode.self, forKey: .loadingMode) ?? .direct
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0
        phaseIndex = try c.decodeIfPresent(Int.self, forKey: .phaseIndex)
    }
}

/// A complete workout or gym routine that the Watch can start without consulting the phone.
///
/// The template identifier remains stable so a finished session can still be
/// associated with (and progress) its originating phone template or routine.
struct WatchStartableWorkout: Identifiable, Codable, Hashable {
    var templateID: UUID
    var routineID: UUID?
    var name: String
    var category: WorkoutCategory
    var exercises: [WatchStartableExercise]
    var phases: [GymSessionLogPhase]
    var notes: String
    var isRoutine: Bool

    var id: UUID { routineID ?? templateID }

    init(
        templateID: UUID,
        routineID: UUID? = nil,
        name: String,
        category: WorkoutCategory,
        exercises: [WatchStartableExercise],
        phases: [GymSessionLogPhase] = [],
        notes: String = "",
        isRoutine: Bool = false
    ) {
        self.templateID = templateID
        self.routineID = routineID
        self.name = name
        self.category = category
        self.exercises = exercises
        self.phases = phases
        self.notes = notes
        self.isRoutine = isRoutine
    }

    private enum CodingKeys: String, CodingKey {
        case templateID, routineID, name, category, exercises, phases, notes, isRoutine
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        templateID = try c.decode(UUID.self, forKey: .templateID)
        routineID = try c.decodeIfPresent(UUID.self, forKey: .routineID)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(WorkoutCategory.self, forKey: .category)
        exercises = try c.decode([WatchStartableExercise].self, forKey: .exercises)
        phases = try c.decodeIfPresent([GymSessionLogPhase].self, forKey: .phases) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isRoutine = try c.decodeIfPresent(Bool.self, forKey: .isRoutine) ?? false
    }

    /// Snapshots a template and every setting needed to start it offline.
    init(
        template: WorkoutTemplate,
        library: [UUID: Exercise],
        settings: AppSettings
    ) {
        templateID = template.id
        routineID = nil
        name = template.name
        category = template.category
        notes = template.notes
        phases = []
        isRoutine = false
        exercises = template.exercises.map { templateExercise in
            if templateExercise.isTimed {
                return WatchStartableExercise(
                    exerciseID: templateExercise.exerciseID,
                    name: templateExercise.name,
                    sets: [WatchStartableSet(
                        reps: 0,
                        weight: 0,
                        durationSeconds: templateExercise.durationSeconds
                    )],
                    restSeconds: 0,
                    usesWeight: false,
                    loadingMode: .direct,
                    durationSeconds: templateExercise.durationSeconds
                )
            }

            let loadingMode = library[templateExercise.exerciseID]?.loadingMode ?? .direct
            let usesWeight = loadingMode == .bodyweight
                ? templateExercise.tracksAddedBodyweight
                : (library[templateExercise.exerciseID]?.usesWeight ?? true)
            let configuredBar = settings.barWeight ?? Warmup.defaultBarWeight(units: settings.units)
            let workingWeight = loadingMode == .barbell
                ? max(templateExercise.weight, configuredBar)
                : templateExercise.weight
            var sets: [WatchStartableSet] = []

            if settings.warmupsEnabled, loadingMode == .barbell {
                sets = Warmup.sets(
                    workingWeight: workingWeight,
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
                    weight: loadingMode == .bodyweight && !templateExercise.tracksAddedBodyweight ? 0 : workingWeight
                )
            }

            return WatchStartableExercise(
                exerciseID: templateExercise.exerciseID,
                name: templateExercise.name,
                sets: sets,
                restSeconds: templateExercise.restSeconds,
                usesWeight: usesWeight,
                loadingMode: loadingMode
            )
        }
    }

    /// Snapshots a GymSessionRoutine and its exercises for offline Watch starts.
    init(
        routine: GymSessionRoutine,
        templates: [WorkoutTemplate],
        library: [UUID: Exercise],
        settings: AppSettings
    ) {
        let session = WorkoutSession.from(
            routine: routine,
            templates: templates,
            library: library,
            settings: settings
        )
        templateID = routine.id
        routineID = routine.id
        name = routine.name
        category = session.category
        notes = routine.notes
        phases = session.phases
        isRoutine = true
        exercises = session.exercises.map { sessionEx in
            WatchStartableExercise(
                id: sessionEx.id,
                exerciseID: sessionEx.exerciseID,
                name: sessionEx.name,
                sets: sessionEx.sets.map { set in
                    WatchStartableSet(
                        id: set.id,
                        reps: set.reps,
                        weight: set.weight,
                        durationSeconds: set.durationSeconds,
                        isWarmup: set.isWarmup
                    )
                },
                restSeconds: sessionEx.restSeconds,
                usesWeight: sessionEx.usesWeight,
                loadingMode: sessionEx.loadingMode,
                durationSeconds: sessionEx.sets.first?.durationSeconds ?? 0,
                phaseIndex: sessionEx.phaseIndex
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

    static func from(
        routine: GymSessionRoutine,
        templates: [WorkoutTemplate],
        library: [UUID: Exercise],
        settings: AppSettings
    ) -> WatchStartableWorkout {
        WatchStartableWorkout(
            routine: routine,
            templates: templates,
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
            templateID: isRoutine ? nil : templateID,
            routineID: isRoutine ? (routineID ?? templateID) : nil,
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
                            durationSeconds: cachedSet.durationSeconds > 0
                                ? cachedSet.durationSeconds
                                : cachedExercise.durationSeconds,
                            isCompleted: false,
                            isWarmup: cachedSet.isWarmup
                        )
                    },
                    restSeconds: cachedExercise.restSeconds,
                    usesWeight: cachedExercise.usesWeight,
                    loadingMode: cachedExercise.loadingMode,
                    phaseIndex: cachedExercise.phaseIndex
                )
            },
            phases: phases.map { phase in
                GymSessionLogPhase(
                    id: UUID(),
                    phaseType: phase.phaseType,
                    name: phase.name,
                    durationSeconds: phase.durationSeconds,
                    actualDurationSeconds: nil,
                    isCompleted: false,
                    exerciseItems: phase.exerciseItems,
                    notes: phase.notes
                )
            },
            currentPhaseIndex: 0,
            startedAt: startedAt,
            finishedAt: nil,
            notes: notes
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
