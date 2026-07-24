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
    private struct LastSetCompletion {
        let sessionID: UUID
        let exerciseIndex: Int
        let setIndex: Int
        let expiresAt: Date
    }

    @Published private(set) var session: WorkoutSession?
    /// Index of the exercise the user is currently working through.
    @Published var currentExerciseIndex: Int = 0 {
        didSet {
            broadcast()
        }
    }
    /// Five-second safety window after a one-tap Watch completion.
    @Published private(set) var undoAvailableUntil: Date?
    @Published private(set) var isWorkoutPaused = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var owner: WorkoutDevice?
    @Published private(set) var canEdit = false
    @Published private(set) var syncStatus: WorkoutSyncStatus = .localOnly
    /// Plans persisted on the Watch for an offline workout start.
    @Published private(set) var watchPlans: [WatchStartableWorkout] = []
    /// Phone configuration cached alongside plans for Watch-owned execution.
    @Published private(set) var watchExecutionSettings = WatchExecutionSettings()

    let restTimer = RestTimerManager()

    private let connectivity = ConnectivityManager.shared
    private let syncCoordinator: WorkoutSyncCoordinator
    private var cancellables = Set<AnyCancellable>()
    /// Suppresses re-broadcasting while we apply a sync from the other device.
    private var applyingRemote = false
    /// Ids of sessions this device has ended (finished/cancelled or received a
    /// remote end for). A late "sync" for one of these — one that raced past
    /// its own "end" across the two transports — must not resurrect it. Session
    /// ids are fresh UUIDs, so a tombstoned id never legitimately returns.
    private var endedSessionIDs: Set<UUID> = []
    private var lastSetCompletion: LastSetCompletion?

    /// Called on the phone when a session finishes, so it can be stored.
    /// The Bool is true when the watch already saved the workout to Apple
    /// Health via its live session, so the phone must not save a duplicate.
    var onFinish: ((WorkoutSession, _ healthAlreadySaved: Bool) -> Void)?

    var isActive: Bool { session != nil }

    init() {
        #if os(watchOS)
        syncCoordinator = WorkoutSyncCoordinator(localDevice: .watch)
        #else
        syncCoordinator = WorkoutSyncCoordinator(localDevice: .phone)
        #endif

        syncCoordinator.transmit = { [weak self] envelope, transport in
            self?.connectivity.send(envelope, transport: transport)
        }
        syncCoordinator.onStateChange = { [weak self] state in
            self?.applyV2State(state)
        }

        // Re-publish rest-timer changes so views observing this manager update
        // when the timer starts/ticks/stops (e.g. to show/hide the rest UI).
        restTimer.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        restTimer.onStateChange = { [weak self] in
            guard let self else { return }
            self.broadcast()
        }

        // Receive sessions/ends pushed from the counterpart device.
        connectivity.$receivedSession
            .compactMap { $0 }
            .sink { [weak self] incoming in self?.applyRemote(incoming) }
            .store(in: &cancellables)

        connectivity.$receivedWorkoutEnvelope
            .compactMap { $0 }
            .sink { [weak self] envelope in self?.handleV2(envelope) }
            .store(in: &cancellables)

        connectivity.$endEvent
            .compactMap { $0 }
            .sink { [weak self] event in self?.handleRemoteEnd(event) }
            .store(in: &cancellables)

        connectivity.$isReachable
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in self?.syncCoordinator.flushOutbox() }
            .store(in: &cancellables)

        connectivity.$activationGeneration
            .dropFirst()
            .sink { [weak self] _ in self?.syncCoordinator.flushOutbox() }
            .store(in: &cancellables)

        applyV2State(syncCoordinator.state)
        syncCoordinator.flushOutbox()
    }

    private func handleRemoteEnd(_ event: EndEvent) {
        // Legacy decoding remains available for an old counterpart, but once a
        // v2 runtime exists it cannot bypass ownership/epoch/tombstone checks.
        guard syncCoordinator.replica == nil else { return }
        // Tombstone our own outgoing application context for this session id,
        // unconditionally and before the match check below. Application context
        // is per-direction (see ConnectivityManager.clearActiveContext): the
        // sender ending ITS context does nothing to the context THIS device is
        // broadcasting outward. Our last "sync"/"start" push may still be
        // sitting in our own outgoing context; if left there, a cold launch of
        // THIS device (its `activationDidCompleteWith` bootstrap read) would
        // replay it and resurrect the very session we just ended. Run this even
        // when `event.id` doesn't match our local session (the early-return
        // path below) — an end for a session we never applied locally (arrived
        // out of order, or this side was never active) must still clear our
        // own context, so a late/offline end can never leave a stale snapshot
        // that resurrects the session on a future relaunch.
        connectivity.clearActiveContext(event.id)
        endedSessionIDs.insert(event.id)

        guard session?.id == event.id else { return }
        if event.finished, let current = session {
            // Prefer the sender's embedded final snapshot (see EndEvent.session)
            // over our own local copy: "end" (message/userInfo transport) and the
            // last "sync" (application-context transport) have no ordering
            // guarantee relative to each other, so our local copy may be missing
            // an edit the sender made right before finishing (e.g. a last-second
            // rep-count tap before tapping Finish). Only fall back to the local
            // copy if the sender's snapshot failed to encode/decode.
            var finished = event.session ?? current
            // The sender already stamped `finishedAt` on its snapshot before
            // sending; only stamp it ourselves in the fallback case where we're
            // using our own (never-finished) local copy.
            if finished.finishedAt == nil { finished.finishedAt = Date() }
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
        applyingRemote = true
        session = newSession
        clearUndo()
        isWorkoutPaused = false
        isFinalizing = false
        currentExerciseIndex = 0
        restTimer.stop()
        applyingRemote = false
        if broadcast {
            _ = syncCoordinator.start(newSession)
        } else {
            // Used by previews/tests and legacy callers that explicitly opt out
            // of counterpart sync.
            owner = nil
            canEdit = true
            syncStatus = .localOnly
        }
        #if os(watchOS)
        // Watch-initiated workout: run a real HKWorkoutSession so the app
        // stays alive through rest and the workout earns activity-ring credit.
        Task { await WatchWorkoutSession.shared.start(sessionID: newSession.id) }
        #endif
    }

    func cancel() {
        guard canEdit, let current = session else { return }
        endedSessionIDs.insert(current.id)
        guard syncCoordinator.finalize(
            session: current,
            finished: false,
            healthSaved: false
        ) else { return }
        connectivity.clearActiveContext(current.id)
        #if os(watchOS)
        WatchWorkoutSession.shared.discard()
        #endif
        currentExerciseIndex = 0
        clearUndo()
        session = nil
        isWorkoutPaused = false
        restTimer.stop()
    }

    func finish() {
        guard canEdit, !isFinalizing, var finished = session else { return }
        finished.finishedAt = Date()
        endedSessionIDs.insert(finished.id)
        #if os(watchOS)
        // Do not optimistically claim Health was saved just because a live
        // session exists. Wait for HealthKit to return the persisted workout,
        // then let the phone fall back to its de-duplicating save when needed.
        session = finished
        isFinalizing = true
        Task {
            let result = await WatchWorkoutSession.shared.finish()
            guard syncCoordinator.finalize(
                session: finished,
                finished: true,
                healthSaved: result.isVerifiedSaved
            ) else {
                isFinalizing = false
                return
            }
            connectivity.clearActiveContext(finished.id)
            currentExerciseIndex = 0
            clearUndo()
            isWorkoutPaused = false
            restTimer.stop()
            session = nil
            isFinalizing = false
        }
        #else
        guard syncCoordinator.finalize(
            session: finished,
            finished: true,
            healthSaved: false
        ) else { return }
        onFinish?(finished, false)
        connectivity.clearActiveContext(finished.id)
        currentExerciseIndex = 0
        clearUndo()
        restTimer.stop()
        session = nil
        isFinalizing = false
        isWorkoutPaused = false
        #endif
    }

    // MARK: - Editing sets

    var currentExercise: SessionExercise? {
        guard let session, session.exercises.indices.contains(currentExerciseIndex) else { return nil }
        return session.exercises[currentExerciseIndex]
    }

    func completeSet(
        exerciseIndex: Int,
        setIndex: Int,
        autoStartRest: Bool,
        restAlerts: Bool,
        restAlertConfiguration: RestTimerAlertConfiguration = .default,
        adaptiveRest: Bool = true,
        failedSetRestMultiplier: Double = 1.5
    ) {
        guard canEdit, !isWorkoutPaused, var session else { return }
        guard session.exercises.indices.contains(exerciseIndex),
              session.exercises[exerciseIndex].sets.indices.contains(setIndex) else { return }
        session.exercises[exerciseIndex].sets[setIndex].isCompleted.toggle()
        let nowComplete = session.exercises[exerciseIndex].sets[setIndex].isCompleted
        if nowComplete {
            let expiresAt = Date().addingTimeInterval(5)
            lastSetCompletion = LastSetCompletion(
                sessionID: session.id,
                exerciseIndex: exerciseIndex,
                setIndex: setIndex,
                expiresAt: expiresAt
            )
            undoAvailableUntil = expiresAt
        } else {
            clearUndo()
        }
        self.session = session
        playSelectionHaptic()

        if nowComplete && autoStartRest {
            let completedSet = session.exercises[exerciseIndex].sets[setIndex]
            let baseRest = session.exercises[exerciseIndex].restSeconds
            let rest = adaptiveRest && completedSet.reps < completedSet.targetReps
                ? Int((Double(baseRest) * max(1, failedSetRestMultiplier)).rounded())
                : baseRest
            var configuration = restAlertConfiguration
            configuration.alertsEnabled = restAlerts
            restTimer.start(seconds: rest, configuration: configuration)
        }
        broadcast()
    }

    /// Reverts the most recent one-tap completion during its five-second
    /// safety window. The just-started rest is stopped so the user returns to
    /// the corrected working set immediately.
    @discardableResult
    func undoLastSetCompletion(now: Date = Date()) -> Bool {
        guard canEdit,
              let last = lastSetCompletion,
              now <= last.expiresAt,
              var session,
              session.id == last.sessionID,
              session.exercises.indices.contains(last.exerciseIndex),
              session.exercises[last.exerciseIndex].sets.indices.contains(last.setIndex),
              session.exercises[last.exerciseIndex].sets[last.setIndex].isCompleted else {
            clearUndo()
            return false
        }
        session.exercises[last.exerciseIndex].sets[last.setIndex].isCompleted = false
        self.session = session
        restTimer.stop()
        clearUndo()
        playSelectionHaptic()
        broadcast()
        return true
    }

    var canUndoLastSetCompletion: Bool {
        guard let expiry = undoAvailableUntil else { return false }
        return Date() <= expiry
    }

    func updateSet(exerciseIndex: Int, setIndex: Int, reps: Int? = nil, weight: Double? = nil) {
        guard canEdit, !isWorkoutPaused, var session else { return }
        guard session.exercises.indices.contains(exerciseIndex),
              session.exercises[exerciseIndex].sets.indices.contains(setIndex) else { return }
        if let reps { session.exercises[exerciseIndex].sets[setIndex].reps = max(0, reps) }
        if let weight { session.exercises[exerciseIndex].sets[setIndex].weight = max(0, weight) }
        self.session = session
        broadcast()
    }

    func addSet(exerciseIndex: Int) {
        guard canEdit, var session, session.exercises.indices.contains(exerciseIndex) else { return }
        let template = session.exercises[exerciseIndex].sets.last
        let new = SetEntry(reps: template?.reps ?? 10, weight: template?.weight ?? 0)
        session.exercises[exerciseIndex].sets.append(new)
        self.session = session
        broadcast()
    }

    func removeSet(exerciseIndex: Int, setIndex: Int) {
        guard canEdit, var session, session.exercises.indices.contains(exerciseIndex),
              session.exercises[exerciseIndex].sets.indices.contains(setIndex) else { return }
        session.exercises[exerciseIndex].sets.remove(at: setIndex)
        self.session = session
        broadcast()
    }

    func updateNotes(_ text: String) {
        guard canEdit, var session else { return }
        session.notes = text
        self.session = session
        broadcast()
    }

    func toggleWorkoutPause() {
        guard canEdit, session != nil else { return }
        isWorkoutPaused.toggle()
        if isWorkoutPaused {
            restTimer.pause()
        } else {
            restTimer.resume()
        }
        playSelectionHaptic()
        broadcast()
    }

    func addRest(seconds: Int) {
        guard canEdit, !isWorkoutPaused else { return }
        restTimer.add(seconds: seconds)
    }

    func toggleRestPause() {
        guard canEdit, !isWorkoutPaused else { return }
        if restTimer.isPaused { restTimer.resume() } else { restTimer.pause() }
    }

    func resetRest() {
        guard canEdit, !isWorkoutPaused else { return }
        restTimer.reset()
    }

    func skipRest() {
        guard canEdit, !isWorkoutPaused else { return }
        restTimer.skip()
    }

    func goToNextExercise() {
        guard canEdit, let session else { return }
        if currentExerciseIndex < session.exercises.count - 1 {
            currentExerciseIndex += 1
        }
    }

    func goToPreviousExercise() {
        if canEdit && currentExerciseIndex > 0 { currentExerciseIndex -= 1 }
    }

    /// The phone remains a read-only mirror until the Watch durably accepts
    /// this explicit ownership transfer.
    func requestPhoneTakeover() {
        #if os(iOS)
        _ = syncCoordinator.requestTakeover()
        #endif
    }

    #if os(iOS)
    /// Rebuilds the Watch's offline-start cache from the phone's authoritative
    /// templates. Revisions make a delayed old cache harmless.
    func updateWatchPlanCache(
        templates: [WorkoutTemplate],
        library: [UUID: Exercise],
        settings: AppSettings
    ) {
        let workouts = templates.map {
            WatchStartableWorkout(template: $0, library: library, settings: settings)
        }
        let cache = (syncCoordinator.watchPlanCache ?? WatchPlanCache()).advanced(
            workouts: workouts,
            executionSettings: WatchExecutionSettings(settings: settings)
        )
        _ = syncCoordinator.updateWatchPlanCache(cache)
    }
    #endif

    #if os(watchOS)
    func startCachedPlan(_ plan: WatchStartableWorkout) {
        guard !isActive else { return }
        watchExecutionSettings = syncCoordinator.watchPlanCache?.executionSettings
            ?? WatchExecutionSettings()
        start(plan.makeFreshSession())
    }
    #endif

    // MARK: - Sync

    private func broadcast() {
        guard !applyingRemote, let session else { return }
        let rest: RestTimerSnapshot?
        if let endDate = restTimer.endDate {
            rest = RestTimerSnapshot(endDate: endDate, totalSeconds: restTimer.totalSeconds, alertConfiguration: restTimer.alertConfiguration)
        } else if restTimer.isPaused, restTimer.secondsRemaining > 0 {
            // `endDate` is retained for wire compatibility only while paused;
            // receivers use pausedRemainingSeconds rather than this value.
            rest = RestTimerSnapshot(
                endDate: Date(), totalSeconds: restTimer.totalSeconds,
                pausedRemainingSeconds: restTimer.secondsRemaining,
                alertConfiguration: restTimer.alertConfiguration
            )
        } else {
            rest = nil
        }
        _ = syncCoordinator.mutate(
            session: session,
            currentExerciseIndex: currentExerciseIndex,
            restTimer: rest,
            isWorkoutPaused: isWorkoutPaused
        )
    }

    private func applyRemote(_ incoming: WorkoutSession) {
        // Once v2 has durable state, legacy snapshots remain decodable but
        // cannot bypass v2 ownership and revision checks.
        guard syncCoordinator.replica == nil else { return }
        // A "sync" for a session we already ended must never bring it back
        // (see endedSessionIDs) — this is the watch "revert to a discarded
        // workout" bug: an in-flight sync landing just after the end.
        guard !endedSessionIDs.contains(incoming.id) else { return }
        applyingRemote = true
        // Adopt the incoming session when it's an update to the one we're
        // showing, the first session we've seen, OR a *newer* session than our
        // current one. The newer-wins rule lets a freshly started workout take
        // over a device still displaying an older session (e.g. the phone
        // starts a new workout while the watch lingers on a previous one),
        // while an out-of-order sync for an older session can't stomp a newer
        // active one.
        let supersedes = incoming.startedAt > (session?.startedAt ?? .distantPast)
        if session?.id == incoming.id || session == nil || supersedes {
            #if os(watchOS)
            let wasNil = (session == nil)
            #endif

            // Reset currentExerciseIndex to 0 if starting a new session (was nil or different id)
            if session?.id != incoming.id {
                currentExerciseIndex = 0
                isWorkoutPaused = false
            }

            // Sync exercise index if present in connectivity
            if let remoteIndex = connectivity.receivedExerciseIndex,
               incoming.exercises.indices.contains(remoteIndex) {
                currentExerciseIndex = remoteIndex
            }

            // Sync rest timer state
            if let newEndDate = connectivity.receivedRestTimerEndDate,
               let total = connectivity.receivedRestTimerTotalSeconds {
                let remaining = Int(ceil(newEndDate.timeIntervalSinceNow))
                if remaining > 0 {
                    if restTimer.endDate != newEndDate {
                restTimer.sync(endDate: newEndDate, totalSeconds: total)
                    }
                } else {
                    restTimer.stop()
                }
            } else {
                restTimer.stop()
            }

            session = incoming
            clearUndo()
            if currentExerciseIndex >= incoming.exercises.count {
                currentExerciseIndex = max(0, incoming.exercises.count - 1)
            }
            #if os(watchOS)
            if wasNil {
                // Phone-initiated workout mirrored on watch: run HKWorkoutSession
                // so watch app stays alive, reads heart rate, and plays haptics.
                Task { await WatchWorkoutSession.shared.start(sessionID: incoming.id) }
            }
            #endif
        }
        applyingRemote = false
    }

    private func handleV2(_ envelope: WorkoutMessageEnvelope) {
        let finalization = envelope.kind == .tombstone
            ? try? envelope.decodePayload(WorkoutFinalization.self)
            : nil
        let result = syncCoordinator.receive(envelope)
        guard result == .applied, let finalization else { return }

        endedSessionIDs.insert(finalization.tombstone.sessionID)
        connectivity.clearActiveContext(finalization.tombstone.sessionID)
        if finalization.tombstone.finished {
            onFinish?(finalization.finalSession, finalization.healthSaved)
        }
        #if os(watchOS)
        if envelope.sender == .phone {
            WatchWorkoutSession.shared.discard()
        }
        #endif
        clearUndo()
        isWorkoutPaused = false
        isFinalizing = false
        restTimer.stop()
        session = nil
    }

    /// Publishes a single accepted/persisted replica to the UI. This is the
    /// only v2 path that changes session/index/timer state.
    private func applyV2State(_ state: WorkoutRuntimeState) {
        owner = state.activeReplica?.owner
        canEdit = syncCoordinator.canEdit
        syncStatus = state.syncStatus
        watchPlans = state.watchPlanCache?.workouts ?? []
        if let cachedSettings = state.watchPlanCache?.executionSettings {
            watchExecutionSettings = cachedSettings
        }
        guard let replica = state.activeReplica else { return }

        let wasNil = session == nil
        applyingRemote = true
        session = replica.session
        currentExerciseIndex = replica.session.exercises.indices.contains(
            replica.currentExerciseIndex
        ) ? replica.currentExerciseIndex : max(0, replica.session.exercises.count - 1)
        isWorkoutPaused = replica.isWorkoutPaused
        if let timer = replica.restTimer, let pausedRemaining = timer.pausedRemainingSeconds {
            restTimer.syncPaused(
                remainingSeconds: pausedRemaining,
                totalSeconds: timer.totalSeconds,
                configuration: timer.alertConfiguration
            )
        } else if let timer = replica.restTimer, timer.endDate > Date() {
            restTimer.sync(endDate: timer.endDate, totalSeconds: timer.totalSeconds, configuration: timer.alertConfiguration)
        } else {
            restTimer.stop()
        }
        clearUndo()
        applyingRemote = false

        #if os(watchOS)
        if wasNil {
            Task { await WatchWorkoutSession.shared.start(sessionID: replica.session.id) }
        }
        #endif
    }

    private func clearUndo() {
        lastSetCompletion = nil
        undoAvailableUntil = nil
    }

    private func playSelectionHaptic() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }
}
