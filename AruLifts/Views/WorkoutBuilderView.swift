import SwiftUI

/// Create or edit a workout template: name, category, and a list of exercises
/// each with target sets/reps/weight/rest.
struct WorkoutBuilderView: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss

    let existing: WorkoutTemplate?

    @State private var name: String
    @State private var category: WorkoutCategory
    @State private var notes: String
    @State private var exercises: [TemplateExercise]
    @State private var showingPicker = false

    init(existing: WorkoutTemplate?) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _category = State(initialValue: existing?.category ?? .custom)
        _notes = State(initialValue: existing?.notes ?? "")
        _exercises = State(initialValue: existing?.exercises ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Name (e.g. Upper Body)", text: $name)
                    Picker("Category", selection: $category) {
                        ForEach(WorkoutCategory.allCases) { cat in
                            Label(cat.displayName, systemImage: cat.symbol).tag(cat)
                        }
                    }
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("Exercises") {
                    if exercises.isEmpty {
                        Text("No exercises yet")
                            .foregroundStyle(.secondary)
                    }
                    ForEach($exercises) { $ex in
                        ExerciseConfigRow(exercise: $ex, units: store.settings.units)
                    }
                    .onDelete { exercises.remove(atOffsets: $0) }
                    .onMove { exercises.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        showingPicker = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Workout" : "Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || exercises.isEmpty)
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { selected in
                    let rest = store.settings.defaultRestSeconds
                    let prefill = store.lastWeight(for: selected.id) ?? 0
                    exercises.append(TemplateExercise(
                        exerciseID: selected.id,
                        name: selected.name,
                        weight: prefill,
                        restSeconds: rest
                    ))
                }
            }
        }
    }

    private func save() {
        var template = existing ?? WorkoutTemplate(name: name)
        template.name = name.trimmingCharacters(in: .whitespaces)
        template.category = category
        template.notes = notes
        template.exercises = exercises
        store.updateTemplate(template)
        dismiss()
    }
}

/// Inline stepper controls for one exercise inside the builder.
struct ExerciseConfigRow: View {
    @Binding var exercise: TemplateExercise
    let units: AppSettings.Units

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exercise.name).font(.headline)

            HStack {
                stepper(label: "Sets", value: $exercise.targetSets, range: 1...10)
                Divider().frame(height: 28)
                stepper(label: "Reps", value: $exercise.targetReps, range: 1...50)
            }

            HStack {
                Text("Weight").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { exercise.weight = max(0, exercise.weight - 2.5) } label: {
                    Image(systemName: "minus.circle")
                }
                Text(formatWeight(exercise.weight, units: units))
                    .font(.subheadline.monospacedDigit())
                    .frame(minWidth: 70)
                Button { exercise.weight += 2.5 } label: {
                    Image(systemName: "plus.circle")
                }
            }
            .buttonStyle(.borderless)

            HStack {
                Text("Rest").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("Rest", selection: $exercise.restSeconds) {
                    ForEach([60, 90, 120, 150, 180, 240, 300], id: \.self) { s in
                        Text("\(s / 60):\(String(format: "%02d", s % 60))").tag(s)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(.vertical, 6)
    }

    private func stepper(label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Button { if value.wrappedValue > range.lowerBound { value.wrappedValue -= 1 } } label: {
                Image(systemName: "minus.circle")
            }
            Text("\(value.wrappedValue)")
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 22)
            Button { if value.wrappedValue < range.upperBound { value.wrappedValue += 1 } } label: {
                Image(systemName: "plus.circle")
            }
        }
        .buttonStyle(.borderless)
    }
}

#Preview {
    WorkoutBuilderView(existing: nil)
        .environmentObject(WorkoutStore())
}
