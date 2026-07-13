import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var active: ActiveWorkoutManager
    @ObservedObject private var connectivity = ConnectivityManager.shared

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

            if store.templates.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No workouts yet")
                            .font(.headline)
                        Text("Create your first workout in the Workouts tab.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(store.templates) { template in
                    TemplateRowButton(template: template) {
                        startWorkout(template)
                    }
                }
            }
        }
    }

    private func startWorkout(_ template: WorkoutTemplate) {
        let session = WorkoutSession.from(template: template, library: store.exerciseIndex, settings: store.settings)
        active.start(session)
    }
}

/// A tappable card that starts a workout from a template.
struct TemplateRowButton: View {
    let template: WorkoutTemplate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(template.category.color.opacity(0.18))
                        .frame(width: 46, height: 46)
                    Image(systemName: template.category.symbol)
                        .foregroundStyle(template.category.color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(template.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(template.exerciseCount) exercises · \(template.totalSets) sets · ~\(template.estimatedMinutes) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HomeView()
        .environmentObject(WorkoutStore())
        .environmentObject(ActiveWorkoutManager())
}
