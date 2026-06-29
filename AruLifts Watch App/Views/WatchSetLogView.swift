import SwiftUI

/// Card for the current working set: adjust weight/reps (Digital Crown via
/// Stepper) and complete the set, which starts the rest timer.
struct WatchSetLogView: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    let exerciseIndex: Int
    let setIndex: Int

    private var set: SetEntry? {
        guard let s = active.session,
              s.exercises.indices.contains(exerciseIndex),
              s.exercises[exerciseIndex].sets.indices.contains(setIndex) else { return nil }
        return s.exercises[exerciseIndex].sets[setIndex]
    }

    private var usesWeight: Bool {
        active.session?.exercises[safe: exerciseIndex]?.usesWeight ?? true
    }

    var body: some View {
        if let set {
            VStack(spacing: 8) {
                Text("Set \(setIndex + 1)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if usesWeight {
                    Stepper(value: Binding(
                        get: { set.weight },
                        set: { active.updateSet(exerciseIndex: exerciseIndex, setIndex: setIndex, weight: $0) }
                    ), in: 0...999, step: 2.5) {
                        VStack(spacing: 0) {
                            Text("\(weightString(set.weight))")
                                .font(.title3.monospacedDigit().bold())
                            Text("weight").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }

                Stepper(value: Binding(
                    get: { Double(set.reps) },
                    set: { active.updateSet(exerciseIndex: exerciseIndex, setIndex: setIndex, reps: Int($0)) }
                ), in: 0...100, step: 1) {
                    VStack(spacing: 0) {
                        Text("\(set.reps)")
                            .font(.title3.monospacedDigit().bold())
                        Text("reps").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }

                Button {
                    active.completeSet(exerciseIndex: exerciseIndex, setIndex: setIndex, autoStartRest: true, restAlerts: true)
                } label: {
                    Label("Complete Set", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(10)
            .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func weightString(_ w: Double) -> String {
        w == w.rounded() ? String(Int(w)) : String(format: "%.1f", w)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
