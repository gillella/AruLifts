//
//  CustomWorkout.swift
//  AruLifts
//
//  Created by Aravind Gillella on 10/1/25.
//

import Foundation

// MARK: - Custom Workout (Saveable Routine)
struct CustomWorkout: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var exercises: [WorkoutExerciseConfig]
    let createdDate: Date
    var lastUsedDate: Date?
    var category: String? // e.g., "Upper Body", "Legs", "Full Body"
    var notes: String?
    
    init(id: UUID = UUID(),
         name: String,
         exercises: [WorkoutExerciseConfig] = [],
         createdDate: Date = Date(),
         lastUsedDate: Date? = nil,
         category: String? = nil,
         notes: String? = nil) {
        self.id = id
        self.name = name
        self.exercises = exercises
        self.createdDate = createdDate
        self.lastUsedDate = lastUsedDate
        self.category = category
        self.notes = notes
    }
    
    var totalExercises: Int {
        exercises.count
    }
    
    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets }
    }
    
    var estimatedDuration: Int {
        // Rough estimate: 45 seconds per set + rest time
        let workTime = totalSets * 45
        let restTime = exercises.reduce(0) { total, config in
            total + (config.sets * config.restTime)
        }
        return (workTime + restTime) / 60 // Return in minutes
    }
}

// MARK: - Exercise Configuration in Workout
struct WorkoutExerciseConfig: Identifiable, Codable, Hashable {
    let id: UUID
    let exercise: Exercise
    var sets: Int
    var reps: Int
    var weight: Double?
    var restTime: Int // in seconds
    var order: Int
    var notes: String?
    
    init(id: UUID = UUID(),
         exercise: Exercise,
         sets: Int = 3,
         reps: Int = 10,
         weight: Double? = nil,
         restTime: Int = 90,
         order: Int = 0,
         notes: String? = nil) {
        self.id = id
        self.exercise = exercise
        self.sets = sets
        self.reps = reps
        self.weight = weight
        self.restTime = restTime
        self.order = order
        self.notes = notes
    }
}

// MARK: - Set Result (Completed Set)
struct SetResult: Identifiable, Codable {
    let id: UUID
    let exerciseConfigId: UUID
    var weight: Double?
    var repsCompleted: Int
    let setNumber: Int
    let completedDate: Date
    var isWarmup: Bool
    
    init(id: UUID = UUID(),
         exerciseConfigId: UUID,
         weight: Double?,
         repsCompleted: Int,
         setNumber: Int,
         completedDate: Date = Date(),
         isWarmup: Bool = false) {
        self.id = id
        self.exerciseConfigId = exerciseConfigId
        self.weight = weight
        self.repsCompleted = repsCompleted
        self.setNumber = setNumber
        self.completedDate = completedDate
        self.isWarmup = isWarmup
    }
}

// MARK: - Completed Workout Session
struct CompletedWorkoutSession: Identifiable, Codable {
    let id: UUID
    let workoutId: UUID
    let workoutName: String
    let startDate: Date
    let endDate: Date
    let completedSets: [SetResult]
    let notes: String?
    
    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
    
    var totalSetsCompleted: Int {
        completedSets.filter { !$0.isWarmup }.count
    }
    
    init(id: UUID = UUID(),
         workoutId: UUID,
         workoutName: String,
         startDate: Date,
         endDate: Date,
         completedSets: [SetResult],
         notes: String? = nil) {
        self.id = id
        self.workoutId = workoutId
        self.workoutName = workoutName
        self.startDate = startDate
        self.endDate = endDate
        self.completedSets = completedSets
        self.notes = notes
    }
}

// MARK: - Active Workout Session (In Progress)
class ActiveWorkoutSession: ObservableObject {
    let id: UUID
    let workout: CustomWorkout
    let startDate: Date
    @Published var currentExerciseIndex: Int
    @Published var completedSets: [SetResult]
    @Published var currentSets: [[WorkoutSet]] // Per exercise
    @Published var isRestTimerActive: Bool
    @Published var restTimeRemaining: Int
    @Published var workoutNotes: String
    
    var endDate: Date?
    var duration: TimeInterval {
        return (endDate ?? Date()).timeIntervalSince(startDate)
    }
    
    var currentExercise: WorkoutExerciseConfig? {
        guard currentExerciseIndex < workout.exercises.count else { return nil }
        return workout.exercises[currentExerciseIndex]
    }
    
    var progress: Double {
        let totalSets = workout.totalSets
        let completed = completedSets.filter { !$0.isWarmup }.count
        return totalSets > 0 ? Double(completed) / Double(totalSets) : 0
    }
    
    init(workout: CustomWorkout) {
        self.id = UUID()
        self.workout = workout
        self.startDate = Date()
        self.currentExerciseIndex = 0
        self.completedSets = []
        self.currentSets = []
        self.isRestTimerActive = false
        self.restTimeRemaining = 0
        self.workoutNotes = ""
        
        // Initialize sets for each exercise
        for exerciseConfig in workout.exercises {
            var sets: [WorkoutSet] = []
            
            // Add working sets
            for setNum in 1...exerciseConfig.sets {
                sets.append(WorkoutSet(
                    weight: exerciseConfig.weight ?? 0,
                    reps: exerciseConfig.reps,
                    isCompleted: false,
                    isWarmup: false
                ))
            }
            
            currentSets.append(sets)
        }
    }
    
    func completeSet(exerciseIndex: Int, setIndex: Int) {
        guard exerciseIndex < currentSets.count,
              setIndex < currentSets[exerciseIndex].count else { return }
        
        currentSets[exerciseIndex][setIndex].isCompleted = true
        
        let config = workout.exercises[exerciseIndex]
        let set = currentSets[exerciseIndex][setIndex]
        
        let result = SetResult(
            exerciseConfigId: config.id,
            weight: set.weight > 0 ? set.weight : nil,
            repsCompleted: set.reps,
            setNumber: setIndex + 1,
            isWarmup: set.isWarmup
        )
        
        completedSets.append(result)
        
        // Auto-start rest timer
        if !set.isWarmup && setIndex < currentSets[exerciseIndex].count - 1 {
            startRestTimer(duration: config.restTime)
        }
    }
    
    func updateSetWeight(exerciseIndex: Int, setIndex: Int, weight: Double) {
        guard exerciseIndex < currentSets.count,
              setIndex < currentSets[exerciseIndex].count else { return }
        currentSets[exerciseIndex][setIndex].weight = weight
    }
    
    func updateSetReps(exerciseIndex: Int, setIndex: Int, reps: Int) {
        guard exerciseIndex < currentSets.count,
              setIndex < currentSets[exerciseIndex].count else { return }
        currentSets[exerciseIndex][setIndex].reps = reps
    }
    
    func startRestTimer(duration: Int) {
        restTimeRemaining = duration
        isRestTimerActive = true
    }
    
    func stopRestTimer() {
        isRestTimerActive = false
        restTimeRemaining = 0
    }
    
    func finishWorkout() -> CompletedWorkoutSession {
        endDate = Date()
        return CompletedWorkoutSession(
            workoutId: workout.id,
            workoutName: workout.name,
            startDate: startDate,
            endDate: endDate ?? Date(),
            completedSets: completedSets,
            notes: workoutNotes.isEmpty ? nil : workoutNotes
        )
    }
}

// MARK: - Workout Categories
enum WorkoutCategory: String, CaseIterable, Codable {
    case upperBody = "Upper Body"
    case lowerBody = "Lower Body"
    case fullBody = "Full Body"
    case push = "Push"
    case pull = "Pull"
    case legs = "Legs"
    case core = "Core"
    case cardio = "Cardio"
    case custom = "Custom"
}

// MARK: - Sample Workouts
extension CustomWorkout {
    static let sampleChestDay = CustomWorkout(
        name: "Chest Day",
        exercises: [
            WorkoutExerciseConfig(exercise: .barbellBenchPress, sets: 4, reps: 8, weight: 135, restTime: 180, order: 0),
            WorkoutExerciseConfig(exercise: .inclineBenchPress, sets: 4, reps: 10, weight: 95, restTime: 120, order: 1),
            WorkoutExerciseConfig(exercise: .dumbbellFlyes, sets: 3, reps: 12, weight: 30, restTime: 90, order: 2),
            WorkoutExerciseConfig(exercise: .pushUps, sets: 3, reps: 15, weight: nil, restTime: 60, order: 3)
        ],
        category: "Upper Body"
    )
    
    static let sampleLegDay = CustomWorkout(
        name: "Leg Day",
        exercises: [
            WorkoutExerciseConfig(exercise: .barbellSquat, sets: 5, reps: 5, weight: 185, restTime: 240, order: 0),
            WorkoutExerciseConfig(exercise: .legPress, sets: 4, reps: 12, weight: 270, restTime: 120, order: 1),
            WorkoutExerciseConfig(exercise: .legCurl, sets: 3, reps: 12, weight: 80, restTime: 90, order: 2),
            WorkoutExerciseConfig(exercise: .calfRaises, sets: 4, reps: 15, weight: 100, restTime: 60, order: 3)
        ],
        category: "Lower Body"
    )
    
    static let sampleBackDay = CustomWorkout(
        name: "Back & Biceps",
        exercises: [
            WorkoutExerciseConfig(exercise: .barbellDeadlift, sets: 3, reps: 5, weight: 225, restTime: 240, order: 0),
            WorkoutExerciseConfig(exercise: .pullUps, sets: 4, reps: 10, weight: nil, restTime: 120, order: 1),
            WorkoutExerciseConfig(exercise: .barbellRow, sets: 4, reps: 8, weight: 135, restTime: 120, order: 2),
            WorkoutExerciseConfig(exercise: .barbellCurl, sets: 3, reps: 10, weight: 60, restTime: 90, order: 3)
        ],
        category: "Pull"
    )
    
    static let sampleAbsDay = CustomWorkout(
        name: "Core Blast",
        exercises: [
            WorkoutExerciseConfig(exercise: .plank, sets: 3, reps: 60, weight: nil, restTime: 60, order: 0),
            WorkoutExerciseConfig(exercise: .crunches, sets: 4, reps: 25, weight: nil, restTime: 45, order: 1),
            WorkoutExerciseConfig(exercise: .russianTwists, sets: 3, reps: 30, weight: nil, restTime: 45, order: 2),
            WorkoutExerciseConfig(exercise: .legRaises, sets: 3, reps: 15, weight: nil, restTime: 60, order: 3),
            WorkoutExerciseConfig(exercise: .mountainClimbers, sets: 3, reps: 30, weight: nil, restTime: 45, order: 4)
        ],
        category: "Core"
    )
    
    static let allSampleWorkouts: [CustomWorkout] = [
        sampleChestDay, sampleLegDay, sampleBackDay, sampleAbsDay
    ]
}

