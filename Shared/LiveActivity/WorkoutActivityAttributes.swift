import Foundation

#if os(iOS)
import ActivityKit

public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var currentExerciseName: String
        public var currentSetIndex: Int
        public var totalSets: Int
        public var weightText: String
        public var repsText: String
        public var restTimerEndDate: Date?
        public var restTimerDuration: TimeInterval?
        public var isResting: Bool
        public var isWorkoutPaused: Bool
        public var workoutStartDate: Date

        public init(
            currentExerciseName: String,
            currentSetIndex: Int,
            totalSets: Int,
            weightText: String,
            repsText: String,
            restTimerEndDate: Date? = nil,
            restTimerDuration: TimeInterval? = nil,
            isResting: Bool = false,
            isWorkoutPaused: Bool = false,
            workoutStartDate: Date = Date()
        ) {
            self.currentExerciseName = currentExerciseName
            self.currentSetIndex = currentSetIndex
            self.totalSets = totalSets
            self.weightText = weightText
            self.repsText = repsText
            self.restTimerEndDate = restTimerEndDate
            self.restTimerDuration = restTimerDuration
            self.isResting = isResting
            self.isWorkoutPaused = isWorkoutPaused
            self.workoutStartDate = workoutStartDate
        }
    }

    public var workoutTitle: String
    public var sessionID: String

    public init(workoutTitle: String, sessionID: String) {
        self.workoutTitle = workoutTitle
        self.sessionID = sessionID
    }
}
#endif
