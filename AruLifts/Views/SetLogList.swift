import SwiftUI

/// The list of sets for the current exercise, with inline reps/weight editing
/// and a tap-to-complete checkmark.
struct SetLogList: View {
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var active: ActiveWorkoutManager
    let exerciseIndex: Int
    @State private var showingForm = false

    private var exercise: SessionExercise? {
        guard let s = active.session, s.exercises.indices.contains(exerciseIndex) else { return nil }
        return s.exercises[exerciseIndex]
    }

    var body: some View {
        if let exercise {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Button { showingForm = true } label: {
                            HStack(spacing: 4) {
                                Text(exercise.name).font(.title3.bold())
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        Text("\(exercise.restSeconds / 60):\(String(format: "%02d", exercise.restSeconds % 60)) rest · \(exercise.sets.count) sets")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // Everything below the header edits the session, so it is gated
                // on edit ownership. The exercise-name button above stays live
                // even when the Watch owns the session — checking form guidance
                // is read-only, and mid-workout is exactly when it is needed.
                Group {
                    plateGuide(exercise)

                // Column headers
                HStack {
                    Text("SET").frame(width: 40, alignment: .leading)
                    if exercise.usesWeight {
                        Text("WEIGHT").frame(maxWidth: .infinity)
                    }
                    Text("REPS").frame(maxWidth: .infinity)
                    Text("DONE").frame(width: 50)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { setIndex, set in
                    SetRow(
                        label: setLabel(setIndex, in: exercise),
                        set: set,
                        usesWeight: exercise.usesWeight,
                        loadingMode: exercise.loadingMode,
                        increment: store.settings.weightIncrement,
                        units: store.settings.units,
                        onComplete: { completeSet(setIndex) },
                        onReps: { delta in
                            active.updateSet(exerciseIndex: exerciseIndex, setIndex: setIndex, reps: set.reps + delta)
                        },
                        onWeight: { delta in
                            let minimumWeight = exercise.loadingMode == .barbell
                                ? (store.settings.barWeight ?? Warmup.defaultBarWeight(units: store.settings.units))
                                : 0
                            active.updateSet(
                                exerciseIndex: exerciseIndex,
                                setIndex: setIndex,
                                weight: max(minimumWeight, set.weight + delta)
                            )
                        }
                    )
                }

                HStack {
                    Button {
                        active.addSet(exerciseIndex: exerciseIndex)
                    } label: {
                        Label("Add Set", systemImage: "plus.circle.fill")
                    }
                    Spacer()
                    if exercise.sets.count > 1 {
                        Button(role: .destructive) {
                            active.removeSet(exerciseIndex: exerciseIndex, setIndex: exercise.sets.count - 1)
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                    }
                }
                .font(.subheadline)
                .padding(.top, 4)

                    navigationButtons
                }
                .disabled(!active.canEdit)
            }
            .sheet(isPresented: $showingForm) {
                if let ex = store.exercise(for: exercise.exerciseID) {
                    NavigationStack { ExerciseDetailView(exercise: ex) }
                }
            }
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            Button {
                active.goToPreviousExercise()
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .disabled(active.currentExerciseIndex == 0)

            Button {
                active.goToNextExercise()
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(active.currentExerciseIndex >= (active.session?.exercises.count ?? 1) - 1)
        }
        .padding(.top, 8)
    }

    /// Plate breakdown for the next uncompleted set's weight.
    @ViewBuilder
    private func plateGuide(_ exercise: SessionExercise) -> some View {
        if exercise.loadingMode == .barbell,
           exercise.usesWeight,
           let next = exercise.sets.first(where: { !$0.isCompleted }),
           next.weight > 0 {
            let bar = store.settings.barWeight ?? Warmup.defaultBarWeight(units: store.settings.units)
            let result = PlateCalculator.plates(
                target: next.weight,
                bar: bar,
                available: store.settings.plateSet ?? PlateCalculator.defaultPlates(units: store.settings.units)
            )
            BarbellView(result: result, units: store.settings.units)
        }
    }

    /// Warmups label as W1, W2…; work sets number from 1.
    private func setLabel(_ index: Int, in exercise: SessionExercise) -> String {
        let set = exercise.sets[index]
        let peers = exercise.sets.prefix(index).filter { $0.isWarmup == set.isWarmup }.count
        return set.isWarmup ? "W\(peers + 1)" : "\(peers + 1)"
    }

    private func completeSet(_ setIndex: Int) {
        active.completeSet(
            exerciseIndex: exerciseIndex,
            setIndex: setIndex,
            autoStartRest: store.settings.autoStartRest,
            restAlerts: store.settings.restAlertsEnabled,
            restAlertConfiguration: RestTimerAlertConfiguration(
                alertsEnabled: store.settings.restAlertsEnabled,
                style: store.settings.restAlertStyle,
                earlyCueEnabled: store.settings.earlyRestCueEnabled,
                earlyCueLeadSeconds: store.settings.earlyRestCueLeadSeconds
            ),
            adaptiveRest: store.settings.adaptiveRestEnabled,
            failedSetRestMultiplier: store.settings.failedSetRestMultiplier
        )
    }
}

/// Visual barbell: bar line with per-side plates as height-scaled slabs,
/// plus a text summary. Warns when the target isn't exactly loadable.
struct BarbellView: View {
    let result: PlateCalculator.Result
    let units: AppSettings.Units

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                // Bar sleeve
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: 26, height: 6)
                ForEach(Array(result.platesPerSide.enumerated()), id: \.offset) { _, plate in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.orange.gradient)
                        .frame(width: 10, height: plateHeight(plate))
                        .overlay(alignment: .bottom) {
                            Text(plateLabel(plate))
                                .font(.system(size: 7).bold())
                                .foregroundStyle(.white)
                                .padding(.bottom, 2)
                        }
                }
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: 14, height: 6)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(summary).font(.caption2.weight(.medium))
                    if !result.isExact {
                        Text("closest: \(WeightFormatter.string(result.achievedWeight, units: units))")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var summary: String {
        result.platesPerSide.isEmpty
            ? "empty bar"
            : result.platesPerSide.map(plateLabel).joined(separator: " · ") + " / side"
    }

    private func plateLabel(_ w: Double) -> String {
        w == w.rounded() ? String(Int(w)) : String(format: "%.2g", w)
    }

    private func plateHeight(_ plate: Double) -> CGFloat {
        let biggest = units == .kg ? 25.0 : 45.0
        return CGFloat(16 + (plate / biggest) * 22)
    }
}

/// A single set row. Warmup rows are tinted orange with a "W" label.
struct SetRow: View {
    let label: String
    let set: SetEntry
    let usesWeight: Bool
    let loadingMode: LoadingMode
    let increment: Double
    let units: AppSettings.Units
    let onComplete: () -> Void
    let onReps: (Int) -> Void
    let onWeight: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.headline.monospacedDigit())
                .frame(width: 40, alignment: .leading)
                .foregroundStyle(set.isCompleted ? Color.secondary : (set.isWarmup ? Color.orange : Color.primary))

            if usesWeight {
                StepValue(
                    text: formatWeight(set.weight, units: units),
                    valueAccessibilityLabel: "\(loadingMode.accessibilityLabel), \(formatWeight(set.weight, units: units))",
                    minusAccessibilityLabel: "Decrease \(loadingMode.accessibilityLabel) by \(formatWeight(increment, units: units))",
                    plusAccessibilityLabel: "Increase \(loadingMode.accessibilityLabel) by \(formatWeight(increment, units: units))",
                    adjustmentHint: "Changes the weight for \(spokenSetLabel)",
                    onMinus: { onWeight(-increment) },
                    onPlus: { onWeight(increment) }
                )
            }

            StepValue(
                text: "\(set.reps)",
                valueAccessibilityLabel: "Reps, \(set.reps)",
                minusAccessibilityLabel: "Decrease reps by 1",
                plusAccessibilityLabel: "Increase reps by 1",
                adjustmentHint: "Changes reps for \(spokenSetLabel)",
                onMinus: { onReps(-1) },
                onPlus: { onReps(1) }
            )

            Button(action: onComplete) {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(set.isCompleted ? .green : .secondary)
            }
            .frame(width: 50)
            .buttonStyle(.plain)
            .accessibilityLabel(set.isCompleted ? "\(spokenSetLabel) complete" : "Mark \(spokenSetLabel) complete")
            .accessibilityHint(
                set.isCompleted
                    ? "This set has already been logged"
                    : "Logs \(set.reps) reps and starts the rest timer when enabled"
            )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(set.isCompleted
                      ? Color.green.opacity(0.10)
                      : (set.isWarmup ? Color.orange.opacity(0.08) : Color(.secondarySystemBackground)))
        )
    }

    private var spokenSetLabel: String {
        return set.isWarmup ? "warmup \(label.dropFirst())" : "set \(label)"
    }
}

/// A stepper with - value + laid out compactly.
struct StepValue: View {
    let text: String
    let valueAccessibilityLabel: String
    let minusAccessibilityLabel: String
    let plusAccessibilityLabel: String
    let adjustmentHint: String
    let onMinus: () -> Void
    let onPlus: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Button(action: onMinus) { Image(systemName: "minus") }
                .accessibilityLabel(minusAccessibilityLabel)
                .accessibilityHint(adjustmentHint)
            Text(text)
                .font(.subheadline.monospacedDigit().weight(.medium))
                .frame(minWidth: 52)
                .accessibilityLabel(valueAccessibilityLabel)
            Button(action: onPlus) { Image(systemName: "plus") }
                .accessibilityLabel(plusAccessibilityLabel)
                .accessibilityHint(adjustmentHint)
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// Floating rest-timer bar shown while resting. Observes the timer directly so
/// it re-renders every tick.
struct RestTimerBar: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    @ObservedObject var timer: RestTimerManager
    @State private var showingExpandedTimer = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    showingExpandedTimer = true
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .stroke(Color.orange.opacity(0.18), lineWidth: 4)
                            Circle()
                                .trim(from: 0, to: timer.progress)
                                .stroke(
                                    Color.orange,
                                    style: StrokeStyle(
                                        lineWidth: 4,
                                        lineCap: .round
                                    )
                                )
                                .rotationEffect(.degrees(-90))
                                .animation(
                                    .linear(duration: 0.5),
                                    value: timer.progress
                                )
                            Image(systemName: timer.isPaused ? "pause.fill" : "timer")
                                .foregroundStyle(.orange)
                                .font(.footnote.weight(.semibold))
                        }
                        .frame(width: 42, height: 42)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(timer.isOvertime ? "Rest over" : (timer.isPaused ? "Rest paused" : "Resting"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(timer.isOvertime ? Color.green : Color.secondary)
                            Text(timer.formattedRemaining)
                                .font(.title2.monospacedDigit().bold())
                                .foregroundStyle(timer.isOvertime ? Color.green : Color.primary)
                                .contentTransition(.numericText())
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    timer.isOvertime
                        ? "Rest over by \(timer.formattedRemaining.dropFirst())"
                        : "\(timer.isPaused ? "Rest paused" : "Resting"), \(timer.formattedRemaining) remaining"
                )
                .accessibilityHint("Opens the focused rest timer")

                Spacer(minLength: 2)

                Button {
                    active.addRest(seconds: 30)
                } label: {
                    Text("+30")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 42, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(!active.canEdit)
                .accessibilityLabel("Add 30 seconds")

                Button {
                    active.skipRest()
                } label: {
                    Text("Skip")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 42, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!active.canEdit)

                Menu {
                    Button {
                        active.toggleRestPause()
                    } label: {
                        Label(
                            timer.isPaused ? "Resume rest" : "Pause rest",
                            systemImage: timer.isPaused
                                ? "play.fill"
                                : "pause.fill"
                        )
                    }
                    Button {
                        active.resetRest()
                    } label: {
                        Label(
                            "Reset rest timer",
                            systemImage: "arrow.counterclockwise"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .disabled(!active.canEdit)
                .accessibilityLabel("More rest timer controls")
            }

            if let nextSetDescription {
                HStack(spacing: 5) {
                    Text("UP NEXT")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                    Text(nextSetDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(Color.orange)
                    .frame(
                        width: proxy.size.width * min(max(timer.progress, 0), 1)
                    )
            }
            .frame(height: 3)
            .background(Color.orange.opacity(0.14), in: Capsule())
            .padding(.top, 9)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
        .fullScreenCover(isPresented: $showingExpandedTimer) {
            FocusedRestTimerView(timer: timer)
                .environmentObject(active)
        }
    }

    private var nextSetDescription: String? {
        guard let exercise = active.currentExercise,
              let index = exercise.sets.firstIndex(where: { !$0.isCompleted })
        else {
            return nil
        }
        let set = exercise.sets[index]
        let number =
            exercise.sets.prefix(index).filter { !$0.isWarmup }.count + 1
        if exercise.usesWeight {
            let weight = WeightFormatter.number(set.weight)
            let load = exercise.loadingMode == .bodyweight
                ? "+\(weight)"
                : weight
            return "\(exercise.name) · Set \(number) · \(load) × \(set.reps)"
        }
        return "\(exercise.name) · Set \(number) · \(set.reps) reps"
    }
}

/// Optional focused presentation for users who want the countdown visible from
/// across the gym. The compact card remains the default workout experience.
private struct FocusedRestTimerView: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var timer: RestTimerManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                Text(timer.isPaused ? "REST PAUSED" : "REST")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.secondary)

                ZStack {
                    Circle()
                        .stroke(Color.orange.opacity(0.14), lineWidth: 18)
                    Circle()
                        .trim(from: 0, to: timer.progress)
                        .stroke(
                            Color.orange.gradient,
                            style: StrokeStyle(lineWidth: 18, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: timer.progress)
                    VStack(spacing: 3) {
                        Text(timer.formattedRemaining)
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(timer.isOvertime ? Color.green : Color.primary)
                        Text(timer.isOvertime ? "over" : "remaining")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 270)
                .aspectRatio(1, contentMode: .fit)

                if let nextSetDescription {
                    VStack(spacing: 5) {
                        Text("UP NEXT")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                        Text(nextSetDescription)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .padding(.horizontal)
                }

                HStack(spacing: 12) {
                    Button {
                        active.toggleRestPause()
                    } label: {
                        Label(
                            timer.isPaused ? "Resume" : "Pause",
                            systemImage: timer.isPaused ? "play.fill" : "pause.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        active.addRest(seconds: 30)
                    } label: {
                        Label("30 sec", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)

                    Button {
                        active.skipRest()
                        dismiss()
                    } label: {
                        Label("Skip", systemImage: "forward.end.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .disabled(!active.canEdit)

                Button {
                    active.resetRest()
                } label: {
                    Label("Reset timer", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(!active.canEdit)

                Spacer()
            }
            .padding(24)
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Rest Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var nextSetDescription: String? {
        guard let exercise = active.currentExercise,
              let index = exercise.sets.firstIndex(where: { !$0.isCompleted })
        else {
            return nil
        }
        let set = exercise.sets[index]
        let number =
            exercise.sets.prefix(index).filter { !$0.isWarmup }.count + 1
        if exercise.usesWeight {
            let weight = WeightFormatter.number(set.weight)
            let load = exercise.loadingMode == .bodyweight
                ? "+\(weight)"
                : weight
            return "\(exercise.name) · Set \(number) · \(load) × \(set.reps)"
        }
        return "\(exercise.name) · Set \(number) · \(set.reps) reps"
    }
}
