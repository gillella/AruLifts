# AruLifts — Acceptance Criteria & Agent Test Protocol

Executable acceptance criteria for AruLifts, written for an **AI agent driving the
iOS/watchOS simulators**. Every criterion states a precondition, exact steps, and an
**observable** expected result, so a run produces the same verdict regardless of who
executes it.

- **Companion docs:** [`E2E-TEST-PLAN.md`](E2E-TEST-PLAN.md) holds the goal-level
  narrative and the historical results log. [`ROADMAP.md`](ROADMAP.md) holds forward
  epics. This document is the authoritative *pass/fail* contract.
- **Traceability:** every criterion cites the issue that introduced it (§15).
- **Maintenance:** this document is kept current as the app changes — see §17 for the
  rule and the checklist. A criterion that no longer matches shipped behaviour is a bug
  in this document, not a failing test.

---

## 1. How an agent uses this document

1. Run §4 (automated gates). **If any suite fails, stop** and report — manual results
   on a broken build are meaningless.
2. Perform the §3 reset before each functional area in §5–§14. Skipping the reset is the
   single most common cause of false failures (see §3.3).
3. Execute criteria in ID order within an area. Record one verdict per criterion.
4. Report using the §16 format. Do not summarise several criteria into one verdict.

### 1.1 Verdict vocabulary

| Verdict | Meaning |
|---|---|
| `PASS` | Observed result matches expectation exactly. |
| `FAIL` | Observed result contradicts expectation. Attach a screenshot and the observed text. |
| `BLOCKED-SIM` | Cannot be evaluated in a simulator for a reason listed in §2. **Not a failure.** |
| `BLOCKED-ENV` | Blocked by a setup problem (build failure, device not booted). Fix and rerun. |
| `SKIPPED` | Deliberately not run. State why. |

> **Never report `PASS` for something you did not observe.** If a step could not be
> reached, the verdict is `BLOCKED-*`, not `PASS`.

### 1.2 Evidence rules

- A verdict about on-screen state requires a screenshot taken **after** the action.
- Quote the exact on-screen string you matched. "Looks right" is not evidence.
- For sync/persistence criteria, prefer the runtime JSON (§3.4) over reading the UI —
  it is ground truth and far cheaper than screenshots.

---

## 2. Simulator constraints — read before reporting any failure

These are environmental limits, **not defects**. A criterion blocked by one of these is
`BLOCKED-SIM`.

| Limit | Consequence | Affected |
|---|---|---|
| **Simulator builds carry no HealthKit entitlement.** Xcode strips it; `codesign -d --entitlements :-` returns an empty dict. | `HKWorkoutSession` and `startWatchApp` always fail. No Health workout is ever created. | All of §13, and the phone→Watch wake in §12 |
| No real sensors | No heart rate, no calories, no rings | §13 |
| Haptics are not produced | Cannot verify a haptic fired | AC-E4, AC-E7 |
| Audio/speech is unreliable in CI | Cannot verify an announcement was *heard* | AC-E7, AC-J4 |
| Watch app does not reliably auto-propagate on install | Install it directly from `<iPhone .app>/Watch/AruLifts Watch App.app` | §11, §12 |

**Useful side effect:** because the Watch wake always fails, the simulator reliably
exercises the "Couldn't wake Apple Watch → Retry / Discard" path for free (AC-H5).

Anything marked **DEVICE-ONLY** below must be run on a physical paired iPhone + Watch.

---

## 3. Environment and reset

### 3.1 Devices

Paired simulators (`xcrun simctl list pairs`):

| Role | Device | UDID prefix |
|---|---|---|
| iPhone | iPhone 17 Pro | `EA395468-…` |
| Watch | Apple Watch Series 11 46mm | `3C021BFC-…` |

- Bundle IDs: `com.arulifts.app`, `com.arulifts.app.watchkitapp`
- **Coordinate space is device points, not screenshot pixels.** iPhone 17 Pro is
  `402 × 874`. A 919px-wide screenshot scales by ≈ `0.437`.

### 3.2 Preferred tooling

Use the **Claude iOS-Simulator MCP** (`mcp__Claude_Code_iOS_Simulator__control`). It
attaches, screenshots and taps both simulators by UDID and avoids the macOS overlay
problems that plague generic screen automation. Call `attach` **before** building so the
panel is open while work proceeds.

Fall back to computer-use on Simulator.app only if the MCP breaks. If you do, type text
via `pbcopy` + `cmd+V` (synthetic typing triggers the macOS accent popup), and quit
Wispr Flow / Magnet first — their transparent full-screen overlays swallow clicks.

### 3.3 Reset procedure — run before each functional area

AruLifts persists an active session to disk and restores it on launch. A leftover
session from a previous area will be restored **watch-owned and read-only**, making
unrelated criteria appear to fail. Reset:

```bash
xcrun simctl terminate <IPHONE_UDID> com.arulifts.app 2>/dev/null
xcrun simctl uninstall <IPHONE_UDID> com.arulifts.app
xcrun simctl install   <IPHONE_UDID> <path>/AruLifts.app
```

After a fresh install the app self-seeds: **8 workout templates** and **1 gym routine**
("Complete Gym Visit"). Allow the notification prompt when it appears.

To reset without losing data, discard in-app instead: **Cancel → Discard on iPhone**
(the Discard control only appears once the Watch wake has failed, which takes a few
seconds).

### 3.4 Ground truth

Inspecting the runtime file on either simulator is faster and more reliable than reading
the UI for sync state:

```
<app container>/Library/Application Support/active_workout_runtime.json
```

Locate the container with `xcrun simctl get_app_container <UDID> com.arulifts.app data`.

### 3.5 Reference fixture — "Complete Gym Visit"

The seeded routine, used by most criteria below:

| # | Phase | Duration | Timed | Seeded exercises |
|---|---|---|---|---|
| 1 | Pre-Workout Cardio | 15 min | yes | none (names only: Elliptical, Treadmill Incline) |
| 2 | Dynamic Warm-Up Stretches | 5 min | yes | none (names only) |
| 3 | Main Strength Training | 60 min | no | from linked template |
| 4 | Post-Workout Cool-Down | 15 min | yes | none (names only) |
| 5 | Abdominal / Mat Core Work | 15 min | yes | built-in core defaults |
| 6 | Sauna Recovery | 15 min | yes | none |
| 7 | Steam Recovery | 10 min | yes | none |

Total ≈ 135 min. **Phases 1, 2, 4, 6, 7 have no logged exercises** — that is expected and
is exactly what AC-D5 checks.

---

## 4. Automated gates — run first, must be green

```bash
Tests/run.sh        # pure logic
Tests/run_e2e.sh    # goal-level
Tests/run_sync.sh   # replication seam
```

```bash
xcodebuild -project AruLifts.xcodeproj -scheme AruLifts \
  -destination 'generic/platform=iOS Simulator' build
xcodebuild -project AruLifts.xcodeproj -scheme 'AruLifts Watch App' \
  -destination 'generic/platform=watchOS Simulator' build
```

**AC-0.1** All three suites report their success line.
**AC-0.2** Both targets report `** BUILD SUCCEEDED **`.

> Green suites do **not** imply the devices sync. `run.sh` and `run_e2e.sh` cover pure
> logic only — that is how a total sync outage once shipped past 86 passing tests. §12 is
> not optional.

---

## 5. Area A — Templates, library and My Workouts

Reset first (§3.3).

**AC-A1** *(#75)* — **Workouts** tab shows a **Workout Templates** section and **no**
"Gym Session Routines" section.

**AC-A2** *(#75)* — The `+` toolbar menu offers: *Compose 7-Phase Routine*, *Create Blank
Workout*, *Start from Starter Preset*, *Restore Starter Presets*.

**AC-A3** *(#75)* — Tapping a template opens its detail view; **Edit** opens the builder
and a changed name persists after Save.

**AC-A4** — *Start from Starter Preset* lists presets; choosing one opens the builder
pre-filled, and saving adds a template without mutating the preset.

**AC-A5** — Created templates survive terminate + relaunch.

**AC-A6** *(#78)* — A template created via the composer's **Create New Template** appears
in the Workouts list afterwards.

---

## 6. Area B — Routine composer

Reset first. Open from **Home → tap a routine card body** (not the play button).

**AC-B1** *(#77)* — Navigation title is the routine's **actual name** ("Complete Gym
Visit"), not "Edit Routine" or "Create Gym Routine".

**AC-B2** *(#77)* — An existing routine opens **read-only**: values render as static
labels; no text fields, toggles, steppers or pickers are interactive. Toolbar shows
**Done** and **Edit**.

**AC-B3** *(#77)* — **Edit** switches to edit mode; toolbar becomes **Cancel** / **Save**.

**AC-B4** *(#77)* — **Cancel discards.** In edit mode change a phase's linked template,
tap Cancel; the read-only view shows the **original** value. *(This was broken before
#77 — the discarded edit was retained in state.)*

**AC-B5** *(#77)* — **Save persists** and returns to read-only, with the new value shown.

**AC-B6** *(#77)* — Creating a new routine (Workouts → `+` → Compose 7-Phase Routine)
opens **directly in edit mode**.

**AC-B7** *(#78)* — **Every** phase in edit mode shows a template picker with a
phase-appropriate label (Cardio Template, Warm-Up Template, Strength Template, Cool-Down
Template, Core Template, Recovery Template) — not only Main Strength.

**AC-B8** *(#78)* — Each picker offers **"None (Timed Only)"** plus every workout template.

**AC-B9** *(#78)* — Timed phases show a **duration stepper alongside** the template
picker; both are usable.

**AC-B10** *(#78)* — **Create New Template** opens the builder; on save the new template is
**auto-linked to the phase it was launched from**. Verify by reopening the composer.

**AC-B11** *(#78)* — **The linked template is actually used.** Link a template to
**Pre-Workout Cardio**, Save, start the routine: phase 1 contains that template's
exercises. *(Before #78 only Main Strength honoured `templateID`; every other phase
silently dropped it.)*

**AC-B12** *(#74/#75)* — Routines can be deleted (long-press a Home routine card →
**Delete Routine**).

---

## 7. Area C — Home and starting a workout

**AC-C1** *(#74)* — **Start a Workout** lists only gym **routines**, never individual
templates.

**AC-C2** *(#74)* — Each card shows name, estimated total ("~135 min") and phase count
("7 phases").

**AC-C3** *(#74/#77)* — **Card body and play button are separate targets**: tapping the
body opens the composer read-only; tapping ▶ starts the session.

**AC-C4** *(#74)* — With no routines, an empty state explains how to create one.

---

## 8. Area D — Active session: phase scoping and navigation

Reset, then start "Complete Gym Visit" from Home.

**AC-D1** *(#86)* — **Phase 1's timer is armed at its full duration** and counting down
(shows `14:5x`, pause icon). It must **not** show `00:00` with a play icon.

**AC-D2** *(#80)* — The banner reads **Phase 1 of 7: Pre-Workout Cardio**.

**AC-D3** *(#80)* — **No exercise from another phase is visible.** Phase 1 has no
exercises, so the screen shows the phase card (icon, phase name, machine names, guidance)
— **not** Barbell Bench Press. *(This regression was found by running the app after the
first #80 implementation.)*

**AC-D4** *(#80)* — Tap **Next Phase** twice to reach **Phase 3 of 7: Main Strength
Training**. The pager now lists **only that phase's** exercises.

**AC-D5** *(#80)* — Phases with no exercises (1, 2, 4, 6, 7) still render correctly and
are advanceable.

**AC-D6** *(#80)* — **Prev/Next do not cross a phase boundary.** In phase 3, press Next
past the last exercise: it stops at the last exercise of that phase and never enters
phase 4.

**AC-D7** *(#80)* — Position is **phase-relative**: the Watch shows `2/4` meaning second of
four *in this phase*, not across the session.

**AC-D8** *(#80)* — Going back a phase repositions to that phase's first unfinished
exercise.

**AC-D9** *(#80)* — **A plain template session is unaffected**: start a single template;
navigation spans all its exercises with no phase clamping.

**AC-D10** *(#80)* — Completing a set is attributed to the owning phase; History shows
correct per-phase completed sets. *(The per-phase record was permanently stale before
#80 — it was a copy never updated after session creation.)*

**AC-D11** *(#90)* — **No enabled navigation control is a no-op.** In phase 3 (Main
Strength), navigate to the phase's **last** exercise. The **Next** button must be
**visibly disabled** — greyed, not tappable. Before #90 it stayed enabled and did
nothing when pressed, because it was bounded by the flat exercise array rather than the
phase. *(#80 made the* action *stop at the boundary; #90 makes the* control *agree.)*

**AC-D12** *(#90)* — Navigate to the **first** exercise of phase 3. **Previous** must be
**visibly disabled**, even though earlier phases hold exercises and the underlying index
is greater than zero.

**AC-D13** *(#90)* — A phase holding exactly **one** exercise shows **both** Previous and
Next disabled.

**AC-D14** *(#90)* — **Watch: the end of a phase is not the end of the workout.** On the
Watch, complete every set of the last exercise in phase 3 so the "Exercise complete" card
appears. It must offer **"Next Phase"** — not "Finish Workout". Pressing it advances to
phase 4. *(Before #90 the card offered "Finish Workout" partway through a routine.)*

**AC-D15** *(#90)* — On the Watch, in the **final** phase with its last exercise complete,
the same card offers **"Finish Workout"**. With a further exercise remaining in the phase
it offers **"Next Exercise"**.

**AC-D16** *(#90)* — **A plain template session is unaffected**: start a single template.
Previous is disabled only on the first exercise, Next only on the last, and the Watch card
offers "Next Exercise" then "Finish Workout" with no "Next Phase" ever shown.

---

## 9. Area E — Timers, overtime and cues

> **The governing rule.** A timer **alerts** when it reaches its target, then **keeps
> counting**. It never stops on its own and never advances anything. Moving to the next
> exercise or phase is always an explicit user action. Any observation contradicting this
> is a `FAIL`, whichever criterion you were running.

**AC-E1** *(#81)* — **Phase timer counts past zero.** Reduce a phase to ~1 min (`-1m`),
let it reach zero, keep watching: the display continues as **`+0:01`, `+0:02`…** It must
not stop, and must not sit at `0:00`.

**AC-E2** *(#81)* — Overtime is **visually distinct** — rendered green, labelled `over`,
against the normal orange/primary countdown.

**AC-E3** *(#81)* — **Nothing auto-advances at zero.** The phase stays current and the
exercise does not change until *you* act.

**AC-E4** *(#81)* — The completion alert fires **exactly once**, not repeatedly through
overtime. *(Haptic itself is `BLOCKED-SIM`; verify no repeated visual alert/modal.)*

**AC-E5** *(#81)* — **Extending from overtime returns to a countdown.** In overtime tap
`+1m`: the display returns to a normal descending `M:SS`.

**AC-E6** *(#81)* — **Rest timer behaves identically.** Complete a set, let rest expire:
it counts up as `+M:SS`, labelled "Rest over", green, and does **not** skip to the next
exercise.

**AC-E7** *(#82)* — **Prepare-for-next cue.** With the lead set to 10 s and a phase
shortened so the lead is below its duration, the cue fires once as the countdown crosses
the lead, naming the next phase. *(Audio is `BLOCKED-SIM`; verify via the settings path
and, where visible, the announcement side effects.)*

**AC-E8** *(#82)* — **Setting exists and is discoverable**: Settings → *Gym Session Phases*
→ **Prepare-for-next cue** toggle + **Cue timing** picker (10/30/60 s), **defaulting to
30 seconds**.

**AC-E9** *(#82)* — Cue is **suppressed** when the lead ≥ the phase duration (a 60 s lead on
a 30 s phase must not fire immediately).

**AC-E10** *(#82)* — Cue does **not** re-fire across pause/resume within one phase.

**AC-E11** *(#82)* — On the **final** phase the announcement refers to the session ending,
not a non-existent next phase.

**AC-E12** *(#81)* — A phase's recorded duration includes overtime, and reflects **time in
that phase** — not elapsed time of the whole session. *(Verify in History.)*

**AC-E13** *(#86)* — **Sync cannot blank a running phase timer.** With the phone-started
session in the watch-owned state, the phase timer keeps its remaining time and does not
reset to `00:00`.

---

## 10. Area F — Exercise form access during a workout

**AC-F1** *(#76)* — During an active workout the **exercise name itself is tappable** and
opens the exercise detail view (form video, technique link, numbered steps, tips).

**AC-F2** *(#76)* — The affordance is discoverable — the name is a button with a visible
ⓘ, not a small isolated icon.

**AC-F3** *(#76)* — **Works while the Watch owns the session.** This is the normal state
mid-workout. Form guidance is read-only and must remain reachable even when set editing
is disabled. *(Before the fix the whole list was `.disabled()`, which silently blocked
this exact case.)*

**AC-F4** *(#76)* — Works for both set/rep exercises and exercises inside timed phases.

---

## 11. Area G — Watch app

Install the Watch app from `<iPhone .app>/Watch/AruLifts Watch App.app`.

**AC-G1** *(#83)* — **Idle leads with iPhone.** The idle screen shows "Start on iPhone"
and guidance that tracking begins automatically. **No routine/template start buttons at
the top level.**

**AC-G2** *(#83)* — A clearly **secondary** "Start without iPhone" control opens a sheet
listing cached routines and templates.

**AC-G3** *(#83)* — Starting from that fallback works and begins tracking on the Watch.

**AC-G4** *(#83)* — With no cached plans the fallback is hidden and the existing
empty-state copy is shown instead.

**AC-G5** *(#83)* — The reachability indicator ("iPhone connected" / "Plans saved on
Watch") is retained.

**AC-G6** *(#80)* — During a routine the Watch shows the phase banner and only the current
phase's exercises, with a phase-relative position indicator.

**AC-G7** *(#81)* — Overtime renders on the Watch in green with an `OVER` label.

---

## 12. Area H — Sync, ownership and durability

Paired simulators. Prefer the runtime JSON (§3.4) over UI reading.

**AC-H1** — A phone-started workout is not reported synced until the Watch has persisted
and acknowledged **that exact session**.

**AC-H2** — After acknowledgement the phone shows "Ready on Apple Watch".

**AC-H3** — While the Watch owns the session the phone is a **read-only mirror**: Cancel,
Finish and set rows are disabled.

**AC-H4** — Phone takeover succeeds only through an acknowledged transfer (epoch
increments; phone becomes authoritative).

**AC-H5** — Wake failure surfaces "Couldn't wake Apple Watch" with **Retry** and
**Discard on iPhone**, and Discard clears the session. *(Reliably reproducible in the
simulator — see §2.)*

**AC-H6** — Sync UI distinguishes *Saved locally* / *Waiting* / *Ready on Watch* /
*Synced* rather than equating reachability with receipt.

**AC-H7** — Finish/cancel is durable: a stale application context cannot resurrect a
finished workout.

**AC-H8** — A finished session enters history and progression **exactly once**.

**AC-H9** *(#82)* — The phase-cue setting replicates to the Watch and is honoured there,
**including across an ownership handoff**. *(The lead time is carried through
`sync`/`syncPaused`; without it a handoff would leave the peer with no cue.)*

**AC-H10** *(#81)* — Overtime replicates: a peer adopting an already-overtime timer shows
overtime and does **not** replay the completion alert.

---

## 13. Area I — HealthKit — **DEVICE-ONLY**

Every criterion here is `BLOCKED-SIM` (§2). Run on a physical paired iPhone + Watch.

**AC-I1** *(#84)* — Each phase starts an `HKWorkoutSession` with its mapped activity type:

| Phase | Expected activity |
|---|---|
| Pre-Workout Cardio | machine-specific (`stairClimbing` / `elliptical` / `running` / `cycling` / `rowing`), else `mixedCardio` |
| Dynamic Warm-Up | `preparationAndRecovery` |
| Main Strength | `traditionalStrengthTraining` |
| Post-Workout Cool-Down | `flexibility` |
| Core Work | `coreTraining` |
| Sauna / Steam | `preparationAndRecovery` |

**AC-I2** *(#84)* — Cardio resolves to the machine named by the phase or its linked
template ("Stair Climber" → `stairClimbing`); unrecognised names fall back to
`mixedCardio`.

**AC-I3** *(#84)* — Phase boundaries end the previous session and start the next with **no
orphaned sessions**.

**AC-I4** *(#84)* — Consecutive phases of the **same** activity (Sauna → Steam) remain a
single continuous session rather than fragmenting further.

**AC-I5** *(#84)* — Skipping, going back, finishing and discarding all leave HealthKit
consistent.

**AC-I6** *(#84)* — The resulting Health entries share a `com.arulifts.gymVisitID`
metadata value and carry their phase name, so one visit is recognisable as a group.

**AC-I7** *(#84)* — **Measure and record the heart-rate gap** at each boundary. This is the
accepted cost of per-phase accuracy and must be quantified, not assumed.

**AC-I8** — Apple Health receives **exactly one** workout per session segment even when
Watch result delivery is retried or lost.

> **Known accepted trade-off:** one gym visit becomes ~7 separate Health entries, because
> `HKWorkoutSession.activityType` is immutable. Chosen deliberately. Do not file this as a
> defect.
>
> **Safety note:** sauna/steam tracking has the Watch at 70–100 °C, outside its rated
> 35 °C. Tracking there was requested explicitly; the risk is the owner's.

---

## 14. Area J — Persistence, history and announcements

**AC-J1** — Templates, routines and settings survive terminate + relaunch.

**AC-J2** — An in-progress session is restored on relaunch with its phase, exercise and
timer state intact.

**AC-J3** — Completed sessions appear in History with correct volume, duration and
per-phase detail.

**AC-J4** *(#85)* — The spoken phase-complete announcement uses the **displayed 1-based
number**: finishing phase 1 announces **"Phase 1 … complete"**, never "Phase 0". Must match
the banner (`Phase 1 of 7`). *(Audio is `BLOCKED-SIM`; the numbering is covered by
`Tests/run_sync.sh`.)*

---

## 15. Traceability

| Area | Criteria | Source |
|---|---|---|
| Gates | AC-0.1–0.2 | — |
| A Templates | AC-A1–A6 | #75, #78 |
| B Composer | AC-B1–B12 | #77, #78, #74 |
| C Home | AC-C1–C4 | #74, #77 |
| D Phase scoping | AC-D1–D16 | #80, #86, #90 |
| E Timers | AC-E1–E13 | #81, #82, #86 |
| F Form access | AC-F1–F4 | #76 |
| G Watch | AC-G1–G7 | #83, #80, #81 |
| H Sync | AC-H1–H10 | Goal 2, #81, #82 |
| I HealthKit | AC-I1–I8 | #84 |
| J Persistence | AC-J1–J4 | #85 |

Shipped through PR #99; epic #87. This document's baseline is **v3.1.0**.

**Epic F progress.** Guided multi-phase session execution (#90–#96). Each issue adds its
criteria here as it lands, per §17.

- #90 — landed, covered by AC-D11–D16
- #91–#96 — open, not yet covered

### Superseded findings

`E2E-TEST-PLAN.md` Goal 1 (2026-07-21) records these as ❌ FAIL. They have since been
implemented by the gym-session-routine work and are **no longer valid failures**:

- **1.5** cardio capture → Pre-Workout Cardio phase with duration and linked template
- **1.6** stretching guidance → Warm-Up and Cool-Down phases
- **1.7** recovery activities → Sauna and Steam phases
- **1.10** "watch is mirror-only, cannot start from watch" → superseded by #83, where
  Watch start is a deliberate fallback behind "Start without iPhone"

Goal 1's **1.2** (category-aware exercise suggestions) and **1.3** (preview details from
inside the picker) remain open and are **not** covered by this document.

---

## 16. Result report format

```
## AruLifts acceptance run — <date> — <build/commit>

Environment: iPhone 17 Pro <UDID> / Watch Series 11 <UDID>
Gates: AC-0.1 PASS  AC-0.2 PASS

| ID | Verdict | Evidence / note |
|----|---------|-----------------|
| AC-D1 | PASS | Timer showed 14:57 counting down, pause icon |
| AC-D3 | FAIL | Phase 1 displayed "Barbell Bench Press" — screenshot 03.png |
| AC-I1 | BLOCKED-SIM | No HealthKit entitlement in simulator builds |

Summary: <n> PASS, <n> FAIL, <n> BLOCKED-SIM, <n> BLOCKED-ENV, <n> SKIPPED
Failures requiring triage: AC-D3
```

Report every criterion attempted. A run that reports only failures is not reusable as
evidence that everything else still works.

---

## 17. Keeping this document current

This document only has value if it describes the app as it is **today**. A stale
criterion is worse than a missing one: it produces a confident `FAIL` against correct
behaviour, or a confident `PASS` against a feature that no longer exists.

### The rule

> **A PR that changes user-visible behaviour updates this document in the same PR.**

Not a follow-up issue, not "later". The person who changed the behaviour is the only one
who reliably knows what the new expected result is.

### Checklist for a behaviour-changing PR

- [ ] **New behaviour** → add a criterion to the relevant area, numbered after the
      current highest ID in that area. Never renumber existing criteria — IDs are cited
      in past run reports and must stay stable.
- [ ] **Changed behaviour** → edit the existing criterion in place and update its issue
      citation to include the new issue.
- [ ] **Removed behaviour** → delete the criterion and record it under
      §15 *Superseded findings* with the issue that removed it. Do not leave it in place
      marked "obsolete".
- [ ] **Cite the issue** — every criterion carries `*(#N)*`.
- [ ] **Expected results stay observable** — an exact on-screen string, a JSON value, a
      test-suite success line. "Works correctly" is not a criterion.
- [ ] **Update §15 traceability** — the area's criteria range and source issues.
- [ ] **Check internal references** — if you added a section, section numbers shift and
      `§N` references go stale.

### When no behaviour changed

A refactor, a build fix or a docs-only change needs no update here. Say so in the PR
rather than leaving it ambiguous.

### Auditing for drift

Drift accumulates quietly. When picking up work after a gap, spot-check the areas the
work touches before trusting them, and reconcile §15 against the closed issues on the
board. If a criterion cannot be traced to shipped code, treat it as suspect and verify
it against the app before running a full pass.
