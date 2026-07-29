import Foundation

/// A single logged set within a session.
struct SetEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var reps: Int
    /// The planned repetitions. `reps` may be adjusted to record an actual
    /// partial set while this remains the reference for adaptive recovery.
    var targetReps: Int
    var weight: Double
    /// Target duration for timed work. Zero means this is a rep-based set.
    var durationSeconds: Int
    var isCompleted: Bool
    var isWarmup: Bool

    init(
        id: UUID = UUID(),
        reps: Int,
        targetReps: Int? = nil,
        weight: Double,
        durationSeconds: Int = 0,
        isCompleted: Bool = false,
        isWarmup: Bool = false
    ) {
        self.id = id
        self.reps = reps
        self.targetReps = targetReps ?? reps
        self.weight = weight
        self.durationSeconds = max(0, durationSeconds)
        self.isCompleted = isCompleted
        self.isWarmup = isWarmup
    }

    private enum CodingKeys: String, CodingKey {
        case id, reps, targetReps, weight, durationSeconds, isCompleted, isWarmup
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        reps = try c.decode(Int.self, forKey: .reps)
        targetReps = try c.decodeIfPresent(Int.self, forKey: .targetReps) ?? reps
        weight = try c.decode(Double.self, forKey: .weight)
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0
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
    /// Which routine phase this exercise belongs to, as an index into
    /// `WorkoutSession.phases`. `nil` for plain single-template sessions, which
    /// have no phases and navigate across the whole list.
    var phaseIndex: Int?

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        name: String,
        sets: [SetEntry],
        restSeconds: Int = 180,
        usesWeight: Bool = true,
        loadingMode: LoadingMode = .direct,
        phaseIndex: Int? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.name = name
        self.sets = sets
        self.restSeconds = restSeconds
        self.usesWeight = usesWeight
        self.loadingMode = loadingMode
        self.phaseIndex = phaseIndex
    }

    private enum CodingKeys: String, CodingKey {
        case id, exerciseID, name, sets, restSeconds, usesWeight, loadingMode, phaseIndex
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
        phaseIndex = try c.decodeIfPresent(Int.self, forKey: .phaseIndex)
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

    /// Optional link to the GymSessionRoutine if started from a multi-phase routine.
    var routineID: UUID?
    /// Multi-phase breakdown for complex gym visits (cardio, warm-up, lifting, stretch, core, sauna, steam).
    var phases: [GymSessionLogPhase]
    /// Index of the current active phase during a multi-phase session.
    var currentPhaseIndex: Int
    /// Start of the phase currently in progress. This lives in the replicated
    /// session rather than in a device-local manager so ownership handoffs and
    /// relaunches preserve accurate per-phase elapsed time.
    var currentPhaseStartedAt: Date

    init(
        id: UUID = UUID(),
        templateID: UUID? = nil,
        routineID: UUID? = nil,
        name: String,
        category: WorkoutCategory = .custom,
        exercises: [SessionExercise] = [],
        phases: [GymSessionLogPhase] = [],
        currentPhaseIndex: Int = 0,
        currentPhaseStartedAt: Date? = nil,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.templateID = templateID
        self.routineID = routineID
        self.name = name
        self.category = category
        self.exercises = exercises
        self.phases = phases
        self.currentPhaseIndex = currentPhaseIndex
        self.currentPhaseStartedAt = currentPhaseStartedAt ?? startedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, templateID, routineID, name, category, exercises, phases
        case currentPhaseIndex, currentPhaseStartedAt, startedAt, finishedAt, notes
    }

    // Manual decode so history saved before notes/phases existed still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        templateID = try c.decodeIfPresent(UUID.self, forKey: .templateID)
        routineID = try c.decodeIfPresent(UUID.self, forKey: .routineID)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(WorkoutCategory.self, forKey: .category)
        exercises = try c.decode([SessionExercise].self, forKey: .exercises)
        phases = try c.decodeIfPresent([GymSessionLogPhase].self, forKey: .phases) ?? []
        currentPhaseIndex = try c.decodeIfPresent(Int.self, forKey: .currentPhaseIndex) ?? 0
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        currentPhaseStartedAt = try c.decodeIfPresent(Date.self, forKey: .currentPhaseStartedAt) ?? startedAt
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    var isFinished: Bool { finishedAt != nil }
    var isMultiPhase: Bool { !phases.isEmpty }

    var currentPhase: GymSessionLogPhase? {
        guard phases.indices.contains(currentPhaseIndex) else { return nil }
        return phases[currentPhaseIndex]
    }

    // MARK: - Phase-scoped exercise access

    /// Indices into `exercises` belonging to the given phase.
    ///
    /// A single-template session has no phases, so every exercise is in scope —
    /// that keeps plain workouts navigating across the whole list as before.
    func exerciseIndices(inPhase phaseIndex: Int) -> [Int] {
        guard isMultiPhase else { return Array(exercises.indices) }
        return exercises.indices.filter { exercises[$0].phaseIndex == phaseIndex }
    }

    /// Indices into `exercises` belonging to the phase currently in progress.
    var currentPhaseExerciseIndices: [Int] {
        guard isMultiPhase else { return Array(exercises.indices) }
        return exerciseIndices(inPhase: currentPhaseIndex)
    }

    /// Position of `index` within the current phase's exercise scope, or `nil`
    /// when it belongs to a different phase.
    ///
    /// Navigation availability and the navigation actions themselves must agree
    /// on what "next" means, so both are derived from this one function. Asking
    /// the flat `exercises` array instead is what made navigation controls stay
    /// enabled at a phase boundary while doing nothing (#90).
    func positionInCurrentPhase(of index: Int) -> Int? {
        currentPhaseExerciseIndices.firstIndex(of: index)
    }

    /// True when the current phase holds a further exercise after `index`.
    func hasNextExerciseInCurrentPhase(after index: Int) -> Bool {
        guard let position = positionInCurrentPhase(of: index) else { return false }
        return position + 1 < currentPhaseExerciseIndices.count
    }

    /// True when the current phase holds an earlier exercise before `index`.
    func hasPreviousExerciseInCurrentPhase(before index: Int) -> Bool {
        guard let position = positionInCurrentPhase(of: index) else { return false }
        return position > 0
    }

    /// True when a later phase exists. Always false for a single-template
    /// session, which has no phases to advance through.
    var hasNextPhase: Bool {
        isMultiPhase && currentPhaseIndex + 1 < phases.count
    }

    /// Where navigation should land when a phase becomes current: its first
    /// unfinished exercise, or its first exercise when everything is done.
    func landingExerciseIndex(forPhase phaseIndex: Int) -> Int? {
        let indices = exerciseIndices(inPhase: phaseIndex)
        return indices.first(where: { !exercises[$0].isComplete }) ?? indices.first
    }

    /// Exercises belonging to the given phase, derived from the flat list.
    func exercises(inPhase phaseIndex: Int) -> [SessionExercise] {
        exerciseIndices(inPhase: phaseIndex).map { exercises[$0] }
    }

    /// How a phase should be tracked in Health. Exercises pulled from a linked
    /// template identify the machine more reliably than the routine's declared
    /// names, so they are consulted first.
    func activityKind(forPhase phaseIndex: Int) -> PhaseActivityKind {
        guard phases.indices.contains(phaseIndex) else { return .traditionalStrengthTraining }
        let phase = phases[phaseIndex]
        let names = exercises(inPhase: phaseIndex).map(\.name) + phase.exerciseNames
        return PhaseActivityKind.resolve(phaseType: phase.phaseType, exerciseNames: names)
    }

    /// Activity kind for the phase currently in progress, or plain strength
    /// training for a single-template session.
    var currentActivityKind: PhaseActivityKind {
        guard isMultiPhase else { return .traditionalStrengthTraining }
        return activityKind(forPhase: currentPhaseIndex)
    }

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

    /// Reorders only the exercise instances in this session. Each instance,
    /// including its logged sets and completion state, travels intact. This is
    /// deliberately separate from `WorkoutTemplate` so a one-day order never
    /// rewrites the saved routine.
    mutating func moveExercises(from source: IndexSet, to destination: Int) {
        guard exercises.count > 1, !source.isEmpty else { return }
        let moving = source.compactMap { exercises.indices.contains($0) ? exercises[$0] : nil }
        guard !moving.isEmpty else { return }

        var remaining = exercises.enumerated()
            .filter { !source.contains($0.offset) }
            .map(\.element)
        let removedBeforeDestination = source.filter { $0 < destination }.count
        let insertionIndex = min(
            max(0, destination - removedBeforeDestination),
            remaining.count
        )
        remaining.insert(contentsOf: moving, at: insertionIndex)
        exercises = remaining
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
                    sets: [SetEntry(reps: 0, weight: 0, durationSeconds: te.durationSeconds)],
                    restSeconds: 0,
                    usesWeight: false,
                    loadingMode: .direct
                )
            }
            let loadingMode = library[te.exerciseID]?.loadingMode ?? .direct
            let usesWeight = loadingMode == .bodyweight
                ? te.tracksAddedBodyweight
                : (library[te.exerciseID]?.usesWeight ?? true)
            let configuredBar = settings.map {
                $0.barWeight ?? Warmup.defaultBarWeight(units: $0.units)
            } ?? 0
            let workingWeight = loadingMode == .barbell
                ? max(te.weight, configuredBar)
                : te.weight
            var sets: [SetEntry] = []
            if let settings, settings.warmupsEnabled, loadingMode == .barbell {
                sets = Warmup.sets(
                    workingWeight: workingWeight,
                    units: settings.units,
                    barWeight: settings.barWeight,
                    roundTo: settings.weightIncrement
                )
            }
            sets += (0..<max(1, te.targetSets)).map { _ in
                SetEntry(
                    reps: te.targetReps,
                    weight: loadingMode == .bodyweight && !te.tracksAddedBodyweight ? 0 : workingWeight
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

    /// Builds a fresh multi-phase `WorkoutSession` from a `GymSessionRoutine`.
    static func from(
        routine: GymSessionRoutine,
        templates: [WorkoutTemplate],
        library: [UUID: Exercise],
        settings: AppSettings? = nil
    ) -> WorkoutSession {
        var allExercises: [SessionExercise] = []
        var logPhases: [GymSessionLogPhase] = []

        for phase in routine.enabledPhases {
            let phaseIndex = logPhases.count
            var phaseExercises: [SessionExercise] = []
            // Any phase may link a template, not just main strength — cardio,
            // warm-up, cool-down and recovery phases are composable too. Core
            // work falls back to built-in defaults only when nothing is linked.
            if let templateID = phase.templateID, let template = templates.first(where: { $0.id == templateID }) {
                let templateSession = WorkoutSession.from(template: template, library: library, settings: settings)
                phaseExercises = templateSession.exercises
            } else if phase.phaseType == .coreWork {
                // Pre-populate default core exercises if available
                let coreNames = phase.exerciseNames.isEmpty ? ["Plank", "Ab Rollout", "Hanging Knee Raise", "Cable Crunch"] : phase.exerciseNames
                for name in coreNames {
                    let matchingLib = library.values.first(where: { $0.name.lowercased() == name.lowercased() })
                    let exID = matchingLib?.id ?? UUID()
                    let isTimedCore = matchingLib?.isTimed ?? (name.lowercased().contains("plank"))
                    let set = isTimedCore ? SetEntry(reps: 0, weight: 0) : SetEntry(reps: 15, weight: 0)
                    phaseExercises.append(SessionExercise(
                        exerciseID: exID,
                        name: name,
                        sets: [set, set, set],
                        restSeconds: settings?.defaultRestSeconds ?? 60,
                        usesWeight: false,
                        loadingMode: .bodyweight
                    ))
                }
            }

            // Stamp phase attribution so the flat `exercises` array stays the
            // single source of truth while still knowing which phase owns what.
            for i in phaseExercises.indices {
                phaseExercises[i].phaseIndex = phaseIndex
            }

            allExercises.append(contentsOf: phaseExercises)
            logPhases.append(GymSessionLogPhase(
                phaseType: phase.phaseType,
                name: phase.name,
                durationSeconds: phase.durationSeconds,
                exerciseItems: phase.exerciseItems,
                notes: phase.notes
            ))
        }

        return WorkoutSession(
            routineID: routine.id,
            name: routine.name,
            category: .fullBody,
            exercises: allExercises,
            phases: logPhases,
            currentPhaseIndex: 0
        )
    }
}
