# AruLifts - App Store Submission Guide

## Complete Step-by-Step Guide for First-Time App Store Submission

### Prerequisites ✅
- [x] Apple Developer Account (enrolled and paid $99/year)
- [x] Xcode installed
- [x] App built and tested
- [ ] App icon (1024x1024px)
- [ ] Screenshots
- [ ] App description and metadata

---

## Phase 1: Prepare App Assets (30 minutes)

### Step 1.1: Create App Icon

**Requirements:**
- Size: 1024x1024 pixels
- Format: PNG (no transparency)
- No rounded corners (Apple adds them automatically)

**Quick Options:**
1. **Use Canva** (easiest): https://www.canva.com/create/app-icons/
2. **Use App Icon Generator**: https://www.appicon.co/
3. **Hire on Fiverr**: $5-20 for professional icon

**Simple Icon Idea for AruLifts:**
- Orange gradient background
- White dumbbell or barbell icon
- Or use the SF Symbol: "figure.strengthtraining.traditional"

### Step 1.2: Create Screenshots

**Required Sizes (at minimum):**
- 6.7" iPhone (iPhone 15 Pro Max): 1290 × 2796 pixels
- 5.5" iPhone (for older devices): 1242 × 2208 pixels

**How to Take Screenshots:**
1. Run app in Xcode simulator
2. Select iPhone 15 Pro Max simulator
3. Navigate to different screens:
   - Home/Exercise Library
   - My Workouts
   - Workout in progress
   - History/Stats
   - Settings
4. Press `Cmd + S` to save screenshot
5. Repeat for at least 3-5 different screens

**Screenshot Tips:**
- Show the app's best features
- Include some mock data (create test workouts)
- First screenshot is most important (shows in search results)

### Step 1.3: Prepare App Metadata

**App Name:** AruLifts (or "AruLifts - Workout Tracker")

**Subtitle** (170 chars max):
```
Track strength training workouts with progressive overload
```

**Description** (4000 chars max):
```
AruLifts is your personal strength training companion designed to help you build muscle and track progress with proven principles of progressive overload.

KEY FEATURES:

📊 WORKOUT TRACKING
• Log sets, reps, and weights for every exercise
• Automatic weight progression tracking
• Exercise history with charts and statistics

💪 EXERCISE LIBRARY
• 42+ exercises with video demonstrations
• Organized by muscle group and equipment type
• Detailed instructions and form tips

🏋️ CUSTOM WORKOUTS
• Create personalized workout routines
• Build programs tailored to your goals
• Save and reuse favorite workouts

⏱️ SMART FEATURES
• Built-in rest timer
• Warm-up weight calculator
• Progressive overload tracking
• Workout history and analytics

📈 TRACK YOUR PROGRESS
• View personal records for each exercise
• Monitor workout frequency and consistency
• Track total volume and training stats
• See your strength gains over time

Whether you're a beginner or experienced lifter, AruLifts helps you stay consistent, track progress, and achieve your strength training goals.

Start your strength journey today!
```

**Keywords** (100 chars max):
```
workout,gym,fitness,strength,weights,bodybuilding,powerlifting,exercise,training,muscle
```

**Category:**
- Primary: Health & Fitness
- Secondary: (optional)

**Privacy Policy URL:**
Will create a simple one (required by Apple)

---

## Phase 2: Configure App in Xcode (15 minutes)

### Step 2.1: Update Bundle Identifier
1. Open `AruLifts.xcodeproj` in Xcode
2. Select project in navigator → AruLifts target
3. General tab → Identity
4. Bundle Identifier: `com.yourdomain.arulifts` (use your own domain or `com.yourname.arulifts`)

### Step 2.2: Update Version and Build Number
- Version: `1.0.0`
- Build: `1`

### Step 2.3: Add App Icon
1. In Xcode, open `Assets.xcassets`
2. Click on `AppIcon`
3. Drag your 1024x1024 icon to the "1024pt" slot

### Step 2.4: Configure Signing
1. Signing & Capabilities tab
2. Team: Select your Apple Developer account
3. Signing: Automatic
4. Provisioning Profile: Xcode Managed Profile

---

## Phase 3: Create App in App Store Connect (20 minutes)

### Step 3.1: Access App Store Connect
1. Go to https://appstoreconnect.apple.com/
2. Sign in with your Apple Developer account
3. Click "My Apps"
4. Click the "+" button → "New App"

### Step 3.2: Fill Out App Information

**Platforms:** iOS

**Name:** AruLifts

**Primary Language:** English (U.S.)

**Bundle ID:** Select the one you created in Xcode

**SKU:** arulifts-ios-001 (unique identifier for your records)

**User Access:** Full Access

Click "Create"

### Step 3.3: Fill Out Required Information

**App Information (left sidebar):**
- Category: Health & Fitness
- Content Rights: Check if you have all rights
- Age Rating: 4+ (no restricted content)

**Pricing and Availability:**
- Price: Free (or set price)
- Availability: All territories (or select specific countries)

**App Privacy:**
1. Click "Get Started"
2. Data Collection: Select what data you collect (for AruLifts: minimal/none)
   - If storing workouts locally only: "No, we do not collect data"
3. Click "Save" → "Publish"

**Privacy Policy:**
If required, create simple policy at:
- https://www.termsfeed.com/privacy-policy-generator/ (free)
- Or use this template: "AruLifts stores all workout data locally on your device. We do not collect, store, or share any personal information."

---

## Phase 4: Prepare Build for Upload (15 minutes)

### Step 4.1: Clean and Archive

In Xcode:
1. Select "Any iOS Device (arm64)" as build destination (NOT simulator)
2. Product → Clean Build Folder (Cmd + Shift + K)
3. Product → Archive (Cmd + B first to ensure it builds)
4. Wait for archive to complete (~2-5 minutes)

### Step 4.2: Distribute Archive

1. Organizer window will open automatically
2. Select your archive → Click "Distribute App"
3. Select "App Store Connect" → Next
4. Select "Upload" → Next
5. Distribution options (keep defaults):
   - ✅ Include bitcode: NO (deprecated)
   - ✅ Upload symbols: YES
   - ✅ Manage version: YES
6. Automatic Signing: YES → Next
7. Review info → Upload
8. Wait for upload to complete (~5-10 minutes)

**If you get errors:**
- Missing compliance: Answer "No" if not using encryption
- Missing icon: Go back to Step 2.3
- Signing issues: Check Developer account in Xcode preferences

---

## Phase 5: Submit for Review (15 minutes)

### Step 5.1: Wait for Build Processing
1. In App Store Connect, go to your app
2. TestFlight tab → check if build appears (takes 5-15 minutes)
3. Once processed, green checkmark appears

### Step 5.2: Complete App Store Information

**Version Information:**
1. Go to App Store tab → "1.0 Prepare for Submission"
2. Build: Click "+" and select the uploaded build

**Screenshots:**
1. Upload screenshots for required device sizes
2. App Preview (video): Optional, skip for now

**Description:** Paste from Step 1.3

**Keywords:** Paste from Step 1.3

**Support URL:** Your GitHub or website (e.g., https://github.com/gillella/Arulifts)

**Marketing URL:** Optional

**Promotional Text:** (optional, can update without review)
```
Track your strength training progress and achieve your fitness goals!
```

**App Review Information:**
- First Name: Your name
- Last Name: Your name
- Phone: Your phone
- Email: Your email
- Notes:
```
AruLifts is a workout tracking app for strength training.
Current version uses placeholder videos for exercise demonstrations.
All features are functional. No account required.
```

**Version Release:**
- Automatically release after approval (recommended for first app)

### Step 5.3: Submit

1. Click "Add for Review" (top right)
2. Review all information
3. Export Compliance: "No" (if no encryption)
4. Advertising Identifier: "No" (if no ads)
5. Click "Submit to App Review"

---

## Phase 6: Wait for Review (1-7 days)

### What Happens Next:

1. **Waiting for Review** (1-3 days usually)
   - Your app is in queue

2. **In Review** (few hours to 1 day)
   - Apple is testing your app

3. **Possible Outcomes:**

   **✅ Accepted:**
   - App goes live on App Store!
   - You'll receive email notification
   - Available for download within 24 hours

   **❌ Rejected:**
   - You'll receive reason for rejection
   - Fix issues and resubmit
   - Common issues for workout apps:
     - Need disclaimer about medical advice
     - Privacy policy required
     - Placeholder content (the videos might be flagged)

---

## Common Rejection Reasons & Fixes

### 1. Placeholder Content (Most Likely for AruLifts)
**Issue:** "App contains placeholder videos"

**Fix:**
1. Add real exercise videos (see VIDEO_SETUP.md)
2. OR add disclaimer: "Video demonstrations coming soon in next update"
3. Resubmit

### 2. Privacy Policy Required
**Issue:** "Privacy policy missing"

**Fix:**
1. Create simple privacy policy
2. Host on GitHub Pages or your website
3. Add URL to App Store Connect
4. Resubmit

### 3. Medical Disclaimer
**Issue:** "Health app needs medical disclaimer"

**Fix:**
Add to app description:
```
Disclaimer: Consult with a doctor before starting any new exercise program.
```

### 4. Metadata Rejected
**Issue:** "Screenshots don't match app"

**Fix:**
1. Retake screenshots from actual app
2. Update in App Store Connect
3. Resubmit (no need to upload new build)

---

## Checklist Before Submission

- [ ] App icon (1024x1024px) added to Xcode
- [ ] Screenshots taken (at least 3-5)
- [ ] Bundle identifier configured
- [ ] Version set to 1.0.0
- [ ] Signing configured with Developer account
- [ ] App Store Connect listing created
- [ ] Privacy policy created (if needed)
- [ ] Description and keywords written
- [ ] Build archived and uploaded
- [ ] Build processed in App Store Connect
- [ ] All required info filled in App Store Connect
- [ ] Export compliance answered
- [ ] Submitted for review

---

## After Approval

### Your App is Live! 🎉

**What to do:**
1. Share with friends and family
2. Ask for reviews (important for ranking)
3. Monitor crash reports in App Store Connect
4. Plan updates (add real videos, new features)

**Update Process:**
1. Make changes in Xcode
2. Increment version (1.0.0 → 1.0.1)
3. Archive and upload new build
4. Update "What's New" in App Store Connect
5. Submit for review

---

## Important Notes

### About Placeholder Videos
⚠️ **Apple may reject the app due to placeholder videos.**

**Options:**
1. **Add real videos first** (see VIDEO_SETUP.md) - RECOMMENDED
2. **Submit with placeholder** and add note in review comments
3. **Remove video feature** temporarily, add in update

### First App Tips
- Be patient with review process (1-7 days is normal)
- Respond quickly if rejected
- Read rejection reasons carefully
- Don't argue with reviewers, just fix and resubmit

### Cost Summary
- Developer Account: $99/year (already paid ✅)
- App Icon: $0-20 (if using Canva/Fiverr)
- Everything else: FREE!

---

## Need Help?

**Resources:**
- Apple Documentation: https://developer.apple.com/app-store/
- App Store Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Common Rejection Reasons: https://developer.apple.com/app-store/review/rejections/

**Issues During Submission:**
1. Check Apple Developer Forums
2. Review Apple's documentation
3. Resubmit with fixes (it's okay to resubmit multiple times!)

---

## Quick Start Checklist

Ready to begin? Follow these in order:

1. ⏰ **Today (2 hours):**
   - [ ] Create app icon
   - [ ] Take screenshots
   - [ ] Create App Store Connect listing
   - [ ] Configure Xcode for distribution

2. ⏰ **Tomorrow (1 hour):**
   - [ ] Archive and upload build
   - [ ] Fill out all App Store information
   - [ ] Submit for review

3. ⏰ **Next 1-7 days:**
   - [ ] Wait for review
   - [ ] Respond to any rejections
   - [ ] Celebrate when approved! 🎉

Let's get started! Which step would you like to begin with?
