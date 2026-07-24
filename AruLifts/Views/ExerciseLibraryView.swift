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

/// Reusable picker presented as a sheet to choose an exercise. Surfaces a
/// "Suggested" section matching the workout's category, and lets you preview
/// an exercise's full details before adding it.
struct ExercisePickerView: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var muscleFilter: MuscleGroup?
    /// Exercise whose detail sheet is open for preview, if any.
    @State private var preview: Exercise?
    let category: WorkoutCategory
    let onSelect: (Exercise) -> Void

    private var matching: [Exercise] {
        store.allExercises.filter { exercise in
            let matchesSearch = search.isEmpty || exercise.name.localizedCaseInsensitiveContains(search)
            let matchesMuscle = muscleFilter == nil ||
                exercise.primaryMuscle == muscleFilter ||
                exercise.secondaryMuscles.contains(muscleFilter!)
            return matchesSearch && matchesMuscle
        }
    }

    /// Exercises whose primary or secondary muscle fits the workout's category.
    private var suggested: [Exercise] {
        let muscles = Set(category.suggestedMuscles)
        guard !muscles.isEmpty else { return [] }
        return matching.filter { ex in
            muscles.contains(ex.primaryMuscle) || ex.secondaryMuscles.contains(where: muscles.contains)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                muscleFilterBar

                List {
                    // Suggestions are intentionally preserved only for the
                    // unfiltered All view. A selected muscle is an explicit
                    // request for a complete, narrowed list.
                    if search.isEmpty, muscleFilter == nil, !suggested.isEmpty {
                        let suggestedIDs = Set(suggested.map(\.id))
                        Section("Suggested for \(category.displayName)") {
                            ForEach(suggested) { row($0) }
                        }
                        Section("All Exercises") {
                            ForEach(matching.filter { !suggestedIDs.contains($0.id) }) { row($0) }
                        }
                    } else {
                        ForEach(matching) { row($0) }
                    }
                }
                .listStyle(.insetGrouped)
                .overlay {
                    if matching.isEmpty {
                        ContentUnavailableView(
                            "No Exercises Found",
                            systemImage: "magnifyingglass",
                            description: Text(emptyStateDescription)
                        )
                    }
                }
            }
            .searchable(text: $search, prompt: "Search exercises")
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $preview) { ex in
                NavigationStack {
                    ExerciseDetailView(exercise: ex)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Add") { add(ex) }
                            }
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { preview = nil }
                            }
                        }
                }
            }
        }
    }

    private var muscleFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isOn: muscleFilter == nil) {
                    muscleFilter = nil
                }
                ForEach(MuscleGroup.allCases) { muscle in
                    FilterChip(
                        title: muscle.displayName,
                        isOn: muscleFilter == muscle
                    ) {
                        muscleFilter = muscleFilter == muscle ? nil : muscle
                    }
                    .accessibilityHint("Filters exercises by \(muscle.displayName)")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Muscle group filter")
    }

    private var emptyStateDescription: String {
        switch (search.isEmpty, muscleFilter) {
        case (false, let muscle?):
            return "No \(muscle.displayName.lowercased()) exercises match \(search)."
        case (false, nil):
            return "No exercises match \(search)."
        case (true, let muscle?):
            return "No \(muscle.displayName.lowercased()) exercises are available."
        case (true, nil):
            return "Try another filter."
        }
    }

    /// One picker row: tap the body to add, tap ⓘ to preview details first.
    private func row(_ ex: Exercise) -> some View {
        HStack(spacing: 8) {
            Button { add(ex) } label: {
                HStack {
                    ExerciseRow(exercise: ex)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { preview = ex } label: {
                Image(systemName: "info.circle")
                    .imageScale(.large)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.borderless)
        }
    }

    private func add(_ ex: Exercise) {
        onSelect(ex)
        preview = nil
        dismiss()
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
