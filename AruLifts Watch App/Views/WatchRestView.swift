import SwiftUI

/// Full-screen rest countdown on the watch with a progress ring and quick
/// actions. A haptic fires when the timer completes (handled by the manager).
struct WatchRestView: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    @ObservedObject var timer: RestTimerManager
    @ObservedObject private var liveSession = WatchWorkoutSession.shared

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                Text("REST")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                WatchActiveView.WatchHeartRateChip(bpm: liveSession.heartRateBPM)
            }

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: timer.progress)
                Text(timer.formattedRemaining)
                    .font(.title.monospacedDigit().bold())
            }
            .frame(width: 100, height: 100)

            if let nextSetDescription {
                Text("Next: \(nextSetDescription)")
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityLabel("Next set \(nextSetDescription)")
            }

            if active.canUndoLastSetCompletion {
                Button {
                    active.undoLastSetCompletion()
                } label: {
                    Label("Undo completion", systemImage: "arrow.uturn.backward")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .tint(.yellow)
                .disabled(!active.canEdit)
            }

            HStack(spacing: 8) {
                Button { active.toggleRestPause() } label: {
                    Text(timer.isPaused ? "Resume" : "Pause").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!active.canEdit || active.isWorkoutPaused)

                Button { active.resetRest() } label: {
                    Image(systemName: "arrow.counterclockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Reset rest timer")
                .disabled(!active.canEdit || active.isWorkoutPaused)

                Button { active.addRest(seconds: 30) } label: {
                    Text("+30s").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!active.canEdit || active.isWorkoutPaused)

                Button { active.skipRest() } label: {
                    Text("Skip").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!active.canEdit || active.isWorkoutPaused)
            }
        }
        .padding(.horizontal, 6)
    }

    private var nextSetDescription: String? {
        guard let exercise = active.currentExercise,
              let index = exercise.sets.firstIndex(where: { !$0.isCompleted }) else {
            return nil
        }
        let set = exercise.sets[index]
        let number = exercise.sets.prefix(index).filter { !$0.isWarmup }.count + 1
        if exercise.usesWeight {
            let weight = set.weight == set.weight.rounded()
                ? String(Int(set.weight))
                : String(format: "%.1f", set.weight)
            return "\(exercise.name) · Set \(number) · \(weight) × \(set.reps)"
        }
        return "\(exercise.name) · Set \(number) · \(set.reps) reps"
    }
}
