//
//  CustomWorkoutManager.swift
//  AruLifts
//
//  Created by Aravind Gillella on 10/1/25.
//

import Foundation
import CoreData
import Combine
import AVFoundation
import UIKit

class CustomWorkoutManager: ObservableObject {
    static let shared = CustomWorkoutManager()
    
    @Published var savedWorkouts: [CustomWorkout] = []
    @Published var activeWorkout: ActiveWorkoutSession?
    @Published var workoutHistory: [CompletedWorkoutSession] = []
    @Published var exerciseLibrary: [Exercise] = []
    @Published var exerciseWeights: [String: Double] = [:] // Exercise name -> last used weight
    
    private var cancellables = Set<AnyCancellable>()
    private let userDefaults = UserDefaults.standard
    private var audioPlayer: AVAudioPlayer?
    private var restTimerCancellable: AnyCancellable?
    
    private init() {
        loadExerciseLibrary()
        loadExerciseWeights()
        loadSavedWorkouts()
        loadWorkoutHistory()
    }
    
    // MARK: - Exercise Library
    func loadExerciseLibrary() {
        exerciseLibrary = Exercise.allExercises
    }
    
    // MARK: - Saved Workouts Management
    func loadSavedWorkouts() {
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<CustomWorkoutEntity> = CustomWorkoutEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CustomWorkoutEntity.lastUsedDate, ascending: false)]
        
        do {
            let entities = try context.fetch(fetchRequest)
            savedWorkouts = entities.compactMap { entity in
                guard let exercisesData = entity.exercisesData,
                      let exercises = try? JSONDecoder().decode([WorkoutExerciseConfig].self, from: exercisesData) else {
                    return nil
                }
                
                return CustomWorkout(
                    id: entity.id ?? UUID(),
                    name: entity.name ?? "Unnamed Workout",
                    exercises: exercises,
                    createdDate: entity.createdDate ?? Date(),
                    lastUsedDate: entity.lastUsedDate,
                    category: entity.category,
                    notes: entity.notes
                )
            }
            
            // If no workouts, add samples
            if savedWorkouts.isEmpty {
                for workout in CustomWorkout.allSampleWorkouts {
                    saveWorkout(workout)
                }
            }
        } catch {
            print("Error loading workouts: \(error)")
        }
    }
    
    func saveWorkout(_ workout: CustomWorkout) {
        let context = PersistenceController.shared.container.viewContext
        
        // Check if workout already exists
        let fetchRequest: NSFetchRequest<CustomWorkoutEntity> = CustomWorkoutEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", workout.id as CVarArg)
        
        do {
            let results = try context.fetch(fetchRequest)
            let entity = results.first ?? CustomWorkoutEntity(context: context)
            
            entity.id = workout.id
            entity.name = workout.name
            entity.createdDate = workout.createdDate
            entity.lastUsedDate = workout.lastUsedDate
            entity.category = workout.category
            entity.notes = workout.notes
            
            if let exercisesData = try? JSONEncoder().encode(workout.exercises) {
                entity.exercisesData = exercisesData
            }
            
            try context.save()
            loadSavedWorkouts()
        } catch {
            print("Error saving workout: \(error)")
        }
    }
    
    func deleteWorkout(_ workout: CustomWorkout) {
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<CustomWorkoutEntity> = CustomWorkoutEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", workout.id as CVarArg)
        
        do {
            let results = try context.fetch(fetchRequest)
            for entity in results {
                context.delete(entity)
            }
            try context.save()
            loadSavedWorkouts()
        } catch {
            print("Error deleting workout: \(error)")
        }
    }
    
    func duplicateWorkout(_ workout: CustomWorkout) {
        let newWorkout = CustomWorkout(
            id: UUID(),
            name: "\(workout.name) (Copy)",
            exercises: workout.exercises,
            createdDate: Date(),
            lastUsedDate: nil,
            category: workout.category,
            notes: workout.notes
        )
        saveWorkout(newWorkout)
    }
    
    // MARK: - Active Workout Management
    func startWorkout(_ workout: CustomWorkout) {
        // Update last used date
        var updatedWorkout = workout
        updatedWorkout.lastUsedDate = Date()
        saveWorkout(updatedWorkout)
        
        // Create active session
        let session = ActiveWorkoutSession(workout: updatedWorkout)
        
        // Load saved weights for exercises
        for (index, exerciseConfig) in updatedWorkout.exercises.enumerated() {
            if let savedWeight = exerciseWeights[exerciseConfig.exercise.name] {
                // Update weight in session
                for setIndex in 0..<session.currentSets[index].count {
                    session.updateSetWeight(exerciseIndex: index, setIndex: setIndex, weight: savedWeight)
                }
            }
        }
        
        activeWorkout = session
    }
    
    func finishWorkout(context: NSManagedObjectContext) {
        guard let session = activeWorkout else { return }
        
        let completedSession = session.finishWorkout()
        
        // Save to Core Data
        let entity = WorkoutSessionEntity(context: context)
        entity.id = completedSession.id
        entity.workoutId = completedSession.workoutId
        entity.workoutName = completedSession.workoutName
        entity.date = completedSession.startDate
        entity.duration = completedSession.duration
        entity.isCompleted = true
        entity.notes = completedSession.notes
        
        if let setsData = try? JSONEncoder().encode(completedSession.completedSets) {
            entity.completedSetsData = setsData
        }
        
        // Save exercise weights
        for (index, exerciseConfig) in session.workout.exercises.enumerated() {
            let completedSets = session.currentSets[index].filter { $0.isCompleted && !$0.isWarmup }
            if let lastSet = completedSets.last {
                exerciseWeights[exerciseConfig.exercise.name] = lastSet.weight
            }
        }
        
        saveExerciseWeights()
        
        do {
            try context.save()
        } catch {
            print("Error saving workout session: \(error)")
        }
        
        activeWorkout = nil
        loadWorkoutHistory()
    }
    
    func cancelWorkout() {
        stopRestTimer()
        activeWorkout = nil
    }
    
    // MARK: - Rest Timer with Audio Alert
    func startRestTimer() {
        guard let session = activeWorkout,
              let currentExercise = session.currentExercise else { return }
        
        session.startRestTimer(duration: currentExercise.restTime)
        
        restTimerCancellable?.cancel()
        restTimerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self,
                      let session = self.activeWorkout else { return }
                
                if session.restTimeRemaining > 0 {
                    session.restTimeRemaining -= 1
                    
                    // Haptic feedback at intervals
                    if session.restTimeRemaining == 10 || session.restTimeRemaining == 5 {
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.warning)
                    }
                    
                    // Audio alert when timer completes
                    if session.restTimeRemaining == 0 {
                        self.playRestCompleteSound()
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        session.stopRestTimer()
                        self.restTimerCancellable?.cancel()
                    }
                } else {
                    session.stopRestTimer()
                    self.restTimerCancellable?.cancel()
                }
            }
    }
    
    func stopRestTimer() {
        restTimerCancellable?.cancel()
        activeWorkout?.stopRestTimer()
    }
    
    private func playRestCompleteSound() {
        // Play system sound
        AudioServicesPlaySystemSound(1057) // Tock sound
        
        // Optionally play custom sound
        // if let soundURL = Bundle.main.url(forResource: "rest_complete", withExtension: "mp3") {
        //     try? audioPlayer = AVAudioPlayer(contentsOf: soundURL)
        //     audioPlayer?.play()
        // }
    }
    
    // MARK: - Exercise Weights
    private func saveExerciseWeights() {
        if let encoded = try? JSONEncoder().encode(exerciseWeights) {
            userDefaults.set(encoded, forKey: "exerciseWeights")
        }
    }
    
    private func loadExerciseWeights() {
        if let data = userDefaults.data(forKey: "exerciseWeights"),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            exerciseWeights = decoded
        }
    }
    
    // MARK: - Workout History
    func loadWorkoutHistory() {
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<WorkoutSessionEntity> = WorkoutSessionEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \WorkoutSessionEntity.date, ascending: false)]
        
        do {
            let entities = try context.fetch(fetchRequest)
            workoutHistory = entities.compactMap { entity in
                var completedSets: [SetResult] = []
                if let setsData = entity.completedSetsData {
                    completedSets = (try? JSONDecoder().decode([SetResult].self, from: setsData)) ?? []
                }
                
                return CompletedWorkoutSession(
                    id: entity.id ?? UUID(),
                    workoutId: entity.workoutId ?? UUID(),
                    workoutName: entity.workoutName ?? "Unknown",
                    startDate: entity.date ?? Date(),
                    endDate: (entity.date ?? Date()).addingTimeInterval(entity.duration),
                    completedSets: completedSets,
                    notes: entity.notes
                )
            }
        } catch {
            print("Error loading workout history: \(error)")
        }
    }
    
    // MARK: - Statistics
    func getWorkoutCount() -> Int {
        return workoutHistory.count
    }
    
    func getTotalDuration() -> TimeInterval {
        return workoutHistory.reduce(0) { $0 + $1.duration }
    }
    
    func getWorkoutsThisWeek() -> Int {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return workoutHistory.filter { $0.startDate >= weekAgo }.count
    }
    
    func getCurrentStreak() -> Int {
        guard !workoutHistory.isEmpty else { return 0 }
        
        var streak = 0
        var currentDate = Calendar.current.startOfDay(for: Date())
        
        for session in workoutHistory {
            let workoutDay = Calendar.current.startOfDay(for: session.startDate)
            
            if Calendar.current.isDate(workoutDay, inSameDayAs: currentDate) {
                streak += 1
                currentDate = Calendar.current.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
            } else if workoutDay < currentDate {
                break
            }
        }
        
        return streak
    }
    
    // MARK: - Utility Functions
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

