import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var active: ActiveWorkoutManager
    @ObservedObject private var connectivity = ConnectivityManager.shared
    @State private var openedRoutine: GymSessionRoutine?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statsHeader
                    prBanner
                    progressionBanner
                    watchStatus
                    quickStartSection
                }
                .padding()
            }
            .navigationTitle("AruLifts")
            .background(Color(.systemGroupedBackground))
            .sheet(item: $openedRoutine) { routine in
                RoutineComposerView(routine: routine)
            }
        }
    }

    private var thisWeekCount: Int {
        let cal = Calendar.current
        return store.history.filter {
            cal.isDate($0.startedAt, equalTo: Date(), toGranularity: .weekOfYear)
        }.count
    }

    private var statsHeader: some View {
        HStack(spacing: 12) {
            StatTile(value: "\(store.history.count)", label: "Workouts", systemImage: "checkmark.seal.fill")
            StatTile(value: "\(thisWeekCount)", label: "This Week", systemImage: "calendar")
            StatTile(value: "\(store.templates.count)", label: "Plans", systemImage: "square.grid.2x2.fill")
        }
    }

    /// Celebrates records broken by the last finished session.
    @ViewBuilder
    private var prBanner: some View {
        if !store.lastPRs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("New personal records!", systemImage: "trophy.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.yellow)
                ForEach(store.lastPRs) { pr in
                    Text("\(pr.name): \(pr.kinds.joined(separator: ", ")) PR")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.yellow.opacity(0.12)))
        }
    }

    /// "Next time: X" after a successful session bumps template weights.
    @ViewBuilder
    private var progressionBanner: some View {
        if !store.lastProgression.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Weights updated", systemImage: "arrow.up.arrow.down.circle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
                ForEach(store.lastProgression) { change in
                    Text(changeText(change))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.green.opacity(0.12)))
        }
    }

    private func changeText(_ change: ProgressionChange) -> String {
        let weight = "\(change.toWeight.formatted()) \(store.settings.units.label)"
        switch change.kind {
        case .increase: return "\(change.name): next time \(weight)"
        case .deload: return "\(change.name): deload to \(weight)"
        }
    }

    @ViewBuilder
    private var watchStatus: some View {
        if connectivity.isCounterpartAvailable {
            HStack(spacing: 10) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .foregroundStyle(connectivity.isReachable ? .green : .secondary)
                Text(connectivity.isReachable ? "Apple Watch connected" : "Apple Watch paired")
                    .font(.subheadline)
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
        }
    }

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start a Workout")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            if store.gymRoutines.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No gym routines yet")
                            .font(.headline)
                        Text("Create your first gym session routine in the Workouts tab.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(store.gymRoutines) { routine in
                    RoutineRowButton(
                        routine: routine,
                        onOpen: { openedRoutine = routine },
                        onStart: { start(routine) }
                    )
                    .contextMenu {
                        Button(role: .destructive) {
                            store.deleteGymRoutine(routine)
                        } label: {
                            Label("Delete Routine", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func start(_ routine: GymSessionRoutine) {
        let session = WorkoutSession.from(
            routine: routine,
            templates: store.templates,
            library: store.exerciseIndex,
            settings: store.settings
        )
        active.start(session)
    }
}

/// A gym session routine card with two independent tap targets: the card body
/// opens the routine in `RoutineComposerView` (read-only), while the play
/// button starts the multi-phase session immediately.
struct RoutineRowButton: View {
    let routine: GymSessionRoutine
    let onOpen: () -> Void
    let onStart: () -> Void

    private var subtitle: String {
        "~\(routine.estimatedTotalMinutes) min · \(routine.enabledPhases.count) phases"
    }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.18))
                            .frame(width: 46, height: 46)
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(routine.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens routine details")

            Button(action: onStart) {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start \(routine.name)")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}

#Preview {
    HomeView()
        .environmentObject(WorkoutStore())
        .environmentObject(ActiveWorkoutManager())
}
