# AruLifts Roadmap

Tracked backlog for closing the gap between the current app and a StrongLifts-class
experience on **iPhone + Apple Watch**. Every numbered item below has a matching
GitHub Issue with the same number in the title (`[#N] …`). Loops/goals can pick up
"the next open issue" and check the box here when it merges.

**Legend:** 🔴 High · 🟡 Medium · 🟢 Low · 📱 iPhone · ⌚️ Watch

## Current status (baseline)

Done in the rebuild: two-target iOS + watchOS app, custom workouts by category,
workout builder (sets/reps/weight/rest, reorder), exercise library (25+) with form
instructions + demo-video player, live workout with per-set logging, auto rest timer
(default 3 min) with haptics + notification, Apple Watch mirrored session with
Crown-adjustable weight/reps, history, settings, Codable persistence, WatchConnectivity sync.

---

## Epic A — Apple Health & Watch robustness 🔴

- [ ] **1. HealthKit integration (iPhone)** 📱 — request authorization; save each finished
  workout to Apple Health (type `.traditionalStrengthTraining`), plus body weight; fill activity rings.
- [ ] **2. `HKWorkoutSession` on Apple Watch** ⌚️ — run a real workout session so the app stays
  alive during rest (reliable rest haptic), earns activity-ring/workout credit, and survives suspension.
- [ ] **3. Live heart rate on Watch + Health summary** ⌚️ — show live HR during sets and above the
  rest timer; on finish send duration, avg HR and estimated calories to Apple Health.

## Epic B — StrongLifts core training logic 🔴

- [ ] **4. Auto progression** 📱⌚️ — per-exercise, configurable weight increase after a successful
  session (e.g. +2.5 kg / +5 lb, +5 kg / +10 lb deadlift). Prefill next session automatically.
- [ ] **5. Auto deload** 📱 — drop the weight by a configurable % after N failed sessions in a row
  (StrongLifts default: −10–15% after 2–3 fails). Configurable in settings.
- [ ] **6. Warmup calculator** 📱⌚️ — auto-generate warmup sets and weight jumps up to the working
  weight; show warmup sets on both iPhone and Watch. (Data model already has an `isWarmup` flag.)
- [ ] **7. Plate calculator** 📱⌚️ — show which plates per side for any bar weight, supporting
  fractional and large plates; display on iPhone and Watch.

## Epic C — Progress & tracking 🟡

- [ ] **8. Progress graphs** 📱 — per-exercise weight/volume, body weight, and total, with timeframe
  filters (1m / 3m / 6m / 1y / all).
- [ ] **9. Body-weight tracking** 📱 — log body weight over time with a trend, and sync to Apple Health.
- [ ] **10. Personal records + estimated 1RM** 📱 — detect and surface PRs (weight, reps, volume,
  est. 1RM via Epley) per exercise; badge them in history.
- [ ] **11. Per-session notes + calendar view** 📱 — free-text notes per session; a calendar/heatmap
  showing a mark for each workout day (consistency).

## Epic D — Content & sync 🟡

- [x] **12. Exercise form demonstrations** 📱 — original personalized start/finish illustrations
  are bundled for all 24 built-in exercises, with written cues and direct public YouTube technique
  links. Local looping clips remain supported but are no longer required (see `DEMO_VIDEOS.md`).
- [ ] **13. iCloud sync / backup** 📱⌚️ — sync templates + history across devices (CloudKit or iCloud
  Documents) so data survives device changes and reinstalls.

## Epic E — Library & builder quick wins 🟢

- [ ] **14. Library filters & shortcuts** 📱 — equipment filter, favorite exercises, and an
  "Add to workout" action from the library/detail screen.
- [ ] **15. Builder conveniences** 📱 — duplicate an existing workout; default sets/reps presets per
  exercise type.
- [ ] **16. Rest timer & Watch polish** 📱⌚️ — rest-timer pause/reset controls and alert-sound options;
  let the Watch start/pick a workout on-device (not just receive one from the phone).

---

_See the original goals in git history (`IMPLEMENTATION_PLAN.md`, `FEATURES.md` at commit `31ebe37`).
StrongLifts references: [app](https://stronglifts.com/app/) ·
[Apple Watch](https://support.stronglifts.com/article/111-apple-watch) ·
[Apple Health](https://support.stronglifts.com/article/32-apple-health) ·
[progression](https://support.stronglifts.com/article/71-progression) ·
[warmup](https://support.stronglifts.com/article/87-warmup)._
