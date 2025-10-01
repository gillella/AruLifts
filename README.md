# AruLifts 💪

<div align="center">
  
**Your Personal Strength Training Companion**

Build strength, track progress, and achieve your fitness goals with the power of progressive overload.

</div>

## 🎯 Overview

AruLifts is a modern iOS workout tracking app built with SwiftUI, inspired by proven strength training principles. The app helps you follow structured workout programs, track your progress, and continuously improve your lifts.

## ✨ Features

### 🏋️ **5×5 Strength Program**
- Classic strength building program with two alternating workouts (A & B)
- **Workout A**: Squat, Bench Press, Barbell Row
- **Workout B**: Squat, Overhead Press, Deadlift
- Automatic progressive overload - weights increase as you get stronger

### 📊 **Progress Tracking**
- Track every workout with detailed set and rep logging
- Automatic weight progression based on performance
- Workout history with date, duration, and completion status
- Personal records and statistics

### ⏱️ **Built-in Rest Timer**
- Beautiful circular timer with progress visualization
- Customizable rest periods between sets
- Haptic feedback at key intervals
- Quick add time buttons for extended rest

### 🔥 **Warm-up Calculator**
- Calculate optimal warm-up sets based on your working weight
- Shows exact weight and plates needed for each warm-up set
- Prevents injury and prepares you for heavy lifts
- Supports different bar weights (45, 35, 15 lbs)

### 📚 **Exercise Library**
- Comprehensive database of compound and accessory exercises
- Detailed instructions for proper form
- Muscle group targeting information
- Search and filter by category or muscle group

### 📈 **Statistics & Analytics**
- Total workouts completed
- Current streak tracking
- Weekly workout frequency
- Total time spent training
- Weight progression charts

## 🏗️ Technical Architecture

### Built With
- **SwiftUI** - Modern declarative UI framework
- **Core Data** - Persistent local data storage
- **Combine** - Reactive programming for data flow
- **Swift 5.0** - Latest Swift language features

### Project Structure
```
AruLifts/
├── AruLifts/
│   ├── AruLiftsApp.swift          # App entry point
│   ├── ContentView.swift           # Main tab navigation
│   ├── PersistenceController.swift # Core Data manager
│   ├── Models/
│   │   ├── Exercise.swift          # Exercise data models
│   │   └── WorkoutSession.swift    # Workout session models
│   ├── Views/
│   │   ├── HomeView.swift          # Main dashboard
│   │   ├── WorkoutView.swift       # Active workout tracking
│   │   ├── RestTimerView.swift     # Rest timer interface
│   │   ├── HistoryView.swift       # Workout history & stats
│   │   ├── ExerciseLibraryView.swift # Exercise database
│   │   ├── WarmUpCalculatorView.swift # Warm-up calculator
│   │   └── SettingsView.swift      # App settings
│   ├── Managers/
│   │   └── WorkoutManager.swift    # Business logic & state
│   └── Assets.xcassets/            # Images & colors
└── README.md
```

## 🚀 Getting Started

### Requirements
- iOS 17.0+
- Xcode 15.0+
- Swift 5.0+

### Installation

1. Open the project in Xcode:
```bash
cd AruLifts
open AruLifts.xcodeproj
```

2. Select your target device or simulator

3. Build and run (⌘R)

## 🎨 Design Philosophy

AruLifts features a clean, modern design with:
- **Orange & Red gradient accents** - Energetic and motivating
- **Large, readable typography** - Easy to read during workouts
- **Intuitive navigation** - Tab-based interface for quick access
- **Minimalist UI** - Focus on what matters: your lifts
- **Haptic feedback** - Tactile confirmation of actions
- **Dark mode support** - Easy on the eyes in any lighting

## 📖 How to Use

### Starting Your First Workout

1. **Launch the app** - You'll see the home screen with your next workout
2. **Tap "Start Workout"** - Begin your training session
3. **Follow the program** - Complete each exercise with guided sets and reps
4. **Log your lifts** - Enter weight and reps for each set
5. **Rest between sets** - Use the built-in timer
6. **Finish strong** - Complete all exercises and save your progress

### Progressive Overload

The app automatically increases your weights when you successfully complete all sets:
- **Squat, Bench, Row, OHP**: +5 lbs per workout
- **Deadlift**: +10 lbs per workout

If you fail to complete all reps, the weight stays the same for your next workout.

## 🛠️ Future Enhancements

- [ ] iOS native AI integration for form checking
- [ ] Voice commands during workouts
- [ ] Apple Watch companion app
- [ ] Export workout data
- [ ] Custom program builder
- [ ] Video exercise demonstrations
- [ ] Social features and challenges
- [ ] Plate calculator
- [ ] Body weight and measurements tracking
- [ ] Cloud sync across devices

## 📱 Screenshots

> *Screenshots coming soon - build and run the app to see it in action!*

## 🤝 Contributing

This is a personal project, but feedback and suggestions are welcome! Feel free to:
- Report bugs
- Suggest new features
- Share your progress

## 📄 License

This project is created for personal use. The 5x5 training methodology is based on public domain strength training principles.

## 💡 Inspiration

Inspired by proven strength training programs like StrongLifts 5×5, Starting Strength, and decades of powerlifting wisdom. Built to help lifters of all levels build real strength through consistent, progressive training.

## 🙏 Acknowledgments

- Training methodology based on classic 5×5 programs
- Exercise descriptions and form cues from strength training literature
- Design inspiration from modern fitness apps

---

**Built with ❤️ for strength enthusiasts**

*Keep lifting, stay strong!* 🏋️‍♂️

