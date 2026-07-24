// Standalone assertions for Progression — compiled with the real model files.
import Foundation

var failures = 0
func expect(_ cond: Bool, _ label: String) {
    if cond { print("PASS \(label)") } else { failures += 1; print("FAIL \(label)") }
}

// History finalization is keyed by the stable app session ID. A repeated end
// event must not re-run PR detection or progression.
let historySessionID = UUID()
let recordedHistorySession = WorkoutSession(id: historySessionID, name: "Recorded", finishedAt: Date())
expect(
    !WorkoutStore.shouldRecordSession(id: historySessionID, in: [recordedHistorySession]),
    "duplicate session ID is rejected from history"
)
expect(
    WorkoutStore.shouldRecordSession(id: UUID(), in: [recordedHistorySession]),
    "new session ID is accepted into history"
)

let squatID = UUID(), dlID = UUID(), pressID = UUID(), bwID = UUID()

// Equipment metadata drives a clear loading mode rather than making every
// exercise look like a barbell.
let modeBarbell = Exercise(name: "Squat", primaryMuscle: .quads, equipment: .barbell)
let modeMachine = Exercise(name: "Press", primaryMuscle: .chest, equipment: .machine)
let modeBodyweight = Exercise(name: "Pull Up", primaryMuscle: .back, equipment: .bodyweight, usesWeight: false)
expect(modeBarbell.loadingMode == .barbell, "barbell metadata maps to total-bar loading")
expect(modeMachine.loadingMode == .direct, "machine metadata maps to direct loading")
expect(modeBodyweight.loadingMode == .bodyweight, "bodyweight metadata maps to added-load mode")

// Template: squat 5x5@100 (default inc), deadlift 1x5@140 (default), press 3x5@40 (custom inc 1.0, ), pullups bodyweight
var template = WorkoutTemplate(
    name: "A",
    exercises: [
        TemplateExercise(exerciseID: squatID, name: "Barbell Squat", targetSets: 5, targetReps: 5, weight: 100),
        TemplateExercise(exerciseID: dlID, name: "Deadlift", targetSets: 1, targetReps: 5, weight: 140),
        TemplateExercise(exerciseID: pressID, name: "Overhead Press", targetSets: 3, targetReps: 5, weight: 40, progressionIncrement: 1.0),
        TemplateExercise(exerciseID: bwID, name: "Pull Up", targetSets: 3, targetReps: 8, weight: 0),
    ]
)

func makeSession(from template: WorkoutTemplate, reps: [UUID: [Int]], completed: [UUID: [Bool]]) -> WorkoutSession {
    let exercises = template.exercises.map { te -> SessionExercise in
        let r = reps[te.exerciseID] ?? Array(repeating: te.targetReps, count: te.targetSets)
        let c = completed[te.exerciseID] ?? Array(repeating: true, count: te.targetSets)
        let sets = zip(r, c).map { SetEntry(reps: $0, weight: te.weight, isCompleted: $1) }
        return SessionExercise(exerciseID: te.exerciseID, name: te.name, sets: sets,
                               usesWeight: te.exerciseID != bwID)
    }
    return WorkoutSession(templateID: template.id, name: template.name, exercises: exercises,
                          finishedAt: Date())
}

// 1. Full success bumps all weighted exercises with correct increments (kg).
let s1 = makeSession(from: template, reps: [:], completed: [:])
let r1 = Progression.apply(session: s1, to: template, units: .kg)
expect(r1.changes.count == 3, "3 weighted exercises bumped, bodyweight skipped")
expect(r1.template.exercises[0].weight == 102.5, "squat +2.5 kg default")
expect(r1.template.exercises[1].weight == 145.0, "deadlift +5 kg default")
expect(r1.template.exercises[2].weight == 41.0, "press +1.0 custom increment")
expect(r1.template.exercises[3].weight == 0, "bodyweight exercise untouched")

// 2. lb defaults.
let r2 = Progression.apply(session: s1, to: template, units: .lb)
expect(r2.template.exercises[0].weight == 105.0, "squat +5 lb default")
expect(r2.template.exercises[1].weight == 150.0, "deadlift +10 lb default")

// 3. Missed rep on one set -> that exercise not bumped.
let s3 = makeSession(from: template, reps: [squatID: [5,5,5,5,4]], completed: [:])
let r3 = Progression.apply(session: s3, to: template, units: .kg)
expect(r3.template.exercises[0].weight == 100, "squat with missed rep stays")
expect(r3.template.exercises[1].weight == 145, "deadlift still bumps")

// 4. Uncompleted set -> not bumped.
let s4 = makeSession(from: template, reps: [:], completed: [dlID: [false]])
let r4 = Progression.apply(session: s4, to: template, units: .kg)
expect(r4.template.exercises[1].weight == 140, "uncompleted set blocks bump")

// 5. Progression disabled -> not bumped.
var t5 = template
t5.exercises[0].progressionEnabled = false
let s5 = makeSession(from: t5, reps: [:], completed: [:])
let r5 = Progression.apply(session: s5, to: t5, units: .kg)
expect(r5.template.exercises[0].weight == 100, "disabled progression stays")

// 6. Session from a different template -> no changes.
let other = WorkoutTemplate(name: "B", exercises: template.exercises)
let r6 = Progression.apply(session: s1, to: other, units: .kg)
expect(r6.changes.isEmpty, "foreign session leaves template alone")

// 7. Extra reps still succeed.
let s7 = makeSession(from: template, reps: [squatID: [5,5,5,5,8]], completed: [:])
let r7 = Progression.apply(session: s7, to: template, units: .kg)
expect(r7.template.exercises[0].weight == 102.5, "extra reps count as success")

// 8. Old JSON without progression keys decodes with defaults.
let legacyJSON = """
{"id":"\(UUID().uuidString)","exerciseID":"\(UUID().uuidString)","name":"Row",
"targetSets":3,"targetReps":5,"weight":60,"restSeconds":180}
""".data(using: .utf8)!
if let legacy = try? JSONDecoder().decode(TemplateExercise.self, from: legacyJSON) {
    expect(legacy.progressionEnabled == true, "legacy decode defaults progressionEnabled=true")
    expect(legacy.progressionIncrement == nil, "legacy decode defaults increment=nil")
} else {
    failures += 1; print("FAIL legacy JSON did not decode")
}

// --- Deload (issue #5) ---

// 9. Failures below threshold only increment the counter.
let sFail = makeSession(from: template, reps: [squatID: [5,5,5,5,3]], completed: [:])
let d1 = Progression.apply(session: sFail, to: template, units: .kg, failureThreshold: 3, deloadPercent: 10)
expect(d1.template.exercises[0].failureCount == 1, "first failure counts to 1")
expect(d1.template.exercises[0].weight == 100, "weight unchanged below threshold")
expect(!d1.changes.contains { $0.kind == .deload }, "no deload change below threshold")

// 10. Reaching the threshold deloads by percent, rounded to increment, counter resets.
var t10 = template
t10.exercises[0].failureCount = 2
let s10 = makeSession(from: t10, reps: [squatID: [5,5,5,5,3]], completed: [:])
let d2 = Progression.apply(session: s10, to: t10, units: .kg, failureThreshold: 3, deloadPercent: 10)
expect(d2.template.exercises[0].weight == 90, "100kg -10% -> 90kg")
expect(d2.template.exercises[0].failureCount == 0, "counter resets after deload")
expect(d2.changes.contains { $0.kind == .deload && $0.exerciseID == squatID }, "deload change reported")

// 11. Deload rounds to a plate-loadable multiple of the increment.
var t11 = template
t11.exercises[0].weight = 102.5
t11.exercises[0].failureCount = 2
let s11 = makeSession(from: t11, reps: [squatID: [5,5,5,5,3]], completed: [:])
let d3 = Progression.apply(session: s11, to: t11, units: .kg, failureThreshold: 3, deloadPercent: 10)
// 102.5 * 0.9 = 92.25 -> nearest 2.5 = 92.5
expect(d3.template.exercises[0].weight == 92.5, "deload rounds to nearest 2.5")

// 12. Success resets an accumulated failure counter.
var t12 = template
t12.exercises[0].failureCount = 2
let s12 = makeSession(from: t12, reps: [:], completed: [:])
let d4 = Progression.apply(session: s12, to: t12, units: .kg, failureThreshold: 3, deloadPercent: 10)
expect(d4.template.exercises[0].failureCount == 0, "success resets failure counter")
expect(d4.template.exercises[0].weight == 102.5, "success still bumps weight")

// 13. Unattempted exercise keeps its counter.
var t13 = template
t13.exercises[1].failureCount = 2
var s13 = makeSession(from: t13, reps: [:], completed: [:])
s13.exercises.removeAll { $0.exerciseID == dlID }
let d5 = Progression.apply(session: s13, to: t13, units: .kg, failureThreshold: 3, deloadPercent: 10)
expect(d5.template.exercises[1].failureCount == 2, "unattempted exercise keeps counter")
expect(d5.template.exercises[1].weight == 140, "unattempted exercise keeps weight")

// 14. Legacy JSON without failureCount decodes to 0.
let legacy2 = """
{"id":"\(UUID().uuidString)","exerciseID":"\(UUID().uuidString)","name":"Row",
"targetSets":3,"targetReps":5,"weight":60,"restSeconds":180}
""".data(using: .utf8)!
if let l2 = try? JSONDecoder().decode(TemplateExercise.self, from: legacy2) {
    expect(l2.failureCount == 0, "legacy decode defaults failureCount=0")
} else { failures += 1; print("FAIL legacy JSON (failureCount) did not decode") }

// 15. Legacy AppSettings JSON gains deload defaults.
let legacySettings = """
{"units":"kg","defaultRestSeconds":180,"restAlertsEnabled":true,"autoStartRest":true,"weightIncrement":2.5}
""".data(using: .utf8)!
if let ls = try? JSONDecoder().decode(AppSettings.self, from: legacySettings) {
    expect(ls.deloadFailureThreshold == 3 && ls.deloadPercent == 10, "legacy settings decode with deload defaults")
    expect(ls.defaultRestSeconds == 180 && ls.units == .kg, "legacy settings keep saved values")
} else { failures += 1; print("FAIL legacy AppSettings did not decode") }

// --- Warmup (issue #6) ---

// 16. Standard ramp for 100 kg: bar 2x5, 40x5, 60x3, 80x2.
let w1 = Warmup.sets(workingWeight: 100, units: .kg)
expect(w1.map { $0.weight } == [20, 20, 40, 60, 80], "100kg ramp weights")
expect(w1.map { $0.reps } == [5, 5, 5, 3, 2], "100kg ramp reps")
expect(w1.allSatisfy { $0.isWarmup && !$0.isCompleted }, "warmups flagged and incomplete")

// 17. Working weight at or below the bar -> no warmups.
expect(Warmup.sets(workingWeight: 20, units: .kg).isEmpty, "bar-weight work: no warmups")
expect(Warmup.sets(workingWeight: 15, units: .kg).isEmpty, "below-bar work: no warmups")

// 18. Light working weight collapses ramp steps that round into each other.
let w3 = Warmup.sets(workingWeight: 30, units: .kg)
// 40%=12(below bar, skip), 60%=17.5(below bar, skip), 80%=25 -> bar,bar,25
expect(w3.map { $0.weight } == [20, 20, 25], "30kg ramp collapses to bar+25")

// 19. Custom bar weight is respected.
let w4 = Warmup.sets(workingWeight: 60, units: .kg, barWeight: 15)
expect(w4.first?.weight == 15, "custom 15kg bar honored")
expect(w4.allSatisfy { $0.weight < 60 }, "all warmups below working weight")

// 20. lb bar default is 45.
expect(Warmup.defaultBarWeight(units: .lb) == 45, "lb bar = 45")
expect(Warmup.sets(workingWeight: 135, units: .lb).first?.weight == 45, "lb ramp starts at 45")

// 21. Warmup sets don't affect progression success or volume.
var ex21 = SessionExercise(
    exerciseID: squatID, name: "Squat",
    sets: [SetEntry(reps: 5, weight: 20, isCompleted: false, isWarmup: true),
           SetEntry(reps: 5, weight: 100, isCompleted: true),
           SetEntry(reps: 5, weight: 100, isCompleted: true)]
)
expect(Progression.isSuccessful(ex21, targetReps: 5), "uncompleted warmup doesn't block success")
expect(ex21.volume == 1000, "volume counts work sets only")
ex21.sets[0].isCompleted = true
expect(ex21.volume == 1000, "completed warmup still excluded from volume")

// 22. Session built with warmups enabled prepends flagged sets; disabled -> none.
var settingsOn = AppSettings()
settingsOn.warmupsEnabled = true
let libEmpty: [UUID: Exercise] = [:]
let sess22 = WorkoutSession.from(template: template, library: libEmpty, settings: settingsOn)
let squat22 = sess22.exercises.first { $0.exerciseID == squatID }!
expect(squat22.sets.filter { $0.isWarmup }.count == 5, "session prepends 5 warmups for 100kg squat")
expect(squat22.sets.filter { !$0.isWarmup }.count == 5, "5 work sets intact")
var settingsOff = AppSettings()
settingsOff.warmupsEnabled = false
let sess22b = WorkoutSession.from(template: template, library: libEmpty, settings: settingsOff)
expect(sess22b.exercises.first { $0.exerciseID == squatID }!.sets.allSatisfy { !$0.isWarmup }, "disabled -> no warmups")

// --- Plate calculator (issue #7) ---

let kgPlates = PlateCalculator.defaultPlates(units: .kg)

// 23. Exact load: 100kg on 20kg bar = 40/side = 25+15.
let p1 = PlateCalculator.plates(target: 100, bar: 20, available: kgPlates)
expect(p1.platesPerSide == [25, 15], "100kg -> 25+15 per side")
expect(p1.isExact && p1.achievedWeight == 100, "100kg exact")

// 24. Greedy with repeats: 170kg -> 75/side = 25,25,25.
let p2 = PlateCalculator.plates(target: 170, bar: 20, available: kgPlates)
expect(p2.platesPerSide == [25, 25, 25] && p2.isExact, "170kg greedy stack")

// 25. Fractional plates: 62.5kg -> 21.25/side = 20+1.25.
let p3 = PlateCalculator.plates(target: 62.5, bar: 20, available: kgPlates)
expect(p3.platesPerSide == [20, 1.25], "62.5kg uses fractional 1.25")
expect(p3.isExact, "62.5kg exact with fractionals")

// 26. Non-loadable: 101kg -> closest below (100).
let p4 = PlateCalculator.plates(target: 101, bar: 20, available: kgPlates)
expect(!p4.isExact && p4.achievedWeight == 100, "101kg -> closest 100")

// 27. Target at/below bar -> empty bar.
expect(PlateCalculator.plates(target: 20, bar: 20, available: kgPlates).platesPerSide.isEmpty, "bar weight -> no plates")
expect(PlateCalculator.plates(target: 15, bar: 20, available: kgPlates).achievedWeight == 20, "below bar -> bar")

// 28. Restricted plate set: no 25s -> 100kg = 20+20/side.
let p5 = PlateCalculator.plates(target: 100, bar: 20, available: [20, 15, 10, 5, 2.5, 1.25])
expect(p5.platesPerSide == [20, 20], "no-25s gym uses 20+20")

// 29. lb set: 135lb on 45lb bar = one 45 per side.
let p6 = PlateCalculator.plates(target: 135, bar: 45, available: PlateCalculator.defaultPlates(units: .lb))
expect(p6.platesPerSide == [45] && p6.isExact, "135lb -> 45/side")

// --- Progress series (issue #8) ---

func datedSession(daysAgo: Int, weight: Double, completed: Bool = true, warmup: Bool = false, finished: Bool = true) -> WorkoutSession {
    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
    let ex = SessionExercise(
        exerciseID: squatID, name: "Squat",
        sets: [SetEntry(reps: 5, weight: weight, isCompleted: completed, isWarmup: warmup)]
    )
    return WorkoutSession(templateID: template.id, name: "A", exercises: [ex],
                          startedAt: date, finishedAt: finished ? date : nil)
}

// 30. Max-weight series: oldest first, completed work sets only.
let hist = [
    datedSession(daysAgo: 1, weight: 105),
    datedSession(daysAgo: 10, weight: 100),
    datedSession(daysAgo: 5, weight: 0),                       // zero weight skipped
    datedSession(daysAgo: 3, weight: 200, completed: false),   // uncompleted skipped
    datedSession(daysAgo: 2, weight: 300, warmup: true),       // warmup-only skipped
    datedSession(daysAgo: 4, weight: 150, finished: false),    // unfinished skipped
]
let series = ProgressSeries.exerciseMaxWeight(history: hist, exerciseID: squatID, since: nil)
expect(series.map { $0.value } == [100, 105], "max-weight series: filtered + oldest first")

// 31. Timeframe filter cuts old sessions.
let recent = ProgressSeries.exerciseMaxWeight(
    history: hist, exerciseID: squatID,
    since: Calendar.current.date(byAdding: .day, value: -7, to: Date()))
expect(recent.map { $0.value } == [105], "since-filter drops older sessions")

// 32. Volume series uses work sets only.
let vol = ProgressSeries.totalVolume(history: hist, since: nil)
expect(vol.map { $0.value } == [500, 525], "volume series from work sets (5x100, 5x105)")

// 33. Tracked exercises: weighted with completed work sets, deduped.
let tracked = ProgressSeries.trackedExercises(history: hist)
expect(tracked.count == 1 && tracked.first?.name == "Squat", "tracked exercises deduped")

// --- Body weight (issue #9) ---

// 34. Series converts kg to display units and sorts oldest first.
let now = Date()
let bwEntries = [
    BodyWeightEntry(date: now, weightKg: 80),
    BodyWeightEntry(date: now.addingTimeInterval(-86400 * 10), weightKg: 82),
]
let bwKg = ProgressSeries.bodyWeight(entries: bwEntries, since: nil, units: .kg)
expect(bwKg.map { $0.value } == [82, 80], "body-weight kg series oldest first")
let bwLb = ProgressSeries.bodyWeight(entries: bwEntries, since: nil, units: .lb)
expect(abs(bwLb.last!.value - 176.37) < 0.01, "80kg -> 176.37lb")

// 35. Since-filter applies.
let bwRecent = ProgressSeries.bodyWeight(
    entries: bwEntries,
    since: now.addingTimeInterval(-86400 * 5),
    units: .kg)
expect(bwRecent.count == 1 && bwRecent[0].value == 80, "body-weight since-filter")

// 36. Unit constants round-trip.
expect(AppSettings.Units.kg.kgPerUnit == 1, "kg unit constant")
expect(abs(100 * AppSettings.Units.lb.kgPerUnit - 45.359237) < 0.0001, "lb unit constant")

// --- Records (issue #10) ---

// 37. Epley formula.
expect(Records.epley1RM(weight: 100, reps: 5) == 100 * (1 + 5.0/30), "Epley 100x5")
expect(Records.epley1RM(weight: 100, reps: 1) == 100, "Epley 1 rep = weight")

// 38. Records aggregate across sessions; warmups/uncompleted excluded.
let recHist = [
    datedSession(daysAgo: 10, weight: 100),                    // 100x5
    datedSession(daysAgo: 5, weight: 105),                     // 105x5 (PR)
    datedSession(daysAgo: 2, weight: 300, warmup: true),       // ignored
    datedSession(daysAgo: 1, weight: 200, completed: false),   // ignored
]
let recs = Records.all(history: recHist)
expect(recs.count == 1 && recs[0].maxWeight == 105, "max weight 105")
expect(recs[0].repsAtMaxWeight == 5, "reps at max weight")
expect(abs(recs[0].best1RM - 105 * (1 + 5.0/30)) < 0.001, "best 1RM from 105x5")
expect(recs[0].maxSessionVolume == 525, "max session volume")

// 39. newPRs: beats prior -> Weight/1RM/Volume; first time -> First.
let prior = [datedSession(daysAgo: 10, weight: 100)]
let prSession = datedSession(daysAgo: 0, weight: 105)
let prs = Records.newPRs(session: prSession, priorHistory: prior)
expect(prs.count == 1 && prs[0].kinds.contains("Weight") && prs[0].kinds.contains("1RM"), "105 beats 100: weight+1RM PR")
let firstPRs = Records.newPRs(session: prSession, priorHistory: [])
expect(firstPRs.first?.kinds == ["First"], "first-ever session flagged First")

// 40. No PR when weaker.
let weaker = Records.newPRs(session: datedSession(daysAgo: 0, weight: 90), priorHistory: prior)
expect(weaker.isEmpty, "weaker session: no PR")

// --- Session notes (issue #11) ---

// 41. Legacy session JSON without notes decodes with empty string.
let legacySession = """
{"id":"\(UUID().uuidString)","name":"A","category":"custom","exercises":[],
"startedAt":\(Date().timeIntervalSinceReferenceDate)}
""".data(using: .utf8)!
let dec = JSONDecoder(); dec.dateDecodingStrategy = .deferredToDate
if let ls = try? dec.decode(WorkoutSession.self, from: legacySession) {
    expect(ls.notes == "", "legacy session decodes with empty notes")
} else { failures += 1; print("FAIL legacy session did not decode") }

// 42. Notes round-trip through Codable.
var noted = WorkoutSession(name: "B")
noted.notes = "felt heavy"
if let data = try? JSONEncoder().encode(noted),
   let back = try? JSONDecoder().decode(WorkoutSession.self, from: data) {
    expect(back.notes == "felt heavy", "notes survive encode/decode")
} else { failures += 1; print("FAIL notes round-trip") }

// --- Backup (issue #13) ---

// 43. Full payload round-trips.
var bset = AppSettings(); bset.units = .lb; bset.deloadPercent = 15
let payload = BackupPayload(
    templates: [template],
    history: [datedSession(daysAgo: 1, weight: 100)],
    customExercises: [],
    favoriteExerciseIDs: [squatID],
    bodyWeights: [BodyWeightEntry(weightKg: 80)],
    settings: bset
)
if let data = try? Backup.encode(payload), let back = try? Backup.decode(data) {
    expect(back.templates.count == 1 && back.templates[0].id == template.id, "backup templates round-trip")
    expect(back.history.count == 1, "backup history round-trip")
    expect(back.favoriteExerciseIDs == [squatID], "backup favorites round-trip")
    expect(back.bodyWeights.first?.weightKg == 80, "backup body weights round-trip")
    expect(back.settings.units == .lb && back.settings.deloadPercent == 15, "backup settings round-trip")
    expect(back.version == 1, "backup version present")
} else { failures += 1; print("FAIL backup round-trip") }

// 44. Partial/older backup decodes with defaults.
let partial = #"{"templates":[],"history":[]}"#.data(using: .utf8)!
if let p = try? Backup.decode(partial) {
    expect(p.bodyWeights.isEmpty && p.favoriteExerciseIDs.isEmpty && p.settings.units == .kg, "partial backup fills defaults")
} else { failures += 1; print("FAIL partial backup did not decode") }

// --- Exercise demonstrations (issue #12) ---

// 45. Every set/rep built-in exercise has one offline illustration and one
// external coaching-video link; asset existence is verified by the Xcode build.
// Timed exercises (cardio machines, stretches) are demonstrated by their form
// notes rather than an illustration/video, so they're excluded here.
let demoExercises = ExerciseLibrary.all.filter { !$0.isTimed }
let timedExercises = ExerciseLibrary.all.filter { $0.isTimed }
expect(demoExercises.count == 24, "24 built-in set/rep exercises")
expect(timedExercises.count == 10, "10 built-in timed exercises (cardio + stretch)")
expect(demoExercises.allSatisfy { $0.demoImageName != nil }, "all set/rep built-ins have demo illustrations")
expect(Set(demoExercises.compactMap(\.demoImageName)).count == 24, "demo illustration names are unique")
expect(
    demoExercises.allSatisfy {
        $0.techniqueVideoURL?.host?.contains("youtube.com") == true &&
        $0.techniqueVideoURL?.query?.contains("v=") == true
    },
    "all set/rep built-ins have direct YouTube watch links"
)
expect(ExerciseLibrary.all.allSatisfy { $0.videoName != nil }, "all 34 exercises have video demo clips assigned")
expect(Set(ExerciseLibrary.all.compactMap(\.videoName)).count == 34, "video demo names are unique across all 34 exercises")
expect(timedExercises.allSatisfy { !$0.instructions.isEmpty }, "timed built-ins have form notes")

// --- Watch-first live-workout replication ---

// 46. Ownership epochs outrank revisions from a former owner.
let oldOwnerLateEdit = SessionVersion(ownershipEpoch: 2, revision: 500)
let newOwnerInitial = SessionVersion(ownershipEpoch: 3, revision: 0)
expect(oldOwnerLateEdit < newOwnerInitial, "new ownership epoch rejects former-owner edits")
expect(
    SessionVersion.initial.advanced() == SessionVersion(ownershipEpoch: 0, revision: 1),
    "ordinary edit advances revision"
)
expect(
    oldOwnerLateEdit.transferred() == SessionVersion(ownershipEpoch: 3, revision: 0),
    "ownership transfer advances epoch and resets revision"
)

// 47. Replicas accept only newer state and terminal tombstones always win.
let syncSession = WorkoutSession(name: "Watch-first test")
let initialReplica = WorkoutReplica(session: syncSession, owner: .phone)
let watchReplica = WorkoutReplica(
    session: syncSession,
    owner: .watch,
    version: initialReplica.version.transferred(),
    healthRecorder: .watch
)
var runtime = WorkoutRuntimeState(activeReplica: initialReplica, authorityState: .offeringTransfer)
expect(runtime.accepts(watchReplica), "newer Watch-owned replica accepted")
expect(!runtime.accepts(initialReplica), "duplicate replica rejected")
runtime.terminalSessions[syncSession.id] = WorkoutTombstone(
    sessionID: syncSession.id,
    finalVersion: watchReplica.version,
    finished: true,
    createdAt: Date()
)
expect(!runtime.accepts(watchReplica), "terminal tombstone rejects later replica")

// 48. Active runtime, outbox and tombstones survive an atomic disk round-trip.
let runtimeDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("arulifts-runtime-\(UUID().uuidString)")
let runtimeRepo = ActiveWorkoutRepository(directory: runtimeDir)
let pending = PendingWorkoutMessage(payload: Data("event".utf8))
runtime.activeReplica = watchReplica
runtime.authorityState = .authoritative
runtime.syncStatus = .waitingForPhone
runtime.outbox = [pending]
expect(runtimeRepo.save(runtime), "active runtime persisted atomically")
let restoredRuntime = runtimeRepo.load()
expect(restoredRuntime.activeReplica == watchReplica, "active replica restored")
expect(restoredRuntime.outbox == [pending], "durable outbox restored")
expect(restoredRuntime.terminalSessions[syncSession.id]?.finished == true, "tombstone restored")
runtimeRepo.removeFile()
try? FileManager.default.removeItem(at: runtimeDir)

// 49. Phone-start handoff is two-phase and acceptance is durable on Watch.
let syncRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("arulifts-sync-\(UUID().uuidString)")
let phoneRepository = ActiveWorkoutRepository(directory: syncRoot.appendingPathComponent("phone"))
let watchRepository = ActiveWorkoutRepository(directory: syncRoot.appendingPathComponent("watch"))
var phoneWire: [WorkoutMessageEnvelope] = []
var watchWire: [WorkoutMessageEnvelope] = []
let phoneCoordinator = WorkoutSyncCoordinator(
    localDevice: .phone,
    repository: phoneRepository,
    transmit: { envelope, _ in phoneWire.append(envelope) }
)
let watchCoordinator = WorkoutSyncCoordinator(
    localDevice: .watch,
    repository: watchRepository,
    transmit: { envelope, _ in watchWire.append(envelope) }
)
let handoffSession = WorkoutSession(name: "Handoff")
expect(phoneCoordinator.start(handoffSession), "phone persists ownership offer")
expect(phoneCoordinator.canEdit, "phone remains editable before Watch acceptance")
let offerEnvelope = phoneWire.first { $0.kind == .ownershipOffer }!
expect(watchCoordinator.receive(offerEnvelope) == .applied, "Watch accepts phone start")
expect(
    watchCoordinator.owner == .phone && !watchCoordinator.canEdit,
    "Watch persists acceptance without overlapping phone edits"
)
let acceptanceEnvelope = watchWire.first { $0.kind == .ownershipAcceptance }!
expect(
    phoneCoordinator.receive(acceptanceEnvelope) == .applied,
    "phone applies durable Watch receipt"
)
expect(
    phoneCoordinator.owner == .watch && !phoneCoordinator.canEdit,
    "phone becomes read-only only after acceptance"
)
let ownershipCommit = phoneWire.last { $0.kind == .ownershipCommit }!
expect(
    watchCoordinator.receive(ownershipCommit) == .applied &&
    watchCoordinator.owner == .watch &&
    watchCoordinator.canEdit,
    "Watch edits only after transfer commit"
)

// 50. Application acknowledgments are idempotent.
let receiptAck = watchWire.last { $0.kind == .acknowledgment }!
expect(
    phoneCoordinator.receive(receiptAck) == .applied,
    "application ack clears transfer commit outbox"
)
expect(
    phoneCoordinator.receive(receiptAck) == .duplicate,
    "duplicate application ack is harmless"
)

// 51. Former-owner epochs and revision gaps cannot mutate the mirror.
var staleReplica = phoneCoordinator.replica!
staleReplica.owner = .phone
staleReplica.version = SessionVersion(ownershipEpoch: 0, revision: 99)
let staleEnvelope = try! WorkoutMessageEnvelope(
    kind: .checkpoint,
    sender: .phone,
    sessionID: handoffSession.id,
    payload: WorkoutCheckpoint(replica: staleReplica)
)
expect(watchCoordinator.receive(staleEnvelope) == .stale, "stale former-owner epoch is rejected")

var gapReplica = phoneCoordinator.replica!
gapReplica.version.revision += 2
let gapEnvelope = try! WorkoutMessageEnvelope(
    kind: .checkpoint,
    sender: .watch,
    sessionID: handoffSession.id,
    payload: WorkoutCheckpoint(replica: gapReplica)
)
expect(phoneCoordinator.receive(gapEnvelope) == .applied, "newer full checkpoint repairs reordering")
expect(phoneCoordinator.replica?.version == gapReplica.version, "newer checkpoint converges mirror")

var revisionOne = gapReplica
revisionOne.version.revision -= 1
let revisionOneEnvelope = try! WorkoutMessageEnvelope(
    kind: .checkpoint,
    sender: .watch,
    sessionID: handoffSession.id,
    payload: WorkoutCheckpoint(replica: revisionOne)
)
expect(phoneCoordinator.receive(revisionOneEnvelope) == .stale, "older checkpoint cannot overwrite convergence")
expect(phoneCoordinator.receive(gapEnvelope) == .duplicate, "duplicate newer checkpoint is harmless")

// 52. Terminal state is self-contained, persisted, and wins permanently.
let terminal = WorkoutTombstone(
    sessionID: handoffSession.id,
    finalVersion: gapReplica.version,
    finished: true,
    createdAt: Date()
)
let terminalEnvelope = try! WorkoutMessageEnvelope(
    kind: .tombstone,
    sender: .watch,
    sessionID: handoffSession.id,
    payload: WorkoutFinalization(
        tombstone: terminal,
        finalSession: handoffSession,
        healthSaved: true
    )
)
expect(phoneCoordinator.receive(terminalEnvelope) == .applied, "finalization installs tombstone")
expect(
    phoneCoordinator.replica == nil &&
    phoneCoordinator.state.terminalSessions[handoffSession.id] != nil,
    "tombstone clears active replica"
)
let resurrectionEnvelope = try! WorkoutMessageEnvelope(
    kind: .checkpoint,
    sender: .watch,
    sessionID: handoffSession.id,
    payload: WorkoutCheckpoint(replica: gapReplica)
)
expect(
    phoneCoordinator.receive(resurrectionEnvelope) == .invalid,
    "tombstone prevents resurrection"
)

// 53. Watch ownership and unknown wire kinds both survive decoding/relaunch.
let restoredWatchCoordinator = WorkoutSyncCoordinator(
    localDevice: .watch,
    repository: watchRepository
)
expect(
    restoredWatchCoordinator.owner == .watch &&
    restoredWatchCoordinator.replica?.session.id == handoffSession.id,
    "accepted Watch ownership restores after termination"
)
let unknownEnvelope = try! WorkoutMessageEnvelope(
    kind: WorkoutMessageKind(rawValue: "futureSemanticMutation"),
    sender: .watch,
    sessionID: handoffSession.id,
    payload: ["future": true]
)
let unknownRoundTrip = try! JSONDecoder().decode(
    WorkoutMessageEnvelope.self,
    from: JSONEncoder().encode(unknownEnvelope)
)
expect(
    unknownRoundTrip.kind.rawValue == "futureSemanticMutation",
    "unknown v2 kinds decode forward-compatibly"
)
try? FileManager.default.removeItem(at: syncRoot)

// 54. Phone takeover is also an acknowledged ownership-epoch transfer.
let takeoverRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("arulifts-takeover-\(UUID().uuidString)")
var takeoverWatchWire: [WorkoutMessageEnvelope] = []
var takeoverPhoneWire: [WorkoutMessageEnvelope] = []
let takeoverWatch = WorkoutSyncCoordinator(
    localDevice: .watch,
    repository: ActiveWorkoutRepository(
        directory: takeoverRoot.appendingPathComponent("watch")
    ),
    transmit: { envelope, _ in takeoverWatchWire.append(envelope) }
)
let takeoverPhone = WorkoutSyncCoordinator(
    localDevice: .phone,
    repository: ActiveWorkoutRepository(
        directory: takeoverRoot.appendingPathComponent("phone")
    ),
    transmit: { envelope, _ in takeoverPhoneWire.append(envelope) }
)
let watchStartedSession = WorkoutSession(name: "Watch start")
expect(takeoverWatch.start(watchStartedSession), "Watch-start checkpoint is durable")
let initialWatchCheckpoint = takeoverWatchWire.first { $0.kind == .checkpoint }!
expect(
    takeoverPhone.receive(initialWatchCheckpoint) == .applied,
    "phone mirrors a Watch-started workout"
)
expect(takeoverPhone.requestTakeover(), "phone persists takeover request")
let takeoverRequestEnvelope = takeoverPhoneWire.last { $0.kind == .takeoverRequest }!
expect(
    takeoverWatch.receive(takeoverRequestEnvelope) == .applied,
    "Watch accepts phone takeover"
)
let takeoverAcceptance = takeoverWatchWire.last { $0.kind == .ownershipAcceptance }!
expect(
    takeoverPhone.receive(takeoverAcceptance) == .applied &&
    takeoverPhone.owner == .phone &&
    !takeoverPhone.canEdit,
    "phone stays read-only while takeover commits"
)
let takeoverCommit = takeoverPhoneWire.last { $0.kind == .ownershipCommit }!
expect(
    takeoverWatch.receive(takeoverCommit) == .applied &&
    takeoverWatch.owner == .phone && !takeoverWatch.canEdit,
    "Watch becomes read-only after phone takeover"
)
let takeoverCommitAck = takeoverWatchWire.last { $0.kind == .acknowledgment }!
expect(
    takeoverPhone.receive(takeoverCommitAck) == .applied &&
    takeoverPhone.canEdit,
    "phone edits only after committed takeover ack"
)
try? FileManager.default.removeItem(at: takeoverRoot)

// 55. Cached Watch plans preserve their template relation while every offline
// start creates fresh transient identities.
let watchPlan = WatchStartableWorkout(template: template, library: ExerciseLibrary.byID, settings: AppSettings())
let watchAttemptA = watchPlan.makeFreshSession(at: Date(timeIntervalSinceReferenceDate: 1))
let watchAttemptB = watchPlan.makeFreshSession(at: Date(timeIntervalSinceReferenceDate: 2))
expect(watchAttemptA.templateID == template.id, "Watch plan preserves template link")
expect(watchAttemptA.id != watchAttemptB.id, "Watch plan creates fresh session IDs")
expect(
    watchAttemptA.exercises.first?.id != watchAttemptB.exercises.first?.id &&
        watchAttemptA.exercises.first?.sets.first?.id != watchAttemptB.exercises.first?.sets.first?.id,
    "Watch plan regenerates exercise and set IDs"
)
var lbSettings = AppSettings()
lbSettings.units = .lb
lbSettings.autoStartRest = false
lbSettings.restAlertsEnabled = false
lbSettings.plateSet = [45, 25, 10, 5, 2.5]
let lbExecution = WatchExecutionSettings(settings: lbSettings)
let cacheV1 = WatchPlanCache().advanced(
    workouts: [watchPlan], executionSettings: lbExecution
)
let cacheV2 = cacheV1.advanced(
    workouts: [watchPlan], executionSettings: lbExecution
)
expect(cacheV2 > cacheV1, "Watch plan cache revision advances monotonically")
expect(
    cacheV2.executionSettings.units == .lb &&
        !cacheV2.executionSettings.autoStartRest &&
        cacheV2.executionSettings.availablePlates == [45, 25, 10, 5, 2.5],
    "Watch plan cache retains units, rest behavior, and plates"
)

// 56. New recovery metadata remains compatible with sessions saved before it.
let legacySetData = """
{"id":"00000000-0000-0000-0000-000000000056","reps":4,"weight":100,"isCompleted":false,"isWarmup":false}
""".data(using: .utf8)!
let legacySet = try! JSONDecoder().decode(SetEntry.self, from: legacySetData)
expect(legacySet.targetReps == 4, "legacy set target defaults to its saved reps")
let pausedSnapshot = RestTimerSnapshot(
    endDate: Date(timeIntervalSinceReferenceDate: 0),
    totalSeconds: 120,
    pausedRemainingSeconds: 73
)
let decodedPausedSnapshot = try! JSONDecoder().decode(
    RestTimerSnapshot.self, from: JSONEncoder().encode(pausedSnapshot)
)
expect(
    decodedPausedSnapshot.pausedRemainingSeconds == 73,
    "paused rest remaining duration survives replication"
)

print(failures == 0 ? "ALL TESTS PASSED" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
