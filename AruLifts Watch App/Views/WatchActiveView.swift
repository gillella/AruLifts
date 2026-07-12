import SwiftUI

/// The live workout on the watch: current exercise, a card to log/adjust the
/// current set, set progress, and exercise navigation. A rest cover appears
/// automatically while the rest timer runs.
struct WatchActiveView: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    @ObservedObject private var liveSession = WatchWorkoutSession.shared

    private var exercise: SessionExercise? { active.currentExercise }

    /// Index of the first set that hasn't been completed (the working set).
    private var workingSetIndex: Int? {
        exercise?.sets.firstIndex(where: { !$0.isCompleted })
    }

    var body: some View {
        ScrollView {
            if let exercise {
                VStack(spacing: 10) {
                    header(exercise)

                    if let setIndex = workingSetIndex {
                        WatchSetLogView(exerciseIndex: active.currentExerciseIndex, setIndex: setIndex)
                    } else {
                        allDoneCard
                    }

                    setProgressList(exercise)
                    navButtons
                }
                .padding(.horizontal, 4)
            }
        }
        .navigationTitle(active.session?.name ?? "Workout")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    active.finish()
                } label: {
                    Image(systemName: "flag.checkered")
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { active.restTimer.isRunning },
            set: { if !$0 { active.restTimer.skip() } }
        )) {
            WatchRestView(timer: active.restTimer)
        }
    }

    private func header(_ exercise: SessionExercise) -> some View {
        VStack(spacing: 2) {
            Text(exercise.name)
                .font(.headline)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                Text("\(exercise.completedSets)/\(exercise.sets.count) sets")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                WatchHeartRateChip(bpm: liveSession.heartRateBPM)
            }
        }
    }

    private var allDoneCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(.green)
            Text("Exercise complete")
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }

    private func setProgressList(_ exercise: SessionExercise) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { idx, set in
                HStack {
                    Text(set.isWarmup ? "Warmup" : "Set \(idx + 1)")
                        .font(.caption2)
                        .foregroundStyle(set.isWarmup ? .orange : .primary)
                    Spacer()
                    if exercise.usesWeight {
                        Text("\(Int(set.weight))×\(set.reps)").font(.caption2.monospacedDigit())
                    } else {
                        Text("\(set.reps)").font(.caption2.monospacedDigit())
                    }
                    Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.caption2)
                        .foregroundStyle(set.isCompleted ? .green : .secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    /// Live heart rate from the watch workout session; renders nothing when
    /// there's no reading (no session, no data yet, or permission denied).
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
            }
        }
    }

    private var navButtons: some View {
        HStack(spacing: 8) {
            Button {
                active.goToPreviousExercise()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(active.currentExerciseIndex == 0)

            Button {
                active.goToNextExercise()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(active.currentExerciseIndex >= (active.session?.exercises.count ?? 1) - 1)
        }
        .buttonStyle(.bordered)
        .padding(.top, 4)
    }
}
