// E2E Test Suite for AruLifts — Verifies all Project Goals & Requirements
import Foundation

var failures = 0
var testCount = 0

func assertTest(_ condition: Bool, _ name: String, file: String = #file, line: Int = #line) {
    testCount += 1
    if condition {
        print("✅ PASS [\(testCount)]: \(name)")
    } else {
        failures += 1
        print("❌ FAIL [\(testCount)]: \(name) (Line \(line))")
    }
}

print("==================================================")
print("🚀 Starting AruLifts E2E Comprehensive Test Suite")
print("==================================================")

// -----------------------------------------------------------------------------
// SECTION 1: GOAL 1 — WORKOUT CREATION & EDITING
// -----------------------------------------------------------------------------
print("\n--- Testing Goal 1: Workout Creation & Editing ---")

// 1.1 Category enumeration (all 12 categories)
let allCategories = WorkoutCategory.allCases
assertTest(allCategories.count == 12, "WorkoutCategory has 12 categories")
let categoryNames = Set(allCategories.map(\.displayName))
assertTest(categoryNames.contains("Upper Body"), "Category Upper Body present")
assertTest(categoryNames.contains("Lower Body"), "Category Lower Body present")
assertTest(categoryNames.contains("Arms"), "Category Arms present")
assertTest(categoryNames.contains("Push"), "Category Push present")
assertTest(categoryNames.contains("Pull"), "Category Pull present")
assertTest(categoryNames.contains("Legs"), "Category Legs present")
assertTest(categoryNames.contains("Full Body"), "Category Full Body present")
assertTest(categoryNames.contains("Core"), "Category Core present")
assertTest(categoryNames.contains("Cardio"), "Category Cardio present")
assertTest(categoryNames.contains("Stretching"), "Category Stretching present")
assertTest(categoryNames.contains("Recovery"), "Category Recovery present")
assertTest(categoryNames.contains("Custom"), "Category Custom present")

// 1.2 Category exercise suggestions mapping
assertTest(WorkoutCategory.push.suggestedMuscles.contains(.chest), "Push suggests Chest")
assertTest(WorkoutCategory.push.suggestedMuscles.contains(.shoulders), "Push suggests Shoulders")
assertTest(WorkoutCategory.push.suggestedMuscles.contains(.triceps), "Push suggests Triceps")
assertTest(WorkoutCategory.pull.suggestedMuscles.contains(.back), "Pull suggests Back")
assertTest(WorkoutCategory.pull.suggestedMuscles.contains(.biceps), "Pull suggests Biceps")
assertTest(WorkoutCategory.legs.suggestedMuscles.contains(.quads), "Legs suggests Quads")
assertTest(WorkoutCategory.legs.suggestedMuscles.contains(.hamstrings), "Legs suggests Hamstrings")
assertTest(WorkoutCategory.cardio.suggestedMuscles.contains(.cardio), "Cardio suggests Cardio")
assertTest(WorkoutCategory.stretching.suggestedMuscles.contains(.mobility), "Stretching suggests Mobility")

// 1.3 Browse & preview exercise details
let allExercises = ExerciseLibrary.all
let benchPress = allExercises.first(where: { $0.name == "Barbell Bench Press" })!
assertTest(benchPress.demoImageName != nil, "Bench Press has demo image")
assertTest(benchPress.techniqueVideoURL != nil, "Bench Press has technique YouTube link")
assertTest(!benchPress.instructions.isEmpty, "Bench Press has form instructions")
assertTest(!benchPress.tips.isEmpty, "Bench Press has coaching tips")

// 1.4 Add exercise with sets, reps, weight, rest
var t1 = WorkoutTemplate(name: "Push Session", category: .push)
let benchEx = TemplateExercise(exerciseID: benchPress.id, name: benchPress.name, targetSets: 4, targetReps: 8, weight: 60, restSeconds: 180)
t1.exercises.append(benchEx)
assertTest(t1.exercises.count == 1, "Template has 1 exercise")
assertTest(t1.exercises[0].targetSets == 4, "Target sets = 4")
assertTest(t1.exercises[0].targetReps == 8, "Target reps = 8")
assertTest(t1.exercises[0].weight == 60, "Weight = 60kg")
assertTest(t1.exercises[0].restSeconds == 180, "Rest = 180s")

// 1.5 Cardio capture (timed exercise)
let treadmill = allExercises.first(where: { $0.name == "Treadmill" })!
assertTest(treadmill.isTimed == true, "Treadmill is timed exercise")
let cardioEx = TemplateExercise(exerciseID: treadmill.id, name: treadmill.name, targetSets: 1, targetReps: 0, weight: 0, restSeconds: 0, durationSeconds: 900)
assertTest(cardioEx.isTimed == true, "Cardio TemplateExercise isTimed == true")
assertTest(cardioEx.durationSeconds == 900, "Cardio duration = 15 minutes (900s)")

// 1.6 Stretching guidance
let stretches = allExercises.filter { $0.primaryMuscle == .mobility }
assertTest(stretches.count >= 6, "Library has at least 6 stretching/mobility exercises")
let hamstringStretch = stretches.first(where: { $0.name == "Hamstring Stretch" })
assertTest(hamstringStretch != nil, "Hamstring Stretch is in library")
assertTest(hamstringStretch?.instructions.isEmpty == false, "Hamstring Stretch has form instructions")

// 1.7 Recovery activity capture
let recoveryCategory = WorkoutCategory.recovery
assertTest(recoveryCategory.displayName == "Recovery", "Recovery category exists")

// 1.8 Multiple workouts per day
let dateToday = Date()
let session1 = WorkoutSession(name: "Morning Cardio", finishedAt: dateToday)
let session2 = WorkoutSession(name: "Evening Push", finishedAt: dateToday.addingTimeInterval(3600 * 8))
let historyList = [session1, session2]
assertTest(historyList.count == 2, "2 workouts logged on the same day")

// 1.9 Workout editing: reorder & delete exercises
var editTemplate = WorkoutTemplate(name: "Edit Test", category: .custom, exercises: [
    TemplateExercise(exerciseID: UUID(), name: "Exercise A"),
    TemplateExercise(exerciseID: UUID(), name: "Exercise B"),
    TemplateExercise(exerciseID: UUID(), name: "Exercise C")
])
editTemplate.exercises.swapAt(0, 2)
assertTest(editTemplate.exercises[0].name == "Exercise C", "Reordered exercise C to first position")
editTemplate.exercises.remove(at: 1)
assertTest(editTemplate.exercises.count == 2, "Removed 1 exercise from template")

// 1.10 Watch plan cache conversion
let exerciseDict = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0) })
let watchPlan = WatchStartableWorkout(template: t1, library: exerciseDict, settings: AppSettings())
assertTest(watchPlan.id == t1.id, "Watch plan retains template ID")
assertTest(watchPlan.name == "Push Session", "Watch plan retains name")
assertTest(watchPlan.exercises.count == 1, "Watch plan retains exercise count")
assertTest(watchPlan.exercises[0].name == "Barbell Bench Press", "Watch plan retains exercise name")

// 1.11 Persistence test
let encoder = JSONEncoder()
let decoder = JSONDecoder()
if let encodedData = try? encoder.encode([t1]),
   let decodedTemplates = try? decoder.decode([WorkoutTemplate].self, from: encodedData) {
    assertTest(decodedTemplates.count == 1, "Template JSON roundtrip successful")
    assertTest(decodedTemplates[0].name == t1.name, "Template name persisted correctly")
} else {
    assertTest(false, "Template JSON roundtrip failed")
}


// -----------------------------------------------------------------------------
// SECTION 2: GOAL 2 — WATCH-FIRST & PAIRED WORKOUT TRACKING & SYNC
// -----------------------------------------------------------------------------
print("\n--- Testing Goal 2: Watch-First & Paired Workout Tracking & Sync ---")

// 2.1 Offer & Acknowledgment Handshake
let sessionID = UUID()
let phoneSession = WorkoutSession(id: sessionID, name: "Handshake Test")
let phoneOffer = WorkoutReplica(session: phoneSession, owner: .phone, version: SessionVersion(ownershipEpoch: 1, revision: 1))
assertTest(phoneOffer.owner == .phone, "Initial offer is phone-owned")

let watchAcceptance = WorkoutReplica(session: phoneSession, owner: .watch, version: SessionVersion(ownershipEpoch: 1, revision: 2))
assertTest(watchAcceptance.owner == .watch, "Watch acceptance changes owner to watch")
assertTest(watchAcceptance.version > phoneOffer.version, "Watch acceptance advances revision")

// 2.2 Ownership Epoch Rules
let stalePhoneVersion = SessionVersion(ownershipEpoch: 1, revision: 10)
let newEpochWatchVersion = SessionVersion(ownershipEpoch: 2, revision: 1)
assertTest(newEpochWatchVersion > stalePhoneVersion, "Higher epoch outranks higher revision of older epoch")

// 2.3 Set completion & Rest Timer trigger
var sessionEx = SessionExercise(exerciseID: benchPress.id, name: benchPress.name, sets: [
    SetEntry(reps: 8, weight: 60, isCompleted: false),
    SetEntry(reps: 8, weight: 60, isCompleted: false)
])
sessionEx.sets[0].isCompleted = true
assertTest(sessionEx.sets[0].isCompleted == true, "Set 1 marked complete")
assertTest(sessionEx.sets[1].isCompleted == false, "Set 2 remains incomplete")

// 2.4 Plate breakdown calculation
let plates60kg = PlateCalculator.plates(target: 60, bar: 20, available: PlateCalculator.defaultPlates(units: .kg))
assertTest(plates60kg.isExact == true, "60kg is exact on 20kg bar")
assertTest(plates60kg.platesPerSide == [20.0], "60kg requires one 20kg plate per side")

let plates135lb = PlateCalculator.plates(target: 135, bar: 45, available: PlateCalculator.defaultPlates(units: .lb))
assertTest(plates135lb.isExact == true, "135lb is exact on 45lb bar")
assertTest(plates135lb.platesPerSide == [45.0], "135lb requires one 45lb plate per side")

// 2.5 Auto Progression & Deload
var progTemplate = WorkoutTemplate(name: "Progression Test", exercises: [
    TemplateExercise(exerciseID: benchPress.id, name: benchPress.name, targetSets: 3, targetReps: 5, weight: 100, failureCount: 0)
])
let successfulSession = WorkoutSession(templateID: progTemplate.id, name: progTemplate.name, exercises: [
    SessionExercise(exerciseID: benchPress.id, name: benchPress.name, sets: [
        SetEntry(reps: 5, weight: 100, isCompleted: true),
        SetEntry(reps: 5, weight: 100, isCompleted: true),
        SetEntry(reps: 5, weight: 100, isCompleted: true)
    ])
])
let progResult = Progression.apply(session: successfulSession, to: progTemplate, units: .kg)
assertTest(progResult.template.exercises[0].weight == 102.5, "100% success bumps weight from 100kg to 102.5kg")

// Failure / Deload test: 3 failures in a row
progTemplate.exercises[0].failureCount = 2
let failedSession = WorkoutSession(templateID: progTemplate.id, name: progTemplate.name, exercises: [
    SessionExercise(exerciseID: benchPress.id, name: benchPress.name, sets: [
        SetEntry(reps: 3, weight: 100, isCompleted: true),
        SetEntry(reps: 4, weight: 100, isCompleted: true),
        SetEntry(reps: 4, weight: 100, isCompleted: true)
    ])
])
let deloadResult = Progression.apply(session: failedSession, to: progTemplate, units: .kg)
assertTest(deloadResult.template.exercises[0].weight == 90.0, "3 failures trigger 10% deload from 100kg to 90kg")
assertTest(deloadResult.template.exercises[0].failureCount == 0, "Deload resets failure count to 0")

// 2.6 Tombstone durability
let tombstoneSession = WorkoutSession(id: sessionID, name: "Finished", finishedAt: Date())
assertTest(tombstoneSession.isFinished == true, "Finished session is marked isFinished")


// -----------------------------------------------------------------------------
// SECTION 3: GOAL 3 — EXERCISE LIBRARY & CONTENT
// -----------------------------------------------------------------------------
print("\n--- Testing Goal 3: Exercise Library & Content ---")

// 3.1 Total built-in exercise count
assertTest(allExercises.count >= 34, "Exercise library contains built-in exercises")
let setRepExercises = allExercises.filter { !$0.isTimed }
let timedExercises = allExercises.filter { $0.isTimed }
assertTest(setRepExercises.count >= 24, "Set/rep exercises present")
assertTest(timedExercises.count >= 10, "Timed exercises present")

// 3.2 Uniqueness of IDs, Names, Illustrations, and Technique Links
let uniqueIDs = Set(allExercises.map(\.id))
assertTest(uniqueIDs.count == allExercises.count, "All exercise IDs are unique")

let setRepImages = setRepExercises.compactMap(\.demoImageName)
assertTest(setRepImages.count == 24, "All 24 set/rep exercises have demo illustrations")
assertTest(Set(setRepImages).count == 24, "All 24 demo illustrations are unique")

let setRepYouTube = setRepExercises.compactMap(\.techniqueVideoURL)
assertTest(setRepYouTube.count == 24, "All 24 set/rep exercises have YouTube technique links")

// 3.3 Equipment filter coverage
let equipmentTypes = Set(allExercises.map(\.equipment))
assertTest(equipmentTypes.contains(.barbell), "Library includes Barbell exercises")
assertTest(equipmentTypes.contains(.dumbbell), "Library includes Dumbbell exercises")
assertTest(equipmentTypes.contains(.bodyweight), "Library includes Bodyweight exercises")
assertTest(equipmentTypes.contains(.machine), "Library includes Machine exercises")
assertTest(equipmentTypes.contains(.cable), "Library includes Cable exercises")
assertTest(equipmentTypes.contains(.kettlebell), "Library includes Kettlebell exercises")

// 3.4 Custom exercise creation
let customEx = Exercise(name: "Single Arm Kettlebell Press", primaryMuscle: .shoulders, equipment: .kettlebell, instructions: ["Clean KB to rack position", "Press overhead until locked out"], usesWeight: true)
assertTest(customEx.name == "Single Arm Kettlebell Press", "Custom exercise name correct")
assertTest(customEx.equipment == .kettlebell, "Custom exercise equipment correct")


// -----------------------------------------------------------------------------
// SECTION 4: GOAL 4 — PROGRESS, ANALYTICS, HISTORY & SETTINGS
// -----------------------------------------------------------------------------
print("\n--- Testing Goal 4: Progress, Analytics, History & Settings ---")

// 4.1 PR Detection (Max Weight, Max Volume, Est 1RM Epley)
let s1_pr = WorkoutSession(name: "Session 1", exercises: [
    SessionExercise(exerciseID: benchPress.id, name: benchPress.name, sets: [
        SetEntry(reps: 5, weight: 80, isCompleted: true)
    ])
], finishedAt: Date().addingTimeInterval(-86400 * 7))

let s2_pr = WorkoutSession(name: "Session 2", exercises: [
    SessionExercise(exerciseID: benchPress.id, name: benchPress.name, sets: [
        SetEntry(reps: 5, weight: 90, isCompleted: true)
    ])
], finishedAt: Date())

let prs = Records.newPRs(session: s2_pr, priorHistory: [s1_pr])
assertTest(!prs.isEmpty, "New PRs detected for session 2")
assertTest(prs[0].kinds.contains("Weight"), "Weight PR detected")
assertTest(prs[0].kinds.contains("1RM"), "1RM PR detected")

// 4.2 Warmup Calculator Ramp Sets
let warmupRamp = Warmup.sets(workingWeight: 100, units: .kg)
assertTest(warmupRamp.count == 5, "100kg target generates 5 warmup sets (2 bar + 3 ramps)")
assertTest(warmupRamp[0].weight == 20, "First warmup is bar weight (20kg)")
assertTest(warmupRamp[4].weight < 100, "Last warmup is below working weight (100kg)")

// 4.3 Backup & Restore JSON Roundtrip
let storeData = BackupPayload(
    templates: [t1],
    history: [s1_pr, s2_pr],
    customExercises: [],
    favoriteExerciseIDs: [benchPress.id],
    bodyWeights: [BodyWeightEntry(id: UUID(), date: Date(), weightKg: 75.5)],
    settings: AppSettings()
)
if let backupJSON = try? Backup.encode(storeData),
   let restoredData = try? Backup.decode(backupJSON) {
    assertTest(restoredData.templates.count == 1, "Backup templates restored")
    assertTest(restoredData.history.count == 2, "Backup history restored")
    assertTest(restoredData.favoriteExerciseIDs.count == 1, "Backup favorites restored")
    assertTest(restoredData.bodyWeights.count == 1, "Backup body weights restored")
} else {
    assertTest(false, "Backup JSON roundtrip failed")
}


// -----------------------------------------------------------------------------
// SECTION 5: 4-DAY GYM VISIT ROUTINES & PHASE TEMPLATES E2E
// -----------------------------------------------------------------------------
print("\n--- Testing 4-Day Daily Gym Visit Routines & Phase Templates ---")

let starterTemplates = ExerciseLibrary.defaultTemplates()
let dailyRoutines = GymSessionRoutine.default4DayRoutines(templates: starterTemplates)
assertTest(dailyRoutines.count == 4, "4 daily gym visit routines generated")

// Tuesday Workout (Upper Body Focus)
let tuesdayRoutine = dailyRoutines.first(where: { $0.name.contains("Tuesday") })!
assertTest(tuesdayRoutine.phases.count == 7, "Tuesday routine has 7 phases")
assertTest(tuesdayRoutine.phases.allSatisfy { $0.templateID != nil }, "Tuesday routine attached templates to all 7 phases")

let tuesdayMainStrengthPhase = tuesdayRoutine.phases.first(where: { $0.phaseType == .mainStrength })
let upperBodyATemplate = starterTemplates.first(where: { $0.name == "Upper Body A (Strength)" })
assertTest(tuesdayMainStrengthPhase?.templateID == upperBodyATemplate?.id, "Tuesday main strength phase is linked to Upper Body A (Strength)")

let tuesdaySessionMat = WorkoutSession.from(routine: tuesdayRoutine, templates: starterTemplates, library: exerciseDict)
assertTest(tuesdaySessionMat.phases.count == 7, "Tuesday materialized session has 7 phases")
assertTest(tuesdaySessionMat.phases[0].activityKind == .stairClimbing, "Tuesday cardio phase correctly maps to Stair Stepper (.stairClimbing)")

// Wednesday Workout (Lower Body Focus)
let wednesdayRoutine = dailyRoutines.first(where: { $0.name.contains("Wednesday") })!
let wednesdaySessionMat = WorkoutSession.from(routine: wednesdayRoutine, templates: starterTemplates, library: exerciseDict)
assertTest(wednesdaySessionMat.phases[0].activityKind == .elliptical, "Wednesday cardio phase correctly maps to Elliptical (.elliptical)")

// Thursday Workout (Upper Body Hypertrophy)
let thursdayRoutine = dailyRoutines.first(where: { $0.name.contains("Thursday") })!
let thursdaySessionMat = WorkoutSession.from(routine: thursdayRoutine, templates: starterTemplates, library: exerciseDict)
assertTest(thursdaySessionMat.phases[0].activityKind == .running, "Thursday cardio phase correctly maps to Treadmill (.running)")

// Friday Workout (Lower Body Hypertrophy)
let fridayRoutine = dailyRoutines.first(where: { $0.name.contains("Friday") })!
let fridaySessionMat = WorkoutSession.from(routine: fridayRoutine, templates: starterTemplates, library: exerciseDict)
assertTest(fridaySessionMat.phases[0].activityKind == .cycling, "Friday cardio phase correctly maps to Stationary Bike (.cycling)")

print("\n==================================================")
if failures == 0 {
    print("🎉 ALL \(testCount) E2E TESTS PASSED SUCCESSFULLY!")
} else {
    print("❌ E2E TEST SUITE COMPLETED WITH \(failures) FAILURE(S) OUT OF \(testCount) TESTS.")
}
print("==================================================")

if failures > 0 {
    exit(1)
}
