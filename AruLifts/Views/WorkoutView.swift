//
//  WorkoutView.swift
//  AruLifts
//
//  Created by Aravind Gillella on 9/30/25.
//

import SwiftUI

struct WorkoutView: View {
    @ObservedObject var activeWorkout: LegacyActiveWorkoutSession
    @EnvironmentObject var workoutManager: WorkoutManager
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showRestTimer = false
    @State private var showFinishAlert = false
    @State private var showCancelAlert = false
    @State private var currentTime = Date()
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var currentExercise: WorkoutExercise {
        activeWorkout.workout.exercises[activeWorkout.currentExerciseIndex]
    }
    
    var currentSets: [WorkoutSet] {
        activeWorkout.exerciseSets[currentExercise.id] ?? []
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button(action: {
                    showCancelAlert = true
                }) {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .foregroundColor(.red)
                        .frame(width: 44, height: 44)
                }
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text(activeWorkout.workout.name)
                        .font(.headline)
                    Text(formatElapsedTime())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    showFinishAlert = true
                }) {
                    Image(systemName: "checkmark")
                        .font(.title3)
                        .foregroundColor(.green)
                        .frame(width: 44, height: 44)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            
            // Exercise navigation
            if activeWorkout.workout.exercises.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(activeWorkout.workout.exercises.enumerated()), id: \.element.id) { index, exercise in
                            Button(action: {
                                activeWorkout.currentExerciseIndex = index
                            }) {
                                VStack(spacing: 4) {
                                    Text(exercise.exercise.name)
                                        .font(.caption)
                                        .fontWeight(index == activeWorkout.currentExerciseIndex ? .bold : .regular)
                                    
                                    if index == activeWorkout.currentExerciseIndex {
                                        Rectangle()
                                            .fill(Color.orange)
                                            .frame(height: 2)
                                    }
                                }
                                .foregroundColor(index == activeWorkout.currentExerciseIndex ? .orange : .secondary)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
            }
            
            // Main content
            ScrollView {
                VStack(spacing: 24) {
                    // Exercise info card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(currentExercise.exercise.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            Spacer()
                            Image(systemName: "info.circle")
                                .foregroundColor(.orange)
                        }
                        
                        Text(currentExercise.exercise.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 16) {
                            Label("\(currentExercise.sets) sets", systemImage: "repeat")
                            Label("\(currentExercise.reps) reps", systemImage: "number")
                            Label("\(currentExercise.restTime)s rest", systemImage: "timer")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                    .padding(.horizontal)
                    .padding(.top)
                    
                    // Sets list
                    VStack(spacing: 12) {
                        ForEach(Array(currentSets.enumerated()), id: \.element.id) { index, set in
                            SetRow(
                                setNumber: index + 1,
                                set: set,
                                exerciseId: currentExercise.id,
                                setIndex: index,
                                activeWorkout: activeWorkout,
                                onComplete: {
                                    // Start rest timer after completing a working set
                                    if !set.isWarmup && index < currentSets.count - 1 {
                                        startRestTimer()
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    // Navigation buttons
                    HStack(spacing: 16) {
                        if activeWorkout.currentExerciseIndex > 0 {
                            Button(action: {
                                activeWorkout.currentExerciseIndex -= 1
                            }) {
                                Label("Previous", systemImage: "chevron.left")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                            }
                            .foregroundColor(.primary)
                        }
                        
                        if activeWorkout.currentExerciseIndex < activeWorkout.workout.exercises.count - 1 {
                            Button(action: {
                                activeWorkout.currentExerciseIndex += 1
                            }) {
                                Label("Next", systemImage: "chevron.right")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.orange)
                                    .cornerRadius(12)
                            }
                            .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
        }
        .sheet(isPresented: $showRestTimer) {
            RestTimerView(
                restTime: currentExercise.restTime,
                isPresented: $showRestTimer
            )
        }
        .alert("Finish Workout?", isPresented: $showFinishAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Finish", role: .destructive) {
                workoutManager.finishWorkout(context: viewContext)
            }
        } message: {
            Text("Are you sure you want to finish this workout? Your progress will be saved.")
        }
        .alert("Cancel Workout?", isPresented: $showCancelAlert) {
            Button("No", role: .cancel) {}
            Button("Yes, Cancel", role: .destructive) {
                workoutManager.cancelWorkout()
            }
        } message: {
            Text("Are you sure you want to cancel this workout? Your progress will be lost.")
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }
    
    private func formatElapsedTime() -> String {
        let elapsed = currentTime.timeIntervalSince(activeWorkout.startDate)
        return workoutManager.formatDuration(elapsed)
    }
    
    private func startRestTimer() {
        activeWorkout.restTimeRemaining = currentExercise.restTime
        activeWorkout.isRestTimerActive = true
        showRestTimer = true
    }
}

struct SetRow: View {
    let setNumber: Int
    let set: WorkoutSet
    let exerciseId: UUID
    let setIndex: Int
    @ObservedObject var activeWorkout: LegacyActiveWorkoutSession
    let onComplete: () -> Void
    
    @State private var weight: Double
    @State private var reps: Int
    
    init(setNumber: Int, set: WorkoutSet, exerciseId: UUID, setIndex: Int, activeWorkout: LegacyActiveWorkoutSession, onComplete: @escaping () -> Void) {
        self.setNumber = setNumber
        self.set = set
        self.exerciseId = exerciseId
        self.setIndex = setIndex
        self.activeWorkout = activeWorkout
        self.onComplete = onComplete
        _weight = State(initialValue: set.weight)
        _reps = State(initialValue: set.reps)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Set number
            Text(set.isWarmup ? "W\(setNumber)" : "\(setNumber)")
                .font(.headline)
                .foregroundColor(set.isWarmup ? .orange : .primary)
                .frame(width: 40)
            
            // Weight input
            VStack(alignment: .leading, spacing: 4) {
                Text("Weight")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                HStack {
                    TextField("0", value: $weight, format: .number)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .onChange(of: weight) { _, newValue in
                            activeWorkout.updateSetWeight(exerciseId: exerciseId, setIndex: setIndex, weight: newValue)
                        }
                    Text("lbs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Reps input
            VStack(alignment: .leading, spacing: 4) {
                Text("Reps")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextField("0", value: $reps, format: .number)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .onChange(of: reps) { _, newValue in
                        activeWorkout.updateSetReps(exerciseId: exerciseId, setIndex: setIndex, reps: newValue)
                    }
            }
            
            Spacer()
            
            // Complete button
            Button(action: {
                activeWorkout.completeSet(exerciseId: exerciseId, setIndex: setIndex)
                onComplete()
            }) {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(set.isCompleted ? .green : .gray)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(set.isCompleted ? Color.green.opacity(0.1) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(set.isWarmup ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 2)
        )
    }
}

#Preview {
    @Previewable @StateObject var manager = WorkoutManager.shared
    manager.startWorkout(WorkoutProgram.strongLifts5x5.workouts[0])
    
    return VStack {
        if let workout = manager.activeWorkout {
            WorkoutView(activeWorkout: workout)
                .environmentObject(manager)
                .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        } else {
            Text("Loading workout...")
        }
    }
}

