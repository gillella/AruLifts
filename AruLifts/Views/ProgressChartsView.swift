import SwiftUI
import Charts

/// Progress tab: per-exercise weight chart and total-volume chart with
/// timeframe filters. Body-weight chart arrives with issue #9.
struct ProgressChartsView: View {
    @EnvironmentObject private var store: WorkoutStore

    enum Timeframe: String, CaseIterable, Identifiable {
        case oneMonth = "1M", threeMonths = "3M", sixMonths = "6M", oneYear = "1Y", all = "All"
        var id: String { rawValue }

        var startDate: Date? {
            let cal = Calendar.current
            switch self {
            case .oneMonth: return cal.date(byAdding: .month, value: -1, to: Date())
            case .threeMonths: return cal.date(byAdding: .month, value: -3, to: Date())
            case .sixMonths: return cal.date(byAdding: .month, value: -6, to: Date())
            case .oneYear: return cal.date(byAdding: .year, value: -1, to: Date())
            case .all: return nil
            }
        }
    }

    @State private var timeframe: Timeframe = .threeMonths
    @State private var selectedExerciseID: UUID?

    private var exercises: [(id: UUID, name: String)] {
        ProgressSeries.trackedExercises(history: store.history)
    }

    private var currentExerciseID: UUID? { selectedExerciseID ?? exercises.first?.id }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Timeframe", selection: $timeframe) {
                        ForEach(Timeframe.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    exerciseSection
                    volumeSection
                    bodyWeightSection
                }
                .padding()
            }
            .navigationTitle("Progress")
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Exercise weight

    @ViewBuilder
    private var exerciseSection: some View {
        chartCard(title: "Working Weight") {
            if exercises.isEmpty {
                emptyState("Finish a few workouts to see your strength trend.")
            } else {
                Picker("Exercise", selection: Binding(
                    get: { currentExerciseID ?? UUID() },
                    set: { selectedExerciseID = $0 }
                )) {
                    ForEach(exercises, id: \.id) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.menu)

                let points = currentExerciseID.map {
                    ProgressSeries.exerciseMaxWeight(history: store.history, exerciseID: $0, since: timeframe.startDate)
                } ?? []

                if points.count < 2 {
                    emptyState("Not enough sessions in this timeframe.")
                } else {
                    Chart(points) {
                        LineMark(x: .value("Date", $0.date), y: .value("Weight", $0.value))
                            .foregroundStyle(.orange)
                        PointMark(x: .value("Date", $0.date), y: .value("Weight", $0.value))
                            .foregroundStyle(.orange)
                    }
                    .chartYAxisLabel(store.settings.units.label)
                    .frame(height: 180)
                }
            }
        }
    }

    // MARK: - Volume

    @ViewBuilder
    private var volumeSection: some View {
        chartCard(title: "Session Volume") {
            let points = ProgressSeries.totalVolume(history: store.history, since: timeframe.startDate)
            if points.count < 2 {
                emptyState("Not enough sessions in this timeframe.")
            } else {
                Chart(points) {
                    BarMark(x: .value("Date", $0.date), y: .value("Volume", $0.value))
                        .foregroundStyle(.orange.opacity(0.8))
                }
                .chartYAxisLabel(store.settings.units.label)
                .frame(height: 160)
            }
        }
    }

    // MARK: - Body weight (data arrives with issue #9)

    @ViewBuilder
    private var bodyWeightSection: some View {
        chartCard(title: "Body Weight") {
            emptyState("Body-weight tracking is coming soon.")
        }
    }

    // MARK: - Helpers

    private func chartCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private func emptyState(_ message: String) -> some View {
        HStack {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }
}

#Preview {
    ProgressChartsView().environmentObject(WorkoutStore())
}
