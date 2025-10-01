//
//  WorkoutBuilderView.swift
//  AruLifts
//
//  Created by Aravind Gillella on 10/1/25.
//

import SwiftUI

struct WorkoutBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var workoutManager: CustomWorkoutManager
    
    @State private var workoutName: String = ""
    @State private var workoutCategory: String = WorkoutCategory.custom.rawValue
    @State private var workoutNotes: String = ""
    @State private var exercises: [WorkoutExerciseConfig] = []
    @State private var showExercisePicker = false
    @State private var editingExerciseIndex: Int? = nil
    
    var isEditing: Bool
    var existingWorkout: CustomWorkout?
    
    init(existingWorkout: CustomWorkout? = nil) {
        self.isEditing = existingWorkout != nil
        self.existingWorkout = existingWorkout
        if let workout = existingWorkout {
            _workoutName = State(initialValue: workout.name)
            _workoutCategory = State(initialValue: workout.category ?? WorkoutCategory.custom.rawValue)
            _workoutNotes = State(initialValue: workout.notes ?? "")
            _exercises = State(initialValue: workout.exercises)
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Workout Details Section
                Section("Workout Details") {
                    TextField("Workout Name", text: $workoutName)
                        .font(.headline)
                    
                    Picker("Category", selection: $workoutCategory) {
                        ForEach(WorkoutCategory.allCases, id: \.self) { category in
                            Text(category.rawValue).tag(category.rawValue)
                        }
                    }
                    
                    TextField("Notes (optional)", text: $workoutNotes, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.subheadline)
                }
                
                // Exercises Section
                Section {
                    ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                        ExerciseRowInBuilder(
                            config: exercise,
                            onTap: {
                                editingExerciseIndex = index
                            },
                            onDelete: {
                                exercises.remove(at: index)
                                reorderExercises()
                            }
                        )
                    }
                    .onMove { from, to in
                        exercises.move(fromOffsets: from, toOffset: to)
                        reorderExercises()
                    }
                    
                    Button(action: {
                        showExercisePicker = true
                    }) {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                            .foregroundColor(.orange)
                    }
                } header: {
                    HStack {
                        Text("Exercises (\(exercises.count))")
                        Spacer()
                        if !exercises.isEmpty {
                            Text("Total Sets: \(exercises.reduce(0) { $0 + $1.sets })")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } footer: {
                    if !exercises.isEmpty {
                        Text("Estimated duration: ~\(estimatedDuration()) min")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Workout" : "New Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveWorkout()
                    }
                    .disabled(workoutName.isEmpty || exercises.isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showExercisePicker) {
                ExercisePickerView { exercise in
                    addExercise(exercise)
                }
            }
            .sheet(isPresented: Binding(
                get: { editingExerciseIndex != nil },
                set: { if !$0 { editingExerciseIndex = nil } }
            )) {
                if let index = editingExerciseIndex {
                    ExerciseConfigView(config: $exercises[index])
                }
            }
        }
    }
    
    private func addExercise(_ exercise: Exercise) {
        let defaultWeight = workoutManager.exerciseWeights[exercise.name] ?? (exercise.requiresWeight ? 45.0 : 0)
        let config = WorkoutExerciseConfig(
            exercise: exercise,
            sets: 3,
            reps: 10,
            weight: exercise.requiresWeight ? defaultWeight : nil,
            restTime: 90,
            order: exercises.count
        )
        exercises.append(config)
    }
    
    private func reorderExercises() {
        for (index, _) in exercises.enumerated() {
            exercises[index].order = index
        }
    }
    
    private func estimatedDuration() -> Int {
        let workTime = exercises.reduce(0) { $0 + $1.sets } * 45 // 45 sec per set
        let restTime = exercises.reduce(0) { total, config in
            total + (config.sets * config.restTime)
        }
        return (workTime + restTime) / 60
    }
    
    private func saveWorkout() {
        let workout = CustomWorkout(
            id: existingWorkout?.id ?? UUID(),
            name: workoutName,
            exercises: exercises,
            createdDate: existingWorkout?.createdDate ?? Date(),
            lastUsedDate: existingWorkout?.lastUsedDate,
            category: workoutCategory,
            notes: workoutNotes.isEmpty ? nil : workoutNotes
        )
        
        workoutManager.saveWorkout(workout)
        dismiss()
    }
}

// MARK: - Exercise Row in Builder
struct ExerciseRowInBuilder: View {
    let config: WorkoutExerciseConfig
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(config.exercise.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 12) {
                        Label("\(config.sets) sets", systemImage: "repeat")
                        Label("\(config.reps) reps", systemImage: "number")
                        if let weight = config.weight, weight > 0 {
                            Label("\(Int(weight)) lbs", systemImage: "scalemass")
                        }
                        Label("\(config.restTime)s", systemImage: "timer")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Exercise Picker View
struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var workoutManager: CustomWorkoutManager
    @State private var searchText = ""
    @State private var selectedEquipment: EquipmentType? = nil
    @State private var selectedMuscle: MuscleGroup? = nil
    
    let onSelect: (Exercise) -> Void
    
    var filteredExercises: [Exercise] {
        var exercises = workoutManager.exerciseLibrary
        
        if !searchText.isEmpty {
            exercises = exercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        if let equipment = selectedEquipment {
            exercises = exercises.filter { $0.equipment == equipment }
        }
        
        if let muscle = selectedMuscle {
            exercises = exercises.filter { $0.primaryMuscles.contains(muscle) || $0.secondaryMuscles.contains(muscle) }
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
                            isSelected: selectedEquipment == nil && selectedMuscle == nil,
                            action: {
                                selectedEquipment = nil
                                selectedMuscle = nil
                            }
                        )
                        
                        ForEach(EquipmentType.allCases, id: \.self) { equipment in
                            FilterChip(
                                title: equipment.rawValue,
                                isSelected: selectedEquipment == equipment,
                                action: {
                                    selectedEquipment = selectedEquipment == equipment ? nil : equipment
                                    selectedMuscle = nil
                                }
                            )
                        }
                        
                        Divider()
                            .frame(height: 20)
                        
                        ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                            FilterChip(
                                title: muscle.rawValue,
                                isSelected: selectedMuscle == muscle,
                                action: {
                                    selectedMuscle = selectedMuscle == muscle ? nil : muscle
                                    selectedEquipment = nil
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom)
                
                // Exercise list
                List(filteredExercises) { exercise in
                    Button(action: {
                        onSelect(exercise)
                        dismiss()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                HStack(spacing: 8) {
                                    Text(exercise.equipment.rawValue)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.orange.opacity(0.2))
                                        .foregroundColor(.orange)
                                        .cornerRadius(4)
                                    
                                    ForEach(exercise.primaryMuscles.prefix(2), id: \.self) { muscle in
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
                            
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Exercise Config View
struct ExerciseConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var config: WorkoutExerciseConfig
    
    @State private var sets: Int
    @State private var reps: Int
    @State private var weight: Double
    @State private var restTime: Int
    @State private var notes: String
    
    init(config: Binding<WorkoutExerciseConfig>) {
        self._config = config
        _sets = State(initialValue: config.wrappedValue.sets)
        _reps = State(initialValue: config.wrappedValue.reps)
        _weight = State(initialValue: config.wrappedValue.weight ?? 0)
        _restTime = State(initialValue: config.wrappedValue.restTime)
        _notes = State(initialValue: config.wrappedValue.notes ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Exercise") {
                    Text(config.exercise.name)
                        .font(.headline)
                }
                
                Section("Configuration") {
                    Stepper("Sets: \(sets)", value: $sets, in: 1...10)
                    Stepper("Reps: \(reps)", value: $reps, in: 1...50)
                    
                    if config.exercise.requiresWeight {
                        HStack {
                            Text("Weight")
                            Spacer()
                            TextField("Weight", value: $weight, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("lbs")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Picker("Rest Time", selection: $restTime) {
                        Text("30 sec").tag(30)
                        Text("45 sec").tag(45)
                        Text("60 sec").tag(60)
                        Text("90 sec").tag(90)
                        Text("2 min").tag(120)
                        Text("3 min").tag(180)
                        Text("4 min").tag(240)
                        Text("5 min").tag(300)
                    }
                }
                
                Section("Notes") {
                    TextField("Add notes...", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Configure Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        config.sets = sets
                        config.reps = reps
                        config.weight = config.exercise.requiresWeight ? weight : nil
                        config.restTime = restTime
                        config.notes = notes.isEmpty ? nil : notes
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// Helper for optional Int binding
extension Binding where Value == Int? {
    init(_ source: Binding<Int>) {
        self.init(
            get: { source.wrappedValue },
            set: { source.wrappedValue = $0 ?? 0 }
        )
    }
}

#Preview {
    WorkoutBuilderView()
        .environmentObject(CustomWorkoutManager.shared)
}

