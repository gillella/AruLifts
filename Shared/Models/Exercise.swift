import Foundation

/// A primary or secondary muscle that an exercise trains.
enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case chest, back, shoulders, biceps, triceps, forearms
    case quads, hamstrings, glutes, calves
    case core, fullBody, cardio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .calves: return "Calves"
        case .core: return "Core"
        case .fullBody: return "Full Body"
        case .cardio: return "Cardio"
        }
    }
}

/// Equipment required to perform an exercise.
enum Equipment: String, Codable, CaseIterable, Identifiable {
    case barbell, dumbbell, machine, cable, bodyweight, kettlebell, band, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .barbell: return "Barbell"
        case .dumbbell: return "Dumbbell"
        case .machine: return "Machine"
        case .cable: return "Cable"
        case .bodyweight: return "Bodyweight"
        case .kettlebell: return "Kettlebell"
        case .band: return "Band"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .barbell: return "figure.strengthtraining.traditional"
        case .dumbbell: return "dumbbell.fill"
        case .machine: return "gearshape.fill"
        case .cable: return "cable.connector"
        case .bodyweight: return "figure.cooldown"
        case .kettlebell: return "figure.strengthtraining.functional"
        case .band: return "figure.flexibility"
        case .other: return "ellipsis.circle"
        }
    }
}

/// A single exercise definition. Stored in the exercise library and referenced
/// by workout templates and sessions.
struct Exercise: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var primaryMuscle: MuscleGroup
    var secondaryMuscles: [MuscleGroup]
    var equipment: Equipment

    /// Step-by-step form / posture cues shown on the exercise detail screen.
    var instructions: [String]
    /// Short coaching tips.
    var tips: [String]

    /// Name of a video bundled with the app (without extension, e.g. "squat").
    /// When present the detail screen plays it on a loop. See `Demo Videos`
    /// documentation for how to add clips.
    var videoName: String?
    /// Optional remote demo URL used when no bundled clip is available.
    var videoURL: URL?

    /// SF Symbol used as an illustrative placeholder when no video exists.
    var symbol: String

    /// Whether this exercise is tracked with weight (true) or reps/time only.
    var usesWeight: Bool

    init(
        id: UUID = UUID(),
        name: String,
        primaryMuscle: MuscleGroup,
        secondaryMuscles: [MuscleGroup] = [],
        equipment: Equipment,
        instructions: [String] = [],
        tips: [String] = [],
        videoName: String? = nil,
        videoURL: URL? = nil,
        symbol: String = "figure.strengthtraining.traditional",
        usesWeight: Bool = true
    ) {
        self.id = id
        self.name = name
        self.primaryMuscle = primaryMuscle
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.instructions = instructions
        self.tips = tips
        self.videoName = videoName
        self.videoURL = videoURL
        self.symbol = symbol
        self.usesWeight = usesWeight
    }
}
