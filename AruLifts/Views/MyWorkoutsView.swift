//
//  MyWorkoutsView.swift
//  AruLifts
//
//  Created by Aravind Gillella on 10/1/25.
//

import SwiftUI

struct MyWorkoutsView: View {
    @EnvironmentObject var workoutManager: CustomWorkoutManager
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showWorkoutBuilder = false
    @State private var editingWorkout: CustomWorkout? = nil
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    
    var filteredWorkouts: [CustomWorkout] {
        var workouts = workoutManager.savedWorkouts
        
        if !searchText.isEmpty {
            workouts = workouts.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        if let category = selectedCategory {
            workouts = workouts.filter { $0.category == category }
        }
        
        return workouts
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                if filteredWorkouts.isEmpty {
                    EmptyWorkoutsView(onCreateTap: { showWorkoutBuilder = true })
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Search bar
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.gray)
                                TextField("Search workouts...", text: $searchText)
                                    .textFieldStyle(.plain)
                                if !searchText.isEmpty {
                                    Button(action: { searchText = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .padding(.horizontal)
                            .padding(.top)
                            
                            // Category filters
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    FilterChip(
                                        title: "All",
                                        isSelected: selectedCategory == nil,
                                        action: { selectedCategory = nil }
                                    )
                                    
                                    ForEach(WorkoutCategory.allCases, id: \.self) { category in
                                        FilterChip(
                                            title: category.rawValue,
                                            isSelected: selectedCategory == category.rawValue,
                                            action: {
                                                selectedCategory = selectedCategory == category.rawValue ? nil : category.rawValue
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal)
                            }
                            
                            // Workouts list
                            LazyVStack(spacing: 12) {
                                ForEach(filteredWorkouts) { workout in
                                    WorkoutCard(
                                        workout: workout,
                                        onStart: {
                                            workoutManager.startWorkout(workout)
                                        },
                                        onEdit: {
                                            editingWorkout = workout
                                        },
                                        onDuplicate: {
                                            workoutManager.duplicateWorkout(workout)
                                        },
                                        onDelete: {
                                            workoutManager.deleteWorkout(workout)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 32)
                        }
                    }
                }
            }
            .navigationTitle("My Workouts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showWorkoutBuilder = true }) {
                        Image(systemName: "plus")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showWorkoutBuilder) {
                WorkoutBuilderView()
            }
            .sheet(item: $editingWorkout) { workout in
                WorkoutBuilderView(existingWorkout: workout)
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Workout Card
struct WorkoutCard: View {
    let workout: CustomWorkout
    let onStart: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    
    @State private var showActionSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.name)
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    if let category = workout.category {
                        Text(category)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(6)
                    }
                }
                
                Spacer()
                
                Button(action: { showActionSheet = true }) {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
            }
            
            Divider()
            
            // Workout stats
            HStack(spacing: 20) {
                StatItem(icon: "figure.strengthtraining.traditional", value: "\(workout.totalExercises)", label: "Exercises")
                StatItem(icon: "repeat", value: "\(workout.totalSets)", label: "Sets")
                StatItem(icon: "clock", value: "~\(workout.estimatedDuration)m", label: "Duration")
            }
            
            if let lastUsed = workout.lastUsedDate {
                Text("Last used: \(lastUsed, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Start button
            Button(action: onStart) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start Workout")
                        .fontWeight(.semibold)
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
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        .confirmationDialog("Workout Options", isPresented: $showActionSheet, titleVisibility: .visible) {
            Button("Edit") { onEdit() }
            Button("Duplicate") { onDuplicate() }
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.orange)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Empty State
struct EmptyWorkoutsView: View {
    let onCreateTap: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "dumbbell")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 8) {
                Text("No Workouts Yet")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Create your first custom workout\nto get started!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: onCreateTap) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Create Workout")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .padding()
    }
}

#Preview {
    MyWorkoutsView()
        .environmentObject(CustomWorkoutManager.shared)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

