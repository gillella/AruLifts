import Foundation
import Combine

/// User-configurable settings.
struct AppSettings: Codable, Equatable {
    enum Units: String, Codable, CaseIterable, Identifiable {
        case kg, lb
        var id: String { rawValue }
        var label: String { rawValue.uppercased() }
        /// Kilograms per one display unit (lb → 0.4536).
        var kgPerUnit: Double { self == .kg ? 1 : 0.45359237 }
    }

    var units: Units = .kg
    /// Default rest between sets, in seconds. The user described ~3 minutes.
    var defaultRestSeconds: Int = 180
    /// Play a haptic/notification when the rest timer ends.
    var restAlertsEnabled: Bool = true
    /// Auto-start the rest timer when a set is completed.
    var autoStartRest: Bool = true
    /// Give an incomplete set longer recovery without making successful sets
    /// slower. Target reps are retained in the session for this comparison.
    var adaptiveRestEnabled: Bool = true
    /// Multiplier used after a set logged below its planned repetitions.
    var failedSetRestMultiplier: Double = 1.5
    /// Increment used by the +/- weight steppers.
    var weightIncrement: Double = 2.5
    /// Consecutive failed sessions before an exercise deloads.
    var deloadFailureThreshold: Int = 3
    /// Percent taken off the working weight on deload.
    var deloadPercent: Double = 10
    /// Prepend generated warmup sets when starting a workout.
    var warmupsEnabled: Bool = true
    /// Bar the warmup ramp starts from. nil = standard bar for the units.
    var barWeight: Double?
    /// Plates available in the gym. nil = standard set for the units.
    var plateSet: [Double]?

    init() {}

    // Manual decode so settings saved before new fields existed still load
    // (a plain memberwise decode would throw on the missing keys and
    // silently reset every setting to defaults).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        units = try c.decodeIfPresent(Units.self, forKey: .units) ?? .kg
        defaultRestSeconds = try c.decodeIfPresent(Int.self, forKey: .defaultRestSeconds) ?? 180
        restAlertsEnabled = try c.decodeIfPresent(Bool.self, forKey: .restAlertsEnabled) ?? true
        autoStartRest = try c.decodeIfPresent(Bool.self, forKey: .autoStartRest) ?? true
        adaptiveRestEnabled = try c.decodeIfPresent(Bool.self, forKey: .adaptiveRestEnabled) ?? true
        failedSetRestMultiplier = try c.decodeIfPresent(Double.self, forKey: .failedSetRestMultiplier) ?? 1.5
        weightIncrement = try c.decodeIfPresent(Double.self, forKey: .weightIncrement) ?? 2.5
        deloadFailureThreshold = try c.decodeIfPresent(Int.self, forKey: .deloadFailureThreshold) ?? 3
        deloadPercent = try c.decodeIfPresent(Double.self, forKey: .deloadPercent) ?? 10
        warmupsEnabled = try c.decodeIfPresent(Bool.self, forKey: .warmupsEnabled) ?? true
        barWeight = try c.decodeIfPresent(Double.self, forKey: .barWeight)
        plateSet = try c.decodeIfPresent([Double].self, forKey: .plateSet)
    }
}

/// Single source of truth for templates, history and settings. Persists to JSON
/// in the app's Documents directory. Shared by the iOS and watch targets (each
/// keeps its own copy; the live session is synced over `ConnectivityManager`).
@MainActor
final class WorkoutStore: ObservableObject {
    @Published var templates: [WorkoutTemplate] = []
    @Published var history: [WorkoutSession] = []
    @Published var customExercises: [Exercise] = []
    /// Weight bumps applied by the most recent finished session, for the
    /// "next time: X" UI. Not persisted — informational only.
    @Published var lastProgression: [ProgressionChange] = []
    /// Body-weight log, newest first. Canonical kilograms (see BodyWeightEntry).
    @Published var bodyWeights: [BodyWeightEntry] = []
    /// Records broken by the most recent finished session. Not persisted.
    @Published var lastPRs: [PRHighlight] = []
    @Published var settings: AppSettings = AppSettings() {
        didSet { saveSettings() }
    }

    private let templatesFile = "templates.json"
    private let historyFile = "history.json"
    private let exercisesFile = "custom_exercises.json"
    private let settingsFile = "settings.json"
    private let bodyWeightFile = "bodyweight.json"

    /// True once files live in the iCloud Drive container (iOS only).
    @Published private(set) var iCloudEnabled = false
    /// Where the JSON files live. Starts local; switches to the iCloud
    /// container after `resolveICloud()` migrates.
    private var storageDir: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    private var allFiles: [String] {
        [templatesFile, historyFile, exercisesFile, settingsFile, bodyWeightFile]
    }

    init() {
        load()
        #if os(iOS)
        resolveICloud()
        #endif
    }

    // MARK: - iCloud (iOS; watchOS has no iCloud Documents and stays local)

    #if os(iOS)
    /// The ubiquity check can be slow on first call, so it runs off-main.
    /// When the container exists: migrate local files that aren't there yet,
    /// switch storage, and reload (last writer wins across devices).
    private func resolveICloud() {
        Task { @MainActor [weak self] in
            guard let docs = await Self.ubiquityDocumentsDirectory() else { return }
            self?.adoptICloudDirectory(docs)
        }
    }

    /// Runs the slow ubiquity lookup off-main; returns nil when iCloud is unavailable.
    private static func ubiquityDocumentsDirectory() async -> URL? {
        await Task.detached(priority: .utility) {
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
            let docs = container.appendingPathComponent("Documents")
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            return docs
        }.value
    }

    private func adoptICloudDirectory(_ dir: URL) {
        let fm = FileManager.default
        for file in allFiles {
            let src = storageDir.appendingPathComponent(file)
            let dst = dir.appendingPathComponent(file)
            if fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) {
                try? fm.copyItem(at: src, to: dst)
            }
        }
        storageDir = dir
        iCloudEnabled = true
        load()
    }
    #endif

    // MARK: - Manual backup / restore

    /// Single-file JSON snapshot of everything, for the Settings export.
    func backupData() -> Data? {
        try? Backup.encode(BackupPayload(
            templates: templates,
            history: history,
            customExercises: customExercises,
            bodyWeights: bodyWeights,
            settings: settings
        ))
    }

    /// Replaces all data with the backup's contents (last writer wins).
    func restore(from data: Data) throws {
        let payload = try Backup.decode(data)
        templates = payload.templates
        history = payload.history
        customExercises = payload.customExercises
        bodyWeights = payload.bodyWeights
        settings = payload.settings
        saveTemplates(); saveHistory(); saveExercises(); saveBodyWeights()
        // settings saves via didSet
    }

    // MARK: - Combined exercise catalogue

    /// Library exercises plus any the user created, keyed by id.
    var exerciseIndex: [UUID: Exercise] {
        var dict = ExerciseLibrary.byID
        for ex in customExercises { dict[ex.id] = ex }
        return dict
    }

    var allExercises: [Exercise] {
        (ExerciseLibrary.all + customExercises).sorted { $0.name < $1.name }
    }

    func exercise(for id: UUID) -> Exercise? { exerciseIndex[id] }

    // MARK: - Templates

    func addTemplate(_ template: WorkoutTemplate) {
        templates.append(template)
        saveTemplates()
    }

    func updateTemplate(_ template: WorkoutTemplate) {
        guard let idx = templates.firstIndex(where: { $0.id == template.id }) else {
            addTemplate(template); return
        }
        templates[idx] = template
        saveTemplates()
    }

    func deleteTemplate(_ template: WorkoutTemplate) {
        templates.removeAll { $0.id == template.id }
        saveTemplates()
    }

    func deleteTemplates(at offsets: IndexSet) {
        templates.remove(atOffsets: offsets)
        saveTemplates()
    }

    // MARK: - Custom exercises

    func addCustomExercise(_ exercise: Exercise) {
        customExercises.append(exercise)
        saveExercises()
    }

    // MARK: - History

    func recordSession(_ session: WorkoutSession) {
        guard Self.shouldRecordSession(id: session.id, in: history) else { return }
        var finished = session
        if finished.finishedAt == nil { finished.finishedAt = Date() }
        // PRs compare against history BEFORE this session joins it.
        lastPRs = Records.newPRs(session: finished, priorHistory: history)
        history.insert(finished, at: 0)
        saveHistory()
        applyProgression(from: finished)
    }

    /// Pure duplicate guard kept separate so the history identity rule can be
    /// exercised without persistence or UI state.
    nonisolated static func shouldRecordSession(id: UUID, in history: [WorkoutSession]) -> Bool {
        !history.contains { $0.id == id }
    }

    /// StrongLifts-style auto progression: exercises where every target rep
    /// was completed get their template weight bumped for next session, and
    /// repeated failures trigger a deload. Failure counters live on the
    /// template, so this must run even when no weight changed.
    private func applyProgression(from session: WorkoutSession) {
        guard let templateID = session.templateID,
              let idx = templates.firstIndex(where: { $0.id == templateID }) else { return }
        let result = Progression.apply(
            session: session,
            to: templates[idx],
            units: settings.units,
            failureThreshold: settings.deloadFailureThreshold,
            deloadPercent: settings.deloadPercent
        )
        let countersChanged = result.template != templates[idx]
        guard countersChanged || !result.changes.isEmpty else { return }
        templates[idx] = result.template
        if !result.changes.isEmpty { lastProgression = result.changes }
        saveTemplates()
    }

    func deleteHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        saveHistory()
    }

    func updateSessionNotes(id: UUID, notes: String) {
        guard let idx = history.firstIndex(where: { $0.id == id }) else { return }
        history[idx].notes = notes
        saveHistory()
    }

    // MARK: - Body weight

    /// Logs a measurement (kilograms), keeps the list newest-first, and
    /// mirrors it to Apple Health on the phone.
    func logBodyWeight(kg: Double, date: Date = Date()) {
        guard kg > 0 else { return }
        bodyWeights.insert(BodyWeightEntry(date: date, weightKg: kg), at: 0)
        bodyWeights.sort { $0.date > $1.date }
        saveBodyWeights()
        #if os(iOS)
        Task { await HealthKitManager.shared.saveBodyMass(kg: kg, date: date) }
        #endif
    }

    func deleteBodyWeights(at offsets: IndexSet) {
        bodyWeights.remove(atOffsets: offsets)
        saveBodyWeights()
    }

    /// Most recent completed weight for an exercise, to prefill new sessions.
    func lastWeight(for exerciseID: UUID) -> Double? {
        for session in history {
            if let ex = session.exercises.first(where: { $0.exerciseID == exerciseID }),
               let set = ex.sets.last(where: { $0.isCompleted }) {
                return set.weight
            }
        }
        return nil
    }

    // MARK: - Persistence

    private func url(for file: String) -> URL {
        storageDir.appendingPathComponent(file)
    }

    private func load() {
        templates = decode([WorkoutTemplate].self, from: templatesFile) ?? []
        history = decode([WorkoutSession].self, from: historyFile) ?? []
        customExercises = decode([Exercise].self, from: exercisesFile) ?? []
        settings = decode(AppSettings.self, from: settingsFile) ?? AppSettings()
        bodyWeights = decode([BodyWeightEntry].self, from: bodyWeightFile) ?? []

        if templates.isEmpty {
            templates = ExerciseLibrary.defaultTemplates()
            saveTemplates()
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: file)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T, to file: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(for: file), options: .atomic)
    }

    private func saveTemplates() { encode(templates, to: templatesFile) }
    private func saveHistory() { encode(history, to: historyFile) }
    private func saveExercises() { encode(customExercises, to: exercisesFile) }
    private func saveSettings() { encode(settings, to: settingsFile) }
    private func saveBodyWeights() { encode(bodyWeights, to: bodyWeightFile) }
}
