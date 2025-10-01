//
//  HomeView.swift
//  AruLifts
//
//  Created by Aravind Gillella on 9/30/25.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color.orange.opacity(0.1), Color.orange.opacity(0.05)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                if let activeWorkout = workoutManager.activeWorkout {
                    // Active workout view
                    WorkoutView(activeWorkout: activeWorkout)
                } else {
                    // Start workout view
                    ScrollView {
                        VStack(spacing: 24) {
                            // Header
                            VStack(spacing: 8) {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .font(.system(size: 60))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.orange, .red],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .padding(.top, 20)
                                
                                Text("AruLifts")
                                    .font(.system(size: 42, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                
                                Text("Build Strength, Track Progress")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            
                            // Current Program Card
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Current Program")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(workoutManager.currentProgram.name)
                                            .font(.title2)
                                            .fontWeight(.bold)
                                    }
                                    Spacer()
                                    Image(systemName: "flame.fill")
                                        .font(.title)
                                        .foregroundColor(.orange)
                                }
                                
                                Text(workoutManager.currentProgram.description)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                                
                                Divider()
                                
                                HStack {
                                    StatBadge(
                                        icon: "calendar",
                                        title: "Workouts",
                                        value: "\(workoutManager.workoutHistory.count)"
                                    )
                                    Spacer()
                                    StatBadge(
                                        icon: "chart.line.uptrend.xyaxis",
                                        title: "Streak",
                                        value: "\(calculateStreak())d"
                                    )
                                }
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                            .padding(.horizontal)
                            
                            // Next Workout Preview
                            let nextWorkout = workoutManager.getNextWorkout()
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Next Workout")
                                        .font(.headline)
                                    Spacer()
                                    Text(nextWorkout.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.orange)
                                }
                                
                                ForEach(nextWorkout.exercises) { workoutExercise in
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(workoutExercise.exercise.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            Text("\(workoutExercise.sets)×\(workoutExercise.reps) @ \(workoutManager.formatWeight(workoutManager.exerciseWeights[workoutExercise.exercise.name] ?? 45)) lbs")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                            .padding(.horizontal)
                            
                            // Start Workout Button
                            Button(action: {
                                workoutManager.startWorkout(nextWorkout)
                            }) {
                                HStack {
                                    Image(systemName: "play.fill")
                                        .font(.title3)
                                    Text("Start Workout")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    LinearGradient(
                                        colors: [.orange, .red],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(16)
                                .shadow(color: Color.orange.opacity(0.4), radius: 10, x: 0, y: 5)
                            }
                            .padding(.horizontal)
                            .padding(.top, 8)
                            
                            // Quick Actions
                            HStack(spacing: 16) {
                                NavigationLink(destination: WarmUpCalculatorView()) {
                                    QuickActionCard(
                                        icon: "flame",
                                        title: "Warm-up",
                                        color: .orange
                                    )
                                }
                                
                                NavigationLink(destination: ExerciseLibraryView()) {
                                    QuickActionCard(
                                        icon: "book",
                                        title: "Exercises",
                                        color: .blue
                                    )
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 32)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func calculateStreak() -> Int {
        guard !workoutManager.workoutHistory.isEmpty else { return 0 }
        
        var streak = 0
        var currentDate = Calendar.current.startOfDay(for: Date())
        
        for workout in workoutManager.workoutHistory {
            guard let workoutDate = workout.date else { continue }
            let workoutDay = Calendar.current.startOfDay(for: workoutDate)
            
            if Calendar.current.isDate(workoutDay, inSameDayAs: currentDate) {
                streak += 1
                currentDate = Calendar.current.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
            } else if workoutDay < currentDate {
                break
            }
        }
        
        return streak
    }
}

#Preview {
    HomeView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(WorkoutManager.shared)
}

