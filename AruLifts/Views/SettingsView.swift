//
//  SettingsView.swift
//  AruLifts
//
//  Created by Aravind Gillella on 9/30/25.
//

import SwiftUI
import CoreData

struct SettingsView: View {
    @EnvironmentObject var workoutManager: CustomWorkoutManager
    @AppStorage("weightUnit") private var weightUnit = "lbs"
    @AppStorage("restTimerSound") private var restTimerSound = true
    @AppStorage("restTimerHaptic") private var restTimerHaptic = true
    @State private var showResetAlert = false
    
    var body: some View {
        NavigationView {
            List {
                // Profile Section
                Section {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.orange, .red],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AruLifts User")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Keep pushing your limits!")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 8)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Profile")
                }
                
                // Preferences Section
                Section {
                    Picker("Weight Unit", selection: $weightUnit) {
                        Text("Pounds (lbs)").tag("lbs")
                        Text("Kilograms (kg)").tag("kg")
                    }
                    
                    Toggle("Rest Timer Sound", isOn: $restTimerSound)
                    Toggle("Rest Timer Haptics", isOn: $restTimerHaptic)
                } header: {
                    Text("Preferences")
                } footer: {
                    Text("Customize your workout experience")
                }
                
                // Current Weights Section
                Section {
                    ForEach(Array(workoutManager.exerciseWeights.sorted(by: { $0.key < $1.key })), id: \.key) { exercise, weight in
                        HStack {
                            Text(exercise)
                            Spacer()
                            Text("\(workoutManager.formatWeight(weight)) \(weightUnit)")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Current Weights")
                } footer: {
                    Text("Your current working weights for each exercise")
                }
                
                // Workout Stats Section
                Section {
                    HStack {
                        Text("Total Workouts")
                        Spacer()
                        Text("\(workoutManager.savedWorkouts.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Workouts Completed")
                        Spacer()
                        Text("\(workoutManager.getWorkoutCount())")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Statistics")
                }
                
                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com")!) {
                        HStack {
                            Text("GitHub")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                        }
                    }
                    
                    NavigationLink(destination: AboutView()) {
                        Text("About AruLifts")
                    }
                } header: {
                    Text("About")
                }
                
                // Data Section
                Section {
                    Button(role: .destructive, action: {
                        showResetAlert = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Reset All Progress")
                        }
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("This will delete all your workout history and reset your weights to defaults. This action cannot be undone.")
                }
            }
            .navigationTitle("Settings")
            .alert("Reset All Progress?", isPresented: $showResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    resetAllProgress()
                }
            } message: {
                Text("This will permanently delete all your workout data. Are you sure?")
            }
        }
    }
    
    private func resetAllProgress() {
        // Reset weights
        workoutManager.exerciseWeights = [:]
        
        // Clear workout history from Core Data
        let context = PersistenceController.shared.container.viewContext
        
        // Delete workout sessions
        let sessionFetchRequest: NSFetchRequest<NSFetchRequestResult> = WorkoutSessionEntity.fetchRequest()
        let deleteSessionsRequest = NSBatchDeleteRequest(fetchRequest: sessionFetchRequest)
        
        // Delete custom workouts
        let workoutFetchRequest: NSFetchRequest<NSFetchRequestResult> = CustomWorkoutEntity.fetchRequest()
        let deleteWorkoutsRequest = NSBatchDeleteRequest(fetchRequest: workoutFetchRequest)
        
        do {
            try context.execute(deleteSessionsRequest)
            try context.execute(deleteWorkoutsRequest)
            try context.save()
            
            // Reload data
            workoutManager.loadSavedWorkouts()
            workoutManager.loadWorkoutHistory()
        } catch {
            print("Error resetting progress: \(error)")
        }
    }
}

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Logo
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.top, 32)
                
                Text("AruLifts")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                
                Text("Version 1.0.0")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Description
                VStack(alignment: .leading, spacing: 16) {
                    Text("About")
                        .font(.headline)
                    
                    Text("AruLifts is your personal strength training companion. Built on proven principles of progressive overload, it helps you track your workouts, build strength, and achieve your fitness goals.")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Text("Features")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        FeatureRow(icon: "figure.walk", text: "5×5 strength training program")
                        FeatureRow(icon: "chart.line.uptrend.xyaxis", text: "Progressive weight tracking")
                        FeatureRow(icon: "timer", text: "Built-in rest timer")
                        FeatureRow(icon: "flame", text: "Warm-up calculator")
                        FeatureRow(icon: "book", text: "Comprehensive exercise library")
                        FeatureRow(icon: "calendar", text: "Workout history & statistics")
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                
                Text("Built with ❤️ for strength enthusiasts")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 32)
            }
            .padding()
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.orange.opacity(0.05), Color.clear]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.orange)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(CustomWorkoutManager.shared)
}

