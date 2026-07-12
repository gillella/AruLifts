import Foundation

/// Computes which plates to load per side of the bar for a target weight.
/// Pure and unit-testable; UI on both targets renders the result.
enum PlateCalculator {
    struct Result: Equatable {
        let targetWeight: Double
        /// Plates for ONE side, heaviest first.
        let platesPerSide: [Double]
        /// bar + 2 × side — what actually ends up on the bar.
        let achievedWeight: Double
        var isExact: Bool { abs(achievedWeight - targetWeight) < 0.001 }
    }

    /// Standard plate sets, heaviest first.
    static func defaultPlates(units: AppSettings.Units) -> [Double] {
        switch units {
        case .kg: return [25, 20, 15, 10, 5, 2.5, 1.25]
        case .lb: return [45, 35, 25, 10, 5, 2.5]
        }
    }

    /// Greedy per-side breakdown. Non-loadable targets return the closest
    /// achievable weight at or below the target (never more than asked).
    /// Targets at or below the bar load nothing and achieve the bar weight.
    static func plates(target: Double, bar: Double, available: [Double]) -> Result {
        guard target > bar, bar >= 0 else {
            return Result(targetWeight: target, platesPerSide: [], achievedWeight: bar)
        }
        var remaining = (target - bar) / 2
        var side: [Double] = []
        for plate in available.filter({ $0 > 0 }).sorted(by: >) {
            while remaining >= plate - 0.001 {
                side.append(plate)
                remaining -= plate
            }
        }
        return Result(
            targetWeight: target,
            platesPerSide: side,
            achievedWeight: bar + 2 * side.reduce(0, +)
        )
    }
}
