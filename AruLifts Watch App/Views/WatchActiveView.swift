import SwiftUI

/// Watch-first workout controller. The current target and its one primary
/// action dominate the screen; adjustment, overview, pause and finish remain
/// available without crowding the normal set-completion loop.
struct WatchActiveView: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    @ObservedObject private var liveSession = WatchWorkoutSession.shared

    @State private var showingAdjustment = false
    @State private var showingOverview = false
    @State private var showingFinishConfirmation = false

    private var exercise: SessionExercise? { active.currentExercise }

    private var workingSetIndex: Int? {
        exercise?.sets.firstIndex(where: { !$0.isCompleted })
    }

    var body: some View {
        VStack(spacing: 7) {
            if let exercise {
                header(exercise)

                if !active.canEdit {
                    Label("Waiting for iPhone handoff", systemImage: "iphone.slash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if active.isWorkoutPaused {
                    pausedCard
                } else if let setIndex = workingSetIndex,
                          exercise.sets.indices.contains(setIndex) {
                    focusedSet(exercise.sets[setIndex], index: setIndex, in: exercise)
                } else {
                    allDoneCard
                }

                progressDots(exercise)
                exerciseNavigation
            }
        }
        .padding(.horizontal, 4)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingOverview = true
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Workout options")
            }
        }
        .sheet(isPresented: $showingAdjustment) {
            if let setIndex = workingSetIndex {
                NavigationStack {
                    WatchSetLogView(
                        exerciseIndex: active.currentExerciseIndex,
                        setIndex: setIndex
                    )
                    .environmentObject(active)
                }
            }
        }
        .sheet(isPresented: $showingOverview) {
            workoutOverview
        }
        .confirmationDialog(
            incompleteSetCount == 0 ? "Finish this workout?" : "Finish with \(incompleteSetCount) sets incomplete?",
            isPresented: $showingFinishConfirmation,
            titleVisibility: .visible
        ) {
            Button("Finish Workout") { active.finish() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("The workout will be saved on your Watch and synchronized to your iPhone.")
        }
        .fullScreenCover(isPresented: Binding(
            get: { active.restTimer.isRunning || active.restTimer.isPaused },
            set: { if !$0 && active.restTimer.isRunning { active.restTimer.skip() } }
        )) {
            WatchRestView(timer: active.restTimer)
                .environmentObject(active)
        }
    }

    private func header(_ exercise: SessionExercise) -> some View {
        VStack(spacing: 1) {
            Text(exercise.name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(spacing: 6) {
                Text("\(exercise.completedSets) of \(exercise.sets.count) sets")
                WatchHeartRateChip(bpm: liveSession.heartRateBPM)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func focusedSet(_ set: SetEntry, index: Int, in exercise: SessionExercise) -> some View {
        VStack(spacing: 7) {
            Text(setLabel(index, in: exercise))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(set.isWarmup ? .orange : .secondary)

            if exercise.usesWeight {
                Text("\(weightString(set.weight)) \(unitLabel) × \(set.reps)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            } else {
                Text("\(set.reps) reps")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            if exercise.usesWeight, set.weight > 0 {
                Text(plateString(for: set.weight))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel("Plates \(plateString(for: set.weight))")
            }

            Button {
                active.completeSet(
                    exerciseIndex: active.currentExerciseIndex,
                    setIndex: index,
                    autoStartRest: active.watchExecutionSettings.autoStartRest,
                    restAlerts: active.watchExecutionSettings.restAlertsEnabled,
                    restAlertConfiguration: RestTimerAlertConfiguration(
                        alertsEnabled: active.watchExecutionSettings.restAlertsEnabled,
                        style: active.watchExecutionSettings.restAlertStyle,
                        earlyCueEnabled: active.watchExecutionSettings.earlyRestCueEnabled,
                        earlyCueLeadSeconds: active.watchExecutionSettings.earlyRestCueLeadSeconds
                    ),
                    adaptiveRest: active.watchExecutionSettings.adaptiveRestEnabled,
                    failedSetRestMultiplier: active.watchExecutionSettings.failedSetRestMultiplier
                )
            } label: {
                Label("Complete & Rest", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.borderedProminent)
            .tint(set.isWarmup ? .orange : .green)
            .disabled(active.isFinalizing || !active.canEdit)
            .accessibilityHint("Marks this set complete and starts the rest timer")

            Button("Adjust weight or reps") {
                showingAdjustment = true
            }
            .font(.caption2)
            .buttonStyle(.plain)
            .foregroundStyle(.orange)
            .disabled(!active.canEdit)
            .accessibilityHint("Opens Digital Crown adjustment controls")
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15))
    }

    private var pausedCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Workout paused")
                .font(.headline)
            Button("Resume") { active.toggleWorkoutPause() }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15))
    }

    private var allDoneCard: some View {
        VStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("Exercise complete")
                .font(.headline)
            if active.currentExerciseIndex < (active.session?.exercises.count ?? 1) - 1 {
                Button("Next Exercise") { active.goToNextExercise() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            } else {
                Button("Finish Workout") { showingFinishConfirmation = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
    }

    private func progressDots(_ exercise: SessionExercise) -> some View {
        HStack(spacing: 5) {
            ForEach(exercise.sets) { set in
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        set.isCompleted ? .green : (set.isWarmup ? .orange : .secondary)
                    )
            }
        }
        .font(.caption)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercise.completedSets) of \(exercise.sets.count) sets complete")
    }

    private var exerciseNavigation: some View {
        HStack(spacing: 8) {
            Button {
                active.goToPreviousExercise()
            } label: {
                Label("Previous exercise", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity)
            }
            .disabled(!active.canEdit || active.currentExerciseIndex == 0)

            Text("\(active.currentExerciseIndex + 1)/\(active.session?.exercises.count ?? 1)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                active.goToNextExercise()
            } label: {
                Label("Next exercise", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity)
            }
            .disabled(!active.canEdit || active.currentExerciseIndex >= (active.session?.exercises.count ?? 1) - 1)
        }
        .buttonStyle(.bordered)
    }

    private var workoutOverview: some View {
        NavigationStack {
            List {
                if let session = active.session {
                    ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, exercise in
                        Button {
                            active.currentExerciseIndex = index
                            showingOverview = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(exercise.name)
                                    Text("\(exercise.completedSets)/\(exercise.sets.count) sets")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if exercise.isComplete {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .disabled(!active.canEdit)
                    }

                    if active.canEdit {
                        Section {
                            Button(active.isWorkoutPaused ? "Resume Workout" : "Pause Workout") {
                                active.toggleWorkoutPause()
                                showingOverview = false
                            }
                            Button("Finish Workout") {
                                showingOverview = false
                                showingFinishConfirmation = true
                            }
                            .foregroundStyle(.green)
                            Button("Cancel Workout", role: .destructive) {
                                active.cancel()
                                showingOverview = false
                            }
                        }
                    } else {
                        Section {
                            Text("This workout is controlled on the other device.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(active.session?.name ?? "Workout")
        }
    }

    private var incompleteSetCount: Int {
        active.session?.exercises.reduce(0) {
            $0 + $1.sets.filter { !$0.isCompleted }.count
        } ?? 0
    }

    private var unitLabel: String {
        active.watchExecutionSettings.units.label
    }

    private func setLabel(_ index: Int, in exercise: SessionExercise) -> String {
        let set = exercise.sets[index]
        let earlierSameKind = exercise.sets.prefix(index)
            .filter { $0.isWarmup == set.isWarmup }.count
        return set.isWarmup
            ? "Warmup \(earlierSameKind + 1)"
            : "Set \(earlierSameKind + 1) of \(exercise.sets.filter { !$0.isWarmup }.count)"
    }

    private func weightString(_ weight: Double) -> String {
        weight == weight.rounded()
            ? String(Int(weight))
            : String(format: "%.1f", weight)
    }

    private func plateString(for weight: Double) -> String {
        let result = PlateCalculator.plates(
            target: weight,
            bar: active.watchExecutionSettings.barWeight,
            available: active.watchExecutionSettings.availablePlates
        )
        guard !result.platesPerSide.isEmpty else { return "empty bar" }
        return result.platesPerSide
            .map { $0 == $0.rounded() ? String(Int($0)) : String(format: "%.2g", $0) }
            .joined(separator: " + ") + " per side"
    }

    /// Live heart rate from the Watch workout session; hidden until HealthKit
    /// supplies a reading.
    struct WatchHeartRateChip: View {
        let bpm: Double?

        var body: some View {
            if let bpm {
                HStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                    Text("\(Int(bpm))")
                        .monospacedDigit()
                }
                .font(.caption2)
                .accessibilityLabel("Heart rate \(Int(bpm)) beats per minute")
            }
        }
    }
}
