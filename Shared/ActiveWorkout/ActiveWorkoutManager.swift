import Foundation
import Combine

#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

/// Drives a live workout: which exercise/set is current, completing sets,
/// the rest timer, and keeping the counterpart device in sync. Instantiated on
/// both the phone and the watch.
@MainActor
final class ActiveWorkoutManager: ObservableObject {
    @Published private(set) var session: WorkoutSession?
    /// Index of the exercise the user is currently working through.
    @Published var currentExerciseIndex: Int = 0

    let restTimer = RestTimerManager()

    private let connectivity = ConnectivityManager.shared
    private var cancellables = Set<AnyCancellable>()
    /// Suppresses re-broadcasting while we apply a sync from the other device.
    private var applyingRemote = false

    /// Called on the phone when a session finishes, so it can be stored.
    /// The Bool is true when the watch already saved the workout to Apple
    /// Health via its live session, so the phone must not save a duplicate.
    var onFinish: ((WorkoutSession, _ healthAlreadySaved: Bool) -> Void)?

    var isActive: Bool { session != nil }

    init() {
        // Re-publish rest-timer changes so views observing this manager update
        // when the timer starts/ticks/stops (e.g. to show/hide the rest UI).
        restTimer.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Receive sessions/ends pushed from the counterpart device.
        connectivity.$receivedSession
            .compactMap { $0 }
            .sink { [weak self] incoming in self?.applyRemote(incoming) }
            .store(in: &cancellables)

        connectivity.$endEvent
            .compactMap { $0 }
            .sink { [weak self] event in self?.handleRemoteEnd(event) }
            .store(in: &cancellables)
    }

    private func handleRemoteEnd(_ event: EndEvent) {
        guard session?.id == event.id else { return }
        if event.finished, var finished = session {
            finished.finishedAt = Date()
            onFinish?(finished, event.healthSaved)   // only the phone sets onFinish, so it records.
        }
        #if os(watchOS)
        // The phone ended the workout and owns the Health entry; drop any
        // live session without saving so Health doesn't get a duplicate.
        WatchWorkoutSession.shared.discard()
        #endif
        session = nil
        restTimer.stop()
    }

    // MARK: - Lifecycle

    func start(_ newSession: WorkoutSession, broadcast: Bool = true) {
        session = newSession
        currentExerciseIndex = 0
        restTimer.stop()
        if broadcast { connectivity.sendStart(newSession) }
        #if os(watchOS)
        // Watch-initiated workout: run a real HKWorkoutSession so the app
        // stays alive through rest and the workout earns activity-ring credit.
        Task { await WatchWorkoutSession.shared.start() }
        #endif
    }

    func cancel() {
        guard let id = session?.id else { return }
        connectivity.sendEnd(id, finished: false)
        #if os(watchOS)
        WatchWorkoutSession.shared.discard()
        #endif
        session = nil
        restTimer.stop()
    }

    func finish() {
        guard var finished = session else { return }
        finished.finishedAt = Date()
        onFinish?(finished, false)                // records on the phone
        #if os(watchOS)
        // Save via the live session; tell the phone so it skips its own save.
        let healthSaved = WatchWorkoutSession.shared.isRunning
        Task { await WatchWorkoutSession.shared.finish() }
        connectivity.sendEnd(finished.id, finished: true, healthSaved: healthSaved)
        #else
        connectivity.sendEnd(finished.id, finished: true)
        #endif
        restTimer.stop()
        session = nil
    }

    // MARK: - Editing sets

    var currentExercise: SessionExercise? {
        guard let session, session.exercises.indices.contains(currentExerciseIndex) else { return nil }
        return session.exercises[currentExerciseIndex]
    }

    func completeSet(exerciseIndex: Int, setIndex: Int, autoStartRest: Bool, restAlerts: Bool) {
        guard var session else { return }
        guard session.exercises.indices.contains(exerciseIndex),
              session.exercises[exerciseIndex].sets.indices.contains(setIndex) else { return }
        session.exercises[exerciseIndex].sets[setIndex].isCompleted.toggle()
        let nowComplete = session.exercises[exerciseIndex].sets[setIndex].isCompleted
        self.session = session
        playSelectionHaptic()

        if nowComplete && autoStartRest {
            let rest = session.exercises[exerciseIndex].restSeconds
            restTimer.start(seconds: rest, alertsEnabled: restAlerts)
        }
        broadcast()
    }

    func updateSet(exerciseIndex: Int, setIndex: Int, reps: Int? = nil, weight: Double? = nil) {
        guard var session else { return }
        guard session.exercises.indices.contains(exerciseIndex),
              session.exercises[exerciseIndex].sets.indices.contains(setIndex) else { return }
        if let reps { session.exercises[exerciseIndex].sets[setIndex].reps = max(0, reps) }
        if let weight { session.exercises[exerciseIndex].sets[setIndex].weight = max(0, weight) }
        self.session = session
        broadcast()
    }

    func addSet(exerciseIndex: Int) {
        guard var session, session.exercises.indices.contains(exerciseIndex) else { return }
        let template = session.exercises[exerciseIndex].sets.last
        let new = SetEntry(reps: template?.reps ?? 10, weight: template?.weight ?? 0)
        session.exercises[exerciseIndex].sets.append(new)
        self.session = session
        broadcast()
    }

    func removeSet(exerciseIndex: Int, setIndex: Int) {
        guard var session, session.exercises.indices.contains(exerciseIndex),
              session.exercises[exerciseIndex].sets.indices.contains(setIndex) else { return }
        session.exercises[exerciseIndex].sets.remove(at: setIndex)
        self.session = session
        broadcast()
    }

    func goToNextExercise() {
        guard let session else { return }
        if currentExerciseIndex < session.exercises.count - 1 {
            currentExerciseIndex += 1
        }
    }

    func goToPreviousExercise() {
        if currentExerciseIndex > 0 { currentExerciseIndex -= 1 }
    }

    // MARK: - Sync

    private func broadcast() {
        guard !applyingRemote, let session else { return }
        connectivity.sendSync(session)
    }

    private func applyRemote(_ incoming: WorkoutSession) {
        applyingRemote = true
        if session?.id == incoming.id || session == nil {
            session = incoming
            if currentExerciseIndex >= incoming.exercises.count {
                currentExerciseIndex = max(0, incoming.exercises.count - 1)
            }
        }
        applyingRemote = false
    }

    private func playSelectionHaptic() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }
}
