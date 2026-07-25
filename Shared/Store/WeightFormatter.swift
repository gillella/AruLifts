import Foundation

/// Consistent display formatting for a stored workout weight and its unit.
/// Values are rounded to the precision users can enter (one decimal place),
/// while whole values avoid a distracting trailing `.0`.
enum WeightFormatter {
    static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }

    static func string(_ value: Double, units: AppSettings.Units) -> String {
        "\(number(value)) \(units.label)"
    }
}
