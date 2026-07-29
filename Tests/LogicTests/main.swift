// Standalone assertions for Progression — compiled with the real model files.
import Foundation

var failures = 0
func expect(_ cond: Bool, _ label: String) {
    if cond { print("PASS \(label)") } else { failures += 1; print("FAIL \(label)") }
}

expect(WeightFormatter.number(100) == "100", "weight formatter omits .0")
expect(WeightFormatter.number(100.25) == "100.3", "weight formatter rounds to one decimal")
expect(WeightFormatter.string(45, units: .lb) == "45 LB", "weight formatter includes unit label")

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
let loadedHistorySession = WorkoutSession(id: UUID(), name: "Loaded", finishedAt: Date())
let earlyHistorySession = WorkoutSession(id: UUID(), name: "Early", finishedAt: Date())
let mergedHistory = WorkoutStore.mergedHistory(
    loaded: [loadedHistorySession, recordedHistorySession],
    inMemory: [earlyHistorySession, recordedHistorySession]
)
expect(
    mergedHistory.map(\.id) == [earlyHistorySession.id, recordedHistorySession.id, loadedHistorySession.id],
    "async history load preserves early local sessions without duplicates"
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

// Session ordering is a one-day customization: moving an exercise preserves
// its completed sets and has no relationship to the saved template order.
let reorderA = SessionExercise(exerciseID: UUID(), name: "A", sets: [SetEntry(reps: 5, weight: 50, isCompleted: true)])
let reorderB = SessionExercise(exerciseID: UUID(), name: "B", sets: [SetEntry(reps: 8, weight: 20)])
let reorderC = SessionExercise(exerciseID: UUID(), name: "C", sets: [SetEntry(reps: 10, weight: 0)])
var reorderSession = WorkoutSession(name: "Reorder", exercises: [reorderA, reorderB, reorderC])
reorderSession.moveExercises(from: IndexSet(integer: 2), to: 0)
expect(reorderSession.exercises.map(\.name) == ["C", "A", "B"], "session exercise order can move for today")
expect(reorderSession.exercises[1].sets[0].isCompleted, "reordering retains completed set data")
let reorderIDs = reorderSession.exercises.map(\.id)
reorderSession.moveExercises(from: IndexSet(integer: 0), to: 3)
expect(reorderSession.exercises.map(\.id) == [reorderIDs[1], reorderIDs[2], reorderIDs[0]], "session reorder retains stable exercise identities")

// A terminal event is recorded before WatchConnectivity publishes queued
// snapshots to the main thread, so a late checkpoint cannot revive the session.
let discardedSessionID = UUID()
let terminalGate = TerminalSessionGate(capacity: 2)
expect(!terminalGate.isTerminal(discardedSessionID), "new session is not terminal")
terminalGate.markTerminal(discardedSessionID)
expect(terminalGate.isTerminal(discardedSessionID), "discarded session is terminal before dispatch")
terminalGate.markTerminal(discardedSessionID)
expect(terminalGate.isTerminal(discardedSessionID), "duplicate terminal event remains idempotent")

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
    expect(ls.restAlertStyle == .soundAndHaptic && ls.earlyRestCueEnabled && ls.earlyRestCueLeadSeconds == 10, "legacy settings decode rest alert defaults")
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
let warmupLibrary: [UUID: Exercise] = [
    squatID: Exercise(name: "Barbell Squat", primaryMuscle: .quads, equipment: .barbell)
]
let sess22 = WorkoutSession.from(template: template, library: warmupLibrary, settings: settingsOn)
let squat22 = sess22.exercises.first { $0.exerciseID == squatID }!
expect(squat22.sets.filter { $0.isWarmup }.count == 5, "session prepends 5 warmups for 100kg squat")
expect(squat22.sets.filter { !$0.isWarmup }.count == 5, "5 work sets intact")
var settingsOff = AppSettings()
settingsOff.warmupsEnabled = false
let sess22b = WorkoutSession.from(template: template, library: warmupLibrary, settings: settingsOff)
expect(sess22b.exercises.first { $0.exerciseID == squatID }!.sets.allSatisfy { !$0.isWarmup }, "disabled -> no warmups")

// 22b. Warmup ramps are barbell-only; machines and cables have no implied bar.
let machine22ID = UUID()
let machine22 = Exercise(name: "Chest Press", primaryMuscle: .chest, equipment: .machine)
let machineTemplate22 = WorkoutTemplate(
    name: "Machines",
    exercises: [TemplateExercise(exerciseID: machine22ID, name: machine22.name, weight: 70)]
)
let machineSession22 = WorkoutSession.from(
    template: machineTemplate22,
    library: [machine22ID: machine22],
    settings: settingsOn
)
expect(machineSession22.exercises[0].sets.allSatisfy { !$0.isWarmup }, "direct equipment receives no barbell warmups")

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
expect(timedExercises.count >= 10, "built-in timed exercises (cardio + stretch) present")
expect(demoExercises.allSatisfy { $0.demoImageName != nil }, "all set/rep built-ins have demo illustrations")
expect(Set(demoExercises.compactMap(\.demoImageName)).count == 24, "demo illustration names are unique")
expect(
    demoExercises.allSatisfy {
        $0.techniqueVideoURL?.host?.contains("youtube.com") == true &&
        $0.techniqueVideoURL?.query?.contains("v=") == true
    },
    "all set/rep built-ins have direct YouTube watch links"
)
// A demo entry names an image/clip that must actually ship in the bundle. An
// exercise with no shipped asset must NOT be registered — otherwise the detail
// screen renders a blank media box instead of the exercise's SF Symbol. Keep
// this count literal so adding an exercise forces a conscious asset decision.
let exercisesWithDemoClips = ExerciseLibrary.all.filter { $0.videoName != nil }
expect(exercisesWithDemoClips.count == 34, "34 built-in exercises ship a demo clip")
expect(Set(exercisesWithDemoClips.compactMap(\.videoName)).count == 34, "video demo names are unique across the 34 exercises that ship clips")
expect(
    ExerciseLibrary.all.allSatisfy { $0.videoName != nil || $0.demoImageName == nil },
    "no exercise names a demo image without also naming a clip"
)
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

// 47. Active runtime, outbox and tombstones survive an atomic disk round-trip.
let runtimeSession = WorkoutSession(name: "Runtime persistence")
let runtimeReplica = WorkoutReplica(
    session: runtimeSession,
    owner: .watch,
    version: SessionVersion.initial.transferred(),
    healthRecorder: .watch
)
var runtime = WorkoutRuntimeState(
    activeReplica: runtimeReplica,
    authorityState: .authoritative
)
runtime.terminalSessions[runtimeSession.id] = WorkoutTombstone(
    sessionID: runtimeSession.id,
    finalVersion: runtimeReplica.version,
    finished: true,
    createdAt: Date()
)
let runtimeDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("arulifts-runtime-\(UUID().uuidString)")
let runtimeRepo = ActiveWorkoutRepository(directory: runtimeDir)
let pending = PendingWorkoutMessage(payload: Data("event".utf8))
runtime.syncStatus = .waitingForPhone
runtime.outbox = [pending]
expect(runtimeRepo.save(runtime), "active runtime persisted atomically")
let restoredRuntime = runtimeRepo.load()
expect(restoredRuntime.activeReplica == runtimeReplica, "active replica restored")
expect(restoredRuntime.outbox == [pending], "durable outbox restored")
expect(
    restoredRuntime.terminalSessions[runtimeSession.id]?.finished == true,
    "tombstone restored"
)
runtimeRepo.removeFile()
try? FileManager.default.removeItem(at: runtimeDir)

// 48. Phone-start handoff is two-phase and acceptance is durable on Watch.
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

// 49. Application acknowledgments are idempotent.
let receiptAck = watchWire.last { $0.kind == .acknowledgment }!
expect(
    phoneCoordinator.receive(receiptAck) == .applied,
    "application ack clears transfer commit outbox"
)
expect(
    phoneCoordinator.receive(receiptAck) == .duplicate,
    "duplicate application ack is harmless"
)

// 50. Former-owner epochs and revision gaps cannot mutate the mirror.
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

// 51. Terminal state is self-contained, persisted, and wins permanently.
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

// 52. Watch ownership and unknown wire kinds both survive decoding/relaunch.
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

// 53. Phone takeover is also an acknowledged ownership-epoch transfer.
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

// 54. Cached Watch plans preserve their template relation while every offline
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
lbSettings.defaultRestSeconds = 75
lbSettings.warmupsEnabled = false
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
        cacheV2.executionSettings.defaultRestSeconds == 75 &&
        !cacheV2.executionSettings.warmupsEnabled &&
        cacheV2.executionSettings.availablePlates == [45, 25, 10, 5, 2.5],
    "Watch plan cache retains units, live-edit defaults, rest behavior, and plates"
)
expect(
    lbExecution.sessionEditSettings.defaultRestSeconds == 75
        && !lbExecution.sessionEditSettings.warmupsEnabled
        && lbExecution.sessionEditSettings.units == .lb,
    "Watch rebuilds the settings required by shared live-exercise construction"
)

// 55. New recovery metadata remains compatible with sessions saved before it.
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

// 56. Form media kind drives the full-screen viewer's expand affordance (#27).
var mediaProbe = ExerciseLibrary.all[0]
mediaProbe.videoName = nil
mediaProbe.videoURL = nil
mediaProbe.demoImageName = nil
expect(mediaProbe.formMediaKind(hasBundledVideo: false) == .none,
       "no media resolves to none (nothing to expand)")
expect(mediaProbe.formMediaKind(hasBundledVideo: true) == .video,
       "a bundled clip resolves to video")
mediaProbe.demoImageName = "probe_illustration"
expect(mediaProbe.formMediaKind(hasBundledVideo: false) == .image,
       "an illustration alone resolves to image")
mediaProbe.videoURL = URL(string: "https://example.com/demo.mp4")
expect(mediaProbe.formMediaKind(hasBundledVideo: false) == .video,
       "a remote videoURL wins over the still image")

// Rest snapshots saved before configurable alerts existed still decode, while
// new snapshots carry the exact cue settings to the mirrored timer.
let legacyRestData = #"{"endDate":0,"totalSeconds":60}"#.data(using: .utf8)!
if let legacyRest = try? JSONDecoder().decode(RestTimerSnapshot.self, from: legacyRestData) {
    expect(legacyRest.alertConfiguration == .default, "legacy rest snapshot defaults alert configuration")
} else { failures += 1; print("FAIL legacy rest snapshot did not decode") }
let configuredRest = RestTimerSnapshot(
    endDate: Date(), totalSeconds: 90,
    alertConfiguration: RestTimerAlertConfiguration(alertsEnabled: true, style: .vibrationOnly, earlyCueEnabled: true, earlyCueLeadSeconds: 15)
)
if let restored = try? JSONDecoder().decode(RestTimerSnapshot.self, from: JSONEncoder().encode(configuredRest)) {
    expect(restored.alertConfiguration.style == .vibrationOnly && restored.alertConfiguration.earlyCueLeadSeconds == 15, "rest snapshot retains configured cue")
} else { failures += 1; print("FAIL configured rest snapshot did not decode") }

let defaultTemplates = ExerciseLibrary.defaultTemplates()
expect(defaultTemplates.count >= 8, "8 default templates present including 4-Day Upper/Lower split")
expect(defaultTemplates.contains { $0.name == "Upper Body A (Strength)" }, "Upper Body A (Strength) template present")
expect(defaultTemplates.contains { $0.name == "Lower Body A (Strength)" }, "Lower Body A (Strength) template present")
expect(defaultTemplates.contains { $0.name == "Upper Body B (Hypertrophy)" }, "Upper Body B (Hypertrophy) template present")
expect(defaultTemplates.contains { $0.name == "Lower Body B (Hypertrophy)" }, "Lower Body B (Hypertrophy) template present")

MainActor.assumeIsolated {
    let migrationStore = WorkoutStore()
    migrationStore.ensureDefaultTemplatesExist()
    expect(migrationStore.templates.count >= 8, "ensureDefaultTemplatesExist populates missing starter templates on existing stores")
    expect(!migrationStore.gymRoutines.isEmpty, "default GymSessionRoutine is auto-created on launch")
}

let defaultRoutine = GymSessionRoutine.defaultCompleteGymVisit()
expect(defaultRoutine.phases.count == 7, "default routine contains 7 phases")
expect(defaultRoutine.enabledPhases.count == 7, "all 7 default phases are enabled")

let fourDayRoutines = GymSessionRoutine.default4DayRoutines(templates: defaultTemplates)
expect(fourDayRoutines.count == 4, "default4DayRoutines produces 4 daily gym visit routines")

let tuesday = fourDayRoutines.first(where: { $0.name.contains("Tuesday") })
expect(tuesday != nil, "Tuesday workout routine is present")
if let tuesday {
    expect(tuesday.phases.count == 7, "Tuesday workout routine contains 7 phases")
    expect(tuesday.phases.allSatisfy { $0.templateID != nil }, "Tuesday workout has a template attached to every phase")
    let upperBodyAPhase = tuesday.phases.first(where: { $0.phaseType == .mainStrength })
    let upperBodyATemplate = defaultTemplates.first(where: { $0.name == "Upper Body A (Strength)" })
    expect(upperBodyAPhase?.templateID == upperBodyATemplate?.id, "Tuesday workout main strength phase is linked to Upper Body A (Strength)")

    let tuesdaySession = WorkoutSession.from(routine: tuesday, templates: defaultTemplates, library: ExerciseLibrary.byID)
    expect(tuesdaySession.phases.count == 7, "Tuesday workout session materializes 7 phases")
    expect(!tuesdaySession.exercises.isEmpty, "Tuesday workout session materializes exercises across all attached templates")

    let cardioPhase = tuesdaySession.phases.first(where: { $0.phaseType == .preCardio })
    expect(cardioPhase?.activityKind == .stairClimbing, "Tuesday cardio (Stair Stepper) maps to stairClimbing activity")
}

let wednesday = fourDayRoutines.first(where: { $0.name.contains("Wednesday") })
expect(wednesday != nil, "Wednesday workout routine is present")
if let wednesday {
    expect(wednesday.phases.allSatisfy { $0.templateID != nil }, "Wednesday workout has a template attached to every phase")
    let wednesdaySession = WorkoutSession.from(routine: wednesday, templates: defaultTemplates, library: ExerciseLibrary.byID)
    let cardioPhase = wednesdaySession.phases.first(where: { $0.phaseType == .preCardio })
    expect(cardioPhase?.activityKind == .elliptical, "Wednesday cardio (Elliptical) maps to elliptical activity")
}

let thursday = fourDayRoutines.first(where: { $0.name.contains("Thursday") })
expect(thursday != nil, "Thursday workout routine is present")
if let thursday {
    expect(thursday.phases.allSatisfy { $0.templateID != nil }, "Thursday workout has a template attached to every phase")
    let thursdaySession = WorkoutSession.from(routine: thursday, templates: defaultTemplates, library: ExerciseLibrary.byID)
    let cardioPhase = thursdaySession.phases.first(where: { $0.phaseType == .preCardio })
    expect(cardioPhase?.activityKind == .running, "Thursday cardio (Treadmill) maps to running activity")
}

let friday = fourDayRoutines.first(where: { $0.name.contains("Friday") })
expect(friday != nil, "Friday workout routine is present")
if let friday {
    expect(friday.phases.allSatisfy { $0.templateID != nil }, "Friday workout has a template attached to every phase")
    let fridaySession = WorkoutSession.from(routine: friday, templates: defaultTemplates, library: ExerciseLibrary.byID)
    let cardioPhase = fridaySession.phases.first(where: { $0.phaseType == .preCardio })
    expect(cardioPhase?.activityKind == .cycling, "Friday cardio (Stationary Bike) maps to cycling activity")
}

let routineSession = WorkoutSession.from(
    routine: defaultRoutine,
    templates: defaultTemplates,
    library: ExerciseLibrary.byID
)
expect(routineSession.isMultiPhase, "multi-phase routine produces a multi-phase session")
expect(routineSession.phases.count == 7, "multi-phase session retains 7 phase logs")
expect(routineSession.currentPhaseIndex == 0, "session starts at phase 0")
expect(routineSession.currentPhase?.phaseType == .preCardio, "first phase is pre-workout cardio")

// Issue #78: a template linked to ANY phase must contribute its exercises to
// the session, not just the main-strength phase.
if let cardioTemplate = defaultTemplates.first(where: { !$0.exercises.isEmpty }) {
    var linkedRoutine = GymSessionRoutine.defaultCompleteGymVisit()
    if let cardioIdx = linkedRoutine.phases.firstIndex(where: { $0.phaseType == .preCardio }) {
        linkedRoutine.phases[cardioIdx].templateID = cardioTemplate.id
        let linkedSession = WorkoutSession.from(
            routine: linkedRoutine,
            templates: defaultTemplates,
            library: ExerciseLibrary.byID
        )
        let cardioPhaseIdx = linkedSession.phases.firstIndex(where: { $0.phaseType == .preCardio })
        let cardioPhaseExercises = cardioPhaseIdx.map { linkedSession.exercises(inPhase: $0) } ?? []
        expect(
            cardioPhaseExercises.count == cardioTemplate.exercises.count,
            "template linked to a non-strength phase populates that phase's exercises"
        )
        expect(
            cardioPhaseExercises.first?.name == cardioTemplate.exercises.first?.name,
            "linked non-strength phase pulls exercises from the correct template"
        )

        // Issue #80: every exercise must be attributed to the phase that owns it,
        // and phase scoping must partition the flat list without gaps or overlap.
        expect(
            linkedSession.exercises.allSatisfy { $0.phaseIndex != nil },
            "every exercise in a routine session carries a phaseIndex"
        )
        let partitioned = linkedSession.phases.indices
            .flatMap { linkedSession.exerciseIndices(inPhase: $0) }
            .sorted()
        expect(
            partitioned == Array(linkedSession.exercises.indices),
            "phase scoping partitions the whole exercise list exactly once"
        )
        if let cardioPhaseIdx {
            expect(
                linkedSession.landingExerciseIndex(forPhase: cardioPhaseIdx)
                    == linkedSession.exerciseIndices(inPhase: cardioPhaseIdx).first,
                "landing index for a fresh phase is its first exercise"
            )
        }
    }
}

// Issue #84: each phase maps to the HealthKit activity that matches it, with
// cardio refined by the machine so a stair stepper isn't logged as generic
// cardio (or, as before, as strength training).
expect(
    PhaseActivityKind.resolve(phaseType: .mainStrength, exerciseNames: []) == .traditionalStrengthTraining,
    "main strength maps to traditional strength training"
)
expect(
    PhaseActivityKind.resolve(phaseType: .coreWork, exerciseNames: []) == .coreTraining,
    "core work maps to core training"
)
expect(
    PhaseActivityKind.resolve(phaseType: .warmupStretches, exerciseNames: []) == .preparationAndRecovery,
    "warm-up stretches map to preparation and recovery"
)
expect(
    PhaseActivityKind.resolve(phaseType: .postStretching, exerciseNames: []) == .flexibility,
    "cool-down maps to flexibility"
)
expect(
    PhaseActivityKind.resolve(phaseType: .saunaRecovery, exerciseNames: []) == .preparationAndRecovery,
    "sauna maps to preparation and recovery"
)
expect(
    PhaseActivityKind.resolve(phaseType: .steamRecovery, exerciseNames: []) == .preparationAndRecovery,
    "steam maps to preparation and recovery"
)
expect(
    PhaseActivityKind.resolve(phaseType: .preCardio, exerciseNames: ["Stair Climber"]) == .stairClimbing,
    "stair climber cardio maps to stair climbing"
)
expect(
    PhaseActivityKind.resolve(phaseType: .preCardio, exerciseNames: ["Elliptical"]) == .elliptical,
    "elliptical cardio maps to elliptical"
)
expect(
    PhaseActivityKind.resolve(phaseType: .preCardio, exerciseNames: ["Treadmill Incline"]) == .running,
    "treadmill cardio maps to running"
)
expect(
    PhaseActivityKind.resolve(phaseType: .preCardio, exerciseNames: ["Rowing Machine"]) == .rowing,
    "rowing cardio maps to rowing"
)
expect(
    PhaseActivityKind.resolve(phaseType: .preCardio, exerciseNames: ["Assault Bike"]) == .cycling,
    "bike cardio maps to cycling"
)
expect(
    PhaseActivityKind.resolve(phaseType: .preCardio, exerciseNames: ["Something Unusual"]) == .mixedCardio,
    "unrecognised cardio falls back to mixed cardio"
)
expect(
    PhaseActivityKind.resolve(phaseType: .preCardio, exerciseNames: []) == .mixedCardio,
    "cardio with no named machine falls back to mixed cardio"
)

// A session resolves the kind per phase, preferring exercises pulled from a
// linked template over the routine's declared names.
let activityRoutine = GymSessionRoutine.defaultCompleteGymVisit()
let activitySession = WorkoutSession.from(
    routine: activityRoutine,
    templates: [],
    library: ExerciseLibrary.byID
)
if let cardioIdx = activitySession.phases.firstIndex(where: { $0.phaseType == .preCardio }),
   let strengthIdx = activitySession.phases.firstIndex(where: { $0.phaseType == .mainStrength }) {
    expect(
        activitySession.activityKind(forPhase: cardioIdx) == .elliptical,
        "default cardio phase resolves from its declared machine names"
    )
    expect(
        activitySession.activityKind(forPhase: strengthIdx) == .traditionalStrengthTraining,
        "strength phase resolves independently of the cardio phase"
    )
}
// A plain workout has no phases and stays strength training.
expect(
    WorkoutSession(name: "Plain", category: .fullBody, exercises: []).currentActivityKind
        == .traditionalStrengthTraining,
    "a non-phase session tracks as strength training"
)

// Issue #80: a plain single-template session has no phases, so navigation scope
// must stay the entire exercise list.
if let plainTemplate = defaultTemplates.first(where: { $0.exercises.count > 1 }) {
    let plainSession = WorkoutSession.from(
        template: plainTemplate,
        library: ExerciseLibrary.byID
    )
    expect(!plainSession.isMultiPhase, "single-template session is not multi-phase")
    expect(
        plainSession.currentPhaseExerciseIndices == Array(plainSession.exercises.indices),
        "single-template session scopes navigation to all exercises"
    )
}

if let routineData = try? JSONEncoder().encode(defaultRoutine),
   let decodedRoutine = try? JSONDecoder().decode(GymSessionRoutine.self, from: routineData) {
    expect(decodedRoutine.name == defaultRoutine.name && decodedRoutine.phases.count == 7, "GymSessionRoutine JSON encode/decode round-trip")
} else {
    failures += 1; print("FAIL GymSessionRoutine JSON encode/decode")
}

let startableRoutine = WatchStartableWorkout.from(
    routine: defaultRoutine,
    templates: defaultTemplates,
    library: ExerciseLibrary.byID,
    settings: AppSettings()
)
expect(startableRoutine.isRoutine, "WatchStartableWorkout accurately flags isRoutine")
expect(startableRoutine.phases.count == 7, "WatchStartableWorkout retains 7 routine phases")

let freshWatchSession = startableRoutine.makeFreshSession()
expect(freshWatchSession.isMultiPhase, "freshWatchSession created from routine is multi-phase")
expect(freshWatchSession.routineID == defaultRoutine.id, "freshWatchSession retains routineID")
expect(freshWatchSession.currentPhaseIndex == 0, "freshWatchSession starts at phase 0")

if let startableData = try? JSONEncoder().encode(startableRoutine),
   let decodedStartable = try? JSONDecoder().decode(WatchStartableWorkout.self, from: startableData) {
    expect(decodedStartable.isRoutine && decodedStartable.phases.count == 7, "WatchStartableWorkout routine JSON round-trip")
} else {
    failures += 1; print("FAIL WatchStartableWorkout routine JSON round-trip")
}

expect(PhaseVisualHelper.iconSymbol(for: "Elliptical") == "figure.elliptical", "PhaseVisualHelper resolves Elliptical icon")
expect(PhaseVisualHelper.iconSymbol(for: "Treadmill Incline") == "figure.run", "PhaseVisualHelper resolves Treadmill icon")
expect(PhaseVisualHelper.iconSymbol(for: "Sauna") == "flame.fill", "PhaseVisualHelper resolves Sauna icon")
expect(PhaseVisualHelper.iconSymbol(for: "Steam") == "cloud.fog.fill", "PhaseVisualHelper resolves Steam icon")
expect(PhaseVisualHelper.iconSymbol(for: "Stair Climber") == "figure.stair.stepper", "PhaseVisualHelper resolves Stair Climber icon")

let timerSnapshot = PhaseTimerSnapshot(endDate: Date().addingTimeInterval(300), totalSeconds: 300)
if let snapshotData = try? JSONEncoder().encode(timerSnapshot),
   let decodedSnapshot = try? JSONDecoder().decode(PhaseTimerSnapshot.self, from: snapshotData) {
    expect(decodedSnapshot.totalSeconds == 300, "PhaseTimerSnapshot JSON encode/decode round-trip")
} else {
    failures += 1; print("FAIL PhaseTimerSnapshot JSON encode/decode round-trip")
}

// MARK: - #91 structured phase exercises and timed-set migration

let legacyRoutinePhaseData = """
{
  "id":"00000000-0000-0000-0000-000000000091",
  "phaseType":"warmupStretches",
  "isEnabled":true,
  "name":"Legacy Warm-Up",
  "durationSeconds":300,
  "exerciseNames":["Leg Swings","Arm Circles"],
  "notes":"Saved before structured items"
}
""".data(using: .utf8)!
if let legacyPhase = try? JSONDecoder().decode(
    GymSessionRoutinePhase.self, from: legacyRoutinePhaseData
) {
    expect(
        legacyPhase.exerciseItems.map(\.name) == ["Leg Swings", "Arm Circles"],
        "legacy routine phase names migrate without loss"
    )
    expect(
        legacyPhase.exerciseItems.allSatisfy {
            $0.durationSeconds == 0 && $0.reps == 0 && $0.sets == 1
        },
        "legacy routine phase names receive default targets"
    )
} else {
    failures += 1; print("FAIL legacy routine phase did not decode")
}

let legacyHistoryPhaseData = """
{
  "id":"00000000-0000-0000-0000-000000000092",
  "phaseType":"postStretching",
  "name":"Legacy Cool-Down",
  "durationSeconds":600,
  "actualDurationSeconds":540,
  "isCompleted":true,
  "exerciseNames":["Hamstring Stretch","Child's Pose"],
  "notes":"Historical phase"
}
""".data(using: .utf8)!
if let legacyHistoryPhase = try? JSONDecoder().decode(
    GymSessionLogPhase.self, from: legacyHistoryPhaseData
) {
    expect(
        legacyHistoryPhase.exerciseNames == ["Hamstring Stretch", "Child's Pose"],
        "legacy history phase names still render after migration"
    )
} else {
    failures += 1; print("FAIL legacy history phase did not decode")
}

expect(legacySet.durationSeconds == 0, "legacy set duration defaults to zero")

let timedExerciseID = UUID()
let timedTemplate = WorkoutTemplate(
    name: "Timed Work",
    exercises: [
        TemplateExercise(
            exerciseID: timedExerciseID,
            name: "Plank",
            targetSets: 1,
            targetReps: 0,
            weight: 0,
            restSeconds: 0,
            durationSeconds: 60
        )
    ]
)
let timedSession = WorkoutSession.from(
    template: timedTemplate,
    library: ExerciseLibrary.byID
)
expect(
    timedSession.exercises.first?.sets.first?.durationSeconds == 60,
    "template duration reaches the generated session set"
)
var completedTimedSession = timedSession
completedTimedSession.exercises[0].sets[0].isCompleted = true
expect(completedTimedSession.totalVolume == 0, "timed sets do not contribute training volume")

let typedItems = [
    PhaseExerciseItem(name: "Plank", durationSeconds: 60),
    PhaseExerciseItem(name: "Bird Dog", reps: 8, sets: 2)
]
let typedRoutine = GymSessionRoutine(
    name: "Typed Routine",
    phases: [
        GymSessionRoutinePhase(
            phaseType: .coreWork,
            exerciseItems: typedItems
        )
    ]
)
let typedHistory = WorkoutSession(
    name: "Typed History",
    phases: [
        GymSessionLogPhase(
            phaseType: .coreWork,
            name: "Core",
            exerciseItems: typedItems
        )
    ]
)
let typedBackup = BackupPayload(
    templates: [timedTemplate],
    gymRoutines: [typedRoutine],
    history: [typedHistory],
    customExercises: [],
    bodyWeights: [],
    settings: AppSettings()
)
if let backupData = try? Backup.encode(typedBackup),
   let restoredBackup = try? Backup.decode(backupData) {
    expect(
        restoredBackup.gymRoutines.first?.phases.first?.exerciseItems == typedItems,
        "backup round-trip preserves structured routine items"
    )
    expect(
        restoredBackup.history.first?.phases.first?.exerciseItems == typedItems,
        "backup round-trip preserves structured history items"
    )
} else {
    failures += 1; print("FAIL structured phase backup did not round-trip")
}

// MARK: - #95 routine composer item editing contract

let libraryTimed = ExerciseLibrary.all.first(where: { $0.name == "Hamstring Stretch" })
expect(
    PhaseExerciseItem(name: "Hamstring Stretch").resolvesAsTimed(
        in: .mainStrength,
        matchedExercise: libraryTimed
    ),
    "library metadata makes a timed item timed even inside strength"
)
expect(
    !PhaseExerciseItem(name: "Custom Reps", reps: 12).resolvesAsTimed(
        in: .warmupStretches,
        matchedExercise: nil
    ),
    "an explicit rep target overrides a timed phase default"
)

var composerPhase = GymSessionRoutinePhase(
    phaseType: .warmupStretches,
    durationSeconds: 300,
    exerciseItems: [
        PhaseExerciseItem(name: "Leg Swings"),
        PhaseExerciseItem(name: "Arm Circles", durationSeconds: 40),
        PhaseExerciseItem(name: "Custom Drill", reps: 12, sets: 2)
    ]
)
expect(
    composerPhase.derivedExerciseDuration() == 100,
    "composer derived duration matches session materialization"
)

// Mirror add/remove/reorder edits made through bindings in the composer.
composerPhase.exerciseItems.swapAt(0, 1)
composerPhase.exerciseItems.remove(at: 2)
composerPhase.exerciseItems.append(
    PhaseExerciseItem(name: "Hip Mobility", durationSeconds: 55)
)
let editedRoutine = GymSessionRoutine(
    name: "Edited Routine",
    phases: [composerPhase]
)

if let persisted = try? JSONEncoder().encode(editedRoutine),
   let relaunched = try? JSONDecoder().decode(GymSessionRoutine.self, from: persisted) {
    expect(
        relaunched.phases[0].exerciseItems.map(\.name)
            == ["Arm Circles", "Leg Swings", "Hip Mobility"],
        "phase item add/remove/reorder survives persistence and relaunch"
    )
    expect(
        relaunched.phases[0].exerciseItems[0].durationSeconds == 40
            && relaunched.phases[0].exerciseItems[2].durationSeconds == 55,
        "per-item duration targets survive persistence"
    )
} else {
    failures += 1; print("FAIL edited routine did not persist")
}

let editedSession = WorkoutSession.from(
    routine: editedRoutine,
    templates: [],
    library: ExerciseLibrary.byID
)
expect(
    editedSession.exercises.map(\.name)
        == ["Arm Circles", "Leg Swings", "Hip Mobility"],
    "starting an edited routine runs the edited item order"
)
expect(
    editedSession.exercises[0].sets[0].durationSeconds == 40
        && editedSession.exercises[1].sets[0].durationSeconds == 100
        && editedSession.exercises[2].sets[0].durationSeconds == 55,
    "explicit and derived composer durations reach the active session"
)

let editedWatchPlan = WatchStartableWorkout(
    routine: editedRoutine,
    templates: [],
    library: ExerciseLibrary.byID,
    settings: AppSettings()
)
expect(
    editedWatchPlan.makeFreshSession().exercises.map(\.name)
        == editedSession.exercises.map(\.name),
    "edited phase items reach the Watch offline-start cache"
)
let composerExecutionSettings = WatchExecutionSettings()
let composerCacheBefore = WatchPlanCache().advanced(
    workouts: [],
    executionSettings: composerExecutionSettings
)
let composerCacheAfter = composerCacheBefore.advanced(
    workouts: [editedWatchPlan],
    executionSettings: composerExecutionSettings
)
expect(
    composerCacheAfter.revision == composerCacheBefore.revision + 1,
    "saving edited phase items produces a newer Watch plan-cache revision"
)
expect(
    composerCacheAfter.workouts.first?.phases.first?.exerciseItems
        == composerPhase.exerciseItems,
    "the newer Watch cache snapshots edited names, order and targets"
)

var linkedPhase = composerPhase
linkedPhase.templateID = timedTemplate.id
let linkedRoutine = GymSessionRoutine(
    name: "Linked Precedence",
    phases: [linkedPhase]
)
let templateBeforeComposerEdit = timedTemplate
let linkedSession = WorkoutSession.from(
    routine: linkedRoutine,
    templates: [timedTemplate],
    library: ExerciseLibrary.byID
)
expect(
    linkedSession.exercises.map(\.name) == timedSession.exercises.map(\.name),
    "a linked template takes precedence over the phase item fallback"
)
expect(
    timedTemplate == templateBeforeComposerEdit,
    "editing phase items never mutates the linked workout template"
)

// MARK: - #96 live exercise list mutation contract

let liveSettings = AppSettings()
let liveBarbell = ExerciseLibrary.all.first { $0.name == "Barbell Bench Press" }!
let liveCable = ExerciseLibrary.all.first { $0.name == "Incline Dumbbell Press" }!
let liveTimed = ExerciseLibrary.all.first { $0.isTimed }!
let liveConfigured = TemplateExercise.defaultConfiguration(
    for: liveBarbell,
    settings: liveSettings,
    preferredWeight: 80
)
let liveConstructed = WorkoutSession.makeSessionExercise(
    for: liveBarbell,
    settings: liveSettings,
    preferredWeight: 80
)
let templateConstructed = WorkoutSession.from(
    template: WorkoutTemplate(
        name: "Factory Parity",
        exercises: [liveConfigured]
    ),
    library: ExerciseLibrary.byID,
    settings: liveSettings
).exercises[0]
expect(
    liveConstructed.exerciseID == templateConstructed.exerciseID
        && liveConstructed.loadingMode == templateConstructed.loadingMode
        && liveConstructed.usesWeight == templateConstructed.usesWeight
        && liveConstructed.sets.map {
            ($0.reps, $0.weight, $0.isWarmup)
        }.elementsEqual(
            templateConstructed.sets.map {
                ($0.reps, $0.weight, $0.isWarmup)
            },
            by: ==
        ),
    "mid-workout construction matches template startup loading and warmups"
)
expect(
    liveConstructed.sets.contains(where: \.isWarmup),
    "live barbell construction uses the configured warmup path"
)
let liveTimedConstructed = WorkoutSession.makeSessionExercise(
    for: liveTimed,
    settings: liveSettings
)
expect(
    liveTimedConstructed.usesGuidedTimedStepper
        && liveTimedConstructed.sets[0].durationSeconds > 0,
    "live timed construction uses the same timed-session shape"
)

let livePhases = [
    GymSessionLogPhase(phaseType: .warmupStretches, name: "Warm-Up"),
    GymSessionLogPhase(phaseType: .mainStrength, name: "Strength"),
    GymSessionLogPhase(phaseType: .postStretching, name: "Cool-Down")
]
let liveA = SessionExercise(
    exerciseID: UUID(),
    name: "A",
    sets: [SetEntry(reps: 10, weight: 0)],
    phaseIndex: 0
)
let liveB = SessionExercise(
    exerciseID: UUID(),
    name: "B",
    sets: [SetEntry(reps: 10, weight: 0)],
    phaseIndex: 0
)
let liveC = SessionExercise(
    exerciseID: UUID(),
    name: "C",
    sets: [SetEntry(reps: 10, weight: 0)],
    phaseIndex: 2
)
var liveMutationSession = WorkoutSession(
    name: "Live Edits",
    exercises: [liveA, liveB, liveC],
    phases: livePhases
)
let addedPhaseZeroIndex = liveMutationSession.addExercise(
    liveConstructed,
    toPhase: 0
)
expect(
    addedPhaseZeroIndex == 2
        && liveMutationSession.exercises.map(\.name)
            == ["A", "B", liveBarbell.name, "C"],
    "live add inserts at the end of the requested phase run"
)
expect(
    liveMutationSession.exercises[2].phaseIndex == 0,
    "live add stamps the requested phase"
)
let addedEmptyPhaseIndex = liveMutationSession.addExercise(
    liveTimedConstructed,
    toPhase: 1
)
expect(
    addedEmptyPhaseIndex == 3
        && liveMutationSession.exercises[3].phaseIndex == 1
        && liveMutationSession.exercises[4].name == "C",
    "live add fills an empty phase before the next populated phase"
)

let replacement = WorkoutSession.makeSessionExercise(
    for: liveCable,
    settings: liveSettings
)
let replacedLive = liveMutationSession.replaceExercise(
    at: 1,
    with: replacement
)
expect(
    replacedLive
        && liveMutationSession.exercises[1].name == liveCable.name
        && liveMutationSession.exercises[1].phaseIndex == 0,
    "live swap keeps the original position and phase attribution"
)
liveMutationSession.exercises[1].sets[0].isCompleted = true
expect(
    !liveMutationSession.replaceExercise(
        at: 1,
        with: liveConstructed
    ),
    "live swap cannot discard completed sets"
)
expect(
    liveMutationSession.removeExercise(at: 1) == nil,
    "live removal blocks an exercise with completed sets"
)
expect(
    liveMutationSession.removeExercise(at: 0)?.name == "A",
    "live removal accepts an exercise with no completed sets"
)

let timedWatchPlan = WatchStartableWorkout(
    template: timedTemplate,
    library: ExerciseLibrary.byID,
    settings: AppSettings()
)
if let cacheData = try? JSONEncoder().encode(
    WatchPlanCache(workouts: [timedWatchPlan])
),
   let restoredCache = try? JSONDecoder().decode(WatchPlanCache.self, from: cacheData) {
    let restoredSet = restoredCache.workouts.first?.makeFreshSession()
        .exercises.first?.sets.first
    expect(restoredSet?.durationSeconds == 60, "Watch plan cache preserves timed-set duration")
} else {
    failures += 1; print("FAIL timed Watch plan cache did not round-trip")
}

let legacyTimedWatchPlan = WatchStartableWorkout(
    templateID: UUID(),
    name: "Legacy Timed Plan",
    category: .stretching,
    exercises: [
        WatchStartableExercise(
            exerciseID: timedExerciseID,
            name: "Plank",
            sets: [WatchStartableSet(reps: 0, weight: 0)],
            restSeconds: 0,
            usesWeight: false,
            durationSeconds: 45
        )
    ]
)
if let encodedLegacyPlan = try? JSONEncoder().encode(legacyTimedWatchPlan),
   var legacyObject = try? JSONSerialization.jsonObject(
       with: encodedLegacyPlan
   ) as? [String: Any],
   var legacyExercises = legacyObject["exercises"] as? [[String: Any]],
   var legacyExercise = legacyExercises.first,
   var legacySets = legacyExercise["sets"] as? [[String: Any]],
   var legacySet = legacySets.first {
    legacySet.removeValue(forKey: "durationSeconds")
    legacySets[0] = legacySet
    legacyExercise["sets"] = legacySets
    legacyExercises[0] = legacyExercise
    legacyObject["exercises"] = legacyExercises
    if let legacyData = try? JSONSerialization.data(withJSONObject: legacyObject),
       let decodedLegacyPlan = try? JSONDecoder().decode(
           WatchStartableWorkout.self,
           from: legacyData
       ) {
        expect(
            decodedLegacyPlan.makeFreshSession()
                .exercises.first?.sets.first?.durationSeconds == 45,
            "legacy Watch cache exercise duration migrates onto its fresh session set"
        )
    } else {
        failures += 1
        print("FAIL legacy Watch cache fixture did not decode")
    }
} else {
    failures += 1
    print("FAIL legacy Watch cache fixture could not be created")
}

let mixedWatchPlan = WatchStartableWorkout(
    templateID: UUID(),
    name: "Mixed Set Plan",
    category: .core,
    exercises: [
        WatchStartableExercise(
            exerciseID: UUID(),
            name: "Mixed Hold",
            sets: [
                WatchStartableSet(
                    reps: 0,
                    weight: 0,
                    durationSeconds: 30
                ),
                WatchStartableSet(
                    reps: 8,
                    weight: 0,
                    durationSeconds: 0
                )
            ],
            restSeconds: 60,
            usesWeight: false,
            durationSeconds: 30
        )
    ]
)
if let mixedData = try? JSONEncoder().encode(mixedWatchPlan),
   let decodedMixedPlan = try? JSONDecoder().decode(
       WatchStartableWorkout.self,
       from: mixedData
   ) {
    let restoredMixed = decodedMixedPlan.makeFreshSession().exercises[0]
    expect(
        restoredMixed.sets.map(\.durationSeconds) == [30, 0],
        "Watch cache keeps explicit rep sets rep-based in a mixed exercise"
    )
    expect(
        !restoredMixed.usesGuidedTimedStepper,
        "Watch cache round-trip keeps a mixed exercise in the set logger"
    )
} else {
    failures += 1
    print("FAIL mixed Watch plan cache did not round-trip")
}

// MARK: - #92 materialize every declared phase exercise

let parityTemplate = defaultTemplates[0]
let plainParitySession = WorkoutSession.from(
    template: parityTemplate,
    library: ExerciseLibrary.byID
)
let linkedParityRoutine = GymSessionRoutine(
    name: "Linked parity",
    phases: [
        GymSessionRoutinePhase(
            phaseType: .mainStrength,
            templateID: parityTemplate.id,
            exerciseItems: []
        )
    ]
)
let linkedParitySession = WorkoutSession.from(
    routine: linkedParityRoutine,
    templates: [parityTemplate],
    library: ExerciseLibrary.byID
)
expect(
    linkedParitySession.exercises.count == plainParitySession.exercises.count,
    "linked phase keeps the template exercise count"
)
expect(
    zip(linkedParitySession.exercises, plainParitySession.exercises).allSatisfy { linked, plain in
        linked.exerciseID == plain.exerciseID
            && linked.name == plain.name
            && linked.sets.map(\.reps) == plain.sets.map(\.reps)
            && linked.sets.map(\.weight) == plain.sets.map(\.weight)
            && linked.sets.map(\.durationSeconds) == plain.sets.map(\.durationSeconds)
            && linked.restSeconds == plain.restSeconds
            && linked.usesWeight == plain.usesWeight
            && linked.loadingMode == plain.loadingMode
    },
    "linked phase preserves the template exercise execution shape"
)

let materializedRoutine = GymSessionRoutine(
    name: "Materialized phases",
    phases: [
        GymSessionRoutinePhase(
            phaseType: .warmupStretches,
            durationSeconds: 300,
            exerciseItems: [
                PhaseExerciseItem(name: "Leg Swings"),
                PhaseExerciseItem(name: "Arm Circles", durationSeconds: 45),
                PhaseExerciseItem(name: "Hip Mobility"),
                PhaseExerciseItem(name: "Unlisted Mobility Drill"),
                PhaseExerciseItem(name: "Warm-Up Reps", reps: 12, sets: 2)
            ]
        ),
        GymSessionRoutinePhase(
            phaseType: .saunaRecovery,
            durationSeconds: 900,
            exerciseItems: []
        )
    ]
)
let materializedSession = WorkoutSession.from(
    routine: materializedRoutine,
    templates: [],
    library: ExerciseLibrary.byID
)
let warmupMaterialized = materializedSession.exercises(inPhase: 0)
expect(warmupMaterialized.count == 5, "one session exercise is materialized per phase item")
expect(
    warmupMaterialized.allSatisfy { $0.phaseIndex == 0 },
    "materialized exercises carry their owning phase index"
)
expect(
    warmupMaterialized[0].sets.first?.durationSeconds == 60
        && warmupMaterialized[1].sets.first?.durationSeconds == 45,
    "timed items use derived duration unless an explicit duration wins"
)
expect(
    warmupMaterialized.allSatisfy { $0.restSeconds == 0 },
    "warm-up materialization defaults to zero rest"
)
expect(
    warmupMaterialized[3].name == "Unlisted Mobility Drill"
        && !warmupMaterialized[3].usesWeight
        && warmupMaterialized[3].loadingMode == .bodyweight,
    "unmatched phase item remains a usable non-weighted entry"
)
expect(
    warmupMaterialized[4].sets.count == 2
        && warmupMaterialized[4].sets.allSatisfy {
            $0.reps == 12 && $0.durationSeconds == 0
        },
    "explicit rep targets override a timed phase default"
)
expect(
    materializedSession.exercises(inPhase: 1).isEmpty,
    "an empty recovery phase remains timer-only"
)

let legacyRecoveryRoutineData = """
{
  "id":"00000000-0000-0000-0000-000000000192",
  "name":"Legacy Recovery",
  "notes":"",
  "createdAt":0,
  "phases":[{
    "id":"00000000-0000-0000-0000-000000000193",
    "phaseType":"saunaRecovery",
    "isEnabled":true,
    "name":"Sauna Recovery",
    "durationSeconds":900,
    "exerciseItems":[{
      "id":"00000000-0000-0000-0000-000000000194",
      "name":"Sauna Heat Therapy (Hydrate 500ml)",
      "durationSeconds":0,
      "reps":0,
      "sets":1
    }],
    "notes":""
  }]
}
""".data(using: .utf8)!
if let legacyRecovery = try? JSONDecoder().decode(
    GymSessionRoutine.self, from: legacyRecoveryRoutineData
) {
    expect(
        legacyRecovery.phases.first?.exerciseItems.isEmpty == true,
        "legacy shipped Sauna placeholder migrates back to timer-only"
    )
} else {
    failures += 1; print("FAIL legacy recovery routine did not decode")
}

let lowClampRoutine = GymSessionRoutine(
    name: "Low duration clamp",
    phases: [
        GymSessionRoutinePhase(
            phaseType: .warmupStretches,
            durationSeconds: 10,
            exerciseItems: [
                PhaseExerciseItem(name: "Quick A"),
                PhaseExerciseItem(name: "Quick B")
            ]
        )
    ]
)
let lowClampSession = WorkoutSession.from(
    routine: lowClampRoutine,
    templates: [],
    library: [:]
)
expect(
    lowClampSession.exercises.allSatisfy { $0.sets.first?.durationSeconds == 20 },
    "derived item duration clamps to a 20-second minimum"
)

let highClampRoutine = GymSessionRoutine(
    name: "High duration clamp",
    phases: [
        GymSessionRoutinePhase(
            phaseType: .postStretching,
            durationSeconds: 3600,
            exerciseItems: [
                PhaseExerciseItem(name: "Long A"),
                PhaseExerciseItem(name: "Long B")
            ]
        )
    ]
)
let highClampSession = WorkoutSession.from(
    routine: highClampRoutine,
    templates: [],
    library: [:]
)
expect(
    highClampSession.exercises.allSatisfy { $0.sets.first?.durationSeconds == 180 },
    "derived item duration clamps to a 180-second maximum"
)

let defaultMaterializedRoutine = GymSessionRoutine.defaultCompleteGymVisit(
    templates: defaultTemplates
)
let defaultMaterializedSession = WorkoutSession.from(
    routine: defaultMaterializedRoutine,
    templates: defaultTemplates,
    library: ExerciseLibrary.byID
)
let defaultWarmupIndex = defaultMaterializedSession.phases.firstIndex {
    $0.phaseType == .warmupStretches
}!
let defaultWarmupExercises = defaultMaterializedSession.exercises(
    inPhase: defaultWarmupIndex
)
expect(
    defaultWarmupExercises.count >= 3,
    "default Dynamic Warm-Up materializes three or more exercises"
)
expect(
    defaultMaterializedSession.hasNextExerciseInCurrentPhase(
        after: defaultMaterializedSession.exerciseIndices(inPhase: 0).first!
    ),
    "default first phase materialization is navigable"
)

let defaultCoreIndex = defaultMaterializedSession.phases.firstIndex {
    $0.phaseType == .coreWork
}!
expect(
    defaultMaterializedSession.exercises(inPhase: defaultCoreIndex).map(\.name)
        == ["Plank", "Ab Rollout", "Hanging Knee Raise", "Cable Crunch"],
    "core work flows through declared defaults without a special branch"
)
let defaultSaunaIndex = defaultMaterializedSession.phases.firstIndex {
    $0.phaseType == .saunaRecovery
}!
let defaultSteamIndex = defaultMaterializedSession.phases.firstIndex {
    $0.phaseType == .steamRecovery
}!
expect(
    defaultMaterializedSession.exercises(inPhase: defaultSaunaIndex).isEmpty
        && defaultMaterializedSession.exercises(inPhase: defaultSteamIndex).isEmpty,
    "default Sauna and Steam remain timer-only"
)
let defaultCardioIndex = defaultMaterializedSession.phases.firstIndex {
    $0.phaseType == .preCardio
}!
expect(
    defaultMaterializedSession.activityKind(forPhase: defaultCardioIndex) == .elliptical,
    "materialized cardio retains machine-specific activity classification"
)

let materializedWatchPlan = WatchStartableWorkout(
    routine: defaultMaterializedRoutine,
    templates: defaultTemplates,
    library: ExerciseLibrary.byID,
    settings: AppSettings()
)
let watchWarmup = materializedWatchPlan.makeFreshSession()
    .exercises(inPhase: defaultWarmupIndex)
expect(
    watchWarmup.map(\.name) == defaultWarmupExercises.map(\.name),
    "offline Watch plan exposes the same materialized warm-up list"
)

// MARK: - #90 phase-boundary navigation availability
//
// The flat `exercises` array concatenates every phase, so a global bound is not
// a phase bound. These assert the two must not be confused: availability is
// always phase-relative, and it has to agree with what the navigation actions
// actually do.

func phaseBoundarySession() -> WorkoutSession {
    // Phase 0: two exercises (global 0,1). Phase 1: two exercises (global 2,3).
    var exercises: [SessionExercise] = (0..<4).map { i in
        SessionExercise(
            exerciseID: UUID(),
            name: "Exercise \(i)",
            sets: [SetEntry(reps: 5, weight: 50)]
        )
    }
    exercises[0].phaseIndex = 0
    exercises[1].phaseIndex = 0
    exercises[2].phaseIndex = 1
    exercises[3].phaseIndex = 1
    return WorkoutSession(
        name: "Boundary",
        exercises: exercises,
        phases: [
            GymSessionLogPhase(phaseType: .warmupStretches, name: "Warm-Up"),
            GymSessionLogPhase(phaseType: .mainStrength, name: "Strength")
        ],
        currentPhaseIndex: 0
    )
}

var boundary = phaseBoundarySession()

// Phase 0, first exercise: no previous, has next.
expect(!boundary.hasPreviousExerciseInCurrentPhase(before: 0), "phase start has no previous exercise")
expect(boundary.hasNextExerciseInCurrentPhase(after: 0), "phase start has a next exercise")

// Phase 0, last exercise. Global index 1 is NOT the last of the flat array
// (which has 4), so a global bound would wrongly report a next exercise here.
expect(boundary.hasPreviousExerciseInCurrentPhase(before: 1), "phase end has a previous exercise")
expect(!boundary.hasNextExerciseInCurrentPhase(after: 1), "phase end reports no next exercise despite later phases existing")

// Phase 1, first exercise. Global index 2 is > 0, so a global bound would
// wrongly report a previous exercise here.
boundary.currentPhaseIndex = 1
expect(!boundary.hasPreviousExerciseInCurrentPhase(before: 2), "later phase's first exercise reports no previous despite a non-zero global index")
expect(boundary.hasNextExerciseInCurrentPhase(after: 2), "later phase's first exercise has a next")
expect(!boundary.hasNextExerciseInCurrentPhase(after: 3), "final exercise of final phase has no next")

// An index belonging to another phase is out of scope in both directions.
expect(!boundary.hasNextExerciseInCurrentPhase(after: 0), "an index from another phase reports no next")
expect(!boundary.hasPreviousExerciseInCurrentPhase(before: 1), "an index from another phase reports no previous")

// hasNextPhase drives the Watch's "what comes next" choice.
boundary.currentPhaseIndex = 0
expect(boundary.hasNextPhase, "a further phase is reported while one remains")
boundary.currentPhaseIndex = 1
expect(!boundary.hasNextPhase, "no further phase is reported on the last phase")

// A single-exercise phase has neither direction available.
var lonePhase = phaseBoundarySession()
lonePhase.exercises = [lonePhase.exercises[0]]
expect(!lonePhase.hasNextExerciseInCurrentPhase(after: 0), "a one-exercise phase has no next")
expect(!lonePhase.hasPreviousExerciseInCurrentPhase(before: 0), "a one-exercise phase has no previous")

// A plain template session has no phases: navigation spans the whole list and
// must behave exactly as it did before phase scoping existed.
let plain = WorkoutSession(
    name: "Plain",
    exercises: (0..<3).map {
        SessionExercise(exerciseID: UUID(), name: "E\($0)", sets: [SetEntry(reps: 5, weight: 50)])
    }
)
expect(!plain.hasPreviousExerciseInCurrentPhase(before: 0), "plain session: first exercise has no previous")
expect(plain.hasNextExerciseInCurrentPhase(after: 0), "plain session: first exercise has a next")
expect(plain.hasNextExerciseInCurrentPhase(after: 1), "plain session: middle exercise has a next")
expect(!plain.hasNextExerciseInCurrentPhase(after: 2), "plain session: last exercise has no next")
expect(plain.hasPreviousExerciseInCurrentPhase(before: 2), "plain session: last exercise has a previous")
expect(!plain.hasNextPhase, "plain session reports no next phase")

// Issue #94: guided presentation is selected by exercise shape, never by the
// phase label. A timed mobility item inside strength is guided; weighted or
// mixed-duration work stays in the normal set logger.
let timedMobility = SessionExercise(
    exerciseID: UUID(),
    name: "Timed Mobility",
    sets: [SetEntry(reps: 0, weight: 0, durationSeconds: 45)],
    usesWeight: false,
    phaseIndex: 0
)
expect(timedMobility.usesGuidedTimedStepper, "timed non-weighted exercise uses the guided stepper")

let weightedTimed = SessionExercise(
    exerciseID: UUID(),
    name: "Weighted Hold",
    sets: [SetEntry(reps: 0, weight: 20, durationSeconds: 30)],
    usesWeight: true,
    phaseIndex: 0
)
expect(!weightedTimed.usesGuidedTimedStepper, "weighted timed exercise keeps the set logger")

let mixedWork = SessionExercise(
    exerciseID: UUID(),
    name: "Mixed Work",
    sets: [
        SetEntry(reps: 0, weight: 0, durationSeconds: 30),
        SetEntry(reps: 8, weight: 0)
    ],
    usesWeight: false,
    phaseIndex: 0
)
expect(!mixedWork.usesGuidedTimedStepper, "mixed timed and rep sets keep the set logger")

print(failures == 0 ? "ALL TESTS PASSED" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
