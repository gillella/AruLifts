import Foundation

#if canImport(SwiftUI)
import SwiftUI
#endif

/// High level grouping for a custom workout, e.g. "Upper Body".
enum WorkoutCategory: String, Codable, CaseIterable, Identifiable {
    case upperBody, lowerBody, arms, push, pull, legs, fullBody, core, cardio
    case stretching, recovery, custom

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
        case .stretching: return "Stretching"
        case .recovery: return "Recovery"
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
        case .stretching: return "figure.flexibility"
        case .recovery: return "sparkles"
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
        case .stretching: return "#00B4D8"
        case .recovery: return "#9D4EDD"
        case .custom: return "#7B8794"
        }
    }

    /// Muscle groups a workout of this category typically trains. Drives the
    /// "Suggested" section in the exercise picker. Empty = no suggestions.
    var suggestedMuscles: [MuscleGroup] {
        switch self {
        case .upperBody: return [.chest, .back, .shoulders, .biceps, .triceps, .forearms]
        case .lowerBody, .legs: return [.quads, .hamstrings, .glutes, .calves]
        case .push: return [.chest, .shoulders, .triceps]
        case .pull: return [.back, .biceps, .forearms]
        case .arms: return [.biceps, .triceps, .forearms]
        case .fullBody: return [.chest, .back, .shoulders, .quads, .hamstrings, .glutes, .core]
        case .core: return [.core]
        case .cardio: return [.cardio, .fullBody]
        case .stretching: return [.mobility]
        // Recovery (sauna/steam/bath) is captured as a separate recovery log in
        // the tracking flow, so it has no suggested exercises yet.
        case .recovery: return []
        case .custom: return []
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
    /// Target duration in seconds for time-based exercises (cardio, stretches).
    /// 0 for standard set/rep exercises. `> 0` marks this entry as timed.
    var durationSeconds: Int
    /// Auto-increase the weight after a fully successful session.
    var progressionEnabled: Bool
    /// Weight added on success. nil = unit-aware default (see `Progression`).
    var progressionIncrement: Double?
    /// Consecutive failed sessions; drives the auto deload (see `Progression`).
    var failureCount: Int

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        name: String,
        targetSets: Int = 3,
        targetReps: Int = 10,
        weight: Double = 0,
        restSeconds: Int = 180,
        durationSeconds: Int = 0,
        progressionEnabled: Bool = true,
        progressionIncrement: Double? = nil,
        failureCount: Int = 0
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.name = name
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.weight = weight
        self.restSeconds = restSeconds
        self.durationSeconds = durationSeconds
        self.progressionEnabled = progressionEnabled
        self.progressionIncrement = progressionIncrement
        self.failureCount = failureCount
    }

    /// Time-based entry (cardio/stretch) rather than sets × reps.
    var isTimed: Bool { durationSeconds > 0 }

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
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0
        progressionEnabled = try c.decodeIfPresent(Bool.self, forKey: .progressionEnabled) ?? true
        progressionIncrement = try c.decodeIfPresent(Double.self, forKey: .progressionIncrement)
        failureCount = try c.decodeIfPresent(Int.self, forKey: .failureCount) ?? 0
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

    /// Working sets across all set/rep exercises (timed entries don't count).
    var totalSets: Int { exercises.filter { !$0.isTimed }.reduce(0) { $0 + $1.targetSets } }
    var exerciseCount: Int { exercises.count }

    /// Estimated duration in minutes (work + rest + timed blocks, rough heuristic).
    var estimatedMinutes: Int {
        let restTotal = exercises.filter { !$0.isTimed }.reduce(0) { $0 + $1.targetSets * $1.restSeconds }
        let workTotal = totalSets * 40 // ~40s per working set
        let timedTotal = exercises.reduce(0) { $0 + $1.durationSeconds }
        return max(1, (restTotal + workTotal + timedTotal) / 60)
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
