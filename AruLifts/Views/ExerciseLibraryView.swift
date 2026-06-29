import SwiftUI

struct ExerciseLibraryView: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var search = ""
    @State private var muscleFilter: MuscleGroup?
    @State private var showingNewExercise = false

    private var filtered: [Exercise] {
        store.allExercises.filter { ex in
            (muscleFilter == nil || ex.primaryMuscle == muscleFilter || ex.secondaryMuscles.contains(muscleFilter!)) &&
            (search.isEmpty || ex.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                muscleFilterBar
                List {
                    ForEach(filtered) { ex in
                        NavigationLink {
                            ExerciseDetailView(exercise: ex)
                        } label: {
                            ExerciseRow(exercise: ex)
                        }
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if filtered.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .searchable(text: $search, prompt: "Search exercises")
            .navigationTitle("Exercises")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNewExercise = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingNewExercise) {
                NewExerciseView()
            }
        }
    }

    private var muscleFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isOn: muscleFilter == nil) { muscleFilter = nil }
                ForEach(MuscleGroup.allCases) { m in
                    FilterChip(title: m.displayName, isOn: muscleFilter == m) {
                        muscleFilter = muscleFilter == m ? nil : m
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isOn ? Color.orange : Color(.secondarySystemBackground), in: Capsule())
                .foregroundStyle(isOn ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct ExerciseRow: View {
    let exercise: Exercise
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 46, height: 46)
                Image(systemName: exercise.symbol)
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.body.weight(.medium))
                Text("\(exercise.primaryMuscle.displayName) · \(exercise.equipment.displayName)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Reusable picker presented as a sheet to choose an exercise.
struct ExercisePickerView: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    let onSelect: (Exercise) -> Void

    private var filtered: [Exercise] {
        store.allExercises.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { ex in
                Button {
                    onSelect(ex)
                    dismiss()
                } label: {
                    ExerciseRow(exercise: ex)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $search, prompt: "Search exercises")
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Minimal form to add a user-defined exercise.
struct NewExerciseView: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var muscle: MuscleGroup = .chest
    @State private var equipment: Equipment = .barbell
    @State private var usesWeight = true
    @State private var instructions = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Name", text: $name)
                    Picker("Primary muscle", selection: $muscle) {
                        ForEach(MuscleGroup.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Tracks weight", isOn: $usesWeight)
                }
                Section("Form notes") {
                    TextField("One cue per line", text: $instructions, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let steps = instructions
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let exercise = Exercise(
            name: name.trimmingCharacters(in: .whitespaces),
            primaryMuscle: muscle,
            equipment: equipment,
            instructions: steps,
            symbol: equipment.symbol,
            usesWeight: usesWeight
        )
        store.addCustomExercise(exercise)
        dismiss()
    }
}

#Preview {
    ExerciseLibraryView()
        .environmentObject(WorkoutStore())
}
