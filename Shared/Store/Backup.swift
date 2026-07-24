import Foundation

/// Everything the app persists, bundled for manual backup/restore.
struct BackupPayload: Codable {
    var templates: [WorkoutTemplate]
    var history: [WorkoutSession]
    var customExercises: [Exercise]
    var favoriteExerciseIDs: Set<UUID>
    var bodyWeights: [BodyWeightEntry]
    var settings: AppSettings
    /// Format version for future migrations.
    var version: Int = 1

    init(
        templates: [WorkoutTemplate],
        history: [WorkoutSession],
        customExercises: [Exercise],
        favoriteExerciseIDs: Set<UUID> = [],
        bodyWeights: [BodyWeightEntry],
        settings: AppSettings
    ) {
        self.templates = templates
        self.history = history
        self.customExercises = customExercises
        self.favoriteExerciseIDs = favoriteExerciseIDs
        self.bodyWeights = bodyWeights
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        templates = try c.decodeIfPresent([WorkoutTemplate].self, forKey: .templates) ?? []
        history = try c.decodeIfPresent([WorkoutSession].self, forKey: .history) ?? []
        customExercises = try c.decodeIfPresent([Exercise].self, forKey: .customExercises) ?? []
        favoriteExerciseIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .favoriteExerciseIDs) ?? []
        bodyWeights = try c.decodeIfPresent([BodyWeightEntry].self, forKey: .bodyWeights) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }
}

enum Backup {
    static func encode(_ payload: BackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    static func decode(_ data: Data) throws -> BackupPayload {
        try JSONDecoder().decode(BackupPayload.self, from: data)
    }
}
