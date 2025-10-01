//
//  CustomWorkoutActiveView.swift
//  AruLifts
//
//  Created by Aravind Gillella on 10/1/25.
//

import SwiftUI

struct CustomWorkoutActiveView: View {
    @ObservedObject var activeWorkout: ActiveWorkoutSession
    @EnvironmentObject var workoutManager: CustomWorkoutManager
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showRestTimer = false
    @State private var showFinishAlert = false
    @State private var showCancelAlert = false
    @State private var currentTime = Date()
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var currentExercise: WorkoutExerciseConfig? {
        activeWorkout.currentExercise
    }
    
    var currentSets: [WorkoutSet] {
        guard activeWorkout.currentExerciseIndex < activeWorkout.currentSets.count else { return [] }
        return activeWorkout.currentSets[activeWorkout.currentExerciseIndex]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top bar with timer and actions
            HStack {
                Button(action: {
                    showCancelAlert = true
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                }
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text(activeWorkout.workout.name)
                        .font(.headline)
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.caption)
                        Text(formatElapsedTime())
                            .font(.subheadline)
                    }
                    .foregroundColor(.orange)
                }
                
                Spacer()
                
                Button(action: {
                    showFinishAlert = true
                }) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 4)
                    
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * activeWorkout.progress, height: 4)
                }
            }
            .frame(height: 4)
            
            // Exercise tabs
            if activeWorkout.workout.exercises.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(Array(activeWorkout.workout.exercises.enumerated()), id: \.element.id) { index, exercise in
                            Button(action: {
                                activeWorkout.currentExerciseIndex = index
                            }) {
                                VStack(spacing: 4) {
                                    Text(exercise.exercise.name)
                                        .font(.caption)
                                        .fontWeight(index == activeWorkout.currentExerciseIndex ? .bold : .regular)
                                        .lineLimit(1)
                                    
                                    if index == activeWorkout.currentExerciseIndex {
                                        Rectangle()
                                            .fill(Color.orange)
                                            .frame(height: 3)
                                            .cornerRadius(1.5)
                                    } else {
                                        Rectangle()
                                            .fill(Color.clear)
                                            .frame(height: 3)
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
                VStack(spacing: 20) {
                    // Current Exercise Card
                    if let exercise = currentExercise {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise.exercise.name)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    
                                    HStack(spacing: 8) {
                                        Text(exercise.exercise.equipment.rawValue)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.orange.opacity(0.2))
                                            .foregroundColor(.orange)
                                            .cornerRadius(4)
                                        
                                        ForEach(exercise.exercise.primaryMuscles.prefix(2), id: \.self) { muscle in
                                            Text(muscle.rawValue)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.blue.opacity(0.2))
                                                .foregroundColor(.blue)
                                                .cornerRadius(4)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    // Show exercise details
                                }) {
                                    Image(systemName: "info.circle")
                                        .font(.title2)
                                        .foregroundColor(.orange)
                                }
                            }
                            
                            Text(exercise.exercise.description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                            
                            HStack(spacing: 16) {
                                Label("\(exercise.sets) sets", systemImage: "repeat")
                                Label("\(exercise.reps) reps", systemImage: "number")
                                Label("\(formatTime(exercise.restTime)) rest", systemImage: "timer")
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
                    }
                    
                    // Sets
                    VStack(spacing: 12) {
                        ForEach(Array(currentSets.enumerated()), id: \.element.id) { index, set in
                            if let exercise = currentExercise {
                                ActiveSetRow(
                                    setNumber: index + 1,
                                    set: set,
                                    exerciseConfig: exercise,
                                    exerciseIndex: activeWorkout.currentExerciseIndex,
                                    setIndex: index,
                                    activeWorkout: activeWorkout,
                                    onComplete: {
                                        activeWorkout.completeSet(
                                            exerciseIndex: activeWorkout.currentExerciseIndex,
                                            setIndex: index
                                        )
                                        // Auto-start rest timer
                                        if !set.isWarmup && index < currentSets.count - 1 {
                                            workoutManager.startRestTimer()
                                            showRestTimer = true
                                        }
                                    }
                                )
                            }
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
                                    .foregroundColor(.primary)
                                    .cornerRadius(12)
                            }
                        }
                        
                        if activeWorkout.currentExerciseIndex < activeWorkout.workout.exercises.count - 1 {
                            Button(action: {
                                activeWorkout.currentExerciseIndex += 1
                            }) {
                                Label("Next Exercise", systemImage: "chevron.right")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.orange)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
        }
        .sheet(isPresented: $showRestTimer) {
            RestTimerView(
                restTime: currentExercise?.restTime ?? 90,
                isPresented: $showRestTimer
            )
        }
        .alert("Finish Workout?", isPresented: $showFinishAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Finish") {
                workoutManager.finishWorkout(context: viewContext)
            }
        } message: {
            Text("Great job! Your progress will be saved.")
        }
        .alert("Cancel Workout?", isPresented: $showCancelAlert) {
            Button("No", role: .cancel) {}
            Button("Yes, Cancel", role: .destructive) {
                workoutManager.cancelWorkout()
            }
        } message: {
            Text("Are you sure? Your progress will be lost.")
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }
    
    private func formatElapsedTime() -> String {
        let elapsed = currentTime.timeIntervalSince(activeWorkout.startDate)
        return workoutManager.formatDuration(elapsed)
    }
    
    private func formatTime(_ seconds: Int) -> String {
        if seconds >= 60 {
            let minutes = seconds / 60
            let secs = seconds % 60
            return secs > 0 ? "\(minutes)m \(secs)s" : "\(minutes)m"
        }
        return "\(seconds)s"
    }
}

// MARK: - Active Set Row
struct ActiveSetRow: View {
    let setNumber: Int
    let set: WorkoutSet
    let exerciseConfig: WorkoutExerciseConfig
    let exerciseIndex: Int
    let setIndex: Int
    @ObservedObject var activeWorkout: ActiveWorkoutSession
    let onComplete: () -> Void
    
    @State private var weight: Double
    @State private var reps: Int
    
    init(setNumber: Int, set: WorkoutSet, exerciseConfig: WorkoutExerciseConfig, exerciseIndex: Int, setIndex: Int, activeWorkout: ActiveWorkoutSession, onComplete: @escaping () -> Void) {
        self.setNumber = setNumber
        self.set = set
        self.exerciseConfig = exerciseConfig
        self.exerciseIndex = exerciseIndex
        self.setIndex = setIndex
        self.activeWorkout = activeWorkout
        self.onComplete = onComplete
        _weight = State(initialValue: set.weight)
        _reps = State(initialValue: set.reps)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Set number
            Text("\(setNumber)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(set.isWarmup ? .orange : .primary)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(set.isCompleted ? Color.green.opacity(0.2) : Color(.systemGray6))
                )
            
            // Weight input (if applicable)
            if exerciseConfig.exercise.requiresWeight {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weight")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        TextField("0", value: $weight, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .onChange(of: weight) { _, newValue in
                                activeWorkout.updateSetWeight(exerciseIndex: exerciseIndex, setIndex: setIndex, weight: newValue)
                            }
                        Text("lbs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
                        activeWorkout.updateSetReps(exerciseIndex: exerciseIndex, setIndex: setIndex, reps: newValue)
                    }
            }
            
            Spacer()
            
            // Complete button
            Button(action: {
                onComplete()
            }) {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 32))
                    .foregroundColor(set.isCompleted ? .green : .gray)
            }
            .disabled(set.isCompleted)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(set.isCompleted ? Color.green.opacity(0.1) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(set.isWarmup ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 2)
        )
    }
}

#Preview {
    let manager = CustomWorkoutManager.shared
    let sampleWorkout = CustomWorkout.sampleChestDay
    manager.startWorkout(sampleWorkout)
    
    return Group {
        if let workout = manager.activeWorkout {
            CustomWorkoutActiveView(activeWorkout: workout)
                .environmentObject(manager)
                .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        }
    }
}

