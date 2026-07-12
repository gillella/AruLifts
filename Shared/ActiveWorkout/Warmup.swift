import Foundation

/// StrongLifts-style warmup generation: empty bar 2×5, then ramped jumps
/// (40%×5, 60%×3, 80%×2) up to the working weight. Pure and testable.
enum Warmup {
    /// Standard olympic bar for the unit system.
    static func defaultBarWeight(units: AppSettings.Units) -> Double {
        units == .kg ? 20 : 45
    }

    /// Ramped warmup sets strictly below the working weight, flagged
    /// `isWarmup`. Empty when the working weight doesn't exceed the bar
    /// (nothing lighter to warm up with).
    static func sets(
        workingWeight: Double,
        units: AppSettings.Units,
        barWeight: Double? = nil,
        roundTo quantum: Double = 2.5
    ) -> [SetEntry] {
        let bar = barWeight ?? defaultBarWeight(units: units)
        guard workingWeight > bar, bar > 0 else { return [] }

        var plan: [(weight: Double, reps: Int)] = [(bar, 5), (bar, 5)]

        var lastWeight = bar
        for (fraction, reps) in [(0.4, 5), (0.6, 3), (0.8, 2)] {
            var w = workingWeight * fraction
            if quantum > 0 { w = (w / quantum).rounded() * quantum }
            // Keep the ramp strictly increasing and below the working weight.
            guard w > lastWeight, w < workingWeight else { continue }
            plan.append((w, reps))
            lastWeight = w
        }
        return plan.map { SetEntry(reps: $0.reps, weight: $0.weight, isWarmup: true) }
    }
}
