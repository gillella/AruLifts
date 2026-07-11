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

print(failures == 0 ? "ALL TESTS PASSED" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
