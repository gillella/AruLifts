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
                        Text(exercise.name).font(.title3.bold())
                        Text("\(exercise.restSeconds / 60):\(String(format: "%02d", exercise.restSeconds % 60)) rest · \(exercise.sets.count) sets")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { showingForm = true } label: {
                        Image(systemName: "info.circle").font(.title3)
                    }
                }

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
                        increment: store.settings.weightIncrement,
                        units: store.settings.units,
                        onComplete: { completeSet(setIndex) },
                        onReps: { delta in
                            active.updateSet(exerciseIndex: exerciseIndex, setIndex: setIndex, reps: set.reps + delta)
                        },
                        onWeight: { delta in
                            active.updateSet(exerciseIndex: exerciseIndex, setIndex: setIndex, weight: set.weight + delta)
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
        if exercise.usesWeight,
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
            restAlerts: store.settings.restAlertsEnabled
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
                        Text("closest: \(result.achievedWeight.formatted()) \(units.label)")
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
                    onMinus: { onWeight(-increment) },
                    onPlus: { onWeight(increment) }
                )
            }

            StepValue(
                text: "\(set.reps)",
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
}

/// A stepper with - value + laid out compactly.
struct StepValue: View {
    let text: String
    let onMinus: () -> Void
    let onPlus: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Button(action: onMinus) { Image(systemName: "minus") }
            Text(text)
                .font(.subheadline.monospacedDigit().weight(.medium))
                .frame(minWidth: 52)
            Button(action: onPlus) { Image(systemName: "plus") }
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity)
    }
}

/// Floating rest-timer bar shown while resting. Observes the timer directly so
/// it re-renders every tick.
struct RestTimerBar: View {
    @ObservedObject var timer: RestTimerManager

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.25), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "timer").foregroundStyle(.white).font(.footnote)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 1) {
                Text("Resting").font(.caption).foregroundStyle(.white.opacity(0.8))
                Text(timer.formattedRemaining)
                    .font(.title2.monospacedDigit().bold())
                    .foregroundStyle(.white)
            }
            Spacer()
            Button { timer.add(seconds: 30) } label: {
                Text("+30s").font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.white.opacity(0.2), in: Capsule())
            }
            Button { timer.skip() } label: {
                Text("Skip").font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.white.opacity(0.2), in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(Color.orange, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(radius: 8, y: 4)
    }
}
