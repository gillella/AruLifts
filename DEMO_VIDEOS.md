# Adding exercise demo videos

Each exercise can show a short looping video of the correct posture on its
detail screen. The playback code is already in place
(`ExerciseDemoView` in `AruLifts/Views/ExerciseDetailView.swift`); you only need
to supply clips and point exercises at them.

## How resolution works

`ExerciseDemoView` looks for a clip in this order:

1. A file **bundled with the app** whose name matches the exercise's
   `videoName` (tries `.mp4`, `.mov`, `.m4v`).
2. The exercise's `videoURL` (a remote URL), if set.
3. Otherwise it shows an animated SF Symbol placeholder.

The video plays muted, on a loop, with controls disabled — ideal for a silent
form reference.

## Option A — bundle local clips (recommended)

1. Add your clips (e.g. `squat.mp4`, `bench_press.mp4`) to the project.
   - In Xcode: drag them into the **AruLifts** group.
   - Check **Copy items if needed** and add them to the **AruLifts** target
     (the Resources build phase).
2. Set `videoName` on the matching exercise in
   `Shared/Models/ExerciseLibrary.swift`. Example:

   ```swift
   Exercise(
       id: uid(50),
       name: "Back Squat",
       primaryMuscle: .quads,
       secondaryMuscles: [.glutes, .hamstrings, .core],
       equipment: .barbell,
       instructions: [ ... ],
       videoName: "squat",          // ← matches squat.mp4 in the bundle
       symbol: "figure.strengthtraining.traditional"
   )
   ```

Keep clips short (3–6 s), portrait or square, and compressed (H.264/HEVC) to
keep the app small.

## Option B — stream from a URL

Set `videoURL` instead of `videoName`:

```swift
videoURL: URL(string: "https://example.com/demos/squat.mp4")
```

Requires network access at view time. Prefer Option A for offline use.

## User-added exercises

Exercises created in-app (Exercises → +) don't have videos by default. You can
extend `NewExerciseView` to accept a `videoURL`, or ship the clip in the bundle
and set `videoName` to match.

## Licensing note

Ship only footage you have the rights to use. The repository intentionally does
not include video files.
