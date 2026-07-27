import SwiftUI

struct RoutineComposerView: View {
    @EnvironmentObject var store: WorkoutStore
    @EnvironmentObject var activeManager: ActiveWorkoutManager
    @Environment(\.dismiss) private var dismiss

    @State private var routine: GymSessionRoutine
    @State private var selectedTemplateID: UUID?

    let isNew: Bool

    init(routine: GymSessionRoutine? = nil) {
        if let routine = routine {
            _routine = State(initialValue: routine)
            isNew = false
        } else {
            _routine = State(initialValue: GymSessionRoutine(name: "New Gym Routine", notes: "Custom multi-phase gym session"))
            isNew = true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Routine Details")) {
                    TextField("Routine Name", text: $routine.name)
                        .font(.headline)
                    TextField("Notes / Focus", text: $routine.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section(header: Text("Session Architecture (7 Sequential Phases)")) {
                    Text("Customize, reorder, or enable/disable each phase of your gym visit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach($routine.phases) { $phase in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: phase.phaseType.iconSymbol)
                                    .foregroundStyle(phase.phaseType.color)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(phase.name)
                                        .font(.headline)
                                    Text(phase.phaseType.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Toggle("", isOn: $phase.isEnabled)
                                    .labelsHidden()
                            }

                            if phase.isEnabled {
                                Divider()

                                if phase.phaseType == .mainStrength {
                                    Picker("Strength Template", selection: $phase.templateID) {
                                        Text("None (Custom Set/Rep)").tag(UUID?.none)
                                        ForEach(store.templates) { template in
                                            Text(template.name).tag(UUID?.some(template.id))
                                        }
                                    }
                                } else if phase.phaseType.isTimed {
                                    HStack {
                                        Text("Duration:")
                                            .font(.subheadline)
                                        Spacer()
                                        Stepper("\(phase.durationSeconds / 60) min", value: Binding(
                                            get: { max(1, phase.durationSeconds / 60) },
                                            set: { phase.durationSeconds = $0 * 60 }
                                        ), in: 1...120)
                                    }
                                }

                                if !phase.notes.isEmpty || phase.phaseType == .saunaRecovery || phase.phaseType == .steamRecovery {
                                    TextField("Notes / Hydration Cue", text: $phase.notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { indices, newOffset in
                        routine.phases.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }

                Section {
                    Button(action: startRoutineNow) {
                        HStack {
                            Spacer()
                            Label("Start Gym Session Now", systemImage: "play.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .navigationTitle(isNew ? "Create Gym Routine" : "Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveRoutine()
                        dismiss()
                    }
                }
            }
        }
    }

    private func saveRoutine() {
        if isNew {
            store.addGymRoutine(routine)
        } else {
            store.updateGymRoutine(routine)
        }
    }

    private func startRoutineNow() {
        saveRoutine()
        let session = WorkoutSession.from(
            routine: routine,
            templates: store.templates,
            library: store.exerciseIndex,
            settings: store.settings
        )
        activeManager.start(session)
        dismiss()
    }
}
