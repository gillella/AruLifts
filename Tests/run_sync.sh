#!/bin/sh
# Compiles the sync/transport layer with the assertion harness and runs it.
#
# Unlike run.sh and run_e2e.sh this suite includes ConnectivityManager,
# ActiveWorkoutManager and RestTimerManager: on the host, WatchConnectivity /
# HealthKit / UIKit are all behind `#if canImport` or `#if os(...)` and compile
# out, leaving the replication logic testable.
#
# The binary is placed inside a minimal .app because RestTimerManager calls
# UNUserNotificationCenter.current(), which raises an NSException in a process
# with no bundle identifier. This is a harness detail only — nothing in the app
# is conditioned on being under test.
#
# Usage: Tests/run_sync.sh   (from the repo root)
set -e
WORK=$(mktemp -d)
APP="$WORK/AruLiftsSyncTests.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.arulifts.synctests</string>
<key>CFBundleName</key><string>AruLiftsSyncTests</string>
<key>CFBundleExecutable</key><string>AruLiftsSyncTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
swiftc -o "$APP/Contents/MacOS/AruLiftsSyncTests" \
  Shared/Models/WorkoutTemplate.swift \
  Shared/Models/WorkoutSession.swift \
  Shared/Models/WorkoutSyncModels.swift \
  Shared/Models/WatchStartableWorkout.swift \
  Shared/Models/Exercise.swift \
  Shared/Models/ExerciseLibrary.swift \
  Shared/Models/ProgressSeries.swift \
  Shared/Store/WorkoutStore.swift \
  Shared/Store/Backup.swift \
  Shared/Store/ActiveWorkoutRepository.swift \
  Shared/Connectivity/WorkoutSyncCoordinator.swift \
  Shared/Connectivity/ConnectivityManager.swift \
  Shared/ActiveWorkout/Progression.swift \
  Shared/ActiveWorkout/Warmup.swift \
  Shared/ActiveWorkout/PlateCalculator.swift \
  Shared/ActiveWorkout/Records.swift \
  Shared/ActiveWorkout/RestTimerManager.swift \
  Shared/ActiveWorkout/ActiveWorkoutManager.swift \
  Shared/LiveActivity/WorkoutActivityAttributes.swift \
  Shared/LiveActivity/WorkoutLiveActivityManager.swift \
  Tests/SyncTests/main.swift
exec "$APP/Contents/MacOS/AruLiftsSyncTests"
