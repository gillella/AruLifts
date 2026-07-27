import Foundation

#if os(iOS)
import AppIntents

struct CompleteSetIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Set"
    static var description: IntentDescription = "Logs the current active set."

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        if let manager = ActiveWorkoutManager.shared {
            manager.completeCurrentSet()
        }
        return .result()
    }
}

struct AddRestTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Add 30s Rest"
    static var description: IntentDescription = "Adds 30 seconds to the current rest timer."

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        if let manager = ActiveWorkoutManager.shared {
            manager.restTimer.add(seconds: 30)
        }
        return .result()
    }
}

struct SkipRestIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Rest"
    static var description: IntentDescription = "Skips the rest timer immediately."

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        if let manager = ActiveWorkoutManager.shared {
            manager.restTimer.skip()
        }
        return .result()
    }
}
#endif
