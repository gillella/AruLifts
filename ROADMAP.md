# AruLifts Roadmap

Tracked backlog for closing the gap between the current app and a StrongLifts-class
experience on **iPhone + Apple Watch**. Loops/goals can pick up "the next open issue"
and check the box here when it merges.

Items 1–16 use the original roadmap numbering. From Epic F onward, items are labelled
with their real GitHub issue number (`[#90]`, `[#91]`, …) so the board and this file
cannot drift apart.

**Legend:** 🔴 High · 🟡 Medium · 🟢 Low · 📱 iPhone · ⌚️ Watch

## Current status (baseline — v3.1.0)

Epics A–D are complete and Epic E is all but one item. Shipped: two-target iOS +
watchOS app, custom workouts by category, workout builder (sets/reps/weight/rest,
reorder), exercise library (25+) with form illustrations and technique links, live
workout with per-set logging, adaptive rest timer with haptics and notifications,
Apple Watch session with live heart rate and Crown-adjustable weight/reps, HealthKit
workout + body-mass writing, auto progression and deload, warmup and plate
calculators, progress graphs, PRs and estimated 1RM, calendar view, Live Activity
and Dynamic Island, watchOS complications, iCloud Documents sync, and a durable
WatchConnectivity replication layer with ownership handoff.

The active frontier is **Epic F** — turning a multi-phase gym routine into a
genuinely guided, phase-by-phase session on both devices.

---

## Epic A — Apple Health & Watch robustness 🔴

- [x] **1. HealthKit integration (iPhone)** 📱 — request authorization; save each finished
  workout to Apple Health (type `.traditionalStrengthTraining`), plus body weight; fill activity rings.
- [x] **2. `HKWorkoutSession` on Apple Watch** ⌚️ — run a real workout session so the app stays
  alive during rest (reliable rest haptic), earns activity-ring/workout credit, and survives suspension.
- [x] **3. Live heart rate on Watch + Health summary** ⌚️ — show live HR during sets and above the
  rest timer; on finish send duration, avg HR and estimated calories to Apple Health.

## Epic B — StrongLifts core training logic 🔴

- [x] **4. Auto progression** 📱⌚️ — per-exercise, configurable weight increase after a successful
  session (e.g. +2.5 kg / +5 lb, +5 kg / +10 lb deadlift). Prefill next session automatically.
- [x] **5. Auto deload** 📱 — drop the weight by a configurable % after N failed sessions in a row
  (StrongLifts default: −10–15% after 2–3 fails). Configurable in settings.
- [x] **6. Warmup calculator** 📱⌚️ — auto-generate warmup sets and weight jumps up to the working
  weight; show warmup sets on both iPhone and Watch.
- [x] **7. Plate calculator** 📱⌚️ — show which plates per side for any bar weight, supporting
  fractional and large plates; display on iPhone and Watch.

## Epic C — Progress & tracking 🟡

- [x] **8. Progress graphs** 📱 — per-exercise weight/volume, body weight, and total, with timeframe
  filters (1m / 3m / 6m / 1y / all).
- [x] **9. Body-weight tracking** 📱 — log body weight over time with a trend, and sync to Apple Health.
- [x] **10. Personal records + estimated 1RM** 📱 — detect and surface PRs (weight, reps, volume,
  est. 1RM via Epley) per exercise; badge them in history.
- [x] **11. Per-session notes + calendar view** 📱 — free-text notes per session; a calendar/heatmap
  showing a mark for each workout day (consistency).

## Epic D — Content & sync 🟡

- [x] **12. Exercise form demonstrations** 📱 — original personalized start/finish illustrations
  are bundled for all 24 built-in exercises, with written cues and direct public YouTube technique
  links. Local looping clips remain supported but are no longer required (see `DEMO_VIDEOS.md`).
- [x] **13. iCloud sync / backup** 📱⌚️ — templates + history live in the app's iCloud Documents
  container, with an `NSMetadataQuery` observer so edits on another device appear without a cold
  launch. Local JSON remains the fallback when iCloud is unavailable.

## Epic E — Library & builder quick wins 🟢

- [x] **14. Library filters & shortcuts** 📱 — equipment filter, favorite exercises, and an
  "Add to workout" action from the library/detail screen.
- [ ] **15. Builder conveniences** 📱 — starter-preset templates ship and are restorable, but
  **duplicating an existing workout** and **default sets/reps presets per exercise type** are
  still outstanding. Partially done.
- [x] **16. Rest timer & Watch polish** 📱⌚️ — rest-timer pause/reset controls and alert-sound options;
  the Watch can start a cached workout on-device, not only receive one from the phone.

## Epic F — Guided multi-phase gym session 🔴

A routine phase currently produces navigable exercises only when a template is linked
(plus a hardcoded core-work fallback), so the shipped warm-up, cardio and cool-down
phases are bare countdowns. This epic makes every phase a first-class, guided,
loggable part of the session on both devices.

- [x] **[#90] Previous/Next disabled state ignores the phase boundary** 📱⌚️ 🐞 — navigation
  buttons gate on the global exercise index while the actions are phase-scoped, so enabled
  controls become no-ops at every phase boundary.
- [x] **[#91] Structured phase exercise list and per-set duration** 📱⌚️ — replace the untyped
  `[String]` phase list with `PhaseExerciseItem`, and carry `durationSeconds` onto `SetEntry`
  so timed work survives into execution. Model + migration; gates #92–#95.
- [ ] **[#92] Materialize every phase's exercises into the active session** 📱⌚️ — generalize
  the template-or-core-work special case so any phase with declared exercises becomes navigable.
- [ ] **[#93] Per-exercise countdown timer, replicated to Watch** 📱⌚️ — a third timer alongside
  rest and phase, with the same overtime / never-auto-advance contract and full sync replication.
- [ ] **[#94] Guided exercise stepper UI** 📱⌚️ — "3 of 5 · Hip Mobility" with its countdown,
  chosen by exercise shape rather than phase type. The visible payoff of #92 + #93.
- [ ] **[#95] Composer: edit a phase's exercise list and targets** 📱 — make the shipped defaults
  curatable instead of unreachable.
- [ ] **[#96] Add or swap an exercise mid-workout** 📱⌚️ — for an occupied machine or extra work,
  without ever mutating the saved template.

---

_See the original goals in git history (`IMPLEMENTATION_PLAN.md`, `FEATURES.md` at commit `31ebe37`).
StrongLifts references: [app](https://stronglifts.com/app/) ·
[Apple Watch](https://support.stronglifts.com/article/111-apple-watch) ·
[Apple Health](https://support.stronglifts.com/article/32-apple-health) ·
[progression](https://support.stronglifts.com/article/71-progression) ·
[warmup](https://support.stronglifts.com/article/87-warmup)._
