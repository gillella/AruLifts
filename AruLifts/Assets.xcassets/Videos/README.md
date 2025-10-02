# Exercise Videos Setup

## Current Status
The app is currently using network-based demo videos that may have connectivity issues in simulators.

## Quick Fix - Add Local Videos

To add working videos immediately:

1. **Download a small test video** (any MP4 file under 5MB)
2. **Rename it** to match the exercise names:
   - `bench_press_demo.mp4`
   - `dumbbell_bench_demo.mp4` 
   - `squat_demo.mp4`
   - `pullup_demo.mp4`

3. **Add to Xcode**:
   - Drag the video files into the Xcode project navigator
   - Make sure "Copy items if needed" is checked
   - Add to target "AruLifts"

4. **Build and run** - videos will work locally without network issues

## Alternative: Use System Videos

The app will automatically fall back to a professional "Coming Soon" interface if videos can't load, with exercise instructions and a retry button.

## For Production

When ready for production:
- Use high-quality exercise demonstration videos
- Optimize for mobile (compress to reasonable file sizes)
- Consider using a CDN for better performance