import Foundation

#if os(iOS)
import ActivityKit
import OSLog

@MainActor
final class WorkoutLiveActivityManager {
    static let shared = WorkoutLiveActivityManager()
    private var currentActivity: Activity<WorkoutActivityAttributes>?
    private let logger = Logger(subsystem: "com.arulifts.app", category: "LiveActivity")

    private init() {}

    func startActivity(
        session: WorkoutSession,
        exerciseIndex: Int,
        restTimerEndDate: Date? = nil,
        restTimerDuration: TimeInterval? = nil,
        isResting: Bool = false,
        isWorkoutPaused: Bool = false
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if currentActivity != nil {
            endActivity()
        }

        let attributes = WorkoutActivityAttributes(
            workoutTitle: session.name,
            sessionID: session.id.uuidString
        )

        let initialContentState = makeContentState(
            session: session,
            exerciseIndex: exerciseIndex,
            restTimerEndDate: restTimerEndDate,
            restTimerDuration: restTimerDuration,
            isResting: isResting,
            isWorkoutPaused: isWorkoutPaused
        )

        let activityContent = ActivityContent(
            state: initialContentState,
            staleDate: nil
        )

        do {
            let activity = try Activity<WorkoutActivityAttributes>.request(
                attributes: attributes,
                content: activityContent,
                pushType: nil
            )
            self.currentActivity = activity
            logger.info("Live Activity requested for session: \(session.id)")
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    func updateActivity(
        session: WorkoutSession,
        exerciseIndex: Int,
        restTimerEndDate: Date? = nil,
        restTimerDuration: TimeInterval? = nil,
        isResting: Bool = false,
        isWorkoutPaused: Bool = false
    ) {
        guard let activity = currentActivity else {
            startActivity(
                session: session,
                exerciseIndex: exerciseIndex,
                restTimerEndDate: restTimerEndDate,
                restTimerDuration: restTimerDuration,
                isResting: isResting,
                isWorkoutPaused: isWorkoutPaused
            )
            return
        }

        let updatedState = makeContentState(
            session: session,
            exerciseIndex: exerciseIndex,
            restTimerEndDate: restTimerEndDate,
            restTimerDuration: restTimerDuration,
            isResting: isResting,
            isWorkoutPaused: isWorkoutPaused
        )

        let content = ActivityContent(state: updatedState, staleDate: nil)
        Task {
            await activity.update(content)
        }
    }

    func endActivity() {
        guard let activity = currentActivity else { return }
        let finalState = activity.content.state
        let content = ActivityContent(state: finalState, staleDate: nil)
        Task {
            await activity.end(content, dismissalPolicy: .immediate)
        }
        currentActivity = nil
    }

    private func makeContentState(
        session: WorkoutSession,
        exerciseIndex: Int,
        restTimerEndDate: Date? = nil,
        restTimerDuration: TimeInterval? = nil,
        isResting: Bool = false,
        isWorkoutPaused: Bool = false
    ) -> WorkoutActivityAttributes.ContentState {
        let validIndex = min(max(0, exerciseIndex), max(0, session.exercises.count - 1))
        let exercise = session.exercises.indices.contains(validIndex) ? session.exercises[validIndex] : nil
        let exerciseName = exercise?.name ?? "Workout"

        let completedSets = exercise?.sets.filter { $0.isCompleted }.count ?? 0
        let totalSets = exercise?.sets.count ?? 0
        let currentSetNumber = min(completedSets + 1, max(1, totalSets))

        var weightText = "--"
        var repsText = "--"
        if let exercise = exercise {
            let nextSetIndex = min(completedSets, max(0, exercise.sets.count - 1))
            if exercise.sets.indices.contains(nextSetIndex) {
                let set = exercise.sets[nextSetIndex]
                weightText = WeightFormatter.string(set.weight, units: .kg)
                repsText = exercise.usesWeight ? "\(set.reps) reps" : "\(set.reps)s"
            }
        }

        return WorkoutActivityAttributes.ContentState(
            currentExerciseName: exerciseName,
            currentSetIndex: currentSetNumber,
            totalSets: totalSets,
            weightText: weightText,
            repsText: repsText,
            restTimerEndDate: restTimerEndDate,
            restTimerDuration: restTimerDuration,
            isResting: isResting,
            isWorkoutPaused: isWorkoutPaused,
            workoutStartDate: session.startedAt
        )
    }
}
#endif
