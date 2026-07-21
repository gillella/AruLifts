# Adding exercise demo videos

Every built-in exercise ships with an original, personalized start/finish
illustration plus a direct public YouTube technique link. The illustrations are
offline app assets; the linked videos remain on YouTube and open externally.

The app also retains support for optional short looping clips through
`ExerciseDemoView` in `AruLifts/Views/ExerciseDetailView.swift`.

## How resolution works

`ExerciseDemoView` looks for a clip in this order:

1. A file **bundled with the app** whose name matches the exercise's
   `videoName` (tries `.mp4`, `.mov`, `.m4v`).
2. The exercise's `videoURL` (a remote URL), if set.
3. The exercise's bundled `demoImageName` illustration.
4. Otherwise it shows an animated SF Symbol placeholder.

The video plays muted, on a loop, with controls disabled — ideal for a silent
form reference.

`techniqueVideoURL` is separate from `videoURL`: it may point to a YouTube watch
page and is opened by the **Watch technique video** button. Do not put a YouTube
page URL in `videoURL`, because `AVPlayer` requires a directly playable media
file.

## Bundled personalized illustrations

The 24 app-owned JPEGs live under
`AruLifts/Assets.xcassets/ExerciseDemos`. They are 1200 pixels wide and total
about 2.8 MB. The source generations used owner-supplied identity reference
photos; the personal source photos are not copied into the repository or app
bundle.

The illustrations are supporting references, not medical advice. The written
form steps and linked coaching videos provide the detailed technique context.

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

Ship only footage you have the rights to use. AruLifts does not download or
redistribute the linked YouTube videos; it stores ordinary public watch-page
URLs and opens them in YouTube or the browser.
