import Foundation

#if canImport(SwiftUI)
import SwiftUI
#endif

/// Visual icons, colors, and presentation metadata for multi-phase routines, cardio, recovery, and strength exercises.
struct PhaseVisualHelper {
    static func iconSymbol(for exerciseName: String, phaseType: GymSessionPhaseType? = nil) -> String {
        let name = exerciseName.lowercased()
        if name.contains("elliptical") {
            return "figure.elliptical"
        } else if name.contains("treadmill") || name.contains("run") || name.contains("incline") {
            return "figure.run"
        } else if name.contains("stair") || name.contains("climber") {
            return "figure.stair.stepper"
        } else if name.contains("bike") || name.contains("cycle") {
            return "figure.indoor.cycle"
        } else if name.contains("sauna") || name.contains("heat") {
            return "flame.fill"
        } else if name.contains("steam") {
            return "cloud.fog.fill"
        } else if name.contains("stretch") || name.contains("mobility") || name.contains("pose") {
            return "figure.flexibility"
        } else if name.contains("plank") || name.contains("core") || name.contains("crunch") || name.contains("knee raise") {
            return "figure.core.training"
        } else if let phaseType {
            return phaseType.iconSymbol
        } else {
            return "figure.strengthtraining.traditional"
        }
    }
}
