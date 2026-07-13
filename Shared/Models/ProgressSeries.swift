import Foundation

/// A dated data point for progress charts.
struct ProgressPoint: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let value: Double
}

/// Pure chart-series extraction from workout history. Kept UI-free so the
/// rules (completed work sets only, finished sessions only) are testable.
enum ProgressSeries {
    /// Heaviest completed work-set weight per finished session, oldest first.
    static func exerciseMaxWeight(history: [WorkoutSession], exerciseID: UUID, since: Date?) -> [ProgressPoint] {
        history
            .filter { $0.isFinished && inRange($0, since: since) }
            .compactMap { session -> ProgressPoint? in
                guard let ex = session.exercises.first(where: { $0.exerciseID == exerciseID }) else { return nil }
                let best = ex.sets
                    .filter { $0.isCompleted && !$0.isWarmup }
                    .map(\.weight)
                    .max()
                guard let best, best > 0 else { return nil }
                return ProgressPoint(date: session.startedAt, value: best)
            }
            .sorted { $0.date < $1.date }
    }

    /// Total completed work-set volume per finished session, oldest first.
    static func totalVolume(history: [WorkoutSession], since: Date?) -> [ProgressPoint] {
        history
            .filter { $0.isFinished && inRange($0, since: since) }
            .compactMap { session in
                let volume = session.totalVolume
                guard volume > 0 else { return nil }
                return ProgressPoint(date: session.startedAt, value: volume)
            }
            .sorted { $0.date < $1.date }
    }

    /// Exercises that appear in history with at least one completed work set,
    /// (id, name) pairs sorted by name — drives the exercise picker.
    static func trackedExercises(history: [WorkoutSession]) -> [(id: UUID, name: String)] {
        var seen: [UUID: String] = [:]
        for session in history where session.isFinished {
            for ex in session.exercises
            where ex.usesWeight && ex.sets.contains(where: { $0.isCompleted && !$0.isWarmup }) {
                seen[ex.exerciseID] = ex.name
            }
        }
        return seen.map { (id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }

    private static func inRange(_ session: WorkoutSession, since: Date?) -> Bool {
        guard let since else { return true }
        return session.startedAt >= since
    }
}
