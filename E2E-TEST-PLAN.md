# AruLifts — End-to-End Test Plan

Living document. Captures Aravind's real gym flow as requirements, and the
E2E test goals derived from them. Tested on iPhone + Watch simulators.
More functionality (tracking, food, etc.) will be described in later
sessions — add new goals below as they arrive.

## User's real-world flow (source of truth for requirements)

Morning gym sessions, 6–7 days/week:

1. **Cardio** — 10–15 min at the start of every session.
2. **Warm-up** — brief, after cardio.
3. **Main lift block** — rotates by day:
   - *Push / upper-body push* day — bench press, etc.
   - *Pull / back* day — rows and other upper-body pulls ("pull" in Aravind's
     terminology includes rows and general upper-body pulling).
   - *Leg* day — leg press, lunges, etc.
4. **Stretching** — after lifting; wants guided stretching content.
5. **Recovery** — sauna, steam room, bath — wants these captured too.
6. **Food** — protein shake, sandwich, etc. — capture planned for later.

Can do **multiple workouts per day**.

## Goal 1 — Workout creation (CURRENT)

**Goal:** A user can intuitively create named workout plans (Upper Body,
Push, Pull, Legs, etc.), and when a category is chosen the app intelligently
suggests exercises that belong to that routine. The user can browse
suggestions, view videos/pictures/instructions, select exercises, and set
sets/reps/weights to compose a complete plan — on iPhone, with the result
visible/usable on Watch.

### Requirements checklist

| # | Requirement | Status (2026-07-21, simulators) |
|---|-------------|--------|
| 1.1 | Create a workout with a name and category (Upper Body, Push, Pull, Legs, Lower Body, Full Body, Core, Cardio, Custom) | ✅ PASS — all 10 categories in picker; "Push Day"/"Pull Day" created |
| 1.2 | Selecting a category surfaces **suggested exercises for that category** (e.g. Push → bench press, overhead press) | ❌ FAIL — picker is a flat A–Z list + name search; for a Push workout it leads with Back Squat/Barbell Curl/Barbell Row |
| 1.3 | Browse/check exercises: pictures + videos + instructions before adding | ⚠️ PARTIAL — detail view has muscle tags, numbered form steps, tips; but media is an SF-symbol placeholder (no videos bundled), and there is **no way to preview details from inside the Add Exercise picker** |
| 1.4 | Add exercises with sets, reps, weight (and rest) per exercise | ✅ PASS — steppers for sets/reps, ±2.5 weight, rest picker; weight prefills from last-used |
| 1.5 | Capture cardio (type + duration, e.g. 10–15 min treadmill) as part of a plan | ❌ FAIL — no duration-based exercise type; library has no treadmill/bike/elliptical (Kettlebell Swing is the only cardio-adjacent entry) |
| 1.6 | Stretching guidance: stretching exercises with instructions available to add to a plan | ❌ FAIL — zero stretching content in the 24-exercise library; no stretching muscle group/category |
| 1.7 | Capture recovery activities (sauna, steam room, bath) | ❌ FAIL — concept absent from models and UI |
| 1.8 | Multiple workouts per day supported | ⏸ NOT TESTED — belongs to Goal 2 (tracking) |
| 1.9 | Edit an existing workout: rename, recategorize, reorder/remove exercises | ✅ PASS — drag-reorder persisted after save; delete buttons present; name/category/steppers editable |
| 1.10 | Created workout syncs to / is startable from the Watch app | ⚠️ PARTIAL — watch is mirror-only ("Start a workout on your iPhone"); cannot browse or start templates from the watch. Active sessions do appear once synced |
| 1.11 | Routine phases can directly edit, persist and cache ordered timed or reps × sets exercise targets with library suggestions and free-text fallback | ✅ IMPLEMENTED (#95) — model/persistence/materialization/Watch-cache contracts and builds pass; read-only Simulator rendering passed, interactive edit walkthrough pending |
| — | Templates persist across app relaunch | ✅ PASS — 5 plans intact after terminate/relaunch |

### E2E test procedure

**iPhone simulator:**
1. Build + install + launch AruLifts on an iPhone simulator.
2. My Workouts → create "Push Day" with category Push.
3. Observe whether exercise suggestions reflect the Push category (req 1.2).
4. Add Bench Press + Overhead Press; set 4×8 @ 135 lb, rest 3:00.
5. Open an exercise's detail page — verify instructions/tips/video (req 1.3).
6. Save; verify it appears in My Workouts with correct category badge,
   exercise count, estimated duration.
7. Repeat for "Pull Day" (rows) and "Leg Day" (leg press/lunges).
8. Edit Push Day: reorder, remove one exercise, change reps; verify persisted.
9. Attempt to represent cardio (1.5), stretching (1.6), sauna/steam (1.7) —
   record what's possible vs. missing.
10. Relaunch app — verify templates persist.

**Watch simulator:**
11. Launch Watch app paired with the iPhone simulator.
12. Verify created workouts appear on the Watch (template sync).
13. Start one created workout from the Watch; verify exercises/sets/reps match.

### Routine phase-item composer checks (#95)

1. Open Complete Gym Visit read-only. Verify each non-empty phase lists its
   exercise names and target summaries with no edit controls.
2. Tap Edit and open Dynamic Warm-Up. Add an exercise, type part of a library
   name and choose a filtered suggestion; add a second unmatched free-text name.
3. Switch one item between Time and Reps. Verify Time accepts seconds and shows
   the derived phase-duration default when blank; verify Reps exposes separate
   repetitions and sets steppers.
4. Move both new items up/down, remove one, and Save. Read-only mode must show
   the exact final order and targets.
5. Link a template. Verify the composer says the template runs and phase items
   are fallback. Edit fallback items and verify the linked template is unchanged.
6. Terminate and relaunch. Reopen the routine and verify names, order and targets
   persisted.
7. Start the routine without a linked template and verify the active phase uses
   the edited list. Rebuild the Watch plan cache and start it offline; verify the
   Watch receives the same list and targets.

`Tests/run.sh` covers target inference, derived duration parity, JSON relaunch,
add/remove/reorder state, active-session materialization, linked-template
precedence/isolation and Watch offline-cache construction. Visible autocomplete,
controls, read-only rendering and save/relaunch flow remain simulator acceptance
checks (AC-B13–B21).

### Known gaps found by code inspection (verify during test)

- `ExercisePickerView` ([ExerciseLibraryView.swift:104](AruLifts/Views/ExerciseLibraryView.swift:104))
  filters by **name search only** — no category-based suggestion (req 1.2 ✗ in code).
- Exercise library has 25 exercises; no dedicated stretching entries, no
  sauna/steam/recovery concept anywhere in models (reqs 1.6, 1.7 ✗ in code).
- Cardio is a category and a muscle group, but `TemplateExercise` is
  sets/reps/weight-shaped — no duration field for "15 min cardio" (req 1.5 partial).

## Goal 2 — Watch-first workout tracking (CURRENT)

**Goal:** Start a planned workout on either device, put the iPhone down, and
run the complete workout from Apple Watch with one-tap set logging, automatic
rest coaching, durable offline state, unambiguous ownership, and exactly one
history/Health result.

### Requirements checklist

| # | Requirement | Evidence required | Current status |
|---|-------------|-------------------|----------------|
| 2.1 | A phone-started workout is not called synced until the Watch has persisted and acknowledged that exact session | Protocol/state test plus paired-simulator handoff | ✅ PASS — 2026-07-27 paired sims: offer→acceptance→commit→ack observed, both sides converge to epoch 1 |
| 2.2 | After acknowledgment, phone says the Watch is ready and can be put away | iPhone UI inspection and paired-simulator run | ✅ PASS — 2026-07-27 banner reads “Ready on Apple Watch — open AruLifts on your wrist” |
| 2.3 | Watch owns edits after handoff; phone is a read-only mirror unless takeover is acknowledged | Ownership epoch/revision tests and two-device edit attempt | ✅ PASS — 2026-07-27 phone Cancel/Finish/set rows disabled while Watch owns |
| 2.4 | Watch current-set screen prominently shows exercise, set, weight, reps and plates with one large completion action | Watch UI inspection, VoiceOver labels, physical glance test | ✅ IMPLEMENTED; runtime validation pending |
| 2.5 | Completing a set starts rest, advances to the next incomplete set, provides haptic feedback, and offers a five-second Undo | Logic/UI test and Watch simulator run | ✅ IMPLEMENTED; runtime validation pending |
| 2.6 | Weight/reps are adjustable without crowding the normal completion screen | Watch UI inspection and Digital Crown test | ✅ IMPLEMENTED; physical Crown validation pending |
| 2.7 | Rest screen shows countdown and next-set context, supports +30/Skip, closes at zero, and speaks/haptics at 10/3/2/1/Go | Timer tests, simulator UI, physical audio/haptic test | ✅ IMPLEMENTED; physical cues pending |
| 2.8 | Workout can pause/resume safely, and finish warns when sets remain incomplete | Logic/UI tests and simulator interaction | ✅ IMPLEMENTED; runtime validation pending |
| 2.9 | Watch edits survive disconnection, app termination and relaunch, then synchronize without reverting newer work | Persistence/state tests and paired-simulator offline run | 🚧 IN PROGRESS |
| 2.10 | Duplicate, stale, reordered and former-owner updates cannot overwrite newer state | Pure protocol injection tests | 🚧 IN PROGRESS |
| 2.11 | Finish/cancel is durable and a stale application context cannot resurrect the workout | Tombstone tests and relaunch scenario | ✅ PASS — 2026-07-27 finish on phone tombstoned both replicas; Watch cleared |
| 2.12 | A finished session is inserted into app history and progression exactly once | Pure duplicate-finalization test plus simulator history | ✅ PASS — 2026-07-27 Home showed exactly 1 workout after finish |
| 2.13 | Apple Health receives exactly one workout, tagged by app session ID, even when Watch result delivery is retried/lost | Health query/save code test plus physical Health inspection | ✅ IMPLEMENTED; physical confirmation pending |
| 2.14 | Latest/today workout plans are cached and startable from Watch without the phone | Cache tests and offline Watch start | ⏳ PENDING |
| 2.15 | Phone can explicitly take over only through an acknowledged ownership transfer | Protocol tests and paired-simulator takeover | ✅ PASS — 2026-07-27 takeoverRequest→acceptance→commit, epoch 2, phone authoritative |
| 2.16 | Sync UI distinguishes Saved locally, Waiting, Ready on Watch, and Synced rather than equating reachability with receipt | UI state tests and disconnected screenshots | ✅ PASS — 2026-07-27 Waking / Couldn’t wake + Retry / Ready on Watch all rendered |
| 2.17 | Adaptive rest and previous-performance guidance are configurable and understandable | Logic tests and Watch UI inspection | ⏳ PENDING |
| 2.18 | Speech, haptics, coaching level, contrast, large targets and VoiceOver are configurable/accessible | Settings inspection, Accessibility Inspector, physical Watch | ⏳ PENDING |
| 2.19 | Live Activity/Smart Stack is included only if lifecycle tests do not produce stale/lingering workout state | Platform feasibility check and lifecycle tests | ⏳ PENDING |
| 2.20 | User-facing guidance explains phone-start, Watch-start, offline, takeover and finish/sync flows | In-app guide inspection | ⏳ PENDING |
| 2.21 | Exercise navigation is phase-scoped: Previous/Next is disabled exactly at the current phase boundary, and the Watch offers Next Phase instead of Finish Workout between phases | Model/manager contract tests plus paired-simulator UI inspection | ✅ IMPLEMENTED (#90); automated contract coverage added, paired-simulator UI validation pending |
| 2.22 | Each duration-based set has a replicated iPhone/Watch timer with pause, adjust, reset, overtime, explicit completion, and ownership-transfer continuity | Manager/wire tests, paired-simulator UI, physical audio/haptic check | ✅ PASS (#93) — paired sims showed the matching timer and phone→Watch pause at the same `1:17`; physical cues pending |
| 2.23 | Timed non-weighted exercises use a guided, accessible Done/Next stepper on iPhone and Watch while weighted/mixed exercises retain normal set logging | Shape/manager tests, both builds, paired-simulator guided walkthrough | ✅ PASS (#94) — automated contract/builds and paired-simulator layout pass; interaction is manager-tested because desktop UI input was locked |
| 2.24 | A live workout can add/swap/remove session-only exercises with phase-correct insertion, logged-work protection, Watch contextual swap/remove and selection-stable sync | Model/manager/wire tests, both builds, paired-simulator UI walkthrough | ✅ PASS (#96) — automated contract and both-target builds pass; paired simulators confirmed iPhone add/swap/remove plus selection-stable Watch replication. Watch menu interaction remains physical-device acceptance |

### Automated protocol and persistence tests

1. Phone offer remains phone-owned and non-editable while transfer is pending.
2. Watch persists the offered checkpoint before returning acceptance.
3. Repeating the same offer/acceptance is idempotent.
4. New ownership epoch outranks any revision from the prior owner.
5. Duplicate revision is ignored and acknowledged.
6. Reordered checkpoints converge to the newest complete snapshot; older
   checkpoints cannot overwrite it.
7. Durable outbox survives encode/decode and drains only after app acknowledgment.
8. A terminal tombstone rejects every later checkpoint/mutation for its session.
9. Duplicate finalization produces one history entry and one progression update.
10. Cached workout construction generates fresh session, exercise and set IDs.

### Phase-boundary navigation checks (#90)

1. In a multi-phase routine, open the first exercise of a later phase. Verify
   **Previous** is visibly disabled even though the flat exercise index is
   greater than zero.
2. Open the last exercise of a non-final phase. Verify **Next** is visibly
   disabled even though later phases contain exercises.
3. Repeat with a phase containing one exercise. Verify both controls are
   disabled.
4. On Watch, complete the last exercise of a non-final phase. The completion
   card must offer **Next Phase**, and pressing it must advance to the next
   phase. It must not offer **Finish Workout**.
5. At the last exercise of the final phase, verify the card offers **Finish
   Workout**; with another exercise in the current phase, verify it offers
   **Next Exercise**.
6. Repeat with a plain single-template session. Navigation must span the whole
   exercise list, and **Next Phase** must never appear.

`Tests/run.sh` covers the pure `WorkoutSession` boundary helpers.
`Tests/run_sync.sh` sweeps every exercise position and asserts that manager
availability agrees with whether the corresponding navigation action moves.
The visible disabled states and the Watch card labels remain paired-simulator
acceptance checks (AC-D11–D16), not claims made by those script suites.

### Guided phase materialization checks (#92)

1. Start the default Complete Gym Visit without editing it. Verify Pre-Workout
   Cardio shows Elliptical and Treadmill Incline as navigable exercises.
2. Advance to Dynamic Warm-Up. Walk Leg Swings → Arm Circles → Hip Mobility
   using Previous/Next on iPhone and Watch; navigation must remain phase-scoped.
3. Verify each derived timed set carries a target duration and zero rest, and
   completing one does not open the recovery rest timer.
4. Advance to Core Work and verify all four declared defaults are navigable.
5. Advance through Sauna and Steam and verify both intentionally remain
   timer-only and advanceable.
6. Start a routine containing an unmatched free-text item and verify it remains
   a usable non-weighted entry.

`Tests/run.sh` covers template parity, materialization, unknown names, empty
phases, duration derivation/clamping, rest defaults, activity classification,
and Watch-plan construction. Visible phone/Watch navigation remains a paired
simulator acceptance check (AC-D17–D20).

### Guided exercise stepper checks (#94)

1. Start the default Complete Gym Visit and advance to Dynamic Warm-Up. On both
   devices verify the first item reads **1 of 3 · Leg Swings**, the exercise
   countdown is prominent, and the whole-phase countdown remains visible.
2. Let an exercise pass zero. Verify overtime appears without completion or
   navigation. Tap **Done & Next** and verify the item gains a checkmark and
   Arm Circles opens; repeat through Hip Mobility.
3. Use a routine containing two timed intervals in one exercise. The first Done
   must start the second interval without changing exercise; the final Done may
   advance within the phase.
4. Complete the phase's last item. Verify the phase does not advance until
   **Next Phase** is tapped.
5. Place a timed non-weighted item in Main Strength and verify it uses the guided
   stepper. Verify a weighted timed hold and mixed timed/rep exercise use
   `SetLogList` instead.
6. Advance to Sauna and Steam. Verify each shows intentional Recovery phase
   guidance, its phase timer and an explicit phase action.
7. Inspect iPhone and Watch accessibility trees. Verify exercise name, position,
   interval progress and remaining/overtime time are announced, and every timer
   and Done/Next control has a label and hint.

`Tests/run.sh` covers shape selection. `Tests/run_sync.sh` covers explicit
interval completion, multi-interval behavior, phase-boundary protection and a
timed item inside strength. Both schemes must build. Visible hierarchy,
whole-phase coexistence and VoiceOver output remain paired-simulator acceptance
checks (AC-D21–D28).

### Live exercise-list editing checks (#96)

1. Start a multi-phase routine on iPhone and select an exercise in a later
   phase. Open **Exercise Options → Add Exercise**, search/filter the full
   library, and add a movement to the current phase. Verify it appears at the
   end of that phase without changing the selected exercise on either device.
2. Add to a phase that previously had no exercises. Verify the item appears in
   that phase before the next phase's flat-array run and is navigable.
3. Choose **Swap Current Exercise**. Verify the replacement keeps the same
   phase-relative position and receives template-parity sets, loading behavior,
   timing, rest, bar minimum and warmups.
4. Remove an exercise with no completed sets, confirming the warning that the
   saved plan is unchanged. Complete a set and verify both Swap and Remove are
   blocked with explanatory copy.
5. Reopen the saved template or routine and verify names, order and targets
   were not changed by any live edit.
6. On Watch, open Workout Options. Verify there is no Add/full-library action;
   Swap shows no more than six contextual same-muscle alternatives and Remove
   is available only before logging work.
7. Perform an insertion/removal before the exercise displayed on the peer.
   Inspect the replicated checkpoint and verify `currentExerciseID` preserves
   the same session instance even as `currentExerciseIndex` changes.

`Tests/run.sh` covers shared construction parity, phase insertion including an
empty phase, replacement attribution and completed-set guards.
`Tests/run_sync.sh` covers manager ownership/mutation, selected UUID stability,
checkpoint persistence/adoption, contextual-list bounds and saved-plan
isolation. The paired-simulator walkthrough confirmed the iPhone controls,
searchable full-library add, in-place swap, guarded confirmation/remove flow,
selection stability and replicated Watch exercise count/name. The Watch
Workout Options menu is build- and contract-verified but still requires
physical-device interaction because the watchOS Simulator did not expose its
accessibility tree (AC-D29–D34, AC-G8, AC-H11).

### Per-exercise timer checks (#93)

1. Start a session containing a 60-second timed set. Verify both devices show the
   countdown on the same exercise/set; navigate to a rep-based exercise and verify
   the timer disappears.
2. Pause on either device, adjust by −15/+15, and Reset. Verify the peer converges
   after every action and Reset returns to 60 seconds.
3. Let the timer cross zero. Verify it shows `+M:SS`, alerts once, and does not
   complete the set, change the exercise, or advance the phase.
4. Pause in overtime, transfer ownership, and resume. Verify overtime magnitude and
   direction survive the round-trip.
5. Complete the first timed set. Verify the next timed set starts at its own full
   target duration. Change exercises and verify no previous-set timer is attached.
6. Deliver an older checkpoint without `exerciseTimer`. Verify it cannot blank a
   locally armed matching timer.
7. Let a timed set count down, then add/remove another exercise and add/remove a set.
   Verify the current countdown continues without jumping back to its prescribed duration;
   select a different timed set and verify that target starts fresh.

`Tests/run_sync.sh` covers snapshot coding, active/paused/overtime adoption,
pause/adjust/reset persistence, target transitions, rep-set suppression,
missing-snapshot preservation, structural-edit timer continuity, no auto-advance, and
ownership-commit continuity.
The iPhone/Watch presentation is compiled in both targets. Spoken and haptic delivery
remain physical-device checks (AC-E14–E20).

### Rejoin and delivery-volume tests (`Tests/run_sync.sh`)

Added 2026-07-24 after a sync outage that all three prior suites missed. This
suite is the only one that compiles `ConnectivityManager`, `ActiveWorkoutManager`
and `RestTimerManager`; the others cover pure logic only.

11. A device holding no replica adopts an in-progress checkpoint at any
    revision, and keeps converging afterwards. **Regression guard** — this
    previously required `version == .initial`, returned an unhandled `.gap`
    otherwise, and left the device blank for the rest of the workout.
12. A reinstalled phone re-attaches mid-workout and recovers the sets logged
    while it was gone.
13. Adoption is bounded by a staleness window, so a sticky application context
    cannot resurrect an abandoned workout on cold launch; an already-joined
    mirror keeps updating past that window.
14. A tombstone is recorded even by a device that never tracked the session, so
    a later checkpoint cannot resurrect finished work; an unrelated tombstone
    does not blank an active workout.
15. Superseded checkpoints collapse in the outbox: 31 edits produce ≤62 sends
    (was 496) and one pending snapshot. Handshake messages and tombstones are
    never collapsed.
16. `ActiveWorkoutManager` publishes an adopted replica to the UI with the
    correct owner and read-only state.

### Test suites

| Suite | Command | Covers |
|-------|---------|--------|
| Logic | `Tests/run.sh` | Models, store, progression, plate/warmup math, coordinator state machine |
| E2E | `Tests/run_e2e.sh` | Goal-level assertions across the four product goals |
| Sync | `Tests/run_sync.sh` | Replication seam incl. connectivity + active-workout managers |

### Paired-simulator E2E procedure

1. Launch clean paired iPhone and Watch simulators.
2. Start a workout on iPhone; verify the phone displays a waiting state.
3. Verify HealthKit wakes the Watch app, Watch receives/persists the matching
   session, becomes owner, and the phone changes to **Ready on Apple Watch —
   open AruLifts on your wrist**.
4. Complete a Watch set; verify phone mirrors it and rest begins with next-set
   context. Undo within five seconds and confirm both devices revert.
5. Adjust weight/reps, complete again, use +30 and Skip, and navigate exercises.
6. Attempt to edit on the mirrored phone; verify it is blocked.
7. Request phone takeover; verify neither side edits during transfer and only
   the phone can edit after acceptance.
8. Pause/resume. Attempt early finish and verify incomplete-set confirmation.
9. Disconnect the paired devices, log multiple Watch sets, terminate/relaunch
   the Watch app, and confirm the workout resumes from persisted Watch state.
10. Reconnect and verify the phone converges without set reversion.
11. Inject duplicate, reordered and old-epoch events; verify convergence and
    checkpoint recovery.
12. Finish from Watch, relaunch both apps, and verify one history entry and no
    active-session resurrection. Repeat with Cancel.
13. Repeat the full workout starting from a cached plan on Watch while phone is
    unavailable, then reconnect and verify receipt status.

### Physical iPhone + Apple Watch procedure

1. Verify both counterpart apps are installed before treating a failure as a
   synchronization defect.
2. Open AruLifts on Watch once while visible and grant notification permission.
   Confirm Watch app notification settings are **Allow Notifications**, not
   notification-center-only or off.
3. Finish/cancel any existing session, return to the Watch face, lower the
   wrist, and start a fresh workout on iPhone.
4. Confirm the iPhone progresses through **Waking Apple Watch…** and
   **Waiting for Apple Watch…**, then reaches **Ready on Apple Watch** only
   after the exact-session ownership acknowledgment.
5. Physically observe the wrist alert. Tap it and verify AruLifts opens the
   exact session, exercise, and set state that was started on iPhone. A build,
   log line, queued notification, or Ready status is not proof of this step.
6. Repeat with Watch notifications denied. The workout must still wake/sync,
   the iPhone must not claim a notification exists, and manually opening
   AruLifts must reveal the exact live session.
7. Repeat with Watch offline. Confirm a truthful failure/waiting state, restore
   connectivity, use **Retry Apple Watch**, and verify the original workout
   continues without a duplicate ownership offer or Health workout.
8. Force-quit/relaunch the iPhone while waiting. Confirm the persisted workout
   is restored and one new wake retry occurs without creating a new session.
9. With the workout ready, lock/put down the phone and complete at least three
   sets from Watch.
10. Confirm Digital Crown adjustment, target sizes, screen readability during
   exertion, VoiceOver labels, haptics, Watch speaker and Bluetooth-earphone
   speech at 10/3/2/1/Go.
11. Background the Watch through a full rest interval and confirm the live
    HealthKit session keeps it executing and the rest alert fires.
12. Finish on Watch. Verify exactly one app-history entry and exactly one
    Health workout with the AruLifts session external UUID.

### iPhone-to-Watch wake regression checks (`Tests/run_sync.sh`)

17. A phone start persists its active replica and durable ownership offer
    before invoking the injected Watch launcher.
18. One new workout start invokes one wake request.
19. Wake failure is visible, Retry invokes one additional wake, and Retry
    reuses the original ownership offer.
20. Relaunch with a restored pending ownership offer performs one wake retry.

## Goal 3 — Food / nutrition capture (TBD)

Later, per Aravind.

## Bugs found (Goal 1 run, 2026-07-21)

1. **HIGH — Running watch app ignores live session updates.** With the watch
   app running: discarding the active workout on the phone made the watch
   flash its idle screen, then it **reverted to the stale workout**; starting
   a new workout on the phone never replaced it (>16 s). Relaunching the
   watch app resyncs correctly, and a freshly-launched watch instance applies
   live updates fine. Meanwhile the phone banner claims "Synced with Apple
   Watch" the whole time. Suspect the uncommitted keep-alive / sync-robustness
   changes in `Shared/Connectivity/ConnectivityManager.swift` and
   `Shared/ActiveWorkout/ActiveWorkoutManager.swift` (stale persisted state
   being re-applied over live messages).
2. **MEDIUM — Ancient active session resumes silently.** App launched
   straight into a 6-day-old in-progress workout (elapsed timer 8612:56).
   Should offer "resume or discard?" past some staleness threshold.
3. **COSMETIC — Pluralization.** Workout list shows "1 exercises · 3 sets".

## Test environment

- iPhone 17 Pro sim `EA395468-CF32-42ED-ADBB-B15761893E3F` paired with
  Apple Watch Series 11 46mm sim `3C021BFC-16D3-456C-B9E5-976F1062276A`.
- Both targets build clean (Debug). UI driven via desktop automation on
  Simulator.app; screenshots in session scratchpad.

## Test results log

| Date | Goal | Result | Notes |
|------|------|--------|-------|
| 2026-07-21 | Goal 1 — workout creation | Core creation/edit/persistence PASS; suggestions (1.2), cardio (1.5), stretching (1.6), recovery (1.7) FAIL; watch live-sync bug found | See checklist + bugs above |
| 2026-07-24 | Goal 2 — Watch-start → phone rejoin | **PASS** on paired sims (iPhone 17 Pro iOS 26.3 + Series 11 46mm watchOS 26.1) | See below |
| 2026-07-28 | Goal 2.21 — phase-boundary navigation (#90) | **PASS** automated model/manager contract tests and iOS/watchOS builds; paired-simulator UI checks pending | `Tests/run.sh`, `Tests/run_sync.sh`, `Tests/run_e2e.sh`; AC-D11–D16 |
| 2026-07-28 | Goal 2.22 — per-exercise timer (#93) | **PASS** automated contract, builds, and paired-simulator visible replication | Matching iPhone/Watch timed set; phone pause reached Watch at `1:17`; controls exposed to iPhone accessibility; physical audio/haptic pending |
| 2026-07-28 | Goal 2.23 — guided exercise stepper (#94) | **PASS** automated shape/manager contract, iOS/watchOS builds and paired-simulator visual inspection | iPhone showed phase and exercise timers, `1 of 3 · Leg Swings`, progress, controls and Done & Next; Watch showed the same name/position plus phase overtime and exercise time in a scrollable view. Desktop lock prevented UI tapping; explicit Done/Next behavior passed manager tests |
| 2026-07-28 | Goal 1.11 — routine phase-item composer (#95) | **PASS** model/persistence/materialization/Watch-cache contracts, both-target build and read-only Simulator rendering; interactive edit walkthrough pending | `Tests/run.sh`; iPhone showed saved item names and derived targets; toolbar Edit was visible but unavailable to UI automation; AC-B13–B21 |
| 2026-07-29 | Goal 2.24 — live exercise-list edits (#96) | **PASS** model/manager/replica contracts, all 86 E2E tests, separate iOS/watchOS Simulator builds and paired-simulator iPhone walkthrough | Added Push-Up at the phase end while Elliptical stayed selected on both peers; swapped Elliptical in place for Stationary Bike; removed it and advanced to Treadmill Incline. Watch showed the replicated `1 of 3 · Elliptical`; Watch menu interaction remains physical-device acceptance. AC-D29–D34, AC-G8, AC-H11 |
| 2026-07-29 | Post-v3.1 — structural-edit timer continuity (#107) | **PASS** running-timer regression, logic/sync/E2E suites and both simulator builds | A partially elapsed timed set survives an unrelated live exercise insertion without re-arming; AC-E21 |

### 2026-07-24 — Watch-start rejoin, paired simulators

Verifying the `.gap` adoption fix on real WatchConnectivity, not just in the
script suites.

1. Plan cache replicated phone → watch (revision 2, 4 workouts); watch showed
   "Ready on Watch".
2. Phone app terminated. Started **Upper Body** on the watch and logged 3 sets
   with the phone app not running. Watch reached `revision 9`, owner `watch`,
   authority `authoritative`.
3. Deleted the phone's `active_workout_runtime.json` so it provably held **no
   replica** — the precondition that used to be unrecoverable.
4. Launched the phone. It adopted the checkpoint at **revision 9**, session id
   matching, owner `watch`, authority `mirror`, 3 completed sets, and rendered
   the live workout read-only with "Take Over on iPhone" and the mirrored rest
   timer. Under the old `guard version == .initial` this path returned `.gap`
   and the phone stayed blank for the rest of the workout.

Also observed: iOS background-wakes the companion app for WatchConnectivity
delivery, so the phone converges even before the user opens it. Deleting the
iPhone app also removes the paired watch app (and with it any in-progress
workout) — worth knowing when reproducing install-related bugs.

Environment note: Magnet and Wispr Flow both keep transparent full-screen
overlays that intercept synthetic clicks on the simulators. Wispr Flow can be
added to the automation allowlist; Magnet is menu-bar-only and must be quit.

### 2026-07-27 — Phone-start → Watch handoff, paired simulators

Full bidirectional run on iPhone 17 Pro (`EA395468…`) + Apple Watch Series 11
46mm (`3C021BFC…`), driving both simulator UIs.

1. **Phone start → Watch adoption.** Started *Upper Body* on the phone. Watch
   received `ownershipOffer`, persisted it, and rendered the session read-only
   with a "Waiting for iPhone handoff" banner and a disabled completion button.
2. **Handshake completion.** `ownershipAcceptance` → `ownershipCommit` → ack.
   End state: phone `mirror`/`synced`/owner `watch`, watch
   `authoritative`/`synced`/owner `watch`, both at ownership epoch 1, both
   outboxes empty.
3. **Watch → phone set logging.** Completed a set on the Watch; phone applied
   the checkpoint (revision 2), showed the set green, and mirrored the running
   3:00 rest timer while keeping Cancel/Finish/set rows disabled.
4. **Takeover.** "Take Over on iPhone" produced
   `takeoverRequest` → `acceptance` → `commit`, epoch 2, phone authoritative
   and Watch demoted to mirror.
5. **Finish.** Finishing on the phone wrote history exactly once (Home showed
   1 workout) and tombstoned the session on both devices.
6. **Failed takeover → discard.** With the Watch app terminated, a takeover
   timed out after 15 s and the new **Discard on iPhone** control cleared the
   phone's stuck mirror (tombstoned, outbox empty, back to `localOnly`).
7. **Superseding a stale replica.** With the Watch still holding the abandoned
   *Lower Body* replica, starting *Arms* on the phone was adopted by the Watch
   (`ownershipOffer … applied`) and both devices converged on *Arms*. Before
   the fix in this branch that offer was rejected `.stale` and the pair could
   not converge until the six-hour recovery window expired.

**Not verifiable on the simulator.** Xcode strips the HealthKit entitlement
from simulator builds (`codesign -d --entitlements` returns an empty dict), so
`HKHealthStore.startWatchApp(with:)` and `HKWorkoutSession` both fail with
"Missing com.apple.developer.healthkit entitlement". The HealthKit wake path,
the live workout session, and `WKBackgroundModes` behaviour therefore still
need a physical paired iPhone + Watch. Useful side effect: the guaranteed wake
failure is a convenient way to exercise the "Couldn't wake Apple Watch" /
Retry / Discard UI.

`WKBackgroundModes = workout-processing` was confirmed present in the built
watch app's merged `Info.plist`, so the `INFOPLIST_FILE` +
`GENERATE_INFOPLIST_FILE` merge in this branch does work.

Watch → phone `transferUserInfo` delivery stalled for several minutes at one
point while the Watch app was backgrounded, leaving the Watch in
`mirror`/`waitingForPhone` with a workout it could not log to. It recovered as
soon as the Watch app was foregrounded. The Watch has no timeout for this
state (the phone has 20 s wake and 15 s takeover timeouts) — tracked
separately.
