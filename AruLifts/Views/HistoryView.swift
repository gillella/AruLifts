import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: WorkoutStore

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.history) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        HistoryRow(session: session, units: store.settings.units)
                    }
                }
                .onDelete(perform: store.deleteHistory)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("History")
            .overlay {
                if store.history.isEmpty {
                    ContentUnavailableView(
                        "No History Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Completed workouts will appear here.")
                    )
                }
            }
        }
    }
}

struct HistoryRow: View {
    let session: WorkoutSession
    let units: AppSettings.Units

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(session.category.color.opacity(0.18)).frame(width: 40, height: 40)
                Image(systemName: session.category.symbol).foregroundStyle(session.category.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name).font(.headline)
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(session.completedSets) sets").font(.subheadline.weight(.medium))
                Text(formatWeight(session.totalVolume, units: units))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SessionDetailView: View {
    @EnvironmentObject private var store: WorkoutStore
    let session: WorkoutSession

    private var durationText: String {
        let mins = Int(session.durationSeconds) / 60
        return "\(mins) min"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Date", value: session.startedAt.formatted(date: .complete, time: .shortened))
                LabeledContent("Duration", value: durationText)
                LabeledContent("Sets completed", value: "\(session.completedSets)/\(session.totalSets)")
                LabeledContent("Total volume", value: formatWeight(session.totalVolume, units: store.settings.units))
            }
            ForEach(session.exercises) { ex in
                Section(ex.name) {
                    ForEach(Array(ex.sets.enumerated()), id: \.element.id) { idx, set in
                        HStack {
                            Text("Set \(idx + 1)").foregroundStyle(.secondary)
                            Spacer()
                            if ex.usesWeight {
                                Text("\(formatWeight(set.weight, units: store.settings.units)) × \(set.reps)")
                            } else {
                                Text("\(set.reps) reps")
                            }
                            Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(set.isCompleted ? .green : .secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    HistoryView().environmentObject(WorkoutStore())
}
