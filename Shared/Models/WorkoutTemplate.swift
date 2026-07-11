import Foundation

#if canImport(SwiftUI)
import SwiftUI
#endif

/// High level grouping for a custom workout, e.g. "Upper Body".
enum WorkoutCategory: String, Codable, CaseIterable, Identifiable {
    case upperBody, lowerBody, arms, push, pull, legs, fullBody, core, cardio, custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .upperBody: return "Upper Body"
        case .lowerBody: return "Lower Body"
        case .arms: return "Arms"
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        case .fullBody: return "Full Body"
        case .core: return "Core"
        case .cardio: return "Cardio"
        case .custom: return "Custom"
        }
    }

    var symbol: String {
        switch self {
        case .upperBody: return "figure.arms.open"
        case .lowerBody: return "figure.walk"
        case .arms: return "figure.strengthtraining.functional"
        case .push: return "arrow.up.circle.fill"
        case .pull: return "arrow.down.circle.fill"
        case .legs: return "figure.run"
        case .fullBody: return "figure.mixed.cardio"
        case .core: return "figure.core.training"
        case .cardio: return "heart.fill"
        case .custom: return "square.grid.2x2.fill"
        }
    }

    /// Hint used to tint UI. Returns a hex string so the type stays UI-agnostic
    /// for the shared/watch targets.
    var tintHex: String {
        switch self {
        case .upperBody: return "#FF6B35"
        case .lowerBody: return "#2EC4B6"
        case .arms: return "#E71D36"
        case .push: return "#FF9F1C"
        case .pull: return "#3A86FF"
        case .legs: return "#8338EC"
        case .fullBody: return "#06D6A0"
        case .core: return "#FFBE0B"
        case .cardio: return "#EF476F"
        case .custom: return "#7B8794"
        }
    }
}

/// An exercise as configured inside a workout template (target sets/reps/weight).
struct TemplateExercise: Identifiable, Codable, Hashable {
    var id: UUID
    var exerciseID: UUID
    var name: String
    var targetSets: Int
    var targetReps: Int
    var weight: Double
    /// Rest after each set, in seconds. Defaults to the app-wide rest if 0.
    var restSeconds: Int
    /// Auto-increase the weight after a fully successful session.
    var progressionEnabled: Bool
    /// Weight added on success. nil = unit-aware default (see `Progression`).
    var progressionIncrement: Double?

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        name: String,
        targetSets: Int = 3,
        targetReps: Int = 10,
        weight: Double = 0,
        restSeconds: Int = 180,
        progressionEnabled: Bool = true,
        progressionIncrement: Double? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.name = name
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.weight = weight
        self.restSeconds = restSeconds
        self.progressionEnabled = progressionEnabled
        self.progressionIncrement = progressionIncrement
    }

    // Manual decode so templates saved before progression existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        exerciseID = try c.decode(UUID.self, forKey: .exerciseID)
        name = try c.decode(String.self, forKey: .name)
        targetSets = try c.decode(Int.self, forKey: .targetSets)
        targetReps = try c.decode(Int.self, forKey: .targetReps)
        weight = try c.decode(Double.self, forKey: .weight)
        restSeconds = try c.decode(Int.self, forKey: .restSeconds)
        progressionEnabled = try c.decodeIfPresent(Bool.self, forKey: .progressionEnabled) ?? true
        progressionIncrement = try c.decodeIfPresent(Double.self, forKey: .progressionIncrement)
    }
}

/// A reusable, user-defined workout plan.
struct WorkoutTemplate: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var category: WorkoutCategory
    var exercises: [TemplateExercise]
    var notes: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        category: WorkoutCategory = .custom,
        exercises: [TemplateExercise] = [],
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.exercises = exercises
        self.notes = notes
        self.createdAt = createdAt
    }

    var totalSets: Int { exercises.reduce(0) { $0 + $1.targetSets } }
    var exerciseCount: Int { exercises.count }

    /// Estimated duration in minutes (work + rest, rough heuristic).
    var estimatedMinutes: Int {
        let restTotal = exercises.reduce(0) { $0 + $1.targetSets * $1.restSeconds }
        let workTotal = totalSets * 40 // ~40s per working set
        return max(1, (restTotal + workTotal) / 60)
    }
}

#if canImport(SwiftUI)
extension Color {
    /// Creates a Color from a "#RRGGBB" hex string. Falls back to gray.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}

extension WorkoutCategory {
    var color: Color { Color(hex: tintHex) }
}
#endif
