#!/bin/sh
# Compiles the shared pure-logic files with the assertion harness and runs it.
# Usage: Tests/run.sh   (from the repo root)
set -e
OUT=$(mktemp -d)/logic_tests
swiftc -o "$OUT" \
  Shared/Models/WorkoutTemplate.swift \
  Shared/Models/WorkoutSession.swift \
  Shared/Models/Exercise.swift \
  Shared/Models/ExerciseLibrary.swift \
  Shared/Models/ProgressSeries.swift \
  Shared/Store/WorkoutStore.swift \
  Shared/Store/Backup.swift \
  Shared/ActiveWorkout/Progression.swift \
  Shared/ActiveWorkout/Warmup.swift \
  Shared/ActiveWorkout/PlateCalculator.swift \
  Shared/ActiveWorkout/Records.swift \
  Tests/LogicTests/main.swift
exec "$OUT"
