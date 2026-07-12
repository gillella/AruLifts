import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: WorkoutStore
    @ObservedObject private var connectivity = ConnectivityManager.shared

    private let restOptions = [60, 90, 120, 150, 180, 240, 300]

    /// Non-standard bar choices for the current unit system.
    private var barOptions: [Double] {
        store.settings.units == .kg ? [10, 15] : [25, 35]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Weight units", selection: $store.settings.units) {
                        ForEach(AppSettings.Units.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Weight increment", selection: $store.settings.weightIncrement) {
                        ForEach([1.0, 2.5, 5.0], id: \.self) { Text(String(format: "%.1f", $0)).tag($0) }
                    }
                }

                Section {
                    Stepper(
                        "Deload after \(store.settings.deloadFailureThreshold) failures",
                        value: $store.settings.deloadFailureThreshold,
                        in: 1...5
                    )
                    Picker("Deload by", selection: $store.settings.deloadPercent) {
                        ForEach([5.0, 10.0, 15.0, 20.0], id: \.self) { Text("\(Int($0))%").tag($0) }
                    }
                } header: {
                    Text("Progression")
                } footer: {
                    Text("Weights increase automatically after a fully successful session. After \(store.settings.deloadFailureThreshold) failed sessions in a row, an exercise deloads by \(Int(store.settings.deloadPercent))%.")
                }

                Section {
                    Toggle("Warmup sets", isOn: $store.settings.warmupsEnabled)
                    if store.settings.warmupsEnabled {
                        Picker("Bar weight", selection: $store.settings.barWeight) {
                            Text("Standard (\(Int(Warmup.defaultBarWeight(units: store.settings.units))) \(store.settings.units.label))")
                                .tag(Double?.none)
                            ForEach(barOptions, id: \.self) { w in
                                Text("\(Int(w)) \(store.settings.units.label)").tag(Double?.some(w))
                            }
                        }
                    }
                } header: {
                    Text("Warmup")
                } footer: {
                    Text("New workouts start each weighted exercise with empty-bar sets and ramped jumps up to the working weight. Warmups don't count toward progression or volume.")
                }

                Section {
                    ForEach(PlateCalculator.defaultPlates(units: store.settings.units), id: \.self) { plate in
                        Toggle(plateLabel(plate) + " " + store.settings.units.label, isOn: plateBinding(plate))
                    }
                } header: {
                    Text("Available Plates")
                } footer: {
                    Text("The plate guide on the workout screen only uses plates you have. Weights that can't be loaded exactly show the closest achievable load.")
                }

                Section("Rest Timer") {
                    Picker("Default rest", selection: $store.settings.defaultRestSeconds) {
                        ForEach(restOptions, id: \.self) { s in
                            Text("\(s / 60):\(String(format: "%02d", s % 60))").tag(s)
                        }
                    }
                    Toggle("Auto-start after a set", isOn: $store.settings.autoStartRest)
                    Toggle("Alert when rest ends", isOn: $store.settings.restAlertsEnabled)
                }

                Section("Apple Watch") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(watchStatusText)
                            .foregroundStyle(connectivity.isReachable ? .green : .secondary)
                    }
                    Text("Start a workout on your iPhone and it appears on your Apple Watch automatically. Log sets and the rest timer from either device — they stay in sync.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("Workouts saved", value: "\(store.templates.count)")
                    LabeledContent("History entries", value: "\(store.history.count)")
                } header: {
                    Text("Data")
                } footer: {
                    Text("AruLifts · v1.0")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func plateLabel(_ w: Double) -> String {
        w == w.rounded() ? String(Int(w)) : String(format: "%.2f", w).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
    }

    /// nil plateSet means "all standard plates"; toggling materializes it.
    private func plateBinding(_ plate: Double) -> Binding<Bool> {
        Binding(
            get: {
                (store.settings.plateSet ?? PlateCalculator.defaultPlates(units: store.settings.units)).contains(plate)
            },
            set: { enabled in
                var set = store.settings.plateSet ?? PlateCalculator.defaultPlates(units: store.settings.units)
                if enabled {
                    if !set.contains(plate) { set.append(plate) }
                } else {
                    set.removeAll { $0 == plate }
                }
                store.settings.plateSet = set.sorted(by: >)
            }
        )
    }

    private var watchStatusText: String {
        if connectivity.isReachable { return "Connected" }
        if connectivity.isCounterpartAvailable { return "Paired" }
        return "Not paired"
    }
}

#Preview {
    SettingsView().environmentObject(WorkoutStore())
}
