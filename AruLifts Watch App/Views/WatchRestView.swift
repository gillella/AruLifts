import SwiftUI

/// Full-screen rest countdown on the watch with a progress ring and quick
/// actions. A haptic fires when the timer completes (handled by the manager).
struct WatchRestView: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    @ObservedObject var timer: RestTimerManager
    @ObservedObject private var liveSession = WatchWorkoutSession.shared
    @State private var showingRestOptions = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text("REST")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                    Spacer(minLength: 0)
                    WatchActiveView.WatchHeartRateChip(
                        bpm: liveSession.heartRateBPM
                    )
                }

                ZStack {
                    Circle()
                        .stroke(Color.orange.opacity(0.16), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: timer.progress)
                        .stroke(
                            Color.orange.gradient,
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(
                            .linear(duration: 0.5),
                            value: timer.progress
                        )
                    VStack(spacing: 0) {
                        Text(timer.formattedRemaining)
                            .font(.system(.title2, design: .rounded).bold())
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(timer.isOvertime ? Color.green : Color.primary)
                        if timer.isOvertime {
                            Text("OVER")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.green)
                        } else if timer.isPaused {
                            Text("PAUSED")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 108, height: 108)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    timer.isOvertime
                        ? "Rest over by \(timer.formattedRemaining.dropFirst())"
                        : "\(timer.isPaused ? "Rest paused" : "Resting"), \(timer.formattedRemaining) remaining"
                )

                if let nextSet {
                    VStack(spacing: 1) {
                        Text("UP NEXT")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.orange)
                        Text(nextSet.exercise)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(nextSet.details)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(
                        .thinMaterial,
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "Up next, \(nextSet.exercise), \(nextSet.details)"
                    )
                }

                HStack(spacing: 6) {
                    Button { active.addRest(seconds: 30) } label: {
                        Text("+30")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .disabled(!active.canEdit || active.isWorkoutPaused)
                    .accessibilityLabel("Add 30 seconds")

                    Button { active.skipRest() } label: {
                        Text("Skip")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!active.canEdit || active.isWorkoutPaused)

                    Button {
                        showingRestOptions = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .disabled(!active.canEdit || active.isWorkoutPaused)
                    .accessibilityLabel("More rest timer controls")
                }
            }
            .padding(.horizontal, 6)
        }
        .sheet(isPresented: $showingRestOptions) {
            restOptions
        }
    }

    private struct NextSet {
        let exercise: String
        let details: String
    }

    private var restOptions: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Rest Options")
                    .font(.headline)

                Button {
                    active.toggleRestPause()
                    showingRestOptions = false
                } label: {
                    Label(
                        timer.isPaused ? "Resume Rest" : "Pause Rest",
                        systemImage: timer.isPaused ? "play.fill" : "pause.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button {
                    active.resetRest()
                    showingRestOptions = false
                } label: {
                    Label(
                        "Reset Timer",
                        systemImage: "arrow.counterclockwise"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if active.canUndoLastSetCompletion {
                    Button {
                        active.undoLastSetCompletion()
                        showingRestOptions = false
                    } label: {
                        Label(
                            "Undo Set",
                            systemImage: "arrow.uturn.backward"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.yellow)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var nextSet: NextSet? {
        guard let exercise = active.currentExercise,
              let index = exercise.sets.firstIndex(where: { !$0.isCompleted }) else {
            return nil
        }
        let set = exercise.sets[index]
        let number = exercise.sets.prefix(index).filter { !$0.isWarmup }.count + 1
        if exercise.usesWeight {
            let weight = WeightFormatter.number(set.weight)
            let load = exercise.loadingMode == .bodyweight ? " +\(weight)" : " \(weight)"
            return NextSet(
                exercise: exercise.name,
                details: "Set \(number) ·\(load) × \(set.reps)"
            )
        }
        return NextSet(
            exercise: exercise.name,
            details: "Set \(number) · \(set.reps) reps"
        )
    }
}
