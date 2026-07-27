import Foundation

#if canImport(SwiftUI)
import SwiftUI
#endif

/// The 7 distinct sequential phases of a complete gym session routine.
enum GymSessionPhaseType: String, Codable, CaseIterable, Identifiable {
    case preCardio
    case warmupStretches
    case mainStrength
    case postStretching
    case coreWork
    case saunaRecovery
    case steamRecovery

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .preCardio: return "Pre-Workout Cardio"
        case .warmupStretches: return "Dynamic Warm-Up Stretches"
        case .mainStrength: return "Main Strength Training"
        case .postStretching: return "Post-Workout Cool-Down"
        case .coreWork: return "Abdominal / Mat Core Work"
        case .saunaRecovery: return "Sauna Recovery"
        case .steamRecovery: return "Steam Room Recovery"
        }
    }

    var shortName: String {
        switch self {
        case .preCardio: return "Pre Cardio"
        case .warmupStretches: return "Warm-Up"
        case .mainStrength: return "Strength"
        case .postStretching: return "Post Stretch"
        case .coreWork: return "Core"
        case .saunaRecovery: return "Sauna"
        case .steamRecovery: return "Steam"
        }
    }

    var iconSymbol: String {
        switch self {
        case .preCardio: return "figure.run"
        case .warmupStretches: return "figure.flexibility"
        case .mainStrength: return "figure.strengthtraining.traditional"
        case .postStretching: return "figure.mind.and.body"
        case .coreWork: return "figure.core.training"
        case .saunaRecovery: return "flame.fill"
        case .steamRecovery: return "cloud.fog.fill"
        }
    }

    var tintHex: String {
        switch self {
        case .preCardio: return "#EF476F"
        case .warmupStretches: return "#00B4D8"
        case .mainStrength: return "#FF6B35"
        case .postStretching: return "#9D4EDD"
        case .coreWork: return "#FFBE0B"
        case .saunaRecovery: return "#FF9F1C"
        case .steamRecovery: return "#2EC4B6"
        }
    }

    var isTimed: Bool {
        switch self {
        case .preCardio, .warmupStretches, .postStretching, .saunaRecovery, .steamRecovery:
            return true
        case .mainStrength, .coreWork:
            return false
        }
    }
}

#if canImport(SwiftUI)
extension GymSessionPhaseType {
    var color: Color { Color(hex: tintHex) }
}
#endif

/// A phase entry in a customizable `GymSessionRoutine`.
struct GymSessionRoutinePhase: Identifiable, Codable, Hashable {
    var id: UUID
    var phaseType: GymSessionPhaseType
    var isEnabled: Bool
    var name: String
    var durationSeconds: Int
    var templateID: UUID?
    var exerciseNames: [String]
    var notes: String

    init(
        id: UUID = UUID(),
        phaseType: GymSessionPhaseType,
        isEnabled: Bool = true,
        name: String? = nil,
        durationSeconds: Int = 0,
        templateID: UUID? = nil,
        exerciseNames: [String] = [],
        notes: String = ""
    ) {
        self.id = id
        self.phaseType = phaseType
        self.isEnabled = isEnabled
        self.name = name ?? phaseType.displayName
        self.durationSeconds = durationSeconds > 0 ? durationSeconds : Self.defaultDuration(for: phaseType)
        self.templateID = templateID
        self.exerciseNames = exerciseNames.isEmpty ? Self.defaultExercises(for: phaseType) : exerciseNames
        self.notes = notes
    }

    static func defaultDuration(for phaseType: GymSessionPhaseType) -> Int {
        switch phaseType {
        case .preCardio: return 900 // 15 min
        case .warmupStretches: return 300 // 5 min
        case .mainStrength: return 3600 // 60 min
        case .postStretching: return 900 // 15 min
        case .coreWork: return 900 // 15 min
        case .saunaRecovery: return 900 // 15 min
        case .steamRecovery: return 600 // 10 min
        }
    }

    static func defaultExercises(for phaseType: GymSessionPhaseType) -> [String] {
        switch phaseType {
        case .preCardio: return ["Elliptical", "Treadmill Incline", "Stair Climber"]
        case .warmupStretches: return ["Leg Swings", "Arm Circles", "Hip Mobility", "Thoracic Rotations"]
        case .mainStrength: return []
        case .postStretching: return ["Hamstring Stretch", "Chest Opener", "Quad Stretch", "Child's Pose"]
        case .coreWork: return ["Plank", "Ab Rollout", "Hanging Knee Raise", "Cable Crunch"]
        case .saunaRecovery: return ["Sauna Heat Therapy (Hydrate 500ml)"]
        case .steamRecovery: return ["Steam Room Session"]
        }
    }
}

/// A complete, multi-phase customizable gym visit routine model.
struct GymSessionRoutine: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var notes: String
    var phases: [GymSessionRoutinePhase]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String = "Complete Gym Visit",
        notes: String = "7-Phase structured workout & recovery routine",
        phases: [GymSessionRoutinePhase] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.phases = phases.isEmpty ? Self.defaultPhases() : phases
        self.createdAt = createdAt
    }

    static func defaultPhases(templateID: UUID? = nil) -> [GymSessionRoutinePhase] {
        [
            GymSessionRoutinePhase(phaseType: .preCardio, durationSeconds: 900, exerciseNames: ["Elliptical", "Treadmill Incline"]),
            GymSessionRoutinePhase(phaseType: .warmupStretches, durationSeconds: 300, exerciseNames: ["Leg Swings", "Arm Circles", "Hip Mobility"]),
            GymSessionRoutinePhase(phaseType: .mainStrength, durationSeconds: 3600, templateID: templateID),
            GymSessionRoutinePhase(phaseType: .postStretching, durationSeconds: 900, exerciseNames: ["Hamstring Stretch", "Chest Opener", "Child's Pose"]),
            GymSessionRoutinePhase(phaseType: .coreWork, durationSeconds: 900, exerciseNames: ["Plank", "Ab Rollout", "Hanging Knee Raise", "Cable Crunch"]),
            GymSessionRoutinePhase(phaseType: .saunaRecovery, durationSeconds: 900, notes: "Drink 500ml water before heat exposure"),
            GymSessionRoutinePhase(phaseType: .steamRecovery, durationSeconds: 600, notes: "Cool down gradually with deep breathing")
        ]
    }

    static func defaultCompleteGymVisit(templates: [WorkoutTemplate] = []) -> GymSessionRoutine {
        let firstTemplateID = templates.first?.id
        return GymSessionRoutine(
            name: "Complete Gym Visit",
            notes: "15m Cardio → 5m Warmup → Lifting → 15m Stretch → Core → Sauna → Steam",
            phases: defaultPhases(templateID: firstTemplateID)
        )
    }

    var enabledPhases: [GymSessionRoutinePhase] {
        phases.filter { $0.isEnabled }
    }

    var estimatedTotalMinutes: Int {
        enabledPhases.reduce(0) { $0 + ($1.durationSeconds / 60) }
    }
}

/// Active execution log state for a single phase inside a `WorkoutSession`.
struct GymSessionLogPhase: Identifiable, Codable, Hashable {
    var id: UUID
    var phaseType: GymSessionPhaseType
    var name: String
    var durationSeconds: Int
    var actualDurationSeconds: Int?
    var isCompleted: Bool
    var exerciseNames: [String]
    var notes: String

    init(
        id: UUID = UUID(),
        phaseType: GymSessionPhaseType,
        name: String,
        durationSeconds: Int = 0,
        actualDurationSeconds: Int? = nil,
        isCompleted: Bool = false,
        exerciseNames: [String] = [],
        notes: String = ""
    ) {
        self.id = id
        self.phaseType = phaseType
        self.name = name
        self.durationSeconds = durationSeconds
        self.actualDurationSeconds = actualDurationSeconds
        self.isCompleted = isCompleted
        self.exerciseNames = exerciseNames
        self.notes = notes
    }
}
