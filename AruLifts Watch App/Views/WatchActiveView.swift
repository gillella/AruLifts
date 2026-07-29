import SwiftUI

/// Watch-first workout controller. The current target and its one primary
/// action dominate the screen; adjustment, overview, pause and finish remain
/// available without crowding the normal set-completion loop.
struct WatchActiveView: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    @ObservedObject private var liveSession = WatchWorkoutSession.shared

    @State private var showingAdjustment = false
    @State private var showingOverview = false
    @State private var showingFinishConfirmation = false
    @State private var showingSwapPicker = false
    @State private var showingRemoveConfirmation = false
    @State private var exerciseEditError: String?
    @State private var isReordering = false
    @State private var crownAdjustment: CrownAdjustment = .reps
    @State private var crownValue = 0.0
    @FocusState private var isCrownFocused: Bool

    private var exercise: SessionExercise? { active.currentExercise }

    private var workingSetIndex: Int? {
        exercise?.sets.firstIndex(where: { !$0.isCompleted })
    }

    var body: some View {
        Group {
            if exercise?.usesGuidedTimedStepper == true {
                ScrollView {
                    workoutContent
                }
                .scrollIndicators(.hidden)
            } else {
                workoutContent
            }
        }
        .padding(.horizontal, 4)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingOverview = true
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Workout options")
            }
        }
        .sheet(isPresented: $showingAdjustment) {
            if let setIndex = workingSetIndex {
                NavigationStack {
                    WatchSetLogView(
                        exerciseIndex: active.currentExerciseIndex,
                        setIndex: setIndex
                    )
                    .environmentObject(active)
                }
            }
        }
        .sheet(isPresented: $showingOverview) {
            workoutOverview
        }
        .sheet(isPresented: $active.showingPhaseTransitionModal) {
            WatchPhaseTransitionSheet()
                .environmentObject(active)
        }
        .confirmationDialog(
            incompleteSetCount == 0 ? "Finish this workout?" : "Finish with \(incompleteSetCount) sets incomplete?",
            isPresented: $showingFinishConfirmation,
            titleVisibility: .visible
        ) {
            Button("Finish Workout") { active.finish() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("The workout will be saved on your Watch and synchronized to your iPhone.")
        }
        .fullScreenCover(isPresented: Binding(
            get: { active.restTimer.isRunning || active.restTimer.isPaused },
            set: { if !$0 && active.restTimer.isRunning { active.restTimer.skip() } }
        )) {
            WatchRestView(timer: active.restTimer)
                .environmentObject(active)
        }
    }

    private var workoutContent: some View {
        VStack(spacing: 7) {
            if let session = active.session, session.isMultiPhase {
                HStack(spacing: 4) {
                    Image(systemName: session.currentPhase?.phaseType.iconSymbol ?? "flame.fill")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                    Text("P\(session.currentPhaseIndex + 1)/\(session.phases.count): \(session.currentPhase?.name ?? "")")
                        .font(.caption2.bold())
                        .lineLimit(1)
                    Spacer()
                    if session.currentPhase?.phaseType.isTimed == true {
                        Text(active.phaseTimer.formattedRemaining)
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundStyle(active.phaseTimer.isOvertime ? Color.green : Color.orange)
                            .accessibilityLabel(
                                active.phaseTimer.isOvertime
                                    ? "Phase overtime \(active.phaseTimer.formattedRemaining.dropFirst())"
                                    : "Phase time \(active.phaseTimer.formattedRemaining) remaining"
                            )
                    }
                    Button {
                        active.advancePhase()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            }

            if let exercise {
                header(exercise)

                if !active.canEdit {
                    // A stalled handshake looks identical to a brief one, so
                    // say which it is: the retry is still running underneath,
                    // but the user needs to know why the button is dead and
                    // that logging on iPhone still works.
                    if active.isHandshakeStalled {
                        VStack(spacing: 2) {
                            Label(
                                "Still syncing with iPhone",
                                systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
                            )
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            Text("Keep AruLifts open, or log this set on iPhone.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        Label("Waiting for iPhone handoff", systemImage: "iphone.slash")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if active.isWorkoutPaused {
                    pausedCard
                } else if let setIndex = workingSetIndex,
                          exercise.sets.indices.contains(setIndex) {
                    focusedSet(exercise.sets[setIndex], index: setIndex, in: exercise)
                } else {
                    allDoneCard
                }

                if exercise.usesGuidedTimedStepper {
                    guidedExerciseProgress
                } else {
                    progressDots(exercise)
                }
                exerciseNavigation
            } else if let session = active.session, session.isMultiPhase {
                multiPhaseCard(session)
            }
        }
    }

    private func header(_ exercise: SessionExercise) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: PhaseVisualHelper.iconSymbol(for: exercise.name))
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text(
                    exercise.usesGuidedTimedStepper
                        ? "\(phasePosition) of \(max(phaseScope.count, 1)) · \(exercise.name)"
                        : exercise.name
                )
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            HStack(spacing: 6) {
                Text("\(exercise.completedSets) of \(exercise.sets.count) sets")
                WatchHeartRateChip(bpm: liveSession.heartRateBPM)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func focusedSet(_ set: SetEntry, index: Int, in exercise: SessionExercise) -> some View {
        VStack(spacing: 7) {
            Text(setLabel(index, in: exercise))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(set.isWarmup ? .orange : .secondary)

            if set.durationSeconds > 0,
               active.exerciseTimerExerciseID == exercise.id,
               active.exerciseTimerSetID == set.id {
                VStack(spacing: 5) {
                    Text(active.exerciseTimer.formattedRemaining)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundStyle(active.exerciseTimer.isOvertime ? Color.green : Color.orange)
                        .accessibilityLabel(
                            active.exerciseTimer.isOvertime
                                ? "\(exercise.name) overtime \(active.exerciseTimer.formattedRemaining.dropFirst())"
                                : "\(exercise.name), \(active.exerciseTimer.formattedRemaining) remaining"
                        )
                    if active.exerciseTimer.isOvertime {
                        Text("OVER")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                    }
                    HStack(spacing: 5) {
                        Button("-15") { active.adjustExerciseTimer(by: -15) }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Subtract 15 seconds")
                            .accessibilityHint("Shortens this exercise timer")
                        Button {
                            active.toggleExerciseTimerPause()
                        } label: {
                            Image(systemName: active.exerciseTimer.isRunning ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .accessibilityLabel(active.exerciseTimer.isRunning ? "Pause exercise timer" : "Resume exercise timer")
                        .accessibilityHint("Changes only this exercise timer")
                        Button("+15") { active.adjustExerciseTimer(by: 15) }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Add 15 seconds")
                            .accessibilityHint("Extends this exercise timer")
                        Button {
                            active.resetExerciseTimer()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Reset exercise timer")
                        .accessibilityHint("Returns this exercise to its planned duration")
                    }
                    .font(.caption2)
                    .disabled(!active.canEdit)
                }
            } else if exercise.usesWeight {
                Text("\(WeightFormatter.string(set.weight, units: active.watchExecutionSettings.units)) × \(set.reps)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            } else {
                Text("\(set.reps) reps")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            if exercise.loadingMode == .barbell, exercise.usesWeight, set.weight > 0 {
                Text(plateString(for: set.weight))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel("Plates \(plateString(for: set.weight))")
            }

            if set.durationSeconds == 0 {
                Button {
                    crownAdjustment = crownAdjustment.next(usesWeight: exercise.usesWeight)
                    synchronizeCrownValue(with: set, exercise: exercise)
                    isCrownFocused = true
                } label: {
                    Label(
                        "Crown: \(crownAdjustment.label(usesWeight: exercise.usesWeight))",
                        systemImage: "crown"
                    )
                    .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(!active.canEdit)
                .accessibilityLabel("Digital Crown adjusts \(crownAdjustment.label(usesWeight: exercise.usesWeight))")
                .accessibilityHint(exercise.usesWeight ? "Double tap to switch between weight and reps" : "Rotate the Digital Crown to adjust reps")
            }

            Button {
                if exercise.usesGuidedTimedStepper {
                    active.completeGuidedTimedSetAndAdvance()
                } else {
                    active.completeSet(
                        exerciseIndex: active.currentExerciseIndex,
                        setIndex: index,
                        autoStartRest: active.watchExecutionSettings.autoStartRest,
                        restAlerts: active.watchExecutionSettings.restAlertsEnabled,
                        restAlertConfiguration: RestTimerAlertConfiguration(
                            alertsEnabled: active.watchExecutionSettings.restAlertsEnabled,
                            style: active.watchExecutionSettings.restAlertStyle,
                            earlyCueEnabled: active.watchExecutionSettings.earlyRestCueEnabled,
                            earlyCueLeadSeconds: active.watchExecutionSettings.earlyRestCueLeadSeconds
                        ),
                        adaptiveRest: active.watchExecutionSettings.adaptiveRestEnabled,
                        failedSetRestMultiplier: active.watchExecutionSettings.failedSetRestMultiplier
                    )
                }
            } label: {
                Label(
                    completionButtonTitle(for: exercise),
                    systemImage: "checkmark.circle.fill"
                )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.borderedProminent)
            .tint(set.isWarmup ? .orange : .green)
            .disabled(active.isFinalizing || !active.canEdit)
            .accessibilityHint(completionButtonHint(for: exercise))

            if set.durationSeconds == 0 {
                Button("Adjust weight or reps") {
                    showingAdjustment = true
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .disabled(!active.canEdit)
                .accessibilityHint("Opens Digital Crown adjustment controls")
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15))
        .focusable(true)
        .focused($isCrownFocused)
        .digitalCrownRotation(
            $crownValue,
            from: crownMinimum(for: exercise),
            through: crownMaximum(for: exercise),
            by: crownStep(for: exercise),
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            synchronizeCrownValue(with: set, exercise: exercise)
            isCrownFocused = true
        }
        .onChange(of: index) { _, _ in
            synchronizeCrownValue(with: set, exercise: exercise)
        }
        .onChange(of: crownAdjustment) { _, _ in
            synchronizeCrownValue(with: set, exercise: exercise)
        }
        .onChange(of: crownValue) { _, value in
            updateFocusedSet(fromCrown: value, index: index, exercise: exercise)
        }
    }

    private func synchronizeCrownValue(with set: SetEntry, exercise: SessionExercise) {
        crownValue = crownAdjustment == .weight && exercise.usesWeight
            ? set.weight
            : Double(set.reps)
    }

    private func updateFocusedSet(fromCrown value: Double, index: Int, exercise: SessionExercise) {
        guard active.canEdit,
              exercise.sets.indices.contains(index),
              exercise.sets[index].durationSeconds == 0 else { return }
        switch crownAdjustment {
        case .weight where exercise.usesWeight:
            active.updateSet(
                exerciseIndex: active.currentExerciseIndex,
                setIndex: index,
                weight: value
            )
        case .reps, .weight:
            active.updateSet(
                exerciseIndex: active.currentExerciseIndex,
                setIndex: index,
                reps: Int(value.rounded())
            )
        }
    }

    private func crownMinimum(for exercise: SessionExercise) -> Double {
        crownAdjustment == .weight && exercise.usesWeight && exercise.loadingMode == .barbell
            ? active.watchExecutionSettings.barWeight
            : 0
    }

    private func crownMaximum(for exercise: SessionExercise) -> Double {
        crownAdjustment == .weight && exercise.usesWeight ? 999 : 100
    }

    private func crownStep(for exercise: SessionExercise) -> Double {
        crownAdjustment == .weight && exercise.usesWeight
            ? max(active.watchExecutionSettings.weightIncrement, 0.5)
            : 1
    }

    private var pausedCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Workout paused")
                .font(.headline)
            Button("Resume") { active.toggleWorkoutPause() }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15))
    }

    private var allDoneCard: some View {
        VStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("Exercise complete")
                .font(.headline)
            // Three-way, because the last exercise of a phase is not the end of
            // the workout. Bounding on the flat `exercises` array offered
            // "Finish Workout" partway through a routine (#90).
            if active.hasNextExerciseInPhase {
                Button("Next Exercise") { active.goToNextExercise() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!active.canEdit)
            } else if active.hasNextPhase {
                Button("Next Phase") { active.advancePhase() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!active.canEdit)
            } else {
                Button("Finish Workout") { showingFinishConfirmation = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(!active.canEdit)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
    }

    private func progressDots(_ exercise: SessionExercise) -> some View {
        HStack(spacing: 5) {
            ForEach(exercise.sets) { set in
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        set.isCompleted ? .green : (set.isWarmup ? .orange : .secondary)
                    )
            }
        }
        .font(.caption)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercise.completedSets) of \(exercise.sets.count) sets complete")
    }

    /// Position and count are phase-relative — "2/4" means the second of four
    /// exercises in this phase, not across the whole gym session.
    private var phaseScope: [Int] {
        active.session?.currentPhaseExerciseIndices ?? []
    }

    private var phasePosition: Int {
        (phaseScope.firstIndex(of: active.currentExerciseIndex) ?? 0) + 1
    }

    private var guidedExerciseProgress: some View {
        HStack(spacing: 5) {
            ForEach(phaseScope, id: \.self) { index in
                if let session = active.session, session.exercises.indices.contains(index) {
                    let item = session.exercises[index]
                    Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(
                            item.isComplete ? Color.green :
                                (index == active.currentExerciseIndex ? Color.orange : Color.secondary)
                        )
                        .accessibilityLabel(
                            "\(item.name), \(item.isComplete ? "complete" : "not complete")"
                        )
                }
            }
        }
        .font(.caption)
        .accessibilityElement(children: .contain)
    }

    private func completionButtonTitle(for exercise: SessionExercise) -> String {
        guard exercise.usesGuidedTimedStepper else {
            return exercise.sets.contains(where: { $0.durationSeconds > 0 })
                ? "Done" : "Complete & Rest"
        }
        let remaining = exercise.sets.filter { !$0.isCompleted }.count
        return remaining == 1 && active.hasNextExerciseInPhase ? "Done & Next" : "Done"
    }

    private func completionButtonHint(for exercise: SessionExercise) -> String {
        guard exercise.usesGuidedTimedStepper else {
            return exercise.sets.contains(where: { $0.durationSeconds > 0 })
                ? "Marks this timed set complete without advancing automatically"
                : "Marks this set complete and starts the rest timer"
        }
        let remaining = exercise.sets.filter { !$0.isCompleted }.count
        if remaining > 1 {
            return "Marks this interval complete and starts the next interval"
        }
        return active.hasNextExerciseInPhase
            ? "Marks this exercise complete and opens the next exercise"
            : "Marks this exercise complete without advancing the phase"
    }

    private var exerciseNavigation: some View {
        let scope = phaseScope
        let position = scope.firstIndex(of: active.currentExerciseIndex)
        return HStack(spacing: 8) {
            Button {
                active.goToPreviousExercise()
            } label: {
                Label("Previous exercise", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity)
            }
            .disabled(!active.canEdit || !active.hasPreviousExerciseInPhase)

            Text("\((position ?? 0) + 1)/\(max(scope.count, 1))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                active.goToNextExercise()
            } label: {
                Label("Next exercise", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity)
            }
            .disabled(!active.canEdit || !active.hasNextExerciseInPhase)
        }
        .buttonStyle(.bordered)
    }

    private var workoutOverview: some View {
        NavigationStack {
            List {
                if let session = active.session {
                    ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, exercise in
                        if isReordering {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(exercise.name)
                                    Text("\(exercise.completedSets)/\(exercise.sets.count) sets")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if exercise.isComplete {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                                Button {
                                    active.moveExercises(from: IndexSet(integer: index), to: index - 1)
                                } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .disabled(index == 0)
                                .accessibilityLabel("Move \(exercise.name) earlier")
                                Button {
                                    active.moveExercises(from: IndexSet(integer: index), to: index + 2)
                                } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .disabled(index == session.exercises.count - 1)
                                .accessibilityLabel("Move \(exercise.name) later")
                            }
                        } else {
                            Button {
                                active.currentExerciseIndex = index
                                showingOverview = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(exercise.name)
                                        Text("\(exercise.completedSets)/\(exercise.sets.count) sets")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if exercise.isComplete {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .disabled(!active.canEdit)
                        }
                    }

                    if active.canEdit {
                        if let current = active.currentExercise {
                            Section("Current Exercise") {
                                Button {
                                    showingSwapPicker = true
                                } label: {
                                    Label(
                                        "Swap \(current.name)",
                                        systemImage: "arrow.triangle.2.circlepath"
                                    )
                                }
                                .disabled(current.completedSets > 0)

                                Button(role: .destructive) {
                                    showingRemoveConfirmation = true
                                } label: {
                                    Label(
                                        "Remove \(current.name)",
                                        systemImage: "trash"
                                    )
                                }
                                .disabled(current.completedSets > 0)

                                if current.completedSets > 0 {
                                    Text("Completed sets protect this exercise from being replaced or removed.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("This workout only — the saved plan stays unchanged.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Section {
                            Button(active.isWorkoutPaused ? "Resume Workout" : "Pause Workout") {
                                active.toggleWorkoutPause()
                                showingOverview = false
                            }
                            Button("Finish Workout") {
                                showingOverview = false
                                showingFinishConfirmation = true
                            }
                            .foregroundStyle(.green)
                            Button("Cancel Workout", role: .destructive) {
                                active.cancel()
                                showingOverview = false
                            }
                        }
                    } else {
                        Section {
                            Text("This workout is controlled on the other device.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(active.session?.name ?? "Workout")
            .toolbar {
                if active.canEdit, (active.session?.exercises.count ?? 0) > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isReordering ? "Done" : "Reorder") {
                            isReordering.toggle()
                        }
                        .accessibilityLabel(isReordering ? "Finish reordering exercises" : "Reorder today's exercises")
                    }
                }
            }
            .sheet(isPresented: $showingSwapPicker) {
                WatchExerciseSwapView()
                    .environmentObject(active)
            }
            .confirmationDialog(
                "Remove this exercise?",
                isPresented: $showingRemoveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove from This Workout", role: .destructive) {
                    guard active.removeExercise(
                        at: active.currentExerciseIndex
                    ) else {
                        exerciseEditError =
                            "Completed sets protect this exercise from removal."
                        return
                    }
                    showingOverview = false
                }
                Button("Keep Exercise", role: .cancel) {}
            } message: {
                Text("Your saved workout plan will not change.")
            }
            .alert(
                "Exercise Not Changed",
                isPresented: Binding(
                    get: { exerciseEditError != nil },
                    set: { if !$0 { exerciseEditError = nil } }
                )
            ) {
                Button("OK") { exerciseEditError = nil }
            } message: {
                Text(exerciseEditError ?? "")
            }
        }
    }

    private var incompleteSetCount: Int {
        active.session?.exercises.reduce(0) {
            $0 + $1.sets.filter { !$0.isCompleted }.count
        } ?? 0
    }

    private func setLabel(_ index: Int, in exercise: SessionExercise) -> String {
        let set = exercise.sets[index]
        let earlierSameKind = exercise.sets.prefix(index)
            .filter { $0.isWarmup == set.isWarmup }.count
        return set.isWarmup
            ? "Warmup \(earlierSameKind + 1)"
            : "Set \(earlierSameKind + 1) of \(exercise.sets.filter { !$0.isWarmup }.count)"
    }

    private func plateString(for weight: Double) -> String {
        let result = PlateCalculator.plates(
            target: weight,
            bar: active.watchExecutionSettings.barWeight,
            available: active.watchExecutionSettings.availablePlates
        )
        guard !result.platesPerSide.isEmpty else { return "empty bar" }
        return result.platesPerSide
            .map { $0 == $0.rounded() ? String(Int($0)) : String(format: "%.2g", $0) }
            .joined(separator: " + ") + " per side"
    }

    private func multiPhaseCard(_ session: WorkoutSession) -> some View {
        VStack(spacing: 8) {
            if let phase = session.currentPhase {
                VStack(spacing: 4) {
                    Image(systemName: PhaseVisualHelper.iconSymbol(for: phase.name, phaseType: phase.phaseType))
                        .font(.title2)
                        .foregroundStyle(phase.phaseType.color)
                    Text(phase.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    if phase.phaseType.isTimed {
                        Text(active.phaseTimer.formattedRemaining)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            // Green marks overtime, distinct from the orange countdown.
                            .foregroundStyle(
                                active.phaseTimer.isOvertime
                                    ? Color.green
                                    : (active.phaseTimer.isPaused ? Color.secondary : Color.orange)
                            )

                        HStack(spacing: 6) {
                            Button {
                                active.adjustPhaseTimer(by: -60)
                            } label: {
                                Text("-1m").font(.caption2)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                active.togglePhaseTimerPause()
                            } label: {
                                Image(systemName: active.phaseTimer.isRunning ? "pause.fill" : "play.fill")
                                    .font(.caption2.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)

                            Button {
                                active.adjustPhaseTimer(by: 60)
                            } label: {
                                Text("+1m").font(.caption2)
                            }
                            .buttonStyle(.bordered)
                        }
                    } else if phase.durationSeconds > 0 {
                        Text("\(phase.durationSeconds / 60) min target")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    if phase.phaseType == .saunaRecovery || phase.phaseType == .steamRecovery {
                        Label("Hydrate: Drink 500ml", systemImage: "drop.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                    }

                    if !phase.notes.isEmpty {
                        Text(phase.notes)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
            }

            HStack(spacing: 8) {
                Button {
                    active.previousPhase()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(session.currentPhaseIndex == 0)

                Button {
                    active.advancePhase()
                } label: {
                    HStack(spacing: 4) {
                        Text(session.currentPhaseIndex == session.phases.count - 1 ? "Finish Phase" : "Next Phase")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption2.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(8)
    }

    /// Live heart rate from the Watch workout session; hidden until HealthKit
    /// supplies a reading.
    struct WatchHeartRateChip: View {
        let bpm: Double?

        var body: some View {
            if let bpm {
                HStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                    Text("\(Int(bpm))")
                        .monospacedDigit()
                }
                .font(.caption2)
                .accessibilityLabel("Heart rate \(Int(bpm)) beats per minute")
            }
        }
    }
}

private struct WatchExerciseSwapView: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    private var alternatives: [Exercise] {
        active.contextualExerciseAlternatives()
    }

    var body: some View {
        NavigationStack {
            List {
                if alternatives.isEmpty {
                    Text("No contextual alternatives are available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(alternatives) { exercise in
                        Button {
                            if active.replaceExercise(
                                at: active.currentExerciseIndex,
                                with: exercise
                            ) {
                                dismiss()
                            } else {
                                error =
                                    "Completed sets protect this exercise from being swapped."
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                Text(exercise.primaryMuscle.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Swap Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(
                "Exercise Not Changed",
                isPresented: Binding(
                    get: { error != nil },
                    set: { if !$0 { error = nil } }
                )
            ) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }
}

private enum CrownAdjustment: String {
    case weight
    case reps

    func next(usesWeight: Bool) -> CrownAdjustment {
        guard usesWeight else { return .reps }
        return self == .weight ? .reps : .weight
    }

    func label(usesWeight: Bool) -> String {
        self == .weight && usesWeight ? "weight" : "reps"
    }
}
