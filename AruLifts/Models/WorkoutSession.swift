//
//  WorkoutSession.swift
//  AruLifts
//
//  Created by Aravind Gillella on 9/30/25.
//

import Foundation

struct WorkoutProgram: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String
    let workouts: [Workout]
    
    init(id: UUID = UUID(), name: String, description: String, workouts: [Workout]) {
        self.id = id
        self.name = name
        self.description = description
        self.workouts = workouts
    }
}

struct Workout: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let exercises: [WorkoutExercise]
    
    init(id: UUID = UUID(), name: String, exercises: [WorkoutExercise]) {
        self.id = id
        self.name = name
        self.exercises = exercises
    }
}

struct WorkoutExercise: Identifiable, Codable, Hashable {
    let id: UUID
    let exercise: Exercise
    let sets: Int
    let reps: Int
    let restTime: Int // in seconds
    
    init(id: UUID = UUID(), exercise: Exercise, sets: Int, reps: Int, restTime: Int = 180) {
        self.id = id
        self.exercise = exercise
        self.sets = sets
        self.reps = reps
        self.restTime = restTime
    }
}

struct WorkoutSet: Identifiable, Codable {
    let id: UUID
    var weight: Double
    var reps: Int
    var isCompleted: Bool
    var isWarmup: Bool
    
    init(id: UUID = UUID(), weight: Double, reps: Int, isCompleted: Bool = false, isWarmup: Bool = false) {
        self.id = id
        self.weight = weight
        self.reps = reps
        self.isCompleted = isCompleted
        self.isWarmup = isWarmup
    }
}

class LegacyActiveWorkoutSession: ObservableObject {
    let id: UUID
    let workout: Workout
    let startDate: Date
    @Published var currentExerciseIndex: Int
    @Published var exerciseSets: [UUID: [WorkoutSet]] // Exercise ID -> Sets
    @Published var exerciseWeights: [UUID: Double] // Exercise ID -> Current Weight
    @Published var isRestTimerActive: Bool
    @Published var restTimeRemaining: Int
    
    var endDate: Date?
    var duration: TimeInterval {
        return (endDate ?? Date()).timeIntervalSince(startDate)
    }
    
    init(id: UUID = UUID(), workout: Workout) {
        self.id = id
        self.workout = workout
        self.startDate = Date()
        self.currentExerciseIndex = 0
        self.exerciseSets = [:]
        self.exerciseWeights = [:]
        self.isRestTimerActive = false
        self.restTimeRemaining = 0
        
        // Initialize sets for each exercise
        for workoutExercise in workout.exercises {
            var sets: [WorkoutSet] = []
            // Add warmup sets
            let warmupWeights = calculateWarmupWeights(targetWeight: 45.0) // Default starting weight
            for warmup in warmupWeights {
                sets.append(WorkoutSet(weight: warmup, reps: 5, isWarmup: true))
            }
            // Add working sets
            for _ in 0..<workoutExercise.sets {
                sets.append(WorkoutSet(weight: 45.0, reps: workoutExercise.reps))
            }
            exerciseSets[workoutExercise.id] = sets
            exerciseWeights[workoutExercise.id] = 45.0
        }
    }
    
    func calculateWarmupWeights(targetWeight: Double) -> [Double] {
        if targetWeight <= 45 { return [] }
        
        var warmups: [Double] = []
        warmups.append(45.0) // Empty bar
        
        if targetWeight > 95 {
            warmups.append(45.0 + (targetWeight - 45.0) * 0.4)
        }
        if targetWeight > 135 {
            warmups.append(45.0 + (targetWeight - 45.0) * 0.6)
        }
        if targetWeight > 185 {
            warmups.append(45.0 + (targetWeight - 45.0) * 0.8)
        }
        
        return warmups.map { round($0 / 5) * 5 } // Round to nearest 5
    }
    
    func completeSet(exerciseId: UUID, setIndex: Int) {
        if var sets = exerciseSets[exerciseId], setIndex < sets.count {
            sets[setIndex].isCompleted = true
            exerciseSets[exerciseId] = sets
        }
    }
    
    func updateSetWeight(exerciseId: UUID, setIndex: Int, weight: Double) {
        if var sets = exerciseSets[exerciseId], setIndex < sets.count {
            sets[setIndex].weight = weight
            exerciseSets[exerciseId] = sets
            exerciseWeights[exerciseId] = weight
        }
    }
    
    func updateSetReps(exerciseId: UUID, setIndex: Int, reps: Int) {
        if var sets = exerciseSets[exerciseId], setIndex < sets.count {
            sets[setIndex].reps = reps
            exerciseSets[exerciseId] = sets
        }
    }
    
    func finishWorkout() {
        endDate = Date()
    }
}

// Default 5x5 Program
extension WorkoutProgram {
    static var strongLifts5x5: WorkoutProgram {
        let squat = Exercise.allExercises.first { $0.name == "Barbell Squat" }!
        let benchPress = Exercise.allExercises.first { $0.name == "Barbell Bench Press" }!
        let barbellRow = Exercise.allExercises.first { $0.name == "Barbell Row" }!
        let overheadPress = Exercise.allExercises.first { $0.name == "Overhead Press" }!
        let deadlift = Exercise.allExercises.first { $0.name == "Deadlift" }!
        
        return WorkoutProgram(
            name: "AruLifts 5×5",
            description: "The classic strength building program. Three exercises, 5 sets of 5 reps, three times per week.",
            workouts: [
                Workout(
                    name: "Workout A",
                    exercises: [
                        WorkoutExercise(exercise: squat, sets: 5, reps: 5, restTime: 180),
                        WorkoutExercise(exercise: benchPress, sets: 5, reps: 5, restTime: 180),
                        WorkoutExercise(exercise: barbellRow, sets: 5, reps: 5, restTime: 180)
                    ]
                ),
                Workout(
                    name: "Workout B",
                    exercises: [
                        WorkoutExercise(exercise: squat, sets: 5, reps: 5, restTime: 180),
                        WorkoutExercise(exercise: overheadPress, sets: 5, reps: 5, restTime: 180),
                        WorkoutExercise(exercise: deadlift, sets: 1, reps: 5, restTime: 180)
                    ]
                )
            ]
        )
    }
}

