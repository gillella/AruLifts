import SwiftUI

/// Secondary adjustment screen for the current working set. The primary
/// workout screen stays focused on one-tap completion; weight and reps live
/// here so they do not compete with that action.
struct WatchSetLogView: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    @Environment(\.dismiss) private var dismiss
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
                Text(set.isWarmup ? "Warmup" : "Set \(setIndex + 1)")
                    .font(.caption2)
                    .foregroundStyle(set.isWarmup ? .orange : .secondary)

                if usesWeight, set.weight > 0 {
                    Text(plateString(for: set.weight))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

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
                    dismiss()
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(10)
            .navigationTitle("Adjust Set")
        }
    }

    private func weightString(_ w: Double) -> String {
        w == w.rounded() ? String(Int(w)) : String(format: "%.1f", w)
    }

    /// Compact per-side plate list, e.g. "25·10·2.5 /side". Watch uses
    /// default bar/plates (settings live on the phone).
    private func plateString(for weight: Double) -> String {
        let result = PlateCalculator.plates(
            target: weight,
            bar: Warmup.defaultBarWeight(units: .kg),
            available: PlateCalculator.defaultPlates(units: .kg)
        )
        guard !result.platesPerSide.isEmpty else { return "empty bar" }
        let list = result.platesPerSide
            .map { $0 == $0.rounded() ? String(Int($0)) : String(format: "%.2g", $0) }
            .joined(separator: "·")
        return list + " /side"
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
