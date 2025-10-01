//
//  ExerciseLibraryView.swift
//  AruLifts
//
//  Created by Aravind Gillella on 9/30/25.
//

import SwiftUI

struct ExerciseLibraryView: View {
    @EnvironmentObject var workoutManager: CustomWorkoutManager
    @State private var searchText = ""
    @State private var selectedCategory: ExerciseCategory? = nil
    @State private var selectedMuscleGroup: MuscleGroup? = nil
    
    var filteredExercises: [Exercise] {
        var exercises = workoutManager.exerciseLibrary
        
        if !searchText.isEmpty {
            exercises = exercises.filter { exercise in
                exercise.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        if let category = selectedCategory {
            exercises = exercises.filter { $0.category == category }
        }
        
        if let muscleGroup = selectedMuscleGroup {
            exercises = exercises.filter { exercise in
                exercise.primaryMuscles.contains(muscleGroup) ||
                exercise.secondaryMuscles.contains(muscleGroup)
            }
        }
        
        return exercises
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search exercises...", text: $searchText)
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
                .padding()
                
                // Filters
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        FilterChip(
                            title: "All",
                            isSelected: selectedCategory == nil && selectedMuscleGroup == nil,
                            action: {
                                selectedCategory = nil
                                selectedMuscleGroup = nil
                            }
                        )
                        
                        ForEach(ExerciseCategory.allCases, id: \.self) { category in
                            FilterChip(
                                title: category.rawValue,
                                isSelected: selectedCategory == category,
                                action: {
                                    selectedCategory = selectedCategory == category ? nil : category
                                    selectedMuscleGroup = nil
                                }
                            )
                        }
                        
                        Divider()
                            .frame(height: 20)
                        
                        ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                            FilterChip(
                                title: muscle.rawValue,
                                isSelected: selectedMuscleGroup == muscle,
                                action: {
                                    selectedMuscleGroup = selectedMuscleGroup == muscle ? nil : muscle
                                    selectedCategory = nil
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom)
                
                // Exercise list
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(filteredExercises) { exercise in
                            NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                                ExerciseCard(exercise: exercise)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Exercise Library")
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.orange.opacity(0.05), Color.clear]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.orange : Color(.systemGray6))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
}

struct ExerciseCard: View {
    let exercise: Exercise
    @EnvironmentObject var workoutManager: CustomWorkoutManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        Text(exercise.category.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                        
                        ForEach(exercise.primaryMuscles, id: \.self) { muscle in
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
                
                if let weight = workoutManager.exerciseWeights[exercise.name] {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(workoutManager.formatWeight(weight))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                        Text("lbs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Text(exercise.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct ExerciseDetailView: View {
    let exercise: Exercise
    @EnvironmentObject var workoutManager: CustomWorkoutManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    Text(exercise.name)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    HStack {
                        Label(exercise.category.rawValue, systemImage: "tag.fill")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                        
                        if let weight = workoutManager.exerciseWeights[exercise.name] {
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("Current Weight")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(workoutManager.formatWeight(weight)) lbs")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                
                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.headline)
                    Text(exercise.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                
                // Muscles
                VStack(alignment: .leading, spacing: 12) {
                    Text("Muscle Groups")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        if !exercise.primaryMuscles.isEmpty {
                            HStack {
                                Text("Primary:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                ForEach(exercise.primaryMuscles, id: \.self) { muscle in
                                    Text(muscle.rawValue)
                                        .font(.subheadline)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.orange.opacity(0.2))
                                        .foregroundColor(.orange)
                                        .cornerRadius(8)
                                }
                            }
                        }
                        
                        if !exercise.secondaryMuscles.isEmpty {
                            HStack {
                                Text("Secondary:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                ForEach(exercise.secondaryMuscles, id: \.self) { muscle in
                                    Text(muscle.rawValue)
                                        .font(.subheadline)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.2))
                                        .foregroundColor(.blue)
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                
                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Text("How to Perform")
                        .font(.headline)
                    
                    ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { index, instruction in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.orange)
                                .clipShape(Circle())
                            
                            Text(instruction)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
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
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ExerciseLibraryView()
        .environmentObject(CustomWorkoutManager.shared)
}

