//
//  WorkoutManager.swift
//  AruLifts
//
//  Created by Aravind Gillella on 9/30/25.
//

import Foundation
import CoreData
import Combine

class WorkoutManager: ObservableObject {
    static let shared = WorkoutManager()
    
    @Published var currentProgram: WorkoutProgram = .strongLifts5x5
    @Published var activeWorkout: LegacyActiveWorkoutSession?
    @Published var exerciseLibrary: [Exercise] = []
    @Published var exerciseWeights: [String: Double] = [:] // Exercise name -> current weight
    @Published var workoutHistory: [WorkoutSessionEntity] = []
    
    private var cancellables = Set<AnyCancellable>()
    private let userDefaults = UserDefaults.standard
    
    private init() {
        loadExerciseWeights()
        loadWorkoutHistory()
    }
    
    func initializeExerciseLibrary() {
        if exerciseLibrary.isEmpty {
            exerciseLibrary = Exercise.allExercises
        }
    }
    
    func startWorkout(_ workout: Workout) {
        let session = LegacyActiveWorkoutSession(workout: workout)
        
        // Load saved weights for exercises
        for exercise in workout.exercises {
            if let savedWeight = exerciseWeights[exercise.exercise.name] {
                session.exerciseWeights[exercise.id] = savedWeight
                // Update sets with saved weight
                if var sets = session.exerciseSets[exercise.id] {
                    for i in 0..<sets.count where !sets[i].isWarmup {
                        sets[i].weight = savedWeight
                    }
                    // Update warmup weights
                    let warmupWeights = session.calculateWarmupWeights(targetWeight: savedWeight)
                    var warmupIndex = 0
                    for i in 0..<sets.count where sets[i].isWarmup {
                        if warmupIndex < warmupWeights.count {
                            sets[i].weight = warmupWeights[warmupIndex]
                            warmupIndex += 1
                        }
                    }
                    session.exerciseSets[exercise.id] = sets
                }
            }
        }
        
        activeWorkout = session
    }
    
    func finishWorkout(context: NSManagedObjectContext) {
        guard let workout = activeWorkout else { return }
        
        workout.finishWorkout()
        
        // Save to Core Data
        let entity = WorkoutSessionEntity(context: context)
        entity.id = workout.id
        entity.date = workout.startDate
        entity.workoutName = workout.workout.name
        entity.duration = workout.duration
        entity.isCompleted = true
        
        // Save exercise weights
        for (exerciseId, weight) in workout.exerciseWeights {
            if let exercise = workout.workout.exercises.first(where: { $0.id == exerciseId }) {
                exerciseWeights[exercise.exercise.name] = weight
                
                // Calculate next workout weight (progressive overload)
                let increment: Double
                switch exercise.exercise.name {
                case "Barbell Deadlift":
                    increment = 10.0 // Deadlift increases by 10 lbs
                default:
                    increment = 5.0 // Other exercises increase by 5 lbs
                }
                
                // Check if all sets completed successfully
                if let sets = workout.exerciseSets[exerciseId] {
                    let workingSets = sets.filter { !$0.isWarmup }
                    let allCompleted = workingSets.allSatisfy { $0.isCompleted && $0.reps >= exercise.reps }
                    if allCompleted {
                        exerciseWeights[exercise.exercise.name] = weight + increment
                    }
                }
            }
        }
        
        saveExerciseWeights()
        
        do {
            try context.save()
        } catch {
            print("Error saving workout: \(error)")
        }
        
        activeWorkout = nil
        loadWorkoutHistory()
    }
    
    func cancelWorkout() {
        activeWorkout = nil
    }
    
    func getNextWorkout() -> Workout {
        let workoutCount = workoutHistory.count
        let workoutIndex = workoutCount % currentProgram.workouts.count
        return currentProgram.workouts[workoutIndex]
    }
    
    private func saveExerciseWeights() {
        if let encoded = try? JSONEncoder().encode(exerciseWeights) {
            userDefaults.set(encoded, forKey: "exerciseWeights")
        }
    }
    
    private func loadExerciseWeights() {
        if let data = userDefaults.data(forKey: "exerciseWeights"),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            exerciseWeights = decoded
        } else {
            // Set default starting weights
            exerciseWeights = [
                "Barbell Squat": 45.0,
                "Barbell Bench Press": 45.0,
                "Barbell Deadlift": 95.0,
                "Overhead Press": 45.0,
                "Barbell Row": 65.0
            ]
        }
    }
    
    private func loadWorkoutHistory() {
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<WorkoutSessionEntity> = WorkoutSessionEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \WorkoutSessionEntity.date, ascending: false)]
        
        do {
            workoutHistory = try context.fetch(fetchRequest)
        } catch {
            print("Error fetching workout history: \(error)")
            workoutHistory = []
        }
    }
    
    func formatWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", weight)
        } else {
            return String(format: "%.1f", weight)
        }
    }
    
    func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

