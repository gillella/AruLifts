import SwiftUI

struct MyWorkoutsView: View {
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var active: ActiveWorkoutManager
    @State private var editingTemplate: WorkoutTemplate?
    @State private var showingBuilder = false
    @State private var showingPresetPicker = false
    @State private var editingRoutine: GymSessionRoutine?
    @State private var showingRoutineComposer = false

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Gym Session Routines (7-Phase)").font(.subheadline).bold()) {
                    ForEach(store.gymRoutines) { routine in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color.orange.opacity(0.18)).frame(width: 40, height: 40)
                                Image(systemName: "flame.fill").foregroundStyle(.orange)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(routine.name).font(.headline)
                                Text("~\(routine.estimatedTotalMinutes) min · \(routine.enabledPhases.count) phases")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()

                            Button {
                                let session = WorkoutSession.from(
                                    routine: routine,
                                    templates: store.templates,
                                    library: store.exerciseIndex,
                                    settings: store.settings
                                )
                                active.start(session)
                            } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingRoutine = routine
                            showingRoutineComposer = true
                        }
                    }
                    .onDelete(perform: store.deleteGymRoutines)

                    Button {
                        editingRoutine = nil
                        showingRoutineComposer = true
                    } label: {
                        Label("Compose New Gym Routine", systemImage: "plus.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }

                Section(header: Text("Workout Templates").font(.subheadline).bold()) {
                    ForEach(store.templates) { template in
                        NavigationLink {
                            TemplateDetailView(template: template)
                        } label: {
                            templateRow(template)
                        }
                    }
                    .onDelete(perform: store.deleteTemplates)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("My Workouts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            editingRoutine = nil
                            showingRoutineComposer = true
                        } label: {
                            Label("Compose 7-Phase Routine", systemImage: "flame.fill")
                        }

                        Button {
                            editingTemplate = nil
                            showingBuilder = true
                        } label: {
                            Label("Create Blank Workout", systemImage: "plus.square")
                        }

                        Button {
                            showingPresetPicker = true
                        } label: {
                            Label("Start from Starter Preset", systemImage: "sparkles")
                        }

                        Button {
                            store.ensureDefaultTemplatesExist()
                        } label: {
                            Label("Restore Starter Presets", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingRoutineComposer) {
                RoutineComposerView(routine: editingRoutine)
            }
            .overlay {
                if store.templates.isEmpty {
                    ContentUnavailableView {
                        Label("No Workouts", systemImage: "square.grid.2x2")
                    } description: {
                        Text("Tap + to choose a starter preset or build your first custom workout.")
                    } actions: {
                        Button("Choose Starter Preset") {
                            showingPresetPicker = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }
            }
            .sheet(isPresented: $showingBuilder) {
                WorkoutBuilderView(existing: editingTemplate)
            }
            .sheet(isPresented: $showingPresetPicker) {
                PresetTemplatePickerView { preset in
                    let draft = WorkoutTemplate(
                        name: preset.name,
                        category: preset.category,
                        exercises: preset.exercises.map { ex in
                            var newEx = ex
                            newEx.id = UUID()
                            return newEx
                        },
                        notes: preset.notes
                    )
                    editingTemplate = draft
                    showingBuilder = true
                }
            }
        }
    }

    private func templateRow(_ template: WorkoutTemplate) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(template.category.color.opacity(0.18)).frame(width: 40, height: 40)
                Image(systemName: template.category.symbol).foregroundStyle(template.category.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name).font(.headline)
                Text(subtitle(template))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// "5 exercises · 17 sets" — drops the set count for timed-only plans.
    private func subtitle(_ t: WorkoutTemplate) -> String {
        var parts = [countLabel(t.exerciseCount, "exercise")]
        if t.totalSets > 0 { parts.append(countLabel(t.totalSets, "set")) }
        return parts.joined(separator: " · ")
    }
}

/// Lists built-in starter templates (4-day split and original presets)
/// to populate WorkoutBuilderView for custom editing before saving.
struct PresetTemplatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (WorkoutTemplate) -> Void

    private let presets = ExerciseLibrary.defaultTemplates()

    var body: some View {
        NavigationStack {
            List {
                Section("4-Day Split Presets") {
                    ForEach(presets.filter { $0.name.contains("Upper Body A") || $0.name.contains("Lower Body A") || $0.name.contains("Upper Body B") || $0.name.contains("Lower Body B") }) { preset in
                        Button {
                            onSelect(preset)
                            dismiss()
                        } label: {
                            presetRow(preset)
                        }
                    }
                }

                Section("Other Starter Presets") {
                    ForEach(presets.filter { !$0.name.contains("Upper Body A") && !$0.name.contains("Lower Body A") && !$0.name.contains("Upper Body B") && !$0.name.contains("Lower Body B") }) { preset in
                        Button {
                            onSelect(preset)
                            dismiss()
                        } label: {
                            presetRow(preset)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Choose Starter Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func presetRow(_ template: WorkoutTemplate) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(template.category.color.opacity(0.18)).frame(width: 36, height: 36)
                Image(systemName: template.category.symbol).foregroundStyle(template.category.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name).font(.headline).foregroundStyle(.primary)
                Text("\(template.exerciseCount) exercises · \(template.totalSets) sets")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

/// Read-only template overview with Start and Edit actions.
struct TemplateDetailView: View {
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var active: ActiveWorkoutManager
    let template: WorkoutTemplate
    @State private var showingEdit = false
    @State private var showingTodaySetup = false

    var body: some View {
        List {
            Section {
                HStack {
                    CategoryBadge(category: template.category)
                    Spacer()
                    Text("~\(template.estimatedMinutes) min")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if !template.notes.isEmpty {
                    Text(template.notes).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Section("Exercises") {
                ForEach(template.exercises) { ex in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name).font(.body.weight(.medium))
                            Text(exerciseDetail(ex))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if ex.isTimed {
                            Image(systemName: "timer").font(.caption2).foregroundStyle(.tertiary)
                        } else {
                            Text("\(ex.restSeconds)s rest")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { showingTodaySetup = true } label: {
                Label("Start Workout", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
            }
            .padding()
            .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            WorkoutBuilderView(existing: template)
        }
        .sheet(isPresented: $showingTodaySetup) {
            TodayWorkoutSetupView(
                template: template,
                library: store.exerciseIndex,
                settings: store.settings
            )
            .environmentObject(active)
        }
    }

    /// "4 × 8 · 60 KG" for lifts, or "10 min" for timed cardio/stretches.
    private func exerciseDetail(_ ex: TemplateExercise) -> String {
        if ex.isTimed { return formatDuration(ex.durationSeconds) }
        let base = "\(ex.targetSets) × \(ex.targetReps)"
        return ex.weight > 0 ? base + " · \(formatWeight(ex.weight, units: store.settings.units))" : base
    }
}

/// Lets the lifter choose a one-day exercise order before a session exists.
/// The resulting session contains the reordered instances; the template stays
/// untouched in `WorkoutStore`.
struct TodayWorkoutSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var active: ActiveWorkoutManager
    let template: WorkoutTemplate
    @State private var session: WorkoutSession

    init(template: WorkoutTemplate, library: [UUID: Exercise], settings: AppSettings) {
        self.template = template
        _session = State(initialValue: WorkoutSession.from(template: template, library: library, settings: settings))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose today's exercise order. Your saved workout will stay unchanged.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("Exercises") {
                    ForEach(session.exercises) { exercise in
                        Text(exercise.name)
                            .accessibilityHint("Drag to change the order for today's workout")
                    }
                    .onMove { session.exercises.move(fromOffsets: $0, toOffset: $1) }
                }
            }
            .navigationTitle("Today's Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton().disabled(session.exercises.count < 2)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    active.start(session)
                    dismiss()
                } label: {
                    Label("Start Workout", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding()
                .background(.bar)
            }
        }
    }
}

#Preview {
    MyWorkoutsView()
        .environmentObject(WorkoutStore())
        .environmentObject(ActiveWorkoutManager())
}
