# Exercise Video Setup Guide

## Current Status
⚠️ **The app currently uses a placeholder video for all exercises.** This is a sample video (BigBuckBunny) used for testing purposes only.

## Why Placeholder Videos?

After extensive research, I found that:
- Most free exercise video sources (Pexels, Mixkit, Videvo) require downloading videos rather than providing direct MP4 URLs
- GIF libraries (like GymVisual) cannot be played in AVPlayer (they're images, not videos)
- Exercise APIs (ExerciseDB, etc.) require API keys and may have usage limits
- Direct embedding requires hosting videos on your own CDN

## Quick Start: Add Real Exercise Videos (3 Steps)

### Step 1: Download Free Exercise Videos

**Pexels (RECOMMENDED - 100% Free, No Attribution Required)**
1. Visit https://www.pexels.com/search/videos/
2. Search for each exercise name (e.g., "bench press", "squat", "deadlift")
3. Download videos you like in HD or SD quality

**Other Free Sources:**
- **Mixkit**: https://mixkit.co/free-stock-video/workout/ (718+ free workout videos)
- **Videvo**: https://www.videvo.net/stock-video-footage/fitness/ (free with attribution)
- **Vecteezy**: https://www.vecteezy.com/free-videos/workout

**List of Exercises to Download (42 total):**

**Chest (7):**
- Barbell Bench Press
- Incline Barbell Bench Press
- Dumbbell Bench Press
- Dumbbell Flyes
- Cable Crossover
- Push-ups
- Chest Dips

**Back (6):**
- Barbell Deadlift
- Barbell Row
- Pull-ups
- Lat Pulldown
- Seated Cable Row
- Dumbbell Row

**Legs (7):**
- Barbell Squat
- Front Squat
- Leg Press
- Leg Extension
- Leg Curl
- Lunges
- Calf Raises

**Shoulders (5):**
- Overhead Press
- Dumbbell Shoulder Press
- Lateral Raises
- Front Raises
- Rear Delt Flyes

**Biceps (4):**
- Barbell Curl
- Dumbbell Curl
- Hammer Curl
- Preacher Curl

**Triceps (4):**
- Close Grip Bench Press
- Tricep Dips
- Tricep Pushdown
- Overhead Tricep Extension

**Core/Abs (5):**
- Plank
- Crunches
- Russian Twists
- Leg Raises
- Mountain Climbers

**Cardio (4):**
- Treadmill Running
- Stationary Bike
- Jumping Jacks
- Burpees

### Step 2: Host Your Videos

Choose ONE option below:

#### Option A: Firebase Storage (Easiest - Recommended for Beginners)
1. Create free Firebase project at https://firebase.google.com/
2. Go to Firebase Console → Storage
3. Upload your exercise videos
4. Click on each video → Copy download URL
5. Update URLs in Step 3

**Pros:** Free tier (5GB storage), easy setup, reliable
**Cons:** May have bandwidth limits on free tier

#### Option B: AWS S3 + CloudFront (Best for Production)
1. Create AWS account
2. Create S3 bucket (make it public or use signed URLs)
3. Upload videos
4. Set up CloudFront CDN distribution
5. Get CloudFront URLs

**Pros:** Scalable, fast CDN, professional
**Cons:** Can be complex to set up, costs money (but very cheap)

#### Option C: Bundle with App (Simplest)
1. Drag video files into Xcode project
2. Use `Bundle.main.url(forResource:withExtension:)` to reference them
3. No internet required!

**Pros:** Works offline, no hosting costs
**Cons:** Makes app size larger (30-50MB+), can't update videos without app update

### Step 3: Update Video URLs in Code

Edit `AruLifts/Views/ExerciseLibraryView.swift` around line 759:

**For hosted videos (Firebase/AWS):**
```swift
let exerciseVideoMap: [String: String] = [
    "bench_press_demo": "https://firebasestorage.googleapis.com/.../bench-press.mp4",
    "incline_bench_demo": "https://firebasestorage.googleapis.com/.../incline-bench.mp4",
    "dumbbell_bench_demo": "https://firebasestorage.googleapis.com/.../dumbbell-bench.mp4",
    "flyes_demo": "https://firebasestorage.googleapis.com/.../flyes.mp4",
    "cable_crossover_demo": "https://firebasestorage.googleapis.com/.../cable-crossover.mp4",
    "squat_demo": "https://firebasestorage.googleapis.com/.../squat.mp4",
    "pullup_demo": "https://firebasestorage.googleapis.com/.../pullup.mp4",
    // ... add all 42 exercises
    "exercise_demo": "https://firebasestorage.googleapis.com/.../default.mp4"
]
```

**For bundled videos:**
```swift
// Change the video loading code to use Bundle
if let url = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
    let playerItem = AVPlayerItem(url: url)
    player = AVPlayer(playerItem: playerItem)
    // ... rest of code
}
```

## Alternative: Use Exercise API

If you don't want to manage videos yourself, consider using an API:

### ExerciseDB API (via RapidAPI)
- 1,300+ exercises with GIF animations
- Free tier: 100 requests/month
- Website: https://rapidapi.com/justin-WFnsXH_t6/api/exercisedb
- Returns GIF URLs you can display (note: GIFs can't be played in AVPlayer, need different UI)

## Video Specifications
- **Format**: MP4 (H.264 codec)
- **Resolution**: 720p (1280x720) or SD (640x480) is fine
- **Duration**: 10-30 seconds per exercise
- **File Size**: Keep under 5MB per video for fast loading
- **Aspect Ratio**: 16:9 or 1:1 (square)

## Testing
After adding videos:
1. Build and run app in simulator
2. Go to Exercise Library
3. Tap on an exercise (e.g., "Barbell Bench Press")
4. Tap the play button
5. Video should load and play

## Need Help?
- **Firebase setup**: https://firebase.google.com/docs/storage/ios/start
- **AWS S3 setup**: https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html
- **Pexels videos**: https://www.pexels.com/license/ (100% free, no attribution)

## Summary
1. Download 42 exercise videos from Pexels (free)
2. Upload to Firebase Storage (free tier)
3. Copy Firebase URLs into `ExerciseLibraryView.swift`
4. Test and enjoy!

Total time: ~2-3 hours for all 42 exercises
