// Standalone assertions for Progression — compiled with the real model files.
import Foundation

var failures = 0
func expect(_ cond: Bool, _ label: String) {
    if cond { print("PASS \(label)") } else { failures += 1; print("FAIL \(label)") }
}

let squatID = UUID(), dlID = UUID(), pressID = UUID(), bwID = UUID()

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

print(failures == 0 ? "ALL TESTS PASSED" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
