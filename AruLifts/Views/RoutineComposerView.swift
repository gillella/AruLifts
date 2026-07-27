import SwiftUI

struct RoutineComposerView: View {
    @EnvironmentObject var store: WorkoutStore
    @EnvironmentObject var activeManager: ActiveWorkoutManager
    @Environment(\.dismiss) private var dismiss

    @State private var routine: GymSessionRoutine
    @State private var isEditing: Bool
    @State private var showingNewTemplate = false
    /// Phase awaiting the template about to be built, so the newly saved
    /// template can be linked back to the phase the user started from.
    @State private var phaseForNewTemplate: UUID?
    /// Last persisted copy of the routine, restored when the user cancels an
    /// edit. Without this, `routine` keeps the discarded in-place mutations.
    @State private var savedSnapshot: GymSessionRoutine

    let isNew: Bool

    init(routine: GymSessionRoutine? = nil) {
        let initial = routine ?? GymSessionRoutine(
            name: "New Gym Routine",
            notes: "Custom multi-phase gym session"
        )
        _routine = State(initialValue: initial)
        _savedSnapshot = State(initialValue: initial)
        _isEditing = State(initialValue: routine == nil)
        isNew = routine == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                routineDetailsSection
                phasesSection
                startButton
            }
            .navigationTitle(routine.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingNewTemplate) {
                WorkoutBuilderView(existing: nil) { newTemplate in
                    linkTemplate(newTemplate, toPhaseWithID: phaseForNewTemplate)
                    phaseForNewTemplate = nil
                }
            }
        }
    }

    // MARK: - Routine Details

    @ViewBuilder
    private var routineDetailsSection: some View {
        Section(header: Text("Routine Details")) {
            if isEditing {
                TextField("Routine Name", text: $routine.name)
                    .font(.headline)
                TextField("Notes / Focus", text: $routine.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Name") {
                    Text(routine.name).font(.headline)
                }
                if !routine.notes.isEmpty {
                    LabeledContent("Notes") {
                        Text(routine.notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Total Duration") {
                    Text("~\(routine.estimatedTotalMinutes) min")
                        .font(.subheadline)
                }
                LabeledContent("Enabled Phases") {
                    Text("\(routine.enabledPhases.count) of \(routine.phases.count)")
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Phases

    @ViewBuilder
    private var phasesSection: some View {
        Section(header: Text("Session Phases")) {
            if isEditing {
                Text("Customize, reorder, or enable/disable each phase of your gym visit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach($routine.phases) { $phase in
                if isEditing {
                    editablePhaseRow(phase: $phase)
                } else {
                    readOnlyPhaseRow(phase: phase)
                }
            }
            .onMove { indices, newOffset in
                if isEditing {
                    routine.phases.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
        }
    }

    // MARK: - Read-Only Phase Row

    private func readOnlyPhaseRow(phase: GymSessionRoutinePhase) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: phase.phaseType.iconSymbol)
                    .foregroundStyle(phase.phaseType.color)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(phase.name)
                        .font(.headline)
                    Text(phase.phaseType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if phase.isEnabled {
                    Text("\(phase.durationSeconds / 60) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if phase.isEnabled {
                if let templateID = phase.templateID,
                   let template = store.templates.first(where: { $0.id == templateID }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.caption2)
                        Text(template.name)
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                }

                if !phase.notes.isEmpty {
                    Text(phase.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(phase.isEnabled ? 1 : 0.5)
    }

    // MARK: - Editable Phase Row

    private func editablePhaseRow(phase: Binding<GymSessionRoutinePhase>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: phase.wrappedValue.phaseType.iconSymbol)
                    .foregroundStyle(phase.wrappedValue.phaseType.color)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(phase.wrappedValue.name)
                        .font(.headline)
                    Text(phase.wrappedValue.phaseType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: phase.isEnabled)
                    .labelsHidden()
            }

            if phase.wrappedValue.isEnabled {
                Divider()

                // Template picker for ALL phase types
                phaseTemplatePicker(phase: phase)

                // Duration stepper for timed phases
                if phase.wrappedValue.phaseType.isTimed {
                    HStack {
                        Text("Duration:")
                            .font(.subheadline)
                        Spacer()
                        Stepper("\(phase.wrappedValue.durationSeconds / 60) min", value: Binding(
                            get: { max(1, phase.wrappedValue.durationSeconds / 60) },
                            set: { phase.wrappedValue.durationSeconds = $0 * 60 }
                        ), in: 1...120)
                    }
                }

                // Notes field
                if !phase.wrappedValue.notes.isEmpty || phase.wrappedValue.phaseType == .saunaRecovery || phase.wrappedValue.phaseType == .steamRecovery {
                    TextField("Notes / Hydration Cue", text: phase.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Template Picker (for all phase types)

    private func phaseTemplatePicker(phase: Binding<GymSessionRoutinePhase>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(templatePickerLabel(for: phase.wrappedValue.phaseType), selection: phase.templateID) {
                Text("None (Timed Only)").tag(UUID?.none)
                ForEach(store.templates) { template in
                    Text(template.name).tag(UUID?.some(template.id))
                }
            }

            Button {
                phaseForNewTemplate = phase.wrappedValue.id
                showingNewTemplate = true
            } label: {
                Label("Create New Template", systemImage: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
        }
    }

    private func templatePickerLabel(for phaseType: GymSessionPhaseType) -> String {
        switch phaseType {
        case .preCardio: return "Cardio Template"
        case .warmupStretches: return "Warm-Up Template"
        case .mainStrength: return "Strength Template"
        case .postStretching: return "Cool-Down Template"
        case .coreWork: return "Core Template"
        case .saunaRecovery: return "Recovery Template"
        case .steamRecovery: return "Recovery Template"
        }
    }

    // MARK: - Start Button

    @ViewBuilder
    private var startButton: some View {
        Section {
            Button(action: startRoutineNow) {
                HStack {
                    Spacer()
                    Label("Start Gym Session Now", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(Color.accentColor)
                .cornerRadius(10)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if isNew {
                        dismiss()
                    } else {
                        routine = savedSnapshot
                        isEditing = false
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveRoutine()
                    if isNew {
                        dismiss()
                    } else {
                        isEditing = false
                    }
                }
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
            }
        }
    }

    // MARK: - Actions

    /// Links a template created inline to the phase the user launched the
    /// builder from. The phase is matched by ID because `routine.phases` may
    /// have been reordered while the builder sheet was open.
    private func linkTemplate(_ template: WorkoutTemplate, toPhaseWithID phaseID: UUID?) {
        guard let phaseID,
              let idx = routine.phases.firstIndex(where: { $0.id == phaseID }) else { return }
        routine.phases[idx].templateID = template.id
    }

    private func saveRoutine() {
        if isNew {
            store.addGymRoutine(routine)
        } else {
            store.updateGymRoutine(routine)
        }
        savedSnapshot = routine
    }

    private func startRoutineNow() {
        saveRoutine()
        let session = WorkoutSession.from(
            routine: routine,
            templates: store.templates,
            library: store.exerciseIndex,
            settings: store.settings
        )
        activeManager.start(session)
        dismiss()
    }
}
