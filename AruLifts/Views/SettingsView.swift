import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: WorkoutStore
    @ObservedObject private var connectivity = ConnectivityManager.shared

    private let restOptions = [60, 90, 120, 150, 180, 240, 300]

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

    private var watchStatusText: String {
        if connectivity.isReachable { return "Connected" }
        if connectivity.isCounterpartAvailable { return "Paired" }
        return "Not paired"
    }
}

#Preview {
    SettingsView().environmentObject(WorkoutStore())
}
