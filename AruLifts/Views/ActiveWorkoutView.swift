import SwiftUI

struct ActiveWorkoutView: View {
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var active: ActiveWorkoutManager
    @ObservedObject private var connectivity = ConnectivityManager.shared
    @State private var showingCancelConfirm = false
    @State private var showingExercisePicker = false
    @State private var showingNotes = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if let session = active.session {
                    content(for: session)
                } else {
                    Color(.systemGroupedBackground).ignoresSafeArea()
                }

                if active.restTimer.isRunning {
                    RestTimerBar(timer: active.restTimer)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: active.restTimer.isRunning)
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
            .confirmationDialog("Discard this workout?", isPresented: $showingCancelConfirm, titleVisibility: .visible) {
                Button("Discard workout", role: .destructive) { active.cancel() }
                Button("Keep going", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func content(for session: WorkoutSession) -> some View {
        VStack(spacing: 0) {
            syncBanner

            ExercisePager(session: session)

            ScrollView {
                if let idx = currentIndex(in: session) {
                    SetLogList(exerciseIndex: idx)
                        .padding()
                        .padding(.bottom, active.restTimer.isRunning ? 90 : 16)
                        .disabled(!active.canEdit)
                        .opacity(active.canEdit ? 1 : 0.72)
                }
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
            return "Sending workout to Apple Watch…"
        case .savedOnWatch:
            return "Saved on Watch — waiting for iPhone"
        case .waitingForPhone:
            return "Watch handoff in progress…"
        case .synced where active.owner == .watch:
            return "Ready on Apple Watch — you can put your phone down"
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

#Preview {
    let store = WorkoutStore()
    let active = ActiveWorkoutManager()
    active.start(WorkoutSession.from(template: ExerciseLibrary.defaultTemplates()[0], library: ExerciseLibrary.byID), broadcast: false)
    return ActiveWorkoutView()
        .environmentObject(store)
        .environmentObject(active)
}
