//
//  HistoryView.swift
//  AruLifts
//
//  Created by Aravind Gillella on 9/30/25.
//

import SwiftUI
import Charts

struct HistoryView: View {
    @EnvironmentObject var workoutManager: CustomWorkoutManager
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WorkoutSessionEntity.date, ascending: false)],
        animation: .default)
    private var workouts: FetchedResults<WorkoutSessionEntity>
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color.orange.opacity(0.05), Color.clear]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Stats Overview
                        VStack(spacing: 16) {
                            Text("Your Progress")
                                .font(.title2)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            HStack(spacing: 16) {
                                StatsCard(
                                    title: "Total Workouts",
                                    value: "\(workoutManager.getWorkoutCount())",
                                    icon: "figure.strengthtraining.traditional",
                                    color: .orange
                                )
                                
                                StatsCard(
                                    title: "Total Time",
                                    value: formatTotalTime(workoutManager.getTotalDuration()),
                                    icon: "clock.fill",
                                    color: .blue
                                )
                            }
                            
                            HStack(spacing: 16) {
                                StatsCard(
                                    title: "This Week",
                                    value: "\(workoutManager.getWorkoutsThisWeek())",
                                    icon: "calendar",
                                    color: .green
                                )
                                
                                StatsCard(
                                    title: "Current Streak",
                                    value: "\(workoutManager.getCurrentStreak())d",
                                    icon: "flame.fill",
                                    color: .red
                                )
                            }
                        }
                        .padding()
                        
                        // Weight Progress Chart
                        if !workoutManager.exerciseWeights.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Weight Progress")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(workoutManager.exerciseWeights.sorted(by: { $0.key < $1.key })), id: \.key) { exercise, weight in
                                        HStack {
                                            Text(exercise)
                                                .font(.subheadline)
                                            Spacer()
                                            Text("\(workoutManager.formatWeight(weight)) lbs")
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                                .foregroundColor(.orange)
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal)
                                        .background(Color(.systemBackground))
                                        .cornerRadius(8)
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .padding(.vertical)
                        }
                        
                        // Workout History
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Workout History")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            if workouts.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "calendar.badge.exclamationmark")
                                        .font(.system(size: 60))
                                        .foregroundColor(.gray)
                                    Text("No workouts yet")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    Text("Start your first workout to see your history here")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 60)
                            } else {
                                ForEach(workouts) { workout in
                                    WorkoutHistoryRow(workout: workout)
                                        .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.bottom, 32)
                    }
                    .padding(.top)
                }
            }
            .navigationTitle("History")
        }
    }
    
    private func formatTotalTime(_ total: TimeInterval) -> String {
        let hours = Int(total) / 3600
        if hours > 0 {
            return "\(hours)h"
        } else {
            let minutes = Int(total) / 60
            return "\(minutes)m"
        }
    }
}

struct StatsCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct WorkoutHistoryRow: View {
    let workout: WorkoutSessionEntity
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.workoutName ?? "Workout")
                    .font(.headline)
                if let date = workout.date {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text(formatDuration(workout.duration))
                        .font(.subheadline)
                }
                .foregroundColor(.orange)
                
                if workout.isCompleted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                        Text("Completed")
                            .font(.caption)
                    }
                    .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

#Preview {
    HistoryView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(CustomWorkoutManager.shared)
}

