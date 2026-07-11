import Foundation
import Combine

/// User-configurable settings.
struct AppSettings: Codable, Equatable {
    enum Units: String, Codable, CaseIterable, Identifiable {
        case kg, lb
        var id: String { rawValue }
        var label: String { rawValue.uppercased() }
    }

    var units: Units = .kg
    /// Default rest between sets, in seconds. The user described ~3 minutes.
    var defaultRestSeconds: Int = 180
    /// Play a haptic/notification when the rest timer ends.
    var restAlertsEnabled: Bool = true
    /// Auto-start the rest timer when a set is completed.
    var autoStartRest: Bool = true
    /// Increment used by the +/- weight steppers.
    var weightIncrement: Double = 2.5
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
    @Published var settings: AppSettings = AppSettings() {
        didSet { saveSettings() }
    }

    private let templatesFile = "templates.json"
    private let historyFile = "history.json"
    private let exercisesFile = "custom_exercises.json"
    private let settingsFile = "settings.json"

    init() {
        load()
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
        var finished = session
        if finished.finishedAt == nil { finished.finishedAt = Date() }
        history.insert(finished, at: 0)
        saveHistory()
        applyProgression(from: finished)
    }

    /// StrongLifts-style auto progression: exercises where every target rep
    /// was completed get their template weight bumped for next session.
    private func applyProgression(from session: WorkoutSession) {
        guard let templateID = session.templateID,
              let idx = templates.firstIndex(where: { $0.id == templateID }) else { return }
        let result = Progression.apply(session: session, to: templates[idx], units: settings.units)
        guard !result.changes.isEmpty else { return }
        templates[idx] = result.template
        lastProgression = result.changes
        saveTemplates()
    }

    func deleteHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        saveHistory()
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
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(file)
    }

    private func load() {
        templates = decode([WorkoutTemplate].self, from: templatesFile) ?? []
        history = decode([WorkoutSession].self, from: historyFile) ?? []
        customExercises = decode([Exercise].self, from: exercisesFile) ?? []
        settings = decode(AppSettings.self, from: settingsFile) ?? AppSettings()

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
}
