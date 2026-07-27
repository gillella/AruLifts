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

try? FileManager.default.removeItem(at: root)
print(failures == 0 ? "ALL SYNC TESTS PASSED" : "\(failures) SYNC TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
