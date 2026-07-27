import SwiftUI

struct ActiveWorkoutView: View {
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var active: ActiveWorkoutManager
    @ObservedObject private var connectivity = ConnectivityManager.shared
    @State private var showingCancelConfirm = false
    @State private var showingMirrorDiscardConfirm = false
    @State private var showingExercisePicker = false
    @State private var showingNotes = false
    @State private var showingReorder = false

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

            if !session.exercises.isEmpty {
                ExercisePager(session: session)

                ScrollView {
                    if let idx = currentIndex(in: session) {
                        SetLogList(exerciseIndex: idx)
                            .padding()
                            .padding(.bottom, 16)
                            .disabled(!active.canEdit)
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
                    Text("Focus on timed recovery or exercises for this phase.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
            }
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
                        ForEach(Array(session.exercises.enumerated()), id: \.element.id) { idx, ex in
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
                        Text(formatTime(active.phaseTimer.secondsRemaining))
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                        Text(phase.phaseType.shortName)
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

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
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
