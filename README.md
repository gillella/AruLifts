# AruLifts

A StrongLifts-style strength-training tracker for **iPhone and Apple Watch**, rebuilt from the ground up.

Start a workout on your phone and it instantly appears on your watch. Log each set, and a rest timer auto-starts and buzzes both devices when it's time for the next set. Build your own workouts (Upper Body, Lower Body, Arms, …), add exercises, and see exactly how to perform each one with step-by-step form cues and a video demo.

## Features

- **Custom workouts by category** — create plans (Upper Body, Lower Body, Arms, Push/Pull/Legs, Full Body, Core, Cardio), add exercises, and set target sets × reps × weight and per-exercise rest.
- **Exercise library** — 25+ built-in exercises with primary/secondary muscles, equipment, numbered form instructions, and coaching tips. Add your own exercises too.
- **Form demos** — each exercise detail screen plays a looping video demonstration of the posture when a clip is available (see [Demo Videos](DEMO_VIDEOS.md)); otherwise it shows an illustrated placeholder.
- **Live workout flow** — work through exercises, log each set with inline +/- steppers, tap to mark a set complete.
- **Rest timer (default 3 min, configurable)** — auto-starts after each set, shows a countdown ring, supports +30s / skip, and fires a haptic + local notification when rest ends, even if the app is backgrounded.
- **Apple Watch app** — mirrors the live session: current exercise, Digital-Crown-adjustable weight/reps, complete-set button, full-screen rest countdown with haptics, and exercise navigation. Finish from either device.
- **History** — every completed workout is saved with sets, reps, volume and duration.

## Architecture

```
Shared/                      Code compiled into BOTH the iOS and watch targets
  Models/                    Exercise, WorkoutTemplate, WorkoutSession, ExerciseLibrary
  Store/                     WorkoutStore  (Codable JSON persistence + settings)
  Connectivity/             ConnectivityManager  (WatchConnectivity / WCSession)
  ActiveWorkout/            ActiveWorkoutManager + RestTimerManager

AruLifts/                    iOS app target (SwiftUI)
  AruLiftsApp.swift, Views/

AruLifts Watch App/          watchOS app target (SwiftUI)
  AruLiftsWatchApp.swift, Views/
```

- **Persistence:** plain `Codable` → JSON in the app's Documents directory (no Core Data). The phone owns history.
- **Phone ↔ Watch sync:** `WCSession`. The phone pushes the session on start; thereafter both devices send full-session syncs as sets are logged, so either stays current. Live messages when reachable, guaranteed `transferUserInfo` fallback otherwise.
- **State:** a single shared `ActiveWorkoutManager` drives the live workout on each device; `RestTimerManager` handles the countdown, notification scheduling and haptics.

## Building

1. Open `AruLifts.xcodeproj` in Xcode 15.2+.
2. Select the **AruLifts** scheme.
3. Set your signing team on both the **AruLifts** and **AruLifts Watch App** targets (Signing & Capabilities). The watch app's bundle id must remain `<iOS bundle id>.watchkitapp`.
4. Run on a paired iPhone + Apple Watch (or the paired simulators).

- iOS deployment target: 17.0
- watchOS deployment target: 10.0

## Adding exercise videos

The demo-video infrastructure is wired up; drop in your own clips and reference them by name. See **[DEMO_VIDEOS.md](DEMO_VIDEOS.md)**.
