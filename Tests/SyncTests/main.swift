// Sync-layer assertions: the phone<->watch replication seam.
//
// This suite exists because the pure-logic suites (Tests/run.sh,
// Tests/run_e2e.sh) compiled neither ConnectivityManager nor
// ActiveWorkoutManager, and exercised the coordinator only in states where a
// local replica already existed. That blind spot let a defect ship in which a
// device holding no replica rejected every checkpoint for an in-progress
// workout and never re-attached — the app built clean and every test passed
// while the two devices could not sync at all.
import Foundation

var failures = 0
func expect(_ cond: Bool, _ label: String) {
    if cond { print("PASS \(label)") } else { failures += 1; print("FAIL \(label)") }
}

let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("arulifts-sync-tests-\(UUID().uuidString)")

func repository(_ name: String) -> ActiveWorkoutRepository {
    ActiveWorkoutRepository(directory: root.appendingPathComponent(name))
}

/// A coordinator whose outgoing envelopes are captured rather than transmitted.
final class Wire {
    private(set) var sent: [WorkoutMessageEnvelope] = []
    private(set) var transmitCount = 0
    func record(_ envelope: WorkoutMessageEnvelope) {
        sent.append(envelope)
        transmitCount += 1
    }
    func last(_ kind: WorkoutMessageKind) -> WorkoutMessageEnvelope? {
        sent.last { $0.kind == kind }
    }
    func first(_ kind: WorkoutMessageKind) -> WorkoutMessageEnvelope? {
        sent.first { $0.kind == kind }
    }
}

func makeCoordinator(
    _ device: WorkoutDevice,
    _ name: String,
    maxAge: TimeInterval = 6 * 60 * 60,
    now: @escaping () -> Date = Date.init
) -> (WorkoutSyncCoordinator, Wire) {
    let wire = Wire()
    let coordinator = WorkoutSyncCoordinator(
        localDevice: device,
        repository: repository(name),
        maxAdoptableSessionAge: maxAge,
        now: now,
        transmit: { envelope, _ in wire.record(envelope) }
    )
    return (coordinator, wire)
}

func makeSession(name: String, sets: Int = 5, startedAt: Date = Date()) -> WorkoutSession {
    WorkoutSession(
        name: name,
        exercises: [
            SessionExercise(
                exerciseID: UUID(),
                name: "Barbell Squat",
                sets: (0..<sets).map { _ in SetEntry(reps: 5, weight: 100) }
            )
        ],
        startedAt: startedAt
    )
}

// Rest state is mirrored to both devices, but speech must have exactly one
// physical owner. The phone sends it through the user's selected audio route;
// the Watch retains haptics without duplicating spoken countdown cues.
expect(
    RestTimerManager.spokenAlertsEnabled(for: .phone),
    "phone owns spoken rest alerts"
)
expect(
    !RestTimerManager.spokenAlertsEnabled(for: .watch),
    "watch suppresses mirrored spoken rest alerts"
)

// ---------------------------------------------------------------------------
// 1. A device with no replica joins a workout already in progress.
//
// The regression: this required version == .initial and returned `.gap`
// otherwise. Nothing handled `.gap` and no resync request exists, so a device
// that missed the first checkpoint stayed blank for the whole workout.
// ---------------------------------------------------------------------------

let (watch1, watchWire1) = makeCoordinator(.watch, "join-watch")
var s1 = makeSession(name: "Leg Day")
expect(watch1.start(s1), "watch starts a workout while the phone is away")

for i in 0..<3 {
    s1.exercises[0].sets[i].isCompleted = true
    _ = watch1.mutate(session: s1, currentExerciseIndex: 0, restTimer: nil, isWorkoutPaused: false)
}
expect(watch1.replica?.version.revision == 3, "watch advanced past the initial revision")

let (phone1, _) = makeCoordinator(.phone, "join-phone")
expect(phone1.replica == nil, "joining phone starts with no replica")

let midWorkout = watchWire1.last(.checkpoint)!
expect(phone1.receive(midWorkout) == .applied, "phone adopts an in-progress checkpoint")
expect(phone1.replica?.session.id == s1.id, "phone mirrors the live session")
expect(phone1.replica?.owner == .watch, "adopted replica keeps the watch as owner")
expect(!phone1.canEdit, "joining phone is a read-only mirror")
expect(
    phone1.replica?.session.exercises[0].completedSets == 3,
    "phone sees the three sets logged before it joined"
)

// Convergence continues on subsequent checkpoints.
s1.exercises[0].sets[3].isCompleted = true
_ = watch1.mutate(session: s1, currentExerciseIndex: 0, restTimer: nil, isWorkoutPaused: false)
expect(
    phone1.receive(watchWire1.last(.checkpoint)!) == .applied,
    "phone keeps converging after adoption"
)
expect(
    phone1.replica?.session.exercises[0].completedSets == 4,
    "later checkpoint applies on top of the adopted replica"
)

// ---------------------------------------------------------------------------
// 2. Adoption respects the staleness window.
//
// This is what `.initial` was implicitly buying: the application context is
// sticky and survives termination, so a cold launch must not adopt a workout
// abandoned days ago.
// ---------------------------------------------------------------------------

let (staleWatch, staleWire) = makeCoordinator(.watch, "stale-watch")
let staleSession = makeSession(name: "Abandoned", startedAt: Date().addingTimeInterval(-7 * 60 * 60))
_ = staleWatch.start(staleSession)

let (stalePhone, _) = makeCoordinator(.phone, "stale-phone")
expect(
    stalePhone.receive(staleWire.last(.checkpoint)!) == .stale,
    "a workout older than the adoption window is not resurrected"
)
expect(stalePhone.replica == nil, "stale checkpoint leaves the phone with no replica")

let (freshWatch, freshWire) = makeCoordinator(.watch, "fresh-watch")
let freshSession = makeSession(name: "In Window", startedAt: Date().addingTimeInterval(-5 * 60 * 60))
_ = freshWatch.start(freshSession)

let (freshPhone, _) = makeCoordinator(.phone, "fresh-phone")
expect(
    freshPhone.receive(freshWire.last(.checkpoint)!) == .applied,
    "a workout inside the adoption window is still adopted"
)

// A device already tracking a session is not subject to the adoption window —
// the guard is about joining, not about staying joined.
let (longWatch, longWire) = makeCoordinator(.watch, "long-watch")
var longSession = makeSession(name: "Marathon", startedAt: Date().addingTimeInterval(-7 * 60 * 60))
_ = longWatch.start(longSession)
let (longPhone, _) = makeCoordinator(
    .phone, "long-phone",
    now: { Date().addingTimeInterval(-7 * 60 * 60) }   // phone joined when it was fresh
)
expect(longPhone.receive(longWire.last(.checkpoint)!) == .applied, "phone joins early")
longSession.exercises[0].sets[0].isCompleted = true
_ = longWatch.mutate(session: longSession, currentExerciseIndex: 0, restTimer: nil, isWorkoutPaused: false)
expect(
    longPhone.receive(longWire.last(.checkpoint)!) == .applied,
    "an already-joined mirror keeps updating past the adoption window"
)

// A replica restored after the safety window is abandoned locally, including
// its session-specific outbox entries. This is the exact recovery path for a
// phone stuck requesting takeover of a workout that ended days earlier.
let abandonedRepository = repository("abandoned-restore")
let abandonedStartedAt = Date().addingTimeInterval(-7 * 60 * 60)
let abandonedSession = makeSession(
    name: "Long Gone",
    startedAt: abandonedStartedAt
)
let abandonedOriginal = WorkoutSyncCoordinator(
    localDevice: .phone,
    repository: abandonedRepository,
    now: { abandonedStartedAt }
)
expect(abandonedOriginal.start(abandonedSession), "abandoned workout was originally persisted")
let abandonedRecovered = WorkoutSyncCoordinator(
    localDevice: .phone,
    repository: abandonedRepository
)
expect(abandonedRecovered.replica == nil, "stale restored workout is discarded")
expect(
    abandonedRecovered.discardedStaleSessionID == abandonedSession.id,
    "stale restoration reports the discarded session for context cleanup"
)
expect(
    abandonedRecovered.state.terminalSessions[abandonedSession.id] != nil,
    "stale restored workout is tombstoned against resurrection"
)
expect(
    !abandonedRecovered.state.outbox.contains { pending in
        (try? JSONDecoder().decode(
            WorkoutMessageEnvelope.self,
            from: pending.payload
        ))?.sessionID == abandonedSession.id
    },
    "stale restored workout removes its undeliverable outbox"
)

// ---------------------------------------------------------------------------
// 3. Adoption never resurrects a finished workout.
// ---------------------------------------------------------------------------

let (tombWatch, tombWire) = makeCoordinator(.watch, "tomb-watch")
let tombSession = makeSession(name: "Finished")
_ = tombWatch.start(tombSession)
let liveCheckpoint = tombWire.last(.checkpoint)!
expect(
    tombWatch.finalize(session: tombSession, finished: true, healthSaved: false),
    "watch finalizes the workout"
)

let (tombPhone, _) = makeCoordinator(.phone, "tomb-phone")
expect(tombPhone.receive(tombWire.last(.tombstone)!) == .applied, "phone records the tombstone")
expect(
    tombPhone.receive(liveCheckpoint) == .invalid,
    "a checkpoint that outlived its tombstone cannot resurrect the workout"
)
expect(tombPhone.replica == nil, "phone stays clear after a tombstoned checkpoint")

// ---------------------------------------------------------------------------
// 4. A reinstalled phone re-attaches to a workout it previously owned.
//    This is the reported failure: delete the app mid-session, reopen it.
// ---------------------------------------------------------------------------

let (rPhone, rPhoneWire) = makeCoordinator(.phone, "reinstall-phone")
let (rWatch, rWatchWire) = makeCoordinator(.watch, "reinstall-watch")
var rSession = makeSession(name: "Push Day")
_ = rPhone.start(rSession)
_ = rWatch.receive(rPhoneWire.first(.ownershipOffer)!)
_ = rPhone.receive(rWatchWire.first(.ownershipAcceptance)!)
_ = rWatch.receive(rPhoneWire.last(.ownershipCommit)!)
expect(rWatch.canEdit, "watch owns the workout after the handshake")

for i in 0..<2 {
    rSession.exercises[0].sets[i].isCompleted = true
    _ = rWatch.mutate(session: rSession, currentExerciseIndex: 0, restTimer: nil, isWorkoutPaused: false)
}

// Delete + reinstall wipes the phone's runtime store.
let (reinstalled, _) = makeCoordinator(.phone, "reinstall-phone-fresh")
expect(
    reinstalled.receive(rWatchWire.last(.checkpoint)!) == .applied,
    "a reinstalled phone re-attaches to the live workout"
)
expect(
    reinstalled.replica?.session.exercises[0].completedSets == 2,
    "reinstalled phone recovers the sets logged while it was gone"
)
expect(reinstalled.owner == .watch, "reinstalled phone defers to the watch as owner")

// ---------------------------------------------------------------------------
// 5. Outbox coalescing keeps delivery volume linear.
//
// `commit(flush:)` re-transmits the whole outbox, so an uncoalesced outbox made
// send volume quadratic in the number of logged sets and flooded the finite,
// persistent transferUserInfo queue whenever the counterpart was unreachable.
// ---------------------------------------------------------------------------

let (silentWatch, silentWire) = makeCoordinator(.watch, "silent-watch")
var silentSession = makeSession(name: "Volume", sets: 30)
_ = silentWatch.start(silentSession)
for i in 0..<30 {
    silentSession.exercises[0].sets[i].isCompleted = true
    _ = silentWatch.mutate(
        session: silentSession, currentExerciseIndex: 0,
        restTimer: nil, isWorkoutPaused: false
    )
}
expect(
    silentWatch.state.outbox.count == 1,
    "superseded checkpoints collapse to a single pending snapshot"
)
expect(
    silentWire.transmitCount <= 62,
    "31 edits stay linear in transmit volume (was 496 before coalescing)"
)
expect(
    silentWatch.state.outbox.first.flatMap {
        try? JSONDecoder().decode(WorkoutMessageEnvelope.self, from: $0.payload)
    }?.id == silentWire.sent.last?.id,
    "the surviving pending snapshot is the newest one"
)

// ---------------------------------------------------------------------------
// 6. Coalescing must not eat the transfer handshake or a tombstone.
// ---------------------------------------------------------------------------

let (hPhone, hPhoneWire) = makeCoordinator(.phone, "handshake-phone")
let (hWatch, hWatchWire) = makeCoordinator(.watch, "handshake-watch")
var hSession = makeSession(name: "Handshake")
_ = hPhone.start(hSession)
_ = hWatch.receive(hPhoneWire.first(.ownershipOffer)!)
// The acceptance sits in the watch's outbox; checkpoints must not displace it.
_ = hPhone.receive(hWatchWire.first(.ownershipAcceptance)!)
_ = hWatch.receive(hPhoneWire.last(.ownershipCommit)!)
expect(hWatch.canEdit, "handshake completes with coalescing enabled")

for i in 0..<3 {
    hSession.exercises[0].sets[i].isCompleted = true
    _ = hWatch.mutate(session: hSession, currentExerciseIndex: 0, restTimer: nil, isWorkoutPaused: false)
}
expect(
    hWatch.finalize(session: hSession, finished: true, healthSaved: false),
    "watch finalizes after coalesced edits"
)
let pendingKinds: [WorkoutMessageKind] = hWatch.state.outbox.compactMap {
    (try? JSONDecoder().decode(WorkoutMessageEnvelope.self, from: $0.payload))?.kind
}
expect(
    pendingKinds.contains(.tombstone),
    "the tombstone survives in the outbox and is never collapsed away"
)
expect(
    hPhone.receive(hWatchWire.last(.tombstone)!) == .applied,
    "phone finalizes from the surviving tombstone"
)

// Repeated Take Over taps keep only one live request, and a timeout can return
// the requester to a retryable mirror state without changing ownership.
let (takeoverPhone, takeoverPhoneWire) = makeCoordinator(
    .phone, "takeover-timeout-phone"
)
let (takeoverWatch, takeoverWatchWire) = makeCoordinator(
    .watch, "takeover-timeout-watch"
)
let takeoverSession = makeSession(name: "Takeover Timeout")
_ = takeoverWatch.start(takeoverSession)
_ = takeoverPhone.receive(takeoverWatchWire.last(.checkpoint)!)
expect(takeoverPhone.requestTakeover(), "phone queues a takeover request")
expect(takeoverPhone.requestTakeover(), "repeated takeover refreshes the request")
let takeoverRequests = takeoverPhone.state.outbox.compactMap {
    try? JSONDecoder().decode(WorkoutMessageEnvelope.self, from: $0.payload)
}.filter { $0.kind == .takeoverRequest }
expect(takeoverRequests.count == 1, "repeated takeover requests coalesce")
expect(
    takeoverPhone.cancelTakeoverRequest(),
    "timed-out takeover returns to mirror state"
)
expect(takeoverPhone.owner == .watch, "takeover timeout preserves Watch ownership")
expect(
    takeoverPhone.state.authorityState == .mirror &&
      takeoverPhone.state.syncStatus == .synced,
    "takeover timeout is retryable instead of waiting forever"
)
expect(
    takeoverPhoneWire.sent.filter { $0.kind == .takeoverRequest }.count >= 2,
    "each explicit takeover attempt is transmitted"
)

// ---------------------------------------------------------------------------
// 7. ActiveWorkoutManager surfaces an adopted replica to the UI.
//
// Covers the manager<->connectivity seam that no suite compiled before: an
// envelope arriving on ConnectivityManager must land in the manager's
// published state, which is what the views render.
// ---------------------------------------------------------------------------

// ActiveWorkoutManager is @MainActor; top-level script code is not. This runs
// on the process main thread, so the isolation is real, not assumed away.
MainActor.assumeIsolated {
    let manager = ActiveWorkoutManager(
        localDevice: .phone,
        repository: repository("manager-phone")
    )
    expect(manager.session == nil, "fresh manager has no active session")

    let (mWatch, mWire) = makeCoordinator(.watch, "manager-watch")
    var mSession = makeSession(name: "Mirrored")
    _ = mWatch.start(mSession)
    mSession.exercises[0].sets[0].isCompleted = true
    mSession.exercises[0].sets[1].isCompleted = true
    _ = mWatch.mutate(
        session: mSession, currentExerciseIndex: 0,
        restTimer: nil, isWorkoutPaused: false
    )

    // Deliver as the transport would.
    ConnectivityManager.shared.receivedWorkoutEnvelope = mWire.last(.checkpoint)!

    expect(manager.session?.id == mSession.id, "manager publishes the adopted session")
    expect(manager.owner == .watch, "manager reports the watch as owner")
    expect(!manager.canEdit, "manager is read-only while mirroring")
    expect(
        manager.session?.exercises[0].completedSets == 2,
        "manager surfaces sets logged before it joined"
    )
}

// ---------------------------------------------------------------------------
// 8. Phone start persists before waking Watch; failure/retry is idempotent.
// ---------------------------------------------------------------------------

@MainActor
final class RecordingWatchLauncher: WatchWorkoutLaunching {
    var callCount = 0
    var result: Result<Void, Error> = .success(())
    var onLaunch: (() -> Void)?

    func launchWorkoutOnWatch(
        completion: @escaping @MainActor (Result<Void, Error>) -> Void
    ) {
        callCount += 1
        onLaunch?()
        completion(result)
    }
}

struct ExpectedLaunchFailure: LocalizedError {
    var errorDescription: String? { "Expected launch failure" }
}

MainActor.assumeIsolated {
    let launchRepository = repository("launch-order")
    let launcher = RecordingWatchLauncher()
    var persistedBeforeWake = false
    launcher.onLaunch = {
        let state = launchRepository.load()
        persistedBeforeWake =
            state.activeReplica != nil &&
            state.outbox.contains { pending in
                (try? JSONDecoder().decode(
                    WorkoutMessageEnvelope.self,
                    from: pending.payload
                ))?.kind == .ownershipOffer
            }
    }

    let manager = ActiveWorkoutManager(
        localDevice: .phone,
        repository: launchRepository,
        watchLauncher: launcher
    )
    manager.start(makeSession(name: "Wake ordering"))

    expect(persistedBeforeWake, "phone persists ownership offer before Watch wake")
    expect(launcher.callCount == 1, "phone requests exactly one wake for a new start")
    expect(
        manager.watchLaunchState == .waitingForWatch,
        "successful wake waits for the ownership handshake"
    )

    // Complete the real coordinator handshake through the manager's published
    // transport seam. A HealthKit wake alone must never produce Ready.
    let (launchWatch, launchWatchWire) = makeCoordinator(
        .watch,
        "launch-order-watch"
    )
    let persistedOffer = launchRepository.load().outbox.compactMap {
        try? JSONDecoder().decode(
            WorkoutMessageEnvelope.self,
            from: $0.payload
        )
    }.first { $0.kind == .ownershipOffer }!
    _ = launchWatch.receive(persistedOffer)
    ConnectivityManager.shared.receivedWorkoutEnvelope =
        launchWatchWire.last(.ownershipAcceptance)!

    let persistedCommit = launchRepository.load().outbox.compactMap {
        try? JSONDecoder().decode(
            WorkoutMessageEnvelope.self,
            from: $0.payload
        )
    }.first { $0.kind == .ownershipCommit }!
    _ = launchWatch.receive(persistedCommit)
    ConnectivityManager.shared.receivedWorkoutEnvelope =
        launchWatchWire.last(.acknowledgment)!
    expect(
        manager.watchLaunchState == .ready,
        "Ready appears only after the exact-session ownership acknowledgment"
    )

    let retryRepository = repository("launch-retry")
    let retryLauncher = RecordingWatchLauncher()
    retryLauncher.result = .failure(ExpectedLaunchFailure())
    let retryManager = ActiveWorkoutManager(
        localDevice: .phone,
        repository: retryRepository,
        watchLauncher: retryLauncher
    )
    retryManager.start(makeSession(name: "Retry"))
    expect(retryManager.watchLaunchState == .failed, "wake failure is surfaced")
    expect(retryLauncher.callCount == 1, "failed start made one wake request")

    retryLauncher.result = .success(())
    retryManager.retryWatchLaunch()
    expect(retryLauncher.callCount == 2, "explicit retry makes one additional wake request")
    expect(
        retryManager.watchLaunchState == .waitingForWatch,
        "successful retry returns to waiting without creating another workout"
    )
    expect(
        retryRepository.load().outbox.compactMap {
            try? JSONDecoder().decode(
                WorkoutMessageEnvelope.self,
                from: $0.payload
            )
        }.filter { $0.kind == .ownershipOffer }.count == 1,
        "retry reuses the original durable ownership offer"
    )

    let restoredLauncher = RecordingWatchLauncher()
    _ = ActiveWorkoutManager(
        localDevice: .phone,
        repository: retryRepository,
        watchLauncher: restoredLauncher
    )
    expect(
        restoredLauncher.callCount == 1,
        "relaunch retries one restored pending Watch wake"
    )
}

// The gate is used directly by WatchWorkoutSession across async authorization,
// builder setup, and the live workout. Duplicate HealthKit launches cannot
// pass it until the original session finishes or is discarded.
var startGate = WatchWorkoutStartGate()
let guardedSession = UUID()
let otherGuardedSession = UUID()
expect(startGate.claim(guardedSession), "first Health workout start claims the gate")
expect(!startGate.claim(guardedSession), "duplicate wake cannot start the same Health workout")
expect(!startGate.claim(otherGuardedSession), "duplicate wake cannot start a second Health workout")
startGate.release(otherGuardedSession)
expect(
    !startGate.claim(otherGuardedSession),
    "wrong-session release cannot clear the live Health workout"
)
startGate.release(guardedSession)
expect(
    startGate.claim(otherGuardedSession),
    "Health workout gate reopens only after the original session ends"
)

// ---------------------------------------------------------------------------
// A stale replica must not veto the workout the counterpart is running now.
//
// Sibling of the no-replica regression above. Adoption was fixed for a device
// holding nothing, but a device still holding an abandoned session rejected
// every offer/checkpoint for a newer one as `.stale`, so the pair could not
// converge until the six-hour launch-recovery window expired.
// ---------------------------------------------------------------------------

let staleStart = Date().addingTimeInterval(-1800)

let (supersededWatch, _) = makeCoordinator(.watch, "supersede-watch")
expect(
    supersededWatch.start(makeSession(name: "Abandoned", startedAt: staleStart)),
    "watch is left holding an abandoned workout"
)
let abandonedOnWatch = supersededWatch.replica?.session.id

let (supersedingPhone, supersedingPhoneWire) = makeCoordinator(.phone, "supersede-phone")
let newPhoneSession = makeSession(name: "Push Day", startedAt: Date())
expect(supersedingPhone.start(newPhoneSession), "phone starts a brand-new workout")

if let offer = supersedingPhoneWire.last(.ownershipOffer) {
    expect(
        supersededWatch.receive(offer) == .applied,
        "offer for a newer workout supersedes the abandoned one"
    )
    expect(
        supersededWatch.replica?.session.id == newPhoneSession.id,
        "watch switches to the workout the phone just started"
    )
    if let abandonedOnWatch {
        expect(
            supersededWatch.state.terminalSessions[abandonedOnWatch] != nil,
            "superseded workout is tombstoned, not silently dropped"
        )
        expect(
            !supersededWatch.state.outbox.contains { pending in
                guard let queued = try? JSONDecoder().decode(
                    WorkoutMessageEnvelope.self, from: pending.payload
                ) else { return false }
                return queued.sessionID == abandonedOnWatch
            },
            "superseded workout leaves nothing queued that could resurrect it"
        )
    }
} else {
    expect(false, "phone emitted an ownership offer")
}

// Same rule over the plain checkpoint path, in the other direction.
let (supersededPhone, _) = makeCoordinator(.phone, "supersede-phone-cp")
expect(
    supersededPhone.start(makeSession(name: "Abandoned", startedAt: staleStart)),
    "phone is left holding an abandoned workout"
)
let (supersedingWatch, supersedingWatchWire) = makeCoordinator(.watch, "supersede-watch-cp")
let newWatchSession = makeSession(name: "Pull Day", startedAt: Date())
expect(supersedingWatch.start(newWatchSession), "watch starts a brand-new workout")
if let checkpoint = supersedingWatchWire.last(.checkpoint) {
    expect(
        supersededPhone.receive(checkpoint) == .applied,
        "checkpoint for a newer workout supersedes the abandoned one"
    )
    expect(
        supersededPhone.replica?.session.id == newWatchSession.id,
        "phone switches to the workout the watch just started"
    )
} else {
    expect(false, "watch emitted a checkpoint")
}

// An *older* session must still lose — a stale sticky application context
// replaying yesterday's checkpoint cannot displace the live workout.
let (liveWatch, _) = makeCoordinator(.watch, "supersede-guard-watch")
expect(
    liveWatch.start(makeSession(name: "Live", startedAt: Date())),
    "watch is running the current workout"
)
let (oldPhone, oldPhoneWire) = makeCoordinator(.phone, "supersede-guard-phone")
expect(
    oldPhone.start(makeSession(name: "Yesterday", startedAt: staleStart)),
    "phone replays an older workout"
)
if let oldOffer = oldPhoneWire.last(.ownershipOffer) {
    expect(
        liveWatch.receive(oldOffer) == .stale,
        "an older workout cannot displace the live one"
    )
}

// ---------------------------------------------------------------------------
// A mirror can put down a workout it is unable to take over.
//
// The failed-takeover message tells the user to discard and start fresh;
// cancel/finalize both require ownership, so without this the phone is stuck.
// ---------------------------------------------------------------------------

let (stuckPhone, stuckPhoneWire) = makeCoordinator(.phone, "abandon-phone")
let (stuckWatch, stuckWatchWire) = makeCoordinator(.watch, "abandon-watch")
let stuckSession = makeSession(name: "Handoff")
expect(stuckPhone.start(stuckSession), "phone starts and offers the workout")

var pumpIndex = (phone: 0, watch: 0)
for _ in 0..<12 {
    while pumpIndex.phone < stuckPhoneWire.sent.count {
        _ = stuckWatch.receive(stuckPhoneWire.sent[pumpIndex.phone])
        pumpIndex.phone += 1
    }
    while pumpIndex.watch < stuckWatchWire.sent.count {
        _ = stuckPhone.receive(stuckWatchWire.sent[pumpIndex.watch])
        pumpIndex.watch += 1
    }
}
expect(stuckPhone.owner == .watch, "watch owns the workout after the handshake")
expect(!stuckPhone.canEdit, "phone is a read-only mirror")
expect(
    !stuckPhone.finalize(session: stuckSession, finished: false, healthSaved: false),
    "a mirror still cannot finalize a workout it does not own"
)
expect(stuckPhone.abandonMirroredSession(), "mirror can abandon the stuck workout")
expect(stuckPhone.replica == nil, "phone is clear after abandoning")
expect(
    stuckPhone.state.terminalSessions[stuckSession.id] != nil,
    "abandoned workout is tombstoned so a trailing checkpoint cannot revive it"
)
expect(
    !stuckWatch.abandonMirroredSession(),
    "the owning device cannot abandon its own live workout this way"
)
expect(
    stuckWatch.replica?.session.id == stuckSession.id,
    "abandoning on the phone leaves the Watch's live workout alone"
)

// ---------------------------------------------------------------------------
// A stalled ownership handshake keeps retrying and tells the user.
//
// `flushOutbox` used to be driven purely by edges — launch, a local commit,
// reachability, WCSession activation. A dropped handshake message with no
// following edge left the Watch in `mirror`/`waitingForPhone` holding a
// workout it could not log to, with nothing retrying and nothing said.
// ---------------------------------------------------------------------------

/// Lets the main-actor retry loop actually run inside this synchronous script.
func pumpMainLoop(seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

/// Reads a queued envelope back out of a persisted outbox, which is how the
/// counterpart would eventually see it once delivery recovers.
func queuedEnvelope(
    _ kind: WorkoutMessageKind,
    in repo: ActiveWorkoutRepository
) -> WorkoutMessageEnvelope? {
    repo.load().outbox.lazy
        .compactMap { try? JSONDecoder().decode(WorkoutMessageEnvelope.self, from: $0.payload) }
        .first { $0.kind == kind }
}

let stalledRepository = repository("stalled-handshake-watch")

// Put the Watch in the exact stuck state: it accepted a phone-started workout,
// persisted the phone-owned replica, and queued the acceptance receipt.
let (stalledOfferPhone, stalledOfferWire) = makeCoordinator(.phone, "stalled-handshake-phone")
let stalledSession = makeSession(name: "Stalled Handoff")
expect(stalledOfferPhone.start(stalledSession), "phone offers the workout")

let stalledSeed = WorkoutSyncCoordinator(
    localDevice: .watch,
    repository: stalledRepository
)
expect(
    stalledSeed.receive(stalledOfferWire.last(.ownershipOffer)!) == .applied,
    "watch accepts the offer"
)
expect(!stalledSeed.state.outbox.isEmpty, "acceptance is queued durably")
expect(!stalledSeed.canEdit, "watch cannot edit until the phone commits")

MainActor.assumeIsolated {
    // Short intervals keep the suite fast; production uses 10 s / 30 s.
    let stalledManager = ActiveWorkoutManager(
        localDevice: .watch,
        repository: stalledRepository,
        outboxRetryInterval: .milliseconds(50),
        handshakeStallThreshold: .milliseconds(200)
    )
    expect(
        stalledManager.session?.id == stalledSession.id,
        "watch restores the workout it is waiting to own"
    )
    expect(!stalledManager.canEdit, "restored watch is still read-only")
    expect(
        !stalledManager.isHandshakeStalled,
        "a handshake is not called stalled immediately"
    )

    // Simulate a suspended Watch/main actor. Counting scheduled retry
    // intervals would record only 50 ms after this resumes; a monotonic clock
    // correctly sees that the 200 ms stall threshold has already passed.
    Thread.sleep(forTimeInterval: 0.3)
    pumpMainLoop(seconds: 0.1)
    expect(
        stalledManager.isHandshakeStalled,
        "suspension time counts toward the handshake stall threshold"
    )

    // The retried acceptance finally reaches the phone, which commits. The
    // outbox drains and the Watch becomes the writer, so the warning must
    // clear on its own.
    var commitEnvelope: WorkoutMessageEnvelope?
    stalledOfferPhone.transmit = { envelope, _ in
        if envelope.kind == .ownershipCommit { commitEnvelope = envelope }
    }
    if let acceptance = queuedEnvelope(.ownershipAcceptance, in: stalledRepository) {
        expect(
            stalledOfferPhone.receive(acceptance) == .applied,
            "phone accepts the retried acceptance"
        )
    } else {
        expect(false, "watch had a queued acceptance to retry")
    }

    if let commitEnvelope {
        ConnectivityManager.shared.receivedWorkoutEnvelope = commitEnvelope
        expect(stalledManager.canEdit, "watch owns the workout after the commit")
        pumpMainLoop(seconds: 0.3)
        expect(
            !stalledManager.isHandshakeStalled,
            "the warning clears once the handshake completes"
        )
    } else {
        expect(false, "phone produced an ownership commit")
    }
}

// ---------------------------------------------------------------------------
// Replica acceptance, asserted against the coordinator that actually decides.
//
// These replace assertions that used to run against `WorkoutRuntimeState
// .accepts(_:)`, a helper no device ever called. Two of its three rules are
// covered elsewhere (tombstones above, newer-session adoption further up);
// what was missing was duplicate handling and the ownership-epoch rule, and
// the latter is where the dead helper actively disagreed with the app.
// ---------------------------------------------------------------------------

let (acceptWatch, acceptWire) = makeCoordinator(.watch, "accept-watch")
var acceptSession = makeSession(name: "Acceptance")
expect(acceptWatch.start(acceptSession), "watch starts the workout")
acceptSession.exercises[0].sets[0].isCompleted = true
_ = acceptWatch.mutate(
    session: acceptSession, currentExerciseIndex: 0,
    restTimer: nil, isWorkoutPaused: false
)

let (acceptPhone, _) = makeCoordinator(.phone, "accept-phone")
let acceptCheckpoint = acceptWire.last(.checkpoint)!
expect(acceptPhone.receive(acceptCheckpoint) == .applied, "phone adopts the checkpoint")

// Re-delivery of the very same envelope is a duplicate, not a fresh apply, and
// must still be acknowledged so the sender can retire it from its outbox.
expect(
    acceptPhone.receive(acceptCheckpoint) == .duplicate,
    "the same checkpoint delivered twice is a duplicate"
)
let adoptedVersion = (try? acceptCheckpoint.decodePayload(WorkoutCheckpoint.self))?
    .replica.version
expect(
    adoptedVersion != nil && acceptPhone.replica?.version == adoptedVersion,
    "a duplicate leaves the adopted version untouched"
)

// A replica carrying a *different* ownership epoch cannot arrive as a plain
// checkpoint: ownership only ever moves through the offer/acceptance/commit
// handshake. This is the rule the deleted helper got wrong.
let epochJumped = try! WorkoutMessageEnvelope(
    kind: .checkpoint,
    sender: .watch,
    sessionID: acceptSession.id,
    payload: WorkoutCheckpoint(
        replica: WorkoutReplica(
            session: acceptSession,
            owner: .watch,
            version: SessionVersion(ownershipEpoch: 9, revision: 0)
        )
    )
)
expect(
    acceptPhone.receive(epochJumped) == .stale,
    "a checkpoint from another ownership epoch is rejected, not adopted"
)

// Phase timer snapshot replication test:
let routineForSync = GymSessionRoutine.defaultCompleteGymVisit()
let routineSessionSync = WorkoutSession.from(routine: routineForSync, templates: [], library: ExerciseLibrary.byID)
let (pCoord, pWire) = makeCoordinator(.phone, "phaseTimerPhone")
let (wCoord, wWire) = makeCoordinator(.watch, "phaseTimerWatch")
pCoord.start(routineSessionSync)
let phaseTimerSnap = PhaseTimerSnapshot(endDate: Date().addingTimeInterval(900), totalSeconds: 900)
pCoord.mutate(session: routineSessionSync, currentExerciseIndex: 0, restTimer: nil, isWorkoutPaused: false, phaseTimer: phaseTimerSnap)
let phaseCheckEnvelope = pWire.last(.checkpoint) ?? pWire.last(.ownershipOffer)!
expect(wCoord.receive(phaseCheckEnvelope) == .applied, "Watch adopts phase timer checkpoint")
expect(wCoord.replica?.phaseTimer?.totalSeconds == 900, "Watch replica contains phase timer snapshot")

// MARK: - Issue #80: phase-scoped exercise navigation (ActiveWorkoutManager)

MainActor.assumeIsolated {
    // A routine whose first three phases all carry exercises, so advancing has
    // somewhere distinct to land each time.
    let templates = ExerciseLibrary.defaultTemplates()
    var routine = GymSessionRoutine.defaultCompleteGymVisit(templates: templates)
    let withExercises = templates.filter { !$0.exercises.isEmpty }
    if withExercises.count >= 3 {
        for (offset, phaseType) in [GymSessionPhaseType.preCardio, .warmupStretches, .mainStrength].enumerated() {
            if let idx = routine.phases.firstIndex(where: { $0.phaseType == phaseType }) {
                routine.phases[idx].templateID = withExercises[offset].id
            }
        }
    }

    let session = WorkoutSession.from(
        routine: routine,
        templates: templates,
        library: ExerciseLibrary.byID
    )

    let manager = ActiveWorkoutManager(
        localDevice: .phone,
        repository: ActiveWorkoutRepository(directory: root.appendingPathComponent("phaseNav"))
    )
    manager.start(session, broadcast: false)

    let phase0 = manager.session?.exerciseIndices(inPhase: 0) ?? []
    expect(
        phase0.contains(manager.currentExerciseIndex),
        "starting a routine lands on an exercise inside phase 0"
    )

    // Walking to the end of phase 0 must not spill into phase 1.
    for _ in 0..<(phase0.count + 3) { manager.goToNextExercise() }
    expect(
        phase0.contains(manager.currentExerciseIndex),
        "Next never navigates past the end of the current phase"
    )
    expect(
        manager.currentExerciseIndex == phase0.last,
        "Next stops on the last exercise of the current phase"
    )
    expect(!manager.hasNextExerciseInPhase, "no next exercise reported at the phase boundary")

    // A phase with no exercises of its own must not surface another phase's
    // work. The default routine's cardio phase has no linked template, so
    // starting it should show the phase card, not the first strength lift.
    let bareRoutineSession = WorkoutSession.from(
        routine: GymSessionRoutine.defaultCompleteGymVisit(templates: templates),
        templates: templates,
        library: ExerciseLibrary.byID
    )
    let bare = ActiveWorkoutManager(
        localDevice: .phone,
        repository: ActiveWorkoutRepository(directory: root.appendingPathComponent("barePhase"))
    )
    bare.start(bareRoutineSession, broadcast: false)
    if bareRoutineSession.exerciseIndices(inPhase: 0).isEmpty {
        expect(
            bare.currentExercise == nil,
            "a phase with no exercises shows no exercise, not the next phase's work"
        )
    }
    // Advancing to a phase that does have exercises surfaces them again.
    if let populated = bareRoutineSession.phases.indices.first(where: {
        !bareRoutineSession.exerciseIndices(inPhase: $0).isEmpty
    }) {
        bare.selectPhase(at: populated)
        expect(
            bare.currentExercise != nil,
            "selecting a phase that has exercises surfaces that phase's work"
        )
        expect(
            bare.currentExercise?.phaseIndex == populated,
            "the surfaced exercise belongs to the selected phase"
        )
    }

    // Advancing the phase is what moves you on — and it repositions the exercise.
    // Rest belongs to the phase/set that started it and cannot cross this boundary.
    manager.restTimer.start(seconds: 120)
    manager.advancePhase()
    let phase1 = manager.session?.exerciseIndices(inPhase: 1) ?? []
    expect(manager.session?.currentPhaseIndex == 1, "advancePhase moves to phase 1")
    expect(
        !manager.restTimer.isRunning && !manager.restTimer.isPaused,
        "advancePhase stops rest from the completed phase"
    )
    expect(
        phase1.contains(manager.currentExerciseIndex),
        "advancing a phase repositions the live exercise into that phase"
    )
    expect(
        manager.currentExerciseIndex == phase1.first,
        "advancing lands on the new phase's first unfinished exercise"
    )

    // Going back a phase repositions too and also clears phase-local rest.
    manager.restTimer.start(seconds: 120)
    manager.restTimer.pause()
    manager.previousPhase()
    expect(
        !manager.restTimer.isRunning && !manager.restTimer.isPaused,
        "previousPhase stops rest from the phase being left"
    )
    expect(
        phase0.contains(manager.currentExerciseIndex),
        "previousPhase repositions the live exercise back into the earlier phase"
    )
    expect(!manager.hasPreviousExerciseInPhase || phase0.count > 1, "phase-relative Previous is consistent")

    manager.restTimer.sync(
        endDate: Date().addingTimeInterval(-10),
        totalSeconds: 120
    )
    expect(manager.restTimer.isOvertime, "selectPhase setup enters rest overtime")
    manager.selectPhase(at: 1)
    expect(
        !manager.restTimer.isRunning && !manager.restTimer.isPaused,
        "selectPhase stops rest when selecting a different phase"
    )
    manager.selectPhase(at: 0)

    // MARK: #90 — availability must agree with what the action does
    //
    // These are the properties the iPhone and Watch navigation controls bind
    // to. The bug was that the views gated on the index into the flat
    // `exercises` array instead, which is not a phase bound, so a control could
    // be enabled while its action did nothing.

    // The contract, stated directly: a control is enabled exactly when pressing
    // it moves. Checked at every position of every phase, in both directions.
    for phaseIndex in (manager.session?.phases.indices ?? 0..<0) {
        manager.selectPhase(at: phaseIndex)
        let scope = manager.session?.exerciseIndices(inPhase: phaseIndex) ?? []
        for index in scope {
            manager.currentExerciseIndex = index

            let claimsNext = manager.hasNextExerciseInPhase
            manager.goToNextExercise()
            let movedNext = manager.currentExerciseIndex != index
            expect(
                claimsNext == movedNext,
                "phase \(phaseIndex) index \(index): Next availability matches whether Next moves"
            )

            manager.currentExerciseIndex = index
            let claimsPrevious = manager.hasPreviousExerciseInPhase
            manager.goToPreviousExercise()
            let movedPrevious = manager.currentExerciseIndex != index
            expect(
                claimsPrevious == movedPrevious,
                "phase \(phaseIndex) index \(index): Previous availability matches whether Previous moves"
            )
            manager.currentExerciseIndex = index
        }
    }

    // The two specific mis-reports the global bound produced. Both need a phase
    // that actually holds more than one exercise to be meaningful.
    if let richPhase = manager.session?.phases.indices.first(where: {
        (manager.session?.exerciseIndices(inPhase: $0).count ?? 0) > 1
    }) {
        let scope = manager.session?.exerciseIndices(inPhase: richPhase) ?? []
        let total = manager.session?.exercises.count ?? 0
        manager.selectPhase(at: richPhase)

        // End of a phase that is not the end of the workout.
        manager.currentExerciseIndex = scope.last!
        expect(
            !manager.hasNextExerciseInPhase,
            "no next exercise at a phase boundary"
        )
        if scope.last! < total - 1 {
            expect(
                !manager.hasNextExerciseInPhase,
                "no next exercise at a phase boundary even though later exercises exist in the flat array"
            )
        }

        // Start of a phase whose global index is non-zero.
        manager.currentExerciseIndex = scope.first!
        expect(
            !manager.hasPreviousExerciseInPhase,
            "no previous exercise at the start of a phase"
        )
        if scope.first! > 0 {
            expect(
                !manager.hasPreviousExerciseInPhase,
                "no previous exercise at a phase start even though earlier exercises exist in the flat array"
            )
        }
    }

    // hasNextPhase drives the Watch's Next Exercise / Next Phase / Finish
    // choice, so "last exercise of a phase" must not read as "end of workout".
    if let phaseCount = manager.session?.phases.count, phaseCount > 1 {
        manager.selectPhase(at: 0)
        expect(manager.hasNextPhase, "a routine mid-way reports a further phase")
        manager.selectPhase(at: phaseCount - 1)
        expect(!manager.hasNextPhase, "the final phase reports no further phase")
    }

    // A plain template session must be untouched by phase scoping.
    let plainManager = ActiveWorkoutManager(
        localDevice: .phone,
        repository: ActiveWorkoutRepository(directory: root.appendingPathComponent("plainNav"))
    )
    plainManager.start(
        WorkoutSession.from(template: templates[0], library: ExerciseLibrary.byID),
        broadcast: false
    )
    let plainCount = plainManager.session?.exercises.count ?? 0
    if plainCount > 1 {
        plainManager.currentExerciseIndex = 0
        expect(!plainManager.hasPreviousExerciseInPhase, "plain session: no previous at the first exercise")
        expect(plainManager.hasNextExerciseInPhase, "plain session: a next exists at the first exercise")
        plainManager.currentExerciseIndex = plainCount - 1
        expect(!plainManager.hasNextExerciseInPhase, "plain session: no next at the last exercise")
        expect(plainManager.hasPreviousExerciseInPhase, "plain session: a previous exists at the last exercise")
    }
    expect(!plainManager.hasNextPhase, "plain session never reports a next phase")

    // #92: the default routine now supplies real exercises without linked
    // templates in cardio, warm-up, cool-down and core phases. Exercise
    // selection and navigation use the same manager path as linked strength.
    let guidedSession = WorkoutSession.from(
        routine: GymSessionRoutine.defaultCompleteGymVisit(templates: templates),
        templates: templates,
        library: ExerciseLibrary.byID
    )
    let guidedManager = ActiveWorkoutManager(
        localDevice: .watch,
        repository: ActiveWorkoutRepository(directory: root.appendingPathComponent("guidedPhaseNav"))
    )
    guidedManager.start(guidedSession, broadcast: false)
    expect(
        guidedManager.currentExercise?.name == "Elliptical",
        "default cardio materialization is visible to the active manager"
    )
    guidedManager.goToNextExercise()
    expect(
        guidedManager.currentExercise?.name == "Treadmill Incline",
        "manager navigates the default cardio item list"
    )
    if let warmupIndex = guidedManager.session?.phases.firstIndex(where: {
        $0.phaseType == .warmupStretches
    }) {
        guidedManager.selectPhase(at: warmupIndex)
        expect(
            guidedManager.currentExercise?.name == "Leg Swings",
            "selecting Dynamic Warm-Up lands on its first materialized item"
        )
        guidedManager.goToNextExercise()
        expect(
            guidedManager.currentExercise?.name == "Arm Circles",
            "Watch manager navigates materialized warm-up items"
        )
    }
    if let saunaIndex = guidedManager.session?.phases.firstIndex(where: {
        $0.phaseType == .saunaRecovery
    }) {
        guidedManager.selectPhase(at: saunaIndex)
        expect(
            guidedManager.currentExercise == nil,
            "selecting Sauna retains the intentional timer-only presentation"
        )
    }
}

// MARK: - Issue #81: timers keep counting past zero and never auto-advance

MainActor.assumeIsolated {
    // Phase timer already 3 seconds past its target.
    let phaseTimer = PhaseTimerManager()
    phaseTimer.sync(endDate: Date().addingTimeInterval(-3), totalSeconds: 600)
    expect(phaseTimer.isOvertime, "a past end date syncs as overtime, not as stopped")
    expect(phaseTimer.overtimeSeconds >= 2, "overtime reflects how far past zero the phase is")
    expect(phaseTimer.isRunning, "a phase in overtime keeps running")
    expect(phaseTimer.totalSeconds == 600, "overtime sync retains the phase target")
    expect(phaseTimer.formattedRemaining.hasPrefix("+"), "overtime formats with a leading +")

    // Extending pulls it back into a normal countdown.
    phaseTimer.add(seconds: 300)
    expect(!phaseTimer.isOvertime, "extending from overtime returns to a countdown")
    expect(!phaseTimer.hasCompleted, "extending re-arms the completion alert")

    // Paused overtime survives as overtime rather than collapsing to zero.
    let pausedPhase = PhaseTimerManager()
    pausedPhase.syncPaused(remainingSeconds: -45, totalSeconds: 900)
    expect(pausedPhase.isOvertime, "negative paused remaining decodes as overtime")
    expect(pausedPhase.overtimeSeconds == 45, "paused overtime retains its elapsed value")

    // Rest timer: same rule.
    let rest = RestTimerManager(localDevice: .watch)
    rest.sync(endDate: Date().addingTimeInterval(-4), totalSeconds: 180)
    expect(rest.isOvertime, "rest timer syncs a past end date as overtime")
    expect(rest.isRunning, "a rest timer in overtime keeps running")
    expect(rest.formattedRemaining.hasPrefix("+"), "rest overtime formats with a leading +")

    rest.syncPaused(remainingSeconds: -20, totalSeconds: 180)
    expect(rest.isOvertime && rest.overtimeSeconds == 20, "rest paused overtime replicates")

    // The rule: reaching zero must never advance anything by itself.
    let templates = ExerciseLibrary.defaultTemplates()
    var overtimeRoutine = GymSessionRoutine.defaultCompleteGymVisit(templates: templates)
    if let cardio = overtimeRoutine.phases.firstIndex(where: { $0.phaseType == .preCardio }),
       let firstTemplate = templates.first(where: { !$0.exercises.isEmpty }) {
        overtimeRoutine.phases[cardio].templateID = firstTemplate.id
    }
    let overtimeSession = WorkoutSession.from(
        routine: overtimeRoutine,
        templates: templates,
        library: ExerciseLibrary.byID
    )
    let mgr = ActiveWorkoutManager(
        localDevice: .phone,
        repository: ActiveWorkoutRepository(directory: root.appendingPathComponent("overtime"))
    )
    mgr.start(overtimeSession, broadcast: false)
    let phaseBefore = mgr.session?.currentPhaseIndex
    let exerciseBefore = mgr.currentExerciseIndex

    // Drive the phase timer past zero.
    mgr.phaseTimer.sync(endDate: Date().addingTimeInterval(-1), totalSeconds: 900)
    expect(
        mgr.session?.currentPhaseIndex == phaseBefore,
        "a phase timer reaching zero does not advance the phase"
    )
    expect(
        mgr.currentExerciseIndex == exerciseBefore,
        "a phase timer reaching zero does not move the exercise"
    )

    // And an expired rest timer must not skip to the next exercise.
    mgr.restTimer.sync(endDate: Date().addingTimeInterval(-1), totalSeconds: 120)
    expect(
        mgr.currentExerciseIndex == exerciseBefore,
        "a rest timer reaching zero does not advance the exercise"
    )

    // The phase start timestamp is part of the replicated session. Advancing
    // after an ownership handoff must measure from that shared timestamp, not
    // from when this device's manager happened to be created.
    var handedOffSession = overtimeSession
    handedOffSession.currentPhaseStartedAt = Date().addingTimeInterval(-125)
    let handedOff = ActiveWorkoutManager(
        localDevice: .watch,
        repository: ActiveWorkoutRepository(directory: root.appendingPathComponent("phaseElapsed"))
    )
    handedOff.start(handedOffSession, broadcast: false)
    handedOff.advancePhase()
    let recordedElapsed = handedOff.session?.phases[0].actualDurationSeconds ?? 0
    expect(
        (120...130).contains(recordedElapsed),
        "phase duration uses the replicated phase-start timestamp across ownership handoff"
    )
}

// MARK: - Issue #82: "prepare for next phase" lead cue

MainActor.assumeIsolated {
    var cueCount = 0
    let cued = PhaseTimerManager(localDevice: .phone)
    cued.onLeadCue = { cueCount += 1; return "Next up: Warm-Up." }
    cued.start(seconds: 60, cueLeadSeconds: 30)
    expect(cued.cueLeadSeconds == 30, "lead time is retained when shorter than the phase")
    expect(cueCount == 0, "no cue while the phase is above the lead time")

    // Drive real ticks: a 4s phase with a 3s lead must cue once, and stay at
    // once while it keeps ticking below the threshold.
    var firedCount = 0
    let ticking = PhaseTimerManager(localDevice: .phone)
    ticking.onLeadCue = { firedCount += 1; return nil }
    ticking.start(seconds: 4, cueLeadSeconds: 3)
    RunLoop.current.run(until: Date().addingTimeInterval(2.5))
    expect(firedCount == 1, "the lead cue fires when the countdown crosses the lead time")
    // Run past zero so a tick lands in overtime. Exactly at 0:00 the timer
    // reads "0:00", not "+0:00" — overtime only begins on the next second.
    RunLoop.current.run(until: Date().addingTimeInterval(3.0))
    expect(firedCount == 1, "the lead cue never fires more than once per phase run")
    expect(ticking.isOvertime, "the phase keeps counting into overtime after the cue")
    expect(ticking.isRunning, "the phase is still running after passing zero")

    // Suppressed when the lead is as long as (or longer than) the phase itself.
    let shortPhase = PhaseTimerManager(localDevice: .phone)
    shortPhase.start(seconds: 20, cueLeadSeconds: 30)
    expect(shortPhase.cueLeadSeconds == 0, "a lead >= the phase duration disables the cue")
    let exactPhase = PhaseTimerManager(localDevice: .phone)
    exactPhase.start(seconds: 30, cueLeadSeconds: 30)
    expect(exactPhase.cueLeadSeconds == 0, "a lead equal to the phase duration disables the cue")

    // Only the phone speaks; the Watch still buzzes.
    expect(PhaseTimerManager(localDevice: .phone).spokenAlertsEnabled, "phone speaks phase announcements")
    expect(!PhaseTimerManager(localDevice: .watch).spokenAlertsEnabled, "watch does not duplicate spoken announcements")

    // The setting travels to the Watch with the plan cache.
    var tuned = AppSettings()
    tuned.phaseCueEnabled = true
    tuned.phaseCueLeadSeconds = 60
    let execution = WatchExecutionSettings(settings: tuned)
    expect(execution.phaseCueLeadSeconds == 60, "phase cue lead replicates in execution settings")
    if let data = try? JSONEncoder().encode(execution),
       let restored = try? JSONDecoder().decode(WatchExecutionSettings.self, from: data) {
        expect(restored.phaseCueLeadSeconds == 60, "phase cue lead survives the wire round-trip")
        expect(restored.phaseCueEnabled, "phase cue toggle survives the wire round-trip")
    } else {
        failures += 1; print("FAIL execution settings round-trip")
    }
    expect(WatchExecutionSettings().phaseCueLeadSeconds == 30, "phase cue defaults to 30 seconds")

    // A phone-led phase arrives as a timer snapshot. The Watch must arm the
    // replicated lead cue while adopting that snapshot, not silently keep the
    // timer's default cue of zero.
    let adoptedCue = PhaseTimerManager(localDevice: .watch)
    adoptedCue.sync(
        endDate: Date().addingTimeInterval(60),
        totalSeconds: 90,
        cueLeadSeconds: execution.phaseCueLeadSeconds,
        resetLeadCue: true
    )
    expect(
        adoptedCue.cueLeadSeconds == 60,
        "a replicated phase timer honours the Watch execution cue setting"
    )
}

// MARK: - Issue #85: phase-complete announcement uses the displayed 1-based number

MainActor.assumeIsolated {
    let announceSession = WorkoutSession.from(
        routine: GymSessionRoutine.defaultCompleteGymVisit(),
        templates: [],
        library: ExerciseLibrary.byID
    )
    let announcer = ActiveWorkoutManager(
        localDevice: .phone,
        repository: ActiveWorkoutRepository(directory: root.appendingPathComponent("announce"))
    )
    announcer.start(announceSession, broadcast: false)

    let first = announcer.phaseCompletionAnnouncement()
    expect(first?.hasPrefix("Phase 1 ") == true, "the first phase announces as Phase 1, not Phase 0")
    expect(
        first?.contains(announceSession.phases[0].name) == true,
        "the announcement names the phase that finished"
    )

    announcer.advancePhase()
    expect(
        announcer.phaseCompletionAnnouncement()?.hasPrefix("Phase 2 ") == true,
        "the announcement tracks the displayed phase number as phases advance"
    )
}

// MARK: - Issue #93: per-exercise timer replication

let timedExerciseID = UUID()
let timedSetID = UUID()
let exerciseSnapshot = ExerciseTimerSnapshot(
    endDate: Date().addingTimeInterval(45),
    totalSeconds: 60,
    pausedRemainingSeconds: -12,
    exerciseID: timedExerciseID,
    setID: timedSetID
)
if let encoded = try? JSONEncoder().encode(exerciseSnapshot),
   let decoded = try? JSONDecoder().decode(ExerciseTimerSnapshot.self, from: encoded) {
    expect(decoded == exerciseSnapshot, "exercise timer snapshot round-trips exactly")
    expect(
        decoded.pausedRemainingSeconds == -12,
        "exercise timer snapshot preserves paused overtime"
    )
} else {
    expect(false, "exercise timer snapshot encodes and decodes")
}

func timedSession() -> WorkoutSession {
    WorkoutSession(
        name: "Timed Holds",
        exercises: [
            SessionExercise(
                exerciseID: UUID(),
                name: "Wall Sit",
                sets: [
                    SetEntry(reps: 0, weight: 0, durationSeconds: 60),
                    SetEntry(reps: 0, weight: 0, durationSeconds: 45)
                ],
                usesWeight: false
            ),
            SessionExercise(
                exerciseID: UUID(),
                name: "Goblet Squat",
                sets: [SetEntry(reps: 8, weight: 25)]
            )
        ]
    )
}

MainActor.assumeIsolated {
    let timer = ExerciseTimerManager(localDevice: .phone)
    timer.syncPaused(remainingSeconds: -18, totalSeconds: 60)
    expect(timer.isPaused, "exercise timer adopts a paused snapshot")
    expect(timer.isOvertime, "exercise timer adopts paused overtime")
    expect(timer.overtimeSeconds == 18, "paused overtime magnitude is preserved")
    timer.resume()
    expect(timer.isRunning && timer.isOvertime, "paused overtime resumes in overtime")

    let timedRepo = repository("exercise-timer-manager")
    let manager = ActiveWorkoutManager(localDevice: .phone, repository: timedRepo)
    let session = timedSession()
    let firstSetID = session.exercises[0].sets[0].id
    let secondSetID = session.exercises[0].sets[1].id
    manager.start(session)

    expect(manager.exerciseTimerSetID == firstSetID, "timed workout arms its first set")
    expect(manager.exerciseTimer.isRunning, "timed set countdown starts running")
    expect(
        manager.exerciseTimer.totalSeconds == 60,
        "timed set countdown uses the set duration"
    )
    expect(
        timedRepo.load().activeReplica?.exerciseTimer?.setID == firstSetID,
        "the armed exercise timer is persisted for replication"
    )

    manager.toggleExerciseTimerPause()
    let paused = timedRepo.load().activeReplica?.exerciseTimer
    expect(paused?.pausedRemainingSeconds != nil, "pause is replicated as a paused snapshot")
    manager.adjustExerciseTimer(by: 15)
    let adjusted = timedRepo.load().activeReplica?.exerciseTimer
    expect(
        (adjusted?.pausedRemainingSeconds ?? 0) > (paused?.pausedRemainingSeconds ?? 0),
        "timer adjustment is replicated"
    )
    manager.resetExerciseTimer()
    let reset = timedRepo.load().activeReplica?.exerciseTimer
    expect(reset?.pausedRemainingSeconds == nil, "reset replicates a running timer")
    expect(reset?.totalSeconds == 60, "reset restores the original duration")

    var advanced = session
    advanced.exercises[0].sets[0].isCompleted = true
    manager.applyRuntimeStateForTesting(
        WorkoutRuntimeState(
            activeReplica: WorkoutReplica(
                session: advanced,
                owner: .phone,
                version: SessionVersion(ownershipEpoch: 0, revision: 20),
                currentExerciseIndex: 0
            ),
            syncStatus: .synced
        )
    )
    expect(
        manager.exerciseTimerSetID == secondSetID,
        "completing a timed set arms the next timed set"
    )
    expect(manager.exerciseTimer.totalSeconds == 45, "the next timed set gets a fresh duration")

    manager.currentExerciseIndex = 1
    expect(manager.exerciseTimerSetID == nil, "rep-based exercise has no exercise timer")
    expect(!manager.exerciseTimer.isRunning, "rep-based exercise stops the exercise timer")

    let preserveRepo = repository("exercise-timer-no-snapshot")
    let preserve = ActiveWorkoutManager(localDevice: .phone, repository: preserveRepo)
    let preserveSession = timedSession()
    preserve.start(preserveSession, broadcast: false)
    let preservedSetID = preserve.exerciseTimerSetID
    preserve.applyRuntimeStateForTesting(
        WorkoutRuntimeState(
            activeReplica: WorkoutReplica(
                session: preserveSession,
                owner: .watch,
                version: SessionVersion(ownershipEpoch: 1, revision: 1),
                currentExerciseIndex: 0,
                exerciseTimer: nil
            ),
            syncStatus: .synced
        )
    )
    expect(
        preserve.exerciseTimerSetID == preservedSetID && preserve.exerciseTimer.isRunning,
        "missing peer snapshot does not blank a newly armed exercise timer"
    )

    let synthRepo = repository("exercise-timer-synthesized-owner")
    let synthSession = timedSession()
    var synthState = WorkoutRuntimeState(
        activeReplica: WorkoutReplica(
            session: synthSession,
            owner: .watch,
            version: SessionVersion(ownershipEpoch: 1, revision: 1),
            currentExerciseIndex: 0,
            exerciseTimer: nil
        ),
        authorityState: .authoritative,
        syncStatus: .synced
    )
    _ = synthRepo.save(synthState)
    let synthOwner = ActiveWorkoutManager(localDevice: .watch, repository: synthRepo)
    expect(synthOwner.exerciseTimer.isRunning, "new owner derives a missing exercise timer")
    synthState = synthRepo.load()
    expect(
        synthState.activeReplica?.exerciseTimer?.setID == synthSession.exercises[0].sets[0].id,
        "new owner immediately publishes its synthesized exercise timer"
    )

    let overtimeSet = preserveSession.exercises[0].sets[0]
    preserve.applyRuntimeStateForTesting(
        WorkoutRuntimeState(
            activeReplica: WorkoutReplica(
                session: preserveSession,
                owner: .watch,
                version: SessionVersion(ownershipEpoch: 1, revision: 2),
                currentExerciseIndex: 0,
                exerciseTimer: ExerciseTimerSnapshot(
                    endDate: Date().addingTimeInterval(-20),
                    totalSeconds: overtimeSet.durationSeconds,
                    exerciseID: preserveSession.exercises[0].id,
                    setID: overtimeSet.id
                )
            ),
            syncStatus: .synced
        )
    )
    expect(preserve.exerciseTimer.isOvertime, "exercise timer replicates active overtime")
    expect(
        preserve.session?.exercises[0].sets[0].isCompleted == false,
        "exercise timer reaching overtime does not complete the set"
    )
    expect(preserve.currentExerciseIndex == 0, "exercise timer never auto-advances")
}

// The phone may keep editing while it is offering ownership to the Watch. Its
// final timer snapshot must be merged into the commit rather than replaced by
// the older snapshot carried in the Watch's acceptance receipt.
let (timerOfferPhone, timerOfferPhoneWire) = makeCoordinator(.phone, "timer-offer-phone")
let timerOfferSession = timedSession()
expect(timerOfferPhone.start(timerOfferSession), "phone offers timed workout")
let offeredTimer = ExerciseTimerSnapshot(
    endDate: Date().addingTimeInterval(37),
    totalSeconds: 60,
    exerciseID: timerOfferSession.exercises[0].id,
    setID: timerOfferSession.exercises[0].sets[0].id
)
_ = timerOfferPhone.mutate(
    session: timerOfferSession,
    currentExerciseIndex: 0,
    restTimer: nil,
    isWorkoutPaused: false,
    exerciseTimer: offeredTimer
)
let timerOfferWatchRepo = repository("timer-offer-watch")
let timerOfferWatch = WorkoutSyncCoordinator(
    localDevice: .watch,
    repository: timerOfferWatchRepo
)
expect(
    timerOfferWatch.receive(timerOfferPhoneWire.last(.ownershipOffer)!) == .applied,
    "watch accepts the timed workout offer"
)
if let acceptance = queuedEnvelope(.ownershipAcceptance, in: timerOfferWatchRepo) {
    expect(
        timerOfferPhone.receive(acceptance) == .applied,
        "phone commits timed workout ownership"
    )
    expect(
        timerOfferPhone.replica?.exerciseTimer == offeredTimer,
        "ownership commit preserves the latest exercise timer snapshot"
    )
} else {
    expect(false, "watch queued a timed workout acceptance")
}

// MARK: - Issue #86: a freshly started phase timer must not be blanked

MainActor.assumeIsolated {
    let startSession = WorkoutSession.from(
        routine: GymSessionRoutine.defaultCompleteGymVisit(),
        templates: [],
        library: ExerciseLibrary.byID
    )
    let starter = ActiveWorkoutManager(
        localDevice: .phone,
        repository: ActiveWorkoutRepository(directory: root.appendingPathComponent("timerStart"))
    )
    starter.start(startSession, broadcast: false)

    // Starting a routine must arm the first timed phase at its full duration.
    let firstPhase = startSession.phases[0]
    expect(firstPhase.phaseType.isTimed, "the default routine opens on a timed phase")
    expect(
        starter.phaseTimer.totalSeconds == firstPhase.durationSeconds,
        "starting a routine arms the phase timer at the phase duration"
    )
    expect(
        starter.phaseTimer.secondsRemaining > firstPhase.durationSeconds - 5,
        "the armed timer starts counting down from the full duration, not 00:00"
    )
    expect(starter.phaseTimer.isRunning, "the phase timer is running after start")

    // The reported symptom: an incoming replica carrying no phase-timer
    // snapshot must not wipe the timer this device just started.
    let emptySnapshotState = WorkoutRuntimeState(
        activeReplica: WorkoutReplica(
            session: startSession,
            owner: .watch,
            version: SessionVersion(ownershipEpoch: 1, revision: 1),
            phaseTimer: nil
        ),
        syncStatus: .synced
    )
    starter.applyRuntimeStateForTesting(emptySnapshotState)
    expect(
        starter.phaseTimer.totalSeconds == firstPhase.durationSeconds,
        "a replica with no phase-timer snapshot does not blank a running phase timer"
    )
    expect(
        starter.phaseTimer.secondsRemaining > 0,
        "the phase timer still shows time remaining after an empty snapshot arrives"
    )

    // But a genuine stop still applies: moving to an untimed phase clears it.
    if let strengthIdx = startSession.phases.firstIndex(where: { !$0.phaseType.isTimed }) {
        var untimed = startSession
        untimed.currentPhaseIndex = strengthIdx
        starter.applyRuntimeStateForTesting(
            WorkoutRuntimeState(
                activeReplica: WorkoutReplica(
                    session: untimed,
                    owner: .watch,
                    version: SessionVersion(ownershipEpoch: 1, revision: 2),
                    phaseTimer: nil
                ),
                syncStatus: .synced
            )
        )
        expect(
            !starter.phaseTimer.isRunning,
            "moving to an untimed phase still stops the phase timer"
        )
    }

    // And an overtime snapshot must survive the replica path rather than being
    // filtered into the stop branch.
    let overtimeStarter = ActiveWorkoutManager(
        localDevice: .phone,
        repository: ActiveWorkoutRepository(directory: root.appendingPathComponent("timerOvertime"))
    )
    overtimeStarter.start(startSession, broadcast: false)
    overtimeStarter.applyRuntimeStateForTesting(
        WorkoutRuntimeState(
            activeReplica: WorkoutReplica(
                session: startSession,
                owner: .watch,
                version: SessionVersion(ownershipEpoch: 1, revision: 3),
                phaseTimer: PhaseTimerSnapshot(
                    endDate: Date().addingTimeInterval(-30),
                    totalSeconds: firstPhase.durationSeconds
                )
            ),
            syncStatus: .synced
        )
    )
    expect(
        overtimeStarter.phaseTimer.isOvertime,
        "an overtime phase-timer snapshot replicates as overtime, not as stopped"
    )

    // Rest overtime must survive the manager's replica-adoption path too. A
    // timer-level sync test alone cannot catch a manager that filters out past
    // end dates before handing the snapshot to RestTimerManager.
    overtimeStarter.applyRuntimeStateForTesting(
        WorkoutRuntimeState(
            activeReplica: WorkoutReplica(
                session: startSession,
                owner: .watch,
                version: SessionVersion(ownershipEpoch: 1, revision: 4),
                restTimer: RestTimerSnapshot(
                    endDate: Date().addingTimeInterval(-30),
                    totalSeconds: 120
                )
            ),
            syncStatus: .synced
        )
    )
    expect(
        overtimeStarter.restTimer.isOvertime,
        "an overtime rest-timer snapshot replicates as overtime, not as stopped"
    )
}

// Issue #94: only an explicit guided completion advances. Multiple intervals
// remain on the same exercise until its final one, and the phase boundary is
// never crossed automatically.
MainActor.assumeIsolated {
    let guided = SessionExercise(
        exerciseID: UUID(),
        name: "Hip Mobility",
        sets: [
            SetEntry(reps: 0, weight: 0, durationSeconds: 30),
            SetEntry(reps: 0, weight: 0, durationSeconds: 30)
        ],
        restSeconds: 0,
        usesWeight: false,
        phaseIndex: 0
    )
    let next = SessionExercise(
        exerciseID: UUID(),
        name: "Arm Circles",
        sets: [SetEntry(reps: 0, weight: 0, durationSeconds: 30)],
        restSeconds: 0,
        usesWeight: false,
        phaseIndex: 0
    )
    let laterPhase = SessionExercise(
        exerciseID: UUID(),
        name: "Strength Mobility",
        sets: [SetEntry(reps: 0, weight: 0, durationSeconds: 20)],
        restSeconds: 0,
        usesWeight: false,
        phaseIndex: 1
    )
    let guidedSession = WorkoutSession(
        name: "Guided",
        exercises: [guided, next, laterPhase],
        phases: [
            GymSessionLogPhase(phaseType: .warmupStretches, name: "Warm-Up"),
            GymSessionLogPhase(phaseType: .mainStrength, name: "Strength")
        ]
    )
    let guidedManager = ActiveWorkoutManager(
        localDevice: .phone,
        repository: ActiveWorkoutRepository(directory: root.appendingPathComponent("guidedStepper"))
    )
    guidedManager.start(guidedSession, broadcast: false)

    guidedManager.completeGuidedTimedSetAndAdvance()
    expect(
        guidedManager.currentExerciseIndex == 0,
        "guided stepper stays on an exercise while another interval remains"
    )
    expect(
        guidedManager.session?.exercises[0].completedSets == 1,
        "guided Done records the current interval"
    )

    guidedManager.completeGuidedTimedSetAndAdvance()
    expect(
        guidedManager.currentExerciseIndex == 1,
        "guided Done and Next advances after the final interval"
    )
    expect(
        guidedManager.session?.exercises[0].isComplete == true,
        "guided completion ticks the finished exercise"
    )

    guidedManager.completeGuidedTimedSetAndAdvance()
    expect(
        guidedManager.currentExerciseIndex == 1,
        "guided completion at a phase boundary never advances the phase"
    )
    expect(
        guidedManager.session?.currentPhaseIndex == 0,
        "guided completion leaves phase changes explicit"
    )

    guidedManager.selectPhase(at: 1)
    expect(
        guidedManager.currentExercise?.usesGuidedTimedStepper == true,
        "a timed non-weighted exercise inside strength still uses the guided stepper"
    )
}

// MARK: - Issue #96: live exercise add/swap/remove and identity sync

MainActor.assumeIsolated {
    let phaseA = SessionExercise(
        exerciseID: UUID(),
        name: "Warm A",
        sets: [SetEntry(reps: 10, weight: 0)],
        usesWeight: false,
        phaseIndex: 0
    )
    let phaseB = SessionExercise(
        exerciseID: UUID(),
        name: "Warm B",
        sets: [SetEntry(reps: 10, weight: 0)],
        usesWeight: false,
        phaseIndex: 0
    )
    let selectedLater = SessionExercise(
        exerciseID: UUID(),
        name: "Selected Later",
        sets: [SetEntry(reps: 10, weight: 0)],
        usesWeight: false,
        phaseIndex: 2
    )
    let liveSession = WorkoutSession(
        name: "Live Structural Edits",
        exercises: [phaseA, phaseB, selectedLater],
        phases: [
            GymSessionLogPhase(phaseType: .warmupStretches, name: "Warm-Up"),
            GymSessionLogPhase(phaseType: .mainStrength, name: "Strength"),
            GymSessionLogPhase(phaseType: .postStretching, name: "Cool-Down")
        ],
        currentPhaseIndex: 0
    )
    let liveRepo = repository("live-structural-edits")
    let liveManager = ActiveWorkoutManager(
        localDevice: .phone,
        repository: liveRepo
    )
    liveManager.start(liveSession)
    liveManager.selectPhase(at: 2)
    let selectedIDBeforeAdd = liveManager.currentExercise?.id
    let selectedIndexBeforeAdd = liveManager.currentExerciseIndex
    let bench = ExerciseLibrary.all.first {
        $0.name == "Barbell Bench Press"
    }!
    expect(
        liveManager.addExercise(
            bench,
            toPhase: 0,
            settings: AppSettings(),
            preferredWeight: 80
        ),
        "manager adds an exercise to a live phase"
    )
    expect(
        liveManager.session?.exerciseIndices(inPhase: 0).last == 2,
        "manager insert lands at the end of the requested phase"
    )
    expect(
        liveManager.currentExercise?.id == selectedIDBeforeAdd,
        "adding before the selected exercise preserves its instance identity"
    )
    expect(
        liveManager.currentExerciseIndex == selectedIndexBeforeAdd + 1,
        "selected index follows its identity after an earlier insertion"
    )
    expect(
        liveRepo.load().activeReplica?.currentExerciseID
            == selectedIDBeforeAdd,
        "structural edit checkpoint carries the selected exercise UUID"
    )

    expect(
        liveManager.removeExercise(at: 0),
        "manager removes an unstarted exercise"
    )
    expect(
        liveManager.currentExercise?.id == selectedIDBeforeAdd,
        "removing another exercise preserves the one on screen"
    )

    var completedSession = liveManager.session!
    completedSession.exercises[0].sets[0].isCompleted = true
    liveManager.applyRuntimeStateForTesting(
        WorkoutRuntimeState(
            activeReplica: WorkoutReplica(
                session: completedSession,
                owner: .phone,
                version: SessionVersion(ownershipEpoch: 0, revision: 50),
                currentExerciseIndex: liveManager.currentExerciseIndex,
                currentExerciseID: liveManager.currentExercise?.id
            ),
            authorityState: .authoritative,
            syncStatus: .synced
        )
    )
    expect(
        !liveManager.removeExercise(at: 0),
        "manager blocks removal when completed sets would be lost"
    )

    let selectedIndexBeforeSwap = liveManager.currentExerciseIndex
    let cable = ExerciseLibrary.all.first {
        $0.name == "Incline Dumbbell Press"
    }!
    expect(
        liveManager.replaceExercise(
            at: selectedIndexBeforeSwap,
            with: cable,
            settings: AppSettings()
        ),
        "manager swaps an unstarted current exercise"
    )
    expect(
        liveManager.currentExerciseIndex == selectedIndexBeforeSwap
            && liveManager.currentExercise?.exerciseID == cable.id
            && liveManager.currentExercise?.phaseIndex == 2,
        "swap keeps position and phase while selecting the replacement"
    )

    let alternatives = liveManager.contextualExerciseAlternatives(limit: 4)
    expect(
        alternatives.count <= 4
            && !alternatives.contains(where: {
                $0.id == liveManager.currentExercise?.exerciseID
            }),
        "Watch contextual list stays short and excludes the current exercise"
    )

    // Deliberately provide a stale numeric index. The stable UUID must win
    // when the counterpart adopts a structural checkpoint.
    let mirroredSession = liveManager.session!
    let mirroredSelectedID = mirroredSession.exercises.last!.id
    let mirrorManager = ActiveWorkoutManager(
        localDevice: .watch,
        repository: repository("live-structural-mirror")
    )
    mirrorManager.applyRuntimeStateForTesting(
        WorkoutRuntimeState(
            activeReplica: WorkoutReplica(
                session: mirroredSession,
                owner: .phone,
                version: SessionVersion(ownershipEpoch: 3, revision: 4),
                currentExerciseIndex: 0,
                currentExerciseID: mirroredSelectedID
            ),
            authorityState: .mirror,
            syncStatus: .synced
        )
    )
    expect(
        mirrorManager.currentExercise?.id == mirroredSelectedID,
        "counterpart resolves selected identity before a stale array index"
    )

    let savedTemplate = WorkoutTemplate(
        name: "Saved Plan",
        exercises: [
            TemplateExercise(
                exerciseID: bench.id,
                name: bench.name
            )
        ]
    )
    let savedRoutine = GymSessionRoutine.defaultCompleteGymVisit(
        templates: [savedTemplate]
    )
    let templateSnapshot = savedTemplate
    let routineSnapshot = savedRoutine
    let isolationManager = ActiveWorkoutManager(
        localDevice: .phone,
        repository: repository("live-plan-isolation")
    )
    isolationManager.start(
        WorkoutSession.from(
            routine: savedRoutine,
            templates: [savedTemplate],
            library: ExerciseLibrary.byID
        ),
        broadcast: false
    )
    _ = isolationManager.addExercise(
        cable,
        toPhase: isolationManager.session?.currentPhaseIndex ?? 0
    )
    expect(
        savedTemplate == templateSnapshot && savedRoutine == routineSnapshot,
        "live add never mutates the saved template or routine values"
    )

    let timedEditManager = ActiveWorkoutManager(
        localDevice: .phone,
        repository: repository("live-timed-structural-edit")
    )
    let timedEditSession = timedSession()
    timedEditManager.start(timedEditSession, broadcast: false)
    let timedSetID = timedEditManager.exerciseTimerSetID
    timedEditManager.exerciseTimer.sync(
        endDate: Date().addingTimeInterval(20),
        totalSeconds: 60
    )
    let remainingBeforeEdit = timedEditManager.exerciseTimer.secondsRemaining
    expect(
        timedEditManager.addExercise(
            bench,
            toPhase: 0,
            settings: AppSettings()
        ),
        "structural edit succeeds while a timed set is running"
    )
    let remainingAfterEdit = timedEditManager.exerciseTimer.secondsRemaining
    expect(
        timedEditManager.exerciseTimerSetID == timedSetID
            && timedEditManager.exerciseTimer.isRunning
            && remainingAfterEdit <= remainingBeforeEdit
            && remainingAfterEdit >= remainingBeforeEdit - 1,
        "unrelated structural edit preserves the running exercise timer"
    )
    timedEditManager.toggleExerciseTimerPause()
    let pausedRemaining = timedEditManager.exerciseTimer.secondsRemaining
    timedEditManager.addSet(exerciseIndex: 0)
    expect(
        timedEditManager.exerciseTimerSetID == timedSetID
            && timedEditManager.exerciseTimer.isPaused
            && timedEditManager.exerciseTimer.secondsRemaining == pausedRemaining,
        "adding a set preserves the paused exercise timer"
    )
    timedEditManager.removeSet(exerciseIndex: 0, setIndex: 2)
    expect(
        timedEditManager.exerciseTimerSetID == timedSetID
            && timedEditManager.exerciseTimer.isPaused
            && timedEditManager.exerciseTimer.secondsRemaining == pausedRemaining,
        "removing an unrelated set preserves the paused exercise timer"
    )
}

try? FileManager.default.removeItem(at: root)
print(failures == 0 ? "ALL SYNC TESTS PASSED" : "\(failures) SYNC TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
