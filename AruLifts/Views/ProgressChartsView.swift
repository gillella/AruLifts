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
    @State private var showingWeightSheet = false

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

                    recordsLink
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

    private var recordsLink: some View {
        NavigationLink {
            RecordsView()
        } label: {
            HStack {
                Label("Personal Records", systemImage: "trophy.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
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

    // MARK: - Body weight

    @ViewBuilder
    private var bodyWeightSection: some View {
        chartCard(title: "Body Weight") {
            let points = ProgressSeries.bodyWeight(
                entries: store.bodyWeights,
                since: timeframe.startDate,
                units: store.settings.units
            )
            if let latest = store.bodyWeights.first {
                Text("Latest: \((latest.weightKg / store.settings.units.kgPerUnit).formatted(.number.precision(.fractionLength(0...1)))) \(store.settings.units.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if points.count < 2 {
                emptyState("Log your weight a few times to see the trend.")
            } else {
                Chart(points) {
                    LineMark(x: .value("Date", $0.date), y: .value("Weight", $0.value))
                        .foregroundStyle(.teal)
                    PointMark(x: .value("Date", $0.date), y: .value("Weight", $0.value))
                        .foregroundStyle(.teal)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel(store.settings.units.label)
                .frame(height: 160)
            }
            Button {
                showingWeightSheet = true
            } label: {
                Label("Log Weight", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .sheet(isPresented: $showingWeightSheet) {
            LogWeightSheet()
                .presentationDetents([.height(260)])
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

/// All-time bests per exercise: heaviest set, estimated 1RM, best session
/// volume. Warmups never count (enforced by Records).
struct RecordsView: View {
    @EnvironmentObject private var store: WorkoutStore

    var body: some View {
        List {
            let records = Records.all(history: store.history)
            if records.isEmpty {
                ContentUnavailableView(
                    "No Records Yet",
                    systemImage: "trophy",
                    description: Text("Finish workouts with weighted exercises to start setting records.")
                )
            } else {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.name).font(.headline)
                        HStack {
                            recordStat("Best set", "\(record.maxWeight.formatted()) \(store.settings.units.label) × \(record.repsAtMaxWeight)")
                            recordStat("Est. 1RM", "\(record.best1RM.formatted(.number.precision(.fractionLength(0...1)))) \(store.settings.units.label)")
                            recordStat("Volume", record.maxSessionVolume.formatted(.number.notation(.compactName)))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Records")
    }

    private func recordStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Bottom sheet to log a body-weight measurement in the user's units.
/// Prefills from the last app entry, else the latest Apple Health sample.
struct LogWeightSheet: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Log Body Weight").font(.headline)
            HStack {
                TextField("Weight", text: $weightText)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .font(.title2.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
                Text(store.settings.units.label).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            Button {
                if let value = Double(weightText.replacingOccurrences(of: ",", with: ".")), value > 0 {
                    store.logBodyWeight(kg: value * store.settings.units.kgPerUnit)
                    dismiss()
                }
            } label: {
                Text("Save").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(Double(weightText.replacingOccurrences(of: ",", with: ".")) == nil)
        }
        .padding()
        .task {
            if let last = store.bodyWeights.first {
                weightText = String(format: "%.1f", last.weightKg / store.settings.units.kgPerUnit)
            } else if let healthKg = await HealthKitManager.shared.latestBodyMassKg() {
                weightText = String(format: "%.1f", healthKg / store.settings.units.kgPerUnit)
            }
            focused = true
        }
    }
}

#Preview {
    ProgressChartsView().environmentObject(WorkoutStore())
}
