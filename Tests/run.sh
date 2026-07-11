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
  Shared/Store/WorkoutStore.swift \
  Shared/ActiveWorkout/Progression.swift \
  Tests/LogicTests/main.swift
exec "$OUT"
