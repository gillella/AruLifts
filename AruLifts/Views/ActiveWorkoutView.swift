import SwiftUI

struct ActiveWorkoutView: View {
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var active: ActiveWorkoutManager
    @ObservedObject private var connectivity = ConnectivityManager.shared
    @State private var showingCancelConfirm = false
    @State private var showingMirrorDiscardConfirm = false
    @State private var showingNotes = false
    @State private var showingReorder = false
    @State private var exercisePickerMode: LiveExercisePickerMode?
    @State private var showingExerciseRemovalConfirm = false
    @State private var exerciseEditError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                if let session = active.session {
                    content(for: session)
                } else {
                    Color(.systemGroupedBackground).ignoresSafeArea()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isRestPresented {
                    RestTimerBar(timer: active.restTimer)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: isRestPresented)
            .navigationTitle(active.session?.name ?? "Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showingCancelConfirm = true }
                        .tint(.red)
                        .disabled(!active.canEdit)
                }
                ToolbarItem(placement: .principal) {
                    ElapsedLabel(start: active.session?.startedAt ?? Date())
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNotes = true
                    } label: {
                        Image(systemName: "note.text")
                    }
                    .disabled(!active.canEdit)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingReorder = true
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .disabled(!active.canEdit || (active.session?.exercises.count ?? 0) < 2)
                    .accessibilityLabel("Reorder today's exercises")
                    .accessibilityHint("Changes this workout only, not the saved template")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Finish") { active.finish() }
                        .fontWeight(.semibold)
                        .disabled(!active.canEdit || active.isFinalizing)
                }
            }
            .sheet(isPresented: $showingNotes) {
                SessionNotesSheet(
                    notes: active.session?.notes ?? "",
                    onSave: { active.updateNotes($0) }
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingReorder) {
                ActiveSessionReorderSheet()
                    .environmentObject(active)
            }
            .sheet(item: $exercisePickerMode) { mode in
                ExercisePickerView(
                    category: active.session?.category ?? .custom,
                    title: mode.title,
                    actionTitle: mode.actionTitle
                ) { exercise in
                    applyExerciseSelection(exercise, mode: mode)
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $active.showingPhaseTransitionModal) {
                PhaseTransitionSheet()
                    .environmentObject(active)
            }
            .confirmationDialog("Discard this workout?", isPresented: $showingCancelConfirm, titleVisibility: .visible) {
                Button("Discard workout", role: .destructive) { active.cancel() }
                Button("Keep going", role: .cancel) {}
            }
            .confirmationDialog(
                "Discard this workout on iPhone?",
                isPresented: $showingMirrorDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard on iPhone", role: .destructive) {
                    active.discardMirroredWorkout()
                }
                Button("Keep waiting", role: .cancel) {}
            } message: {
                Text("This removes the workout from iPhone only. If Apple Watch is still running it, finish or discard it there too.")
            }
            .confirmationDialog(
                "Remove this exercise?",
                isPresented: $showingExerciseRemovalConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove from This Workout", role: .destructive) {
                    guard active.removeExercise(
                        at: active.currentExerciseIndex
                    ) else {
                        exerciseEditError =
                            "This exercise has completed sets and cannot be removed."
                        return
                    }
                }
                Button("Keep Exercise", role: .cancel) {}
            } message: {
                Text("Your saved template or routine will not change.")
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

    @ViewBuilder
    private func content(for session: WorkoutSession) -> some View {
        VStack(spacing: 0) {
            syncBanner

            if session.isMultiPhase {
                PhaseProgressionBannerView(session: session)
                if let phase = session.currentPhase, phase.phaseType.isTimed {
                    PhaseTimerView(phase: phase)
                        .padding(.vertical, 8)
                }
            }

            // Scoped to the phase in progress: a cardio or sauna phase with no
            // exercises of its own shows its timer and guidance, never the next
            // phase's lifts.
            if !session.currentPhaseExerciseIndices.isEmpty {
                ExercisePager(session: session)
                liveExerciseControls(for: session)

                if let idx = currentIndex(in: session) {
                    if session.exercises[idx].usesGuidedTimedStepper {
                        GuidedTimedExerciseView(exerciseIndex: idx)
                            .opacity(active.canEdit ? 1 : 0.72)
                    } else {
                        ScrollView {
                            SetLogList(exerciseIndex: idx)
                        }
                        .padding(.bottom, 16)
                        .opacity(active.canEdit ? 1 : 0.72)
                    }
                }
            } else if session.isMultiPhase {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: session.currentPhase?.phaseType.iconSymbol ?? "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text(session.currentPhase?.name ?? "Phase Active")
                        .font(.title2.bold())
                    if let names = session.currentPhase?.exerciseNames, !names.isEmpty {
                        Text(names.joined(separator: " • "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Text(emptyPhaseGuidance(for: session))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        exercisePickerMode = .add(
                            phaseIndex: session.currentPhaseIndex
                        )
                    } label: {
                        Label("Add Exercise to This Phase", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!active.canEdit)
                    Spacer()
                }
                .padding()
            } else {
                ContentUnavailableView {
                    Label("No Exercises", systemImage: "figure.strengthtraining.traditional")
                } description: {
                    Text("Add an exercise for this workout without changing the saved template.")
                } actions: {
                    Button {
                        exercisePickerMode = .add(phaseIndex: 0)
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!active.canEdit)
                }
            }
        }
    }

    private func liveExerciseControls(
        for session: WorkoutSession
    ) -> some View {
        HStack {
            Text("Changes apply to this workout only")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button {
                    exercisePickerMode = .add(
                        phaseIndex: session.currentPhaseIndex
                    )
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                }

                Button {
                    exercisePickerMode = .replace(
                        index: active.currentExerciseIndex
                    )
                } label: {
                    Label("Swap Current Exercise", systemImage: "arrow.triangle.2.circlepath")
                }

                Button(role: .destructive) {
                    if active.canRemoveExercise(
                        at: active.currentExerciseIndex
                    ) {
                        showingExerciseRemovalConfirm = true
                    } else {
                        exerciseEditError =
                            "This exercise has completed sets and cannot be removed or swapped."
                    }
                } label: {
                    Label("Remove Current Exercise", systemImage: "trash")
                }
            } label: {
                Label("Exercise Options", systemImage: "ellipsis.circle")
            }
            .disabled(!active.canEdit)
            .accessibilityHint(
                "Add, swap, or remove exercises for this workout without changing the saved plan"
            )
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    private func applyExerciseSelection(
        _ exercise: Exercise,
        mode: LiveExercisePickerMode
    ) {
        let preferredWeight = store.lastWeight(for: exercise.id)
        let changed: Bool
        switch mode {
        case .add(let phaseIndex):
            changed = active.addExercise(
                exercise,
                toPhase: phaseIndex,
                settings: store.settings,
                preferredWeight: preferredWeight
            )
        case .replace(let index):
            changed = active.replaceExercise(
                at: index,
                with: exercise,
                settings: store.settings,
                preferredWeight: preferredWeight
            )
        }
        if !changed {
            exerciseEditError =
                "This exercise has completed sets or the current phase is no longer editable."
        }
    }

    private var syncBanner: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: syncSymbol)
                Text(syncMessage).font(.caption.weight(.medium))
            }
            .foregroundStyle(syncColor)

            if active.owner == .watch {
                if active.canEdit {
                    Text("This iPhone controls the workout.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Take Over on iPhone") {
                        active.requestPhoneTakeover()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .disabled(active.syncStatus == .waitingForWatch)

                    if let error = active.takeoverError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)

                        // Without this the message above promises something the
                        // user cannot do: Cancel/Finish both require ownership,
                        // so a mirror whose takeover failed has no way out.
                        Button("Discard on iPhone", role: .destructive) {
                            showingMirrorDiscardConfirm = true
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
            }

            if active.watchLaunchState == .failed {
                Button("Retry Apple Watch") {
                    active.retryWatchLaunch()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(.orange)

                if let error = active.watchLaunchError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }

    private func emptyPhaseGuidance(for session: WorkoutSession) -> String {
        switch session.currentPhase?.phaseType {
        case .saunaRecovery, .steamRecovery:
            return "Recovery phase — use the phase timer above, then tap Next Phase when you're ready."
        default:
            return "No exercises are configured for this phase. Use the phase timer above, then tap Next Phase when you're ready."
        }
    }

    private var syncMessage: String {
        switch active.syncStatus {
        case .waitingForWatch:
            switch active.watchLaunchState {
            case .waking:
                return "Waking Apple Watch…"
            case .failed:
                return "Couldn’t wake Apple Watch"
            default:
                return "Waiting for Apple Watch…"
            }
        case .savedOnWatch:
            return "Saved on Watch — waiting for iPhone"
        case .waitingForPhone:
            return "Watch handoff in progress…"
        case .synced where active.owner == .watch:
            return "Ready on Apple Watch — open AruLifts on your wrist"
        case .synced:
            return "Workout synchronized"
        case .needsResync:
            return "Syncing latest workout state…"
        case .localOnly:
            return connectivity.isCounterpartAvailable
                ? "Preparing Apple Watch connection…"
                : "Saved on this iPhone"
        }
    }

    private var syncSymbol: String {
        active.owner == .watch
            ? "applewatch.radiowaves.left.and.right"
            : "iphone.radiowaves.left.and.right"
    }

    private var syncColor: Color {
        switch active.syncStatus {
        case .synced: return .green
        case .needsResync: return .orange
        default: return .secondary
        }
    }

    private func currentIndex(in session: WorkoutSession) -> Int? {
        guard session.exercises.indices.contains(active.currentExerciseIndex) else { return nil }
        return active.currentExerciseIndex
    }

    private var isRestPresented: Bool {
        active.restTimer.isRunning || active.restTimer.isPaused
    }
}

private enum LiveExercisePickerMode: Identifiable {
    case add(phaseIndex: Int)
    case replace(index: Int)

    var id: String {
        switch self {
        case .add(let phaseIndex): return "add-\(phaseIndex)"
        case .replace(let index): return "replace-\(index)"
        }
    }

    var title: String {
        switch self {
        case .add: return "Add Exercise"
        case .replace: return "Swap Exercise"
        }
    }

    var actionTitle: String {
        switch self {
        case .add: return "Add"
        case .replace: return "Swap"
        }
    }
}

/// Session-only ordering controls. The active manager owns the mutation so it
/// remains synchronized to the Watch and does not alter a workout template.
struct ActiveSessionReorderSheet: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let session = active.session {
                    ForEach(session.exercises) { exercise in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                Text("\(exercise.completedSets) of \(exercise.sets.count) sets complete")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if exercise.isComplete {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .accessibilityLabel("\(exercise.name), \(exercise.completedSets) of \(exercise.sets.count) sets complete")
                        .accessibilityHint("Drag to change the order for today's workout")
                    }
                    .onMove(perform: active.moveExercises)
                } else {
                    ContentUnavailableView("No active workout", systemImage: "figure.strengthtraining.traditional")
                }
            }
            .navigationTitle("Today's Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Free-text note editor for the running session.
struct SessionNotesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var notes: String
    let onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            TextEditor(text: $notes)
                .padding(8)
                .navigationTitle("Session Notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onSave(notes)
                            dismiss()
                        }
                    }
                }
        }
    }
}

/// Live-updating elapsed time in the nav bar.
struct ElapsedLabel: View {
    let start: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(start))
            Text(String(format: "%d:%02d", elapsed / 60, elapsed % 60))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// Horizontal selector + prev/next for exercises in the session.
struct ExercisePager: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    let session: WorkoutSession

    var body: some View {
        VStack(spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Scoped to the phase in progress: a gym session shows
                        // only the work belonging to the phase you are in.
                        ForEach(session.currentPhaseExerciseIndices, id: \.self) { idx in
                            let ex = session.exercises[idx]
                            Button {
                                active.currentExerciseIndex = idx
                            } label: {
                                VStack(spacing: 4) {
                                    Text(ex.name)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Text("\(ex.completedSets)/\(ex.sets.count)")
                                        .font(.caption2)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    idx == active.currentExerciseIndex ? Color.orange : Color(.secondarySystemBackground),
                                    in: Capsule()
                                )
                                .foregroundStyle(idx == active.currentExerciseIndex ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                            .disabled(!active.canEdit)
                            .id(idx)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: active.currentExerciseIndex) { _, new in
                    withAnimation { proxy.scrollTo(new, anchor: .center) }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

private struct GuidedTimedExerciseView: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    let exerciseIndex: Int

    private var session: WorkoutSession? { active.session }
    private var exercise: SessionExercise? {
        guard let session, session.exercises.indices.contains(exerciseIndex) else { return nil }
        return session.exercises[exerciseIndex]
    }
    private var scope: [Int] { session?.currentPhaseExerciseIndices ?? [] }
    private var position: Int { (scope.firstIndex(of: exerciseIndex) ?? 0) + 1 }
    private var remainingIntervalCount: Int {
        exercise?.sets.filter { !$0.isCompleted }.count ?? 0
    }

    var body: some View {
        if let session, let exercise {
            VStack(spacing: 0) {
                guidedSummary(for: exercise)
                    .padding(.horizontal)
                    .padding(.top, 6)

                exerciseTimerCard(for: exercise)
                    .padding(.horizontal)
                    .padding(.top, 6)

                doneButton(for: exercise)
                    .padding(.horizontal)
                    .padding(.top, 6)

                ScrollView {
                    VStack(spacing: 18) {
                        phaseProgress(in: session)

                        HStack(spacing: 12) {
                            Button {
                                active.goToPreviousExercise()
                            } label: {
                                Label("Previous", systemImage: "chevron.left")
                                    .frame(maxWidth: .infinity)
                            }
                            .disabled(!active.hasPreviousExerciseInPhase)

                            Button {
                                active.goToNextExercise()
                            } label: {
                                Label("Next", systemImage: "chevron.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .disabled(!active.hasNextExerciseInPhase)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
            }
        }
    }

    private func guidedSummary(for exercise: SessionExercise) -> some View {
        HStack(spacing: 8) {
            Text("\(position) of \(max(scope.count, 1)) · \(exercise.name)")
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(exercise.completedSets)/\(exercise.sets.count) intervals")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(exercise.name), exercise \(position) of \(max(scope.count, 1)), "
            + "\(exercise.completedSets) of \(exercise.sets.count) intervals complete"
        )
    }

    private func exerciseTimerCard(for exercise: SessionExercise) -> some View {
        HStack(spacing: 10) {
            VStack(spacing: 1) {
                Text(active.exerciseTimer.formattedRemaining)
                    .font(.system(size: 42, weight: .bold, design: .monospaced))
                    .foregroundStyle(active.exerciseTimer.isOvertime ? Color.green : Color.orange)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityLabel(timerAccessibilityLabel(for: exercise))

                if active.exerciseTimer.isOvertime {
                    Text("OVERTIME")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                }
            }

            Spacer(minLength: 0)
            timerAdjustmentControls
        }
        .padding(10)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
    }

    private var timerAdjustmentControls: some View {
        HStack(spacing: 6) {
            Button {
                active.adjustExerciseTimer(by: -15)
            } label: {
                Text("−15")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
                .accessibilityLabel("Subtract 15 seconds")
                .accessibilityHint("Subtracts 15 seconds from this exercise timer")
            Button {
                active.toggleExerciseTimerPause()
            } label: {
                Image(
                    systemName: active.exerciseTimer.isRunning
                        ? "pause.fill"
                        : "play.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .accessibilityLabel(
                active.exerciseTimer.isRunning ? "Pause" : "Resume"
            )
            .accessibilityHint("Pauses or resumes only this exercise timer")
            Button {
                active.adjustExerciseTimer(by: 15)
            } label: {
                Text("+15")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
                .accessibilityLabel("Add 15 seconds")
                .accessibilityHint("Adds 15 seconds to this exercise timer")
            Button {
                active.resetExerciseTimer()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .accessibilityLabel("Reset exercise timer")
            .accessibilityHint("Returns this exercise to its planned duration")
        }
        .font(.subheadline)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!active.canEdit)
    }

    private func doneButton(for exercise: SessionExercise) -> some View {
        Button {
            active.completeGuidedTimedSetAndAdvance()
        } label: {
            Label(doneButtonTitle, systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(!active.canEdit || active.isFinalizing || exercise.isComplete)
        .accessibilityLabel("\(doneButtonTitle), \(exercise.name)")
        .accessibilityHint(doneButtonHint)
    }

    private var doneButtonTitle: String {
        if remainingIntervalCount > 1 { return "Done" }
        return active.hasNextExerciseInPhase ? "Done & Next" : "Done"
    }

    private var doneButtonHint: String {
        if remainingIntervalCount > 1 {
            return "Marks this interval complete and starts the next interval"
        }
        if active.hasNextExerciseInPhase {
            return "Marks this exercise complete and opens the next exercise"
        }
        return "Marks this exercise complete without advancing the phase"
    }

    private func timerAccessibilityLabel(for exercise: SessionExercise) -> String {
        active.exerciseTimer.isOvertime
            ? "\(exercise.name) overtime \(active.exerciseTimer.formattedRemaining.dropFirst())"
            : "\(exercise.name), \(active.exerciseTimer.formattedRemaining) remaining"
    }

    private func phaseProgress(in session: WorkoutSession) -> some View {
        HStack(spacing: 7) {
            ForEach(scope, id: \.self) { index in
                let item = session.exercises[index]
                Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        item.isComplete ? Color.green :
                            (index == exerciseIndex ? Color.orange : Color.secondary)
                    )
                    .accessibilityLabel(
                        "\(item.name), \(item.isComplete ? "complete" : "not complete")"
                    )
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct PhaseProgressionBannerView: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    let session: WorkoutSession

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                if let phase = session.currentPhase {
                    Image(systemName: PhaseVisualHelper.iconSymbol(for: phase.name, phaseType: phase.phaseType))
                        .font(.title3)
                        .foregroundStyle(phase.phaseType.color)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Phase \(session.currentPhaseIndex + 1) of \(session.phases.count): \(phase.name)")
                            .font(.headline)
                        if !phase.notes.isEmpty {
                            Text(phase.notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()

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
                            Text("Next Phase")
                            Image(systemName: "chevron.right")
                        }
                        .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(session.currentPhaseIndex >= session.phases.count - 1)
                }
            }

            ProgressView(value: Double(session.currentPhaseIndex + 1), total: Double(max(1, session.phases.count)))
                .tint(session.currentPhase?.phaseType.color ?? .orange)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
    }
}

struct PhaseTimerView: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    let phase: GymSessionLogPhase

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.orange.opacity(0.2), lineWidth: 6)
                        .frame(width: 80, height: 80)

                    VStack(spacing: 2) {
                        Text(active.phaseTimer.formattedRemaining)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            // Overtime reads green so a leading "+" can't be
                            // mistaken for time still remaining.
                            .foregroundStyle(active.phaseTimer.isOvertime ? Color.green : Color.primary)
                        Text(active.phaseTimer.isOvertime ? "over" : phase.phaseType.shortName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: PhaseVisualHelper.iconSymbol(for: phase.name, phaseType: phase.phaseType))
                            .foregroundStyle(phase.phaseType.color)
                        Text(phase.name)
                            .font(.headline)
                    }
                    if !phase.exerciseNames.isEmpty {
                        Text(phase.exerciseNames.joined(separator: " • "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Button {
                            active.adjustPhaseTimer(by: -60)
                        } label: {
                            Text("-1m").font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!active.canEdit)

                        Button {
                            active.togglePhaseTimerPause()
                        } label: {
                            Image(systemName: active.phaseTimer.isRunning ? "pause.fill" : "play.fill")
                                .font(.caption.bold())
                                .padding(8)
                                .background(Color.orange, in: Circle())
                                .foregroundStyle(.white)
                        }
                        .disabled(!active.canEdit)

                        Button {
                            active.adjustPhaseTimer(by: 60)
                        } label: {
                            Text("+1m").font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!active.canEdit)
                    }
                }
                Spacer()
            }

            if phase.phaseType == .saunaRecovery || phase.phaseType == .steamRecovery {
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .foregroundStyle(.blue)
                    Text("Hydration Reminder: Drink 500ml water during heat recovery")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

#Preview {
    let store = WorkoutStore()
    let active = ActiveWorkoutManager()
    active.start(WorkoutSession.from(template: ExerciseLibrary.defaultTemplates()[0], library: ExerciseLibrary.byID), broadcast: false)
    return ActiveWorkoutView()
        .environmentObject(store)
        .environmentObject(active)
}
