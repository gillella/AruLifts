import Foundation

/// Crash-safe local storage for the active replicated workout and its outbox.
///
/// Every accepted mutation is persisted here before the UI publishes it or the
/// transport attempts delivery. That ordering lets a Watch workout continue
/// offline and resume after the app is terminated.
final class ActiveWorkoutRepository {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil, fileName: String = "active_workout_runtime.json") {
        let base = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        fileURL = base.appendingPathComponent(fileName)
    }

    func load() -> WorkoutRuntimeState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? decoder.decode(WorkoutRuntimeState.self, from: data) else {
            return WorkoutRuntimeState()
        }
        return state
    }

    @discardableResult
    func save(_ state: WorkoutRuntimeState) -> Bool {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            print("ActiveWorkoutRepository: save failed: \(error.localizedDescription)")
            return false
        }
    }

    func removeFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
