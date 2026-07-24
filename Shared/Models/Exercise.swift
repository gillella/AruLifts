import Foundation

/// A primary or secondary muscle that an exercise trains.
enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case chest, back, shoulders, biceps, triceps, forearms
    case quads, hamstrings, glutes, calves
    case core, fullBody, cardio, mobility

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
        case .mobility: return "Mobility"
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

    /// Name of a bundled still form illustration in the asset catalogue.
    /// Used when no local/remote demo clip is available.
    var demoImageName: String?
    /// Public coaching video opened externally (for example, in YouTube).
    /// This is intentionally separate from `videoURL`, which must be a directly
    /// playable media file for AVPlayer.
    var techniqueVideoURL: URL?
    /// Name of a full-fledged technique video bundled locally (e.g., in ResourceVideos).
    var localTechniqueVideoName: String?

    /// SF Symbol used as an illustrative placeholder when no video exists.
    var symbol: String

    /// Whether this exercise is tracked with weight (true) or reps/time only.
    var usesWeight: Bool

    /// Tracked by elapsed time rather than reps/sets — cardio machines
    /// (treadmill, bike…) and stretches. Timed exercises carry a target
    /// duration on the template (`TemplateExercise.durationSeconds`).
    var isTimed: Bool

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
        demoImageName: String? = nil,
        techniqueVideoURL: URL? = nil,
        localTechniqueVideoName: String? = nil,
        symbol: String = "figure.strengthtraining.traditional",
        usesWeight: Bool = true,
        isTimed: Bool = false
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
        self.demoImageName = demoImageName
        self.techniqueVideoURL = techniqueVideoURL
        self.localTechniqueVideoName = localTechniqueVideoName
        self.symbol = symbol
        self.usesWeight = usesWeight
        self.isTimed = isTimed
    }

    // Manual decode so custom exercises saved before `isTimed` existed still
    // load (a non-optional Bool would otherwise throw on the missing key; the
    // Optional fields above already decode as absent-is-nil automatically).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        primaryMuscle = try c.decode(MuscleGroup.self, forKey: .primaryMuscle)
        secondaryMuscles = try c.decode([MuscleGroup].self, forKey: .secondaryMuscles)
        equipment = try c.decode(Equipment.self, forKey: .equipment)
        instructions = try c.decode([String].self, forKey: .instructions)
        tips = try c.decode([String].self, forKey: .tips)
        videoName = try c.decodeIfPresent(String.self, forKey: .videoName)
        videoURL = try c.decodeIfPresent(URL.self, forKey: .videoURL)
        demoImageName = try c.decodeIfPresent(String.self, forKey: .demoImageName)
        techniqueVideoURL = try c.decodeIfPresent(URL.self, forKey: .techniqueVideoURL)
        localTechniqueVideoName = try c.decodeIfPresent(String.self, forKey: .localTechniqueVideoName)
        symbol = try c.decode(String.self, forKey: .symbol)
        usesWeight = try c.decode(Bool.self, forKey: .usesWeight)
        isTimed = try c.decodeIfPresent(Bool.self, forKey: .isTimed) ?? false
    }
}
