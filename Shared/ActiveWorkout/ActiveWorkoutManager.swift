import Foundation
import Combine
import OSLog

#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

/// Injectable seam around the iPhone-only HealthKit API that launches or
/// wakes the companion Watch app. Kept free of HealthKit so host tests can
/// verify persistence-before-wake ordering.
@MainActor
protocol WatchWorkoutLaunching: AnyObject {
    func launchWorkoutOnWatch(
        completion: @escaping @MainActor (Result<Void, Error>) -> Void
    )
}

/// Pure, testable guard used by the real Watch HealthKit session runner.
/// Holding one claim across both asynchronous startup and the live session
/// prevents duplicate Health workouts from repeated wake deliveries.
struct WatchWorkoutStartGate {
    private(set) var claimedSessionID: UUID?

    mutating func claim(_ sessionID: UUID) -> Bool {
        guard claimedSessionID == nil else { return false }
        claimedSessionID = sessionID
        return true
    }

    mutating func release(_ sessionID: UUID) {
        guard claimedSessionID == sessionID else { return }
        claimedSessionID = nil
    }
}

/// Drives a live workout: which exercise/set is current, completing sets,
/// the rest timer, and keeping the counterpart device in sync. Instantiated on
/// both the phone and the watch.
@MainActor
final class ActiveWorkoutManager: ObservableObject {
    enum WatchLaunchState: Equatable {
        case idle
        case waking
        case waitingForWatch
        case ready
        case failed
    }

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
    /// iPhone-only presentation state for the HealthKit wake request. The
    /// replication state remains authoritative for ownership and readiness.
    @Published private(set) var watchLaunchState: WatchLaunchState = .idle
    @Published private(set) var watchLaunchError: String?
    @Published private(set) var takeoverError: String?
    /// True when an ownership handshake this device cannot edit through has
    /// been outstanding long enough to be worth telling the user about. The
    /// retry keeps running underneath; this only drives the explanation.
    @Published private(set) var isHandshakeStalled = false
    /// Plans persisted on the Watch for an offline workout start.
    @Published private(set) var watchPlans: [WatchStartableWorkout] = []
    /// Phone configuration cached alongside plans for Watch-owned execution.
    @Published private(set) var watchExecutionSettings = WatchExecutionSettings()

    let restTimer: RestTimerManager

    private let connectivity = ConnectivityManager.shared
    private let syncCoordinator: WorkoutSyncCoordinator
    private let watchLauncher: WatchWorkoutLaunching?
    private let logger = Logger(
        subsystem: "com.arulifts.app",
        category: "ActiveWorkout"
    )
    private var watchLaunchSessionID: UUID?
    private var watchLaunchTimeoutTask: Task<Void, Never>?
    private var takeoverTimeoutTask: Task<Void, Never>?
    private var takeoverErrorSessionID: UUID?
    private var outboxRetryTask: Task<Void, Never>?
    /// How often a non-empty durable outbox is re-flushed, and how long a
    /// non-editable handshake may stay outstanding before the UI says so.
    /// Injectable so tests do not have to wait in real time.
    private let outboxRetryInterval: Duration
    private let handshakeStallThreshold: Duration
    private var cancellables = Set<AnyCancellable>()
    /// Suppresses re-broadcasting while we apply a sync from the other device.
    private var applyingRemote = false
    private var lastSetCompletion: LastSetCompletion?

    /// Called on the phone when a session finishes, so it can be stored.
    /// The Bool is true when the watch already saved the workout to Apple
    /// Health via its live session, so the phone must not save a duplicate.
    var onFinish: ((WorkoutSession, _ healthAlreadySaved: Bool) -> Void)?

    var isActive: Bool { session != nil }

    /// `localDevice` and `repository` exist so tests can stand up an isolated
    /// manager for either side of the pair. Production always uses the
    /// defaults: the role follows the platform, and state lands in the real
    /// Application Support store.
    init(
        localDevice: WorkoutDevice? = nil,
        repository: ActiveWorkoutRepository = ActiveWorkoutRepository(),
        watchLauncher: WatchWorkoutLaunching? = nil,
        outboxRetryInterval: Duration = .seconds(10),
        handshakeStallThreshold: Duration = .seconds(30)
    ) {
        self.outboxRetryInterval = outboxRetryInterval
        self.handshakeStallThreshold = handshakeStallThreshold
        #if os(watchOS)
        let device = localDevice ?? .watch
        #else
        let device = localDevice ?? .phone
        #endif
        restTimer = RestTimerManager(localDevice: device)
        syncCoordinator = WorkoutSyncCoordinator(
            localDevice: device,
            repository: repository
        )
        #if os(iOS)
        self.watchLauncher = watchLauncher ?? HealthKitWatchWorkoutLauncher()
        #else
        self.watchLauncher = watchLauncher
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

        connectivity.$receivedWorkoutEnvelope
            .compactMap { $0 }
            .sink { [weak self] envelope in self?.handleV2(envelope) }
            .store(in: &cancellables)

        connectivity.$isReachable
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in self?.syncCoordinator.flushOutbox() }
            .store(in: &cancellables)

        connectivity.$activationGeneration
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.syncCoordinator.flushOutbox()
                if let staleID = self.syncCoordinator.discardedStaleSessionID {
                    self.connectivity.clearActiveContext(staleID)
                }
            }
            .store(in: &cancellables)

        applyV2State(syncCoordinator.state, isInitialRestore: true)
        syncCoordinator.flushOutbox()
        if let staleID = syncCoordinator.discardedStaleSessionID {
            logger.notice(
                "Discarded abandoned workout \(staleID.uuidString, privacy: .public)"
            )
            connectivity.clearActiveContext(staleID)
        }

        // A force-quit/relaunch while an ownership offer is pending must retry
        // the wake request. The durable outbox is already restored and flushed
        // above, so ordering remains persistence first.
        if watchLauncher != nil,
           let replica = syncCoordinator.replica,
           replica.owner == .phone,
           syncCoordinator.state.syncStatus == .waitingForWatch {
            beginWatchLaunch(for: replica.session.id)
        }
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
            let persisted = syncCoordinator.start(newSession)
            if persisted {
                logger.info(
                    "Persisted workout start \(newSession.id.uuidString, privacy: .public)"
                )
                if syncCoordinator.localDevice == .phone,
                   watchLauncher != nil {
                    beginWatchLaunch(for: newSession.id)
                }
            } else {
                logger.error(
                    "Failed to persist workout start \(newSession.id.uuidString, privacy: .public)"
                )
            }
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

    /// Retries the iPhone-to-Watch wake without creating a second workout or
    /// ownership offer. The existing durable outbox is flushed first.
    func retryWatchLaunch() {
        guard let replica = syncCoordinator.replica,
              replica.owner == .phone,
              syncCoordinator.state.syncStatus == .waitingForWatch else { return }
        syncCoordinator.flushOutbox()
        beginWatchLaunch(for: replica.session.id, force: true)
    }

    func cancel() {
        guard canEdit, let current = session else { return }
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

    /// Reorders exercise instances for this workout only. The template is never
    /// consulted or mutated here, so a one-off gym-floor adjustment cannot
    /// change the user's saved plan. Keep the selected instance stable by id:
    /// its array position may change, but the exercise on screen must not.
    func moveExercises(from source: IndexSet, to destination: Int) {
        guard canEdit, var session, session.exercises.count > 1 else { return }
        let selectedID = session.exercises.indices.contains(currentExerciseIndex)
            ? session.exercises[currentExerciseIndex].id
            : nil
        session.moveExercises(from: source, to: destination)

        applyingRemote = true
        self.session = session
        if let selectedID,
           let newIndex = session.exercises.firstIndex(where: { $0.id == selectedID }) {
            currentExerciseIndex = newIndex
        } else {
            currentExerciseIndex = min(currentExerciseIndex, session.exercises.count - 1)
        }
        applyingRemote = false
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
        guard syncCoordinator.requestTakeover(),
              let sessionID = syncCoordinator.replica?.session.id else { return }
        takeoverError = nil
        takeoverErrorSessionID = nil
        takeoverTimeoutTask?.cancel()
        takeoverTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(15))
            } catch {
                return
            }
            guard let self,
                  self.syncCoordinator.replica?.session.id == sessionID,
                  self.syncCoordinator.state.authorityState ==
                    .requestingTakeover else { return }
            guard self.syncCoordinator.cancelTakeoverRequest() else { return }
            self.takeoverError =
                "Apple Watch did not recognize this workout. You can retry or discard it and start a fresh workout."
            self.takeoverErrorSessionID = sessionID
            self.logger.error(
                "Watch takeover timed out for \(sessionID.uuidString, privacy: .public)"
            )
        }
        #endif
    }

    /// Puts down a workout this device mirrors but cannot take over — the
    /// action the failed-takeover message offers. Clears the local mirror only;
    /// a Watch that is still genuinely running the workout keeps it and must be
    /// finished or discarded there.
    func discardMirroredWorkout() {
        guard let sessionID = syncCoordinator.replica?.session.id,
              syncCoordinator.abandonMirroredSession() else { return }
        connectivity.clearActiveContext(sessionID)
        logger.notice(
            "Discarded stuck mirrored workout \(sessionID.uuidString, privacy: .public)"
        )
        currentExerciseIndex = 0
        clearUndo()
        session = nil
        isWorkoutPaused = false
        isFinalizing = false
        restTimer.stop()
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

    private func handleV2(_ envelope: WorkoutMessageEnvelope) {
        let finalization = envelope.kind == .tombstone
            ? try? envelope.decodePayload(WorkoutFinalization.self)
            : nil
        let result = syncCoordinator.receive(envelope)
        logger.info(
            "Received \(envelope.kind.rawValue, privacy: .public) for \(envelope.sessionID?.uuidString ?? "none", privacy: .public): \(String(describing: result), privacy: .public)"
        )
        guard result == .applied, let finalization else { return }

        connectivity.clearActiveContext(finalization.tombstone.sessionID)
        #if os(watchOS)
        // Runs before the "is this our session?" guard below: a banner may be
        // sitting on the wrist for a workout this device never displayed, and
        // it must not outlive the workout it points at.
        WatchWorkoutNotifier.clear()
        #endif
        if finalization.tombstone.finished {
            // Fires even when this device never mirrored the workout — e.g. a
            // Watch session logged entirely while the phone app was gone. The
            // history store de-duplicates by session id, so recording here is
            // safe and is how such a workout reaches the phone at all.
            onFinish?(finalization.finalSession, finalization.healthSaved)
        }

        // Only tear down live UI state when the tombstone is for the workout
        // this device is actually showing. The coordinator now accepts (and
        // records) tombstones for sessions it never tracked, so an unrelated
        // finalization must not blank out an active workout.
        guard session?.id == finalization.tombstone.sessionID else { return }
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
    ///
    /// `isInitialRestore` marks the one call made from `init` that republishes
    /// already-persisted state. It looks identical to a workout arriving from
    /// the counterpart, but the user is opening the app right now, so it must
    /// not trigger the "a workout appeared" wrist notification.
    private func applyV2State(_ state: WorkoutRuntimeState, isInitialRestore: Bool = false) {
        owner = state.activeReplica?.owner
        canEdit = syncCoordinator.canEdit
        syncStatus = state.syncStatus
        syncOutboxRetry(for: state)
        watchPlans = state.watchPlanCache?.workouts ?? []
        if let cachedSettings = state.watchPlanCache?.executionSettings {
            watchExecutionSettings = cachedSettings
        }
        guard let replica = state.activeReplica else {
            watchLaunchTimeoutTask?.cancel()
            watchLaunchTimeoutTask = nil
            takeoverTimeoutTask?.cancel()
            takeoverTimeoutTask = nil
            watchLaunchSessionID = nil
            watchLaunchState = .idle
            watchLaunchError = nil
            takeoverError = nil
            takeoverErrorSessionID = nil
            return
        }

        if let errorSessionID = takeoverErrorSessionID,
           errorSessionID != replica.session.id {
            takeoverError = nil
            takeoverErrorSessionID = nil
        }
        if state.authorityState != .requestingTakeover {
            takeoverTimeoutTask?.cancel()
            takeoverTimeoutTask = nil
            if replica.owner == syncCoordinator.localDevice {
                takeoverError = nil
                takeoverErrorSessionID = nil
            }
        }

        if replica.owner == .watch, state.syncStatus == .synced {
            watchLaunchTimeoutTask?.cancel()
            watchLaunchTimeoutTask = nil
            watchLaunchSessionID = replica.session.id
            watchLaunchState = .ready
            watchLaunchError = nil
        } else if replica.owner == .phone,
                  state.syncStatus == .waitingForWatch,
                  watchLaunchState == .idle {
            watchLaunchState = .waitingForWatch
        }

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
            let configuration = WatchLaunchContext.shared.consumeConfiguration()
            Task {
                await WatchWorkoutSession.shared.start(
                    sessionID: replica.session.id,
                    configuration: configuration
                )
            }
            // HealthKit wakes the app; this local notification is a secondary
            // presentation step for a workout that is already persisted.
            if !isInitialRestore {
                Task {
                    await WatchWorkoutNotifier.workoutDidArrive(
                        named: replica.session.name,
                        sessionID: replica.session.id
                    )
                }
            }
        }
        #endif
    }

    /// Keeps a retry running for exactly as long as the durable outbox has
    /// something in it.
    ///
    /// `flushOutbox` was previously driven only by edges — launch, a local
    /// commit, reachability becoming true, WCSession activation. None of those
    /// is guaranteed to happen again while the user is mid-workout with the
    /// phone in a locker, so a single dropped handshake message could leave
    /// this device waiting forever in a state it cannot edit through.
    ///
    /// Retrying is safe at any cadence: every envelope carries a stable id,
    /// receivers dedupe on `processedMessageIDs`, and `ConnectivityManager`
    /// skips a transfer that is already outstanding.
    private func syncOutboxRetry(for state: WorkoutRuntimeState) {
        guard !state.outbox.isEmpty else {
            outboxRetryTask?.cancel()
            outboxRetryTask = nil
            isHandshakeStalled = false
            return
        }
        // Already retrying; the running loop re-reads the live state each pass.
        guard outboxRetryTask == nil else { return }

        // `self` is deliberately re-acquired inside the loop rather than
        // unwrapped once up front: holding it across the sleep would keep the
        // manager alive through its own task for as long as the outbox has
        // anything in it, which is exactly the long-lived case.
        let clock = ContinuousClock()
        let retryStartedAt = clock.now
        outboxRetryTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.outboxRetryInterval else { return }
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                guard !self.syncCoordinator.state.outbox.isEmpty else {
                    self.outboxRetryTask = nil
                    self.isHandshakeStalled = false
                    return
                }
                self.syncCoordinator.flushOutbox()

                // Only nag about a handshake the user is actually blocked by.
                // A queued checkpoint while this device is happily editing is
                // normal background catch-up, not something to surface.
                let waited = retryStartedAt.duration(to: clock.now)
                let blocked = self.session != nil && !self.canEdit
                let stalled = blocked && waited >= self.handshakeStallThreshold
                if stalled != self.isHandshakeStalled {
                    self.isHandshakeStalled = stalled
                    if stalled {
                        self.logger.error(
                            "Ownership handshake still pending after \(waited.components.seconds, privacy: .public)s; retrying"
                        )
                    }
                }
            }
        }
    }

    private func beginWatchLaunch(for sessionID: UUID, force: Bool = false) {
        guard let watchLauncher else {
            watchLaunchState = .failed
            watchLaunchError = "Watch launching is unavailable."
            return
        }
        guard force || watchLaunchSessionID != sessionID ||
                watchLaunchState == .failed else { return }

        watchLaunchSessionID = sessionID
        watchLaunchTimeoutTask?.cancel()
        watchLaunchTimeoutTask = nil
        watchLaunchState = .waking
        watchLaunchError = nil
        logger.info(
            "Waking Watch for workout \(sessionID.uuidString, privacy: .public)"
        )
        scheduleWatchLaunchTimeout(for: sessionID)

        watchLauncher.launchWorkoutOnWatch { [weak self] result in
            guard let self,
                  self.session?.id == sessionID,
                  self.watchLaunchSessionID == sessionID else { return }
            switch result {
            case .success:
                // The ownership acknowledgment may beat this callback.
                if self.watchLaunchState != .ready {
                    self.watchLaunchState = .waitingForWatch
                }
            case .failure(let error):
                // Likewise, never regress a handshake that already completed.
                guard self.watchLaunchState != .ready else { return }
                self.watchLaunchTimeoutTask?.cancel()
                self.watchLaunchTimeoutTask = nil
                self.watchLaunchState = .failed
                self.watchLaunchError = error.localizedDescription
            }
        }
    }

    private func scheduleWatchLaunchTimeout(for sessionID: UUID) {
        watchLaunchTimeoutTask?.cancel()
        watchLaunchTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(20))
            } catch {
                return
            }
            guard let self,
                  self.session?.id == sessionID,
                  self.watchLaunchSessionID == sessionID,
                  self.watchLaunchState == .waking ||
                    self.watchLaunchState == .waitingForWatch else { return }
            let timedOutWhileWaking = self.watchLaunchState == .waking
            self.watchLaunchState = .failed
            self.watchLaunchError = timedOutWhileWaking
                ? "Apple Watch did not respond to the wake request."
                : "Apple Watch woke, but the workout handshake did not finish."
            self.logger.error(
                "Watch handshake timed out for \(sessionID.uuidString, privacy: .public)"
            )
        }
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
