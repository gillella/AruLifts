//
//  NewHomeView.swift
//  AruLifts
//
//  Created by Aravind Gillella on 10/1/25.
//

import SwiftUI

struct NewHomeView: View {
    @EnvironmentObject var workoutManager: CustomWorkoutManager
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showWorkoutBuilder = false
    
    var recentWorkouts: [CustomWorkout] {
        workoutManager.savedWorkouts.prefix(3).map { $0 }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color.orange.opacity(0.1), Color.orange.opacity(0.05)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                if let activeWorkout = workoutManager.activeWorkout {
                    CustomWorkoutActiveView(activeWorkout: activeWorkout)
                } else {
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
                                
                                Text("Your Personalized Workout Tracker")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            
                            // Stats Overview
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Your Progress")
                                    .font(.headline)
                                
                                HStack {
                                    StatBadge(
                                        icon: "calendar",
                                        title: "Workouts",
                                        value: "\(workoutManager.getWorkoutCount())"
                                    )
                                    Spacer()
                                    StatBadge(
                                        icon: "flame.fill",
                                        title: "Streak",
                                        value: "\(workoutManager.getCurrentStreak())d"
                                    )
                                }
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                            .padding(.horizontal)
                            
                            // Recent Workouts
                            if !recentWorkouts.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Recent Workouts")
                                            .font(.headline)
                                        Spacer()
                                        NavigationLink(destination: MyWorkoutsView()) {
                                            Text("See All")
                                                .font(.subheadline)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                    .padding(.horizontal)
                                    
                                    ForEach(recentWorkouts) { workout in
                                        QuickStartWorkoutCard(workout: workout) {
                                            workoutManager.startWorkout(workout)
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                            
                            // Create New Workout Button
                            Button(action: {
                                showWorkoutBuilder = true
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                    Text("Create New Workout")
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
                                NavigationLink(destination: MyWorkoutsView()) {
                                    QuickActionCard(
                                        icon: "list.bullet",
                                        title: "My Workouts",
                                        color: .orange
                                    )
                                }
                                
                                NavigationLink(destination: WarmUpCalculatorView()) {
                                    QuickActionCard(
                                        icon: "flame",
                                        title: "Warm-up",
                                        color: .red
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
            .sheet(isPresented: $showWorkoutBuilder) {
                WorkoutBuilderView()
            }
        }
    }
}

struct QuickStartWorkoutCard: View {
    let workout: CustomWorkout
    let onStart: () -> Void
    
    var body: some View {
        Button(action: onStart) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 12) {
                        Label("\(workout.totalExercises)", systemImage: "figure.walk")
                        Label("\(workout.totalSets)", systemImage: "repeat")
                        Label("~\(workout.estimatedDuration)m", systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundColor(.orange)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        }
    }
}

struct StatBadge: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
            }
        }
    }
}

struct QuickActionCard: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    NewHomeView()
        .environmentObject(CustomWorkoutManager.shared)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

