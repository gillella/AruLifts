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

### Known gaps found by code inspection (verify during test)

- `ExercisePickerView` ([ExerciseLibraryView.swift:104](AruLifts/Views/ExerciseLibraryView.swift:104))
  filters by **name search only** — no category-based suggestion (req 1.2 ✗ in code).
- Exercise library has 25 exercises; no dedicated stretching entries, no
  sauna/steam/recovery concept anywhere in models (reqs 1.6, 1.7 ✗ in code).
- Cardio is a category and a muscle group, but `TemplateExercise` is
  sets/reps/weight-shaped — no duration field for "15 min cardio" (req 1.5 partial).

## Goal 2 — Workout tracking (TBD)

To be described by Aravind next session.

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
