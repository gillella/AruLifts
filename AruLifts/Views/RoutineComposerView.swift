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
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.caption2)
                            Text(template.name)
                                .font(.caption)
                        }
                        Text("Linked template runs; phase exercises are saved as fallback.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.orange)
                }

                if !phase.exerciseItems.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("PHASE EXERCISES")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(phase.exerciseItems) { item in
                            HStack {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .foregroundStyle(phase.phaseType.color)
                                Text(item.name)
                                    .font(.caption)
                                Spacer()
                                Text(itemTargetSummary(item, in: phase))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
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

                phaseItemsEditor(phase: phase)

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
                Text("None (Use Phase Exercises)").tag(UUID?.none)
                ForEach(store.templates) { template in
                    Text(template.name).tag(UUID?.some(template.id))
                }
            }

            Text(
                phase.wrappedValue.templateID == nil
                    ? "The phase exercises below run when no template is linked."
                    : "The linked template runs. Phase exercises remain saved as a fallback."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

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

    // MARK: - Phase Exercises

    private func phaseItemsEditor(
        phase: Binding<GymSessionRoutinePhase>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Phase Exercises")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(phase.wrappedValue.exerciseItems.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if phase.wrappedValue.exerciseItems.isEmpty {
                Text("No exercises. This phase will use its phase timer only unless a template is linked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(
                Array(phase.wrappedValue.exerciseItems.enumerated()),
                id: \.element.id
            ) { index, item in
                PhaseExerciseItemEditor(
                    item: phaseItemBinding(
                        id: item.id,
                        fallback: item,
                        in: phase
                    ),
                    phase: phase.wrappedValue,
                    library: store.allExercises,
                    canMoveUp: index > 0,
                    canMoveDown: index + 1 < phase.wrappedValue.exerciseItems.count,
                    onMoveUp: {
                        movePhaseItem(id: item.id, by: -1, in: phase)
                    },
                    onMoveDown: {
                        movePhaseItem(id: item.id, by: 1, in: phase)
                    },
                    onRemove: {
                        phase.wrappedValue.exerciseItems.removeAll { $0.id == item.id }
                    }
                )
            }

            Button {
                phase.wrappedValue.exerciseItems.append(
                    PhaseExerciseItem(name: "")
                )
            } label: {
                Label("Add Exercise", systemImage: "plus.circle.fill")
            }
            .font(.subheadline)
            .accessibilityHint("Adds a free-text exercise target to this phase")
        }
        .padding(.top, 4)
    }

    private func phaseItemBinding(
        id: UUID,
        fallback: PhaseExerciseItem,
        in phase: Binding<GymSessionRoutinePhase>
    ) -> Binding<PhaseExerciseItem> {
        Binding(
            get: {
                phase.wrappedValue.exerciseItems.first(where: { $0.id == id })
                    ?? fallback
            },
            set: { updated in
                guard let index = phase.wrappedValue.exerciseItems.firstIndex(
                    where: { $0.id == id }
                ) else { return }
                phase.wrappedValue.exerciseItems[index] = updated
            }
        )
    }

    private func movePhaseItem(
        id: UUID,
        by offset: Int,
        in phase: Binding<GymSessionRoutinePhase>
    ) {
        guard let index = phase.wrappedValue.exerciseItems.firstIndex(
            where: { $0.id == id }
        ) else { return }
        let destination = index + offset
        guard phase.wrappedValue.exerciseItems.indices.contains(index),
              phase.wrappedValue.exerciseItems.indices.contains(destination) else { return }
        phase.wrappedValue.exerciseItems.swapAt(index, destination)
    }

    private func itemTargetSummary(
        _ item: PhaseExerciseItem,
        in phase: GymSessionRoutinePhase
    ) -> String {
        let match = matchingExercise(named: item.name)
        if item.resolvesAsTimed(in: phase.phaseType, matchedExercise: match) {
            let seconds = item.durationSeconds > 0
                ? item.durationSeconds
                : phase.derivedExerciseDuration()
            return item.durationSeconds > 0 ? "\(seconds)s" : "Derived \(seconds)s"
        }
        let reps = item.reps > 0 ? item.reps : phase.defaultExerciseReps()
        return "\(item.sets) × \(reps) reps"
    }

    private func matchingExercise(named name: String) -> Exercise? {
        store.allExercises.first {
            $0.name.compare(
                name,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
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
        for phaseIndex in routine.phases.indices {
            routine.phases[phaseIndex].exerciseItems = routine.phases[phaseIndex]
                .exerciseItems
                .compactMap { item in
                    var cleaned = item
                    cleaned.name = cleaned.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return cleaned.name.isEmpty ? nil : cleaned
                }
        }
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

private struct PhaseExerciseItemEditor: View {
    @Binding var item: PhaseExerciseItem
    let phase: GymSessionRoutinePhase
    let library: [Exercise]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    private var matchingExercise: Exercise? {
        library.first {
            $0.name.compare(
                item.name,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }
    }

    private var isTimed: Bool {
        item.resolvesAsTimed(
            in: phase.phaseType,
            matchedExercise: matchingExercise
        )
    }

    private var derivedDuration: Int {
        phase.derivedExerciseDuration()
    }

    private var defaultReps: Int {
        phase.defaultExerciseReps()
    }

    private var suggestions: [Exercise] {
        let query = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates: [Exercise]
        if query.isEmpty {
            candidates = library.filter { candidate in
                switch phase.phaseType {
                case .preCardio:
                    return candidate.primaryMuscle == .cardio
                case .warmupStretches, .postStretching, .saunaRecovery, .steamRecovery:
                    return candidate.primaryMuscle == .mobility
                case .coreWork:
                    return candidate.primaryMuscle == .core
                case .mainStrength:
                    return !candidate.isTimed
                }
            }
        } else {
            candidates = library.filter {
                $0.name.localizedCaseInsensitiveContains(query)
            }
        }
        return Array(candidates.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Exercise name", text: $item.name)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Exercise name")
                    .accessibilityHint("Enter any name or choose a library suggestion")

                Menu {
                    if suggestions.isEmpty {
                        Text("No library matches")
                    } else {
                        ForEach(suggestions) { exercise in
                            Button(exercise.name) {
                                applySuggestion(exercise)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "text.magnifyingglass")
                }
                .accessibilityLabel("Exercise suggestions")
                .accessibilityHint("Shows matching exercises from the library; free text is also allowed")

                Button(action: onMoveUp) {
                    Image(systemName: "arrow.up")
                }
                .disabled(!canMoveUp)
                .accessibilityLabel("Move \(displayName) earlier")

                Button(action: onMoveDown) {
                    Image(systemName: "arrow.down")
                }
                .disabled(!canMoveDown)
                .accessibilityLabel("Move \(displayName) later")

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Remove \(displayName)")
            }

            Picker("Target Type", selection: targetTypeBinding) {
                Text("Time").tag(true)
                Text("Reps").tag(false)
            }
            .pickerStyle(.segmented)
            .accessibilityHint("Chooses a duration target or repetitions and sets")

            if isTimed {
                HStack {
                    Text("Duration")
                        .font(.caption)
                    TextField(
                        "Derived \(derivedDuration)s",
                        text: durationTextBinding
                    )
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Duration in seconds")
                    .accessibilityHint(
                        item.durationSeconds > 0
                            ? "Explicit duration"
                            : "Blank uses the derived default of \(derivedDuration) seconds"
                    )
                    Text("sec")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if item.durationSeconds == 0 {
                    Text("Derived from phase duration: \(derivedDuration) seconds")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Stepper(
                        "Reps: \(item.reps > 0 ? item.reps : defaultReps)",
                        value: repsBinding,
                        in: 1...100
                    )
                    Stepper(
                        "Sets: \(item.sets)",
                        value: $item.sets,
                        in: 1...20
                    )
                }
                .font(.caption)
            }

            if let matchingExercise {
                Label(
                    "Library match · \(matchingExercise.primaryMuscle.displayName)",
                    systemImage: "checkmark.circle"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else if !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Custom name — it will remain usable without a library match.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private var displayName: String {
        let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "exercise" : trimmed
    }

    private var targetTypeBinding: Binding<Bool> {
        Binding(
            get: { isTimed },
            set: { timed in
                if timed {
                    item.reps = 0
                    if item.durationSeconds == 0,
                       matchingExercise?.isTimed != true,
                       !phase.phaseType.isTimed {
                        item.durationSeconds = derivedDuration
                    }
                } else {
                    item.durationSeconds = 0
                    if item.reps == 0 {
                        item.reps = defaultReps
                    }
                }
            }
        )
    }

    private var durationTextBinding: Binding<String> {
        Binding(
            get: {
                item.durationSeconds > 0 ? String(item.durationSeconds) : ""
            },
            set: { text in
                let digits = text.filter(\.isNumber)
                item.durationSeconds = max(0, Int(digits) ?? 0)
                if item.durationSeconds > 0 {
                    item.reps = 0
                }
            }
        )
    }

    private var repsBinding: Binding<Int> {
        Binding(
            get: { item.reps > 0 ? item.reps : defaultReps },
            set: {
                item.reps = max(1, $0)
                item.durationSeconds = 0
            }
        )
    }

    private func applySuggestion(_ exercise: Exercise) {
        item.name = exercise.name
        if exercise.isTimed {
            item.durationSeconds = 0
            item.reps = 0
        } else {
            item.durationSeconds = 0
            item.reps = item.reps > 0 ? item.reps : defaultReps
        }
    }
}
