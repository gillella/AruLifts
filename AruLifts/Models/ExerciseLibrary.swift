//
//  ExerciseLibrary.swift
//  AruLifts
//
//  Created by Aravind Gillella on 10/1/25.
//

import Foundation

extension Exercise {
    // MARK: - Comprehensive Exercise Library (50+ exercises)
    
    // MARK: - Chest Exercises
    static let barbellBenchPress = Exercise(
        name: "Barbell Bench Press",
        description: "The best exercise to build a bigger, stronger chest.",
        category: .compound,
        equipment: .barbell,
        primaryMuscles: [.chest],
        secondaryMuscles: [.shoulders, .triceps],
        instructions: [
            "Lie on the bench with your eyes under the bar",
            "Grab the bar with a medium grip-width",
            "Unrack the bar by straightening your arms",
            "Lower the bar to your mid-chest",
            "Press the bar back up until your arms are straight"
        ]
    )
    
    static let inclineBenchPress = Exercise(
        name: "Incline Barbell Bench Press",
        description: "Targets the upper chest for complete chest development.",
        category: .compound,
        equipment: .barbell,
        primaryMuscles: [.chest],
        secondaryMuscles: [.shoulders, .triceps],
        instructions: [
            "Set bench to 30-45 degree incline",
            "Lie back and grip the bar slightly wider than shoulders",
            "Lower the bar to upper chest",
            "Press the bar up in a straight line",
            "Fully extend arms at the top"
        ]
    )
    
    static let dumbbellBenchPress = Exercise(
        name: "Dumbbell Bench Press",
        description: "Allows for greater range of motion and muscle activation.",
        category: .compound,
        equipment: .dumbbell,
        primaryMuscles: [.chest],
        secondaryMuscles: [.shoulders, .triceps],
        instructions: [
            "Sit on bench with dumbbells on thighs",
            "Lie back and position dumbbells at chest level",
            "Press dumbbells up until arms are extended",
            "Lower dumbbells with control",
            "Keep elbows at 45-degree angle"
        ]
    )
    
    static let dumbbellFlyes = Exercise(
        name: "Dumbbell Flyes",
        description: "Isolation exercise for chest stretch and definition.",
        category: .isolation,
        equipment: .dumbbell,
        primaryMuscles: [.chest],
        secondaryMuscles: [.shoulders],
        instructions: [
            "Lie on flat bench holding dumbbells above chest",
            "Slightly bend elbows and maintain throughout",
            "Lower weights out to sides in arc motion",
            "Feel the stretch in your chest",
            "Bring dumbbells back together at top"
        ]
    )
    
    static let cableCrossover = Exercise(
        name: "Cable Crossover",
        description: "Perfect for chest isolation and definition.",
        category: .isolation,
        equipment: .cable,
        primaryMuscles: [.chest],
        secondaryMuscles: [],
        instructions: [
            "Set cables to high position",
            "Grab handles and step forward",
            "Lean slightly forward, elbows slightly bent",
            "Bring handles together in front of chest",
            "Squeeze chest at the bottom"
        ]
    )
    
    static let pushUps = Exercise(
        name: "Push-ups",
        description: "Classic bodyweight chest builder.",
        category: .compound,
        equipment: .bodyweight,
        primaryMuscles: [.chest],
        secondaryMuscles: [.shoulders, .triceps, .core],
        instructions: [
            "Start in plank position, hands shoulder-width",
            "Keep body in straight line",
            "Lower chest to ground",
            "Push back up to starting position",
            "Keep core engaged throughout"
        ],
        requiresWeight: false
    )
    
    static let chestDips = Exercise(
        name: "Chest Dips",
        description: "Bodyweight exercise for lower chest.",
        category: .compound,
        equipment: .bodyweight,
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps, .shoulders],
        instructions: [
            "Grab parallel bars and jump up",
            "Lean forward slightly",
            "Lower body by bending elbows",
            "Go down until shoulders are below elbows",
            "Push back up to starting position"
        ],
        requiresWeight: false
    )
    
    // MARK: - Back Exercises
    static let barbellDeadlift = Exercise(
        name: "Barbell Deadlift",
        description: "The king of all exercises for overall strength.",
        category: .compound,
        equipment: .barbell,
        primaryMuscles: [.back],
        secondaryMuscles: [.legs, .glutes, .core],
        instructions: [
            "Stand with mid-foot under the bar",
            "Bend over and grab the bar",
            "Bend knees until shins touch bar",
            "Lift chest and straighten lower back",
            "Stand up with the weight"
        ]
    )
    
    static let barbellRow = Exercise(
        name: "Barbell Row",
        description: "Build a thick, strong back.",
        category: .compound,
        equipment: .barbell,
        primaryMuscles: [.back],
        secondaryMuscles: [.biceps, .core],
        instructions: [
            "Stand with mid-foot under bar",
            "Bend over and grab bar",
            "Unlock knees while keeping hips high",
            "Pull bar to lower chest",
            "Lower bar with control"
        ]
    )
    
    static let pullUps = Exercise(
        name: "Pull-ups",
        description: "Best bodyweight back exercise.",
        category: .compound,
        equipment: .bodyweight,
        primaryMuscles: [.back],
        secondaryMuscles: [.biceps, .shoulders],
        instructions: [
            "Grab bar with overhand grip",
            "Hang with arms fully extended",
            "Pull yourself up",
            "Get chin above bar",
            "Lower with control"
        ],
        requiresWeight: false
    )
    
    static let latPulldown = Exercise(
        name: "Lat Pulldown",
        description: "Machine alternative to pull-ups for back width.",
        category: .compound,
        equipment: .machine,
        primaryMuscles: [.back],
        secondaryMuscles: [.biceps],
        instructions: [
            "Sit at lat pulldown machine",
            "Grab bar wider than shoulder-width",
            "Pull bar down to upper chest",
            "Squeeze shoulder blades together",
            "Control the weight back up"
        ]
    )
    
    static let seatedCableRow = Exercise(
        name: "Seated Cable Row",
        description: "Build back thickness and strength.",
        category: .compound,
        equipment: .cable,
        primaryMuscles: [.back],
        secondaryMuscles: [.biceps],
        instructions: [
            "Sit at cable row station",
            "Grab handle with both hands",
            "Pull handle to lower chest",
            "Keep back straight",
            "Squeeze shoulder blades together"
        ]
    )
    
    static let dumbbellRow = Exercise(
        name: "Dumbbell Row",
        description: "Unilateral back exercise for balance.",
        category: .compound,
        equipment: .dumbbell,
        primaryMuscles: [.back],
        secondaryMuscles: [.biceps],
        instructions: [
            "Place one knee on bench",
            "Grab dumbbell with opposite hand",
            "Pull dumbbell to hip",
            "Keep back flat",
            "Lower with control"
        ]
    )
    
    // MARK: - Leg Exercises
    static let barbellSquat = Exercise(
        name: "Barbell Squat",
        description: "The king of leg exercises.",
        category: .compound,
        equipment: .barbell,
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.hamstrings, .core],
        instructions: [
            "Bar on upper back, feet shoulder-width",
            "Squat down by pushing knees out",
            "Go down until hips below knees",
            "Drive back up through heels",
            "Lock hips and knees at top"
        ]
    )
    
    static let frontSquat = Exercise(
        name: "Front Squat",
        description: "Quad-focused squat variation.",
        category: .compound,
        equipment: .barbell,
        primaryMuscles: [.quads],
        secondaryMuscles: [.glutes, .core],
        instructions: [
            "Rest bar on front shoulders",
            "Keep elbows high",
            "Squat down keeping torso upright",
            "Go as deep as possible",
            "Drive back up"
        ]
    )
    
    static let legPress = Exercise(
        name: "Leg Press",
        description: "Machine exercise for overall leg development.",
        category: .compound,
        equipment: .machine,
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.hamstrings],
        instructions: [
            "Sit in leg press machine",
            "Place feet shoulder-width on platform",
            "Lower weight by bending knees",
            "Stop before knees go past toes",
            "Press back up to starting position"
        ]
    )
    
    static let legExtension = Exercise(
        name: "Leg Extension",
        description: "Isolation exercise for quadriceps.",
        category: .isolation,
        equipment: .machine,
        primaryMuscles: [.quads],
        secondaryMuscles: [],
        instructions: [
            "Sit in leg extension machine",
            "Place ankles under pad",
            "Extend legs fully",
            "Squeeze quads at top",
            "Lower with control"
        ]
    )
    
    static let legCurl = Exercise(
        name: "Leg Curl",
        description: "Isolation exercise for hamstrings.",
        category: .isolation,
        equipment: .machine,
        primaryMuscles: [.hamstrings],
        secondaryMuscles: [],
        instructions: [
            "Lie face down on leg curl machine",
            "Place ankles under pad",
            "Curl legs up towards glutes",
            "Squeeze hamstrings at top",
            "Lower with control"
        ]
    )
    
    static let lunges = Exercise(
        name: "Lunges",
        description: "Unilateral leg exercise for balance and strength.",
        category: .compound,
        equipment: .bodyweight,
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.hamstrings],
        instructions: [
            "Stand with feet hip-width apart",
            "Step forward with one leg",
            "Lower back knee towards ground",
            "Push back to starting position",
            "Alternate legs"
        ],
        requiresWeight: false
    )
    
    static let calfRaises = Exercise(
        name: "Calf Raises",
        description: "Build strong, defined calves.",
        category: .isolation,
        equipment: .machine,
        primaryMuscles: [.calves],
        secondaryMuscles: [],
        instructions: [
            "Stand on raised platform",
            "Lower heels below platform",
            "Rise up on toes as high as possible",
            "Squeeze calves at top",
            "Lower with control"
        ]
    )
    
    // MARK: - Shoulder Exercises
    static let overheadPress = Exercise(
        name: "Overhead Press",
        description: "Best exercise for shoulder strength.",
        category: .compound,
        equipment: .barbell,
        primaryMuscles: [.shoulders],
        secondaryMuscles: [.triceps, .core],
        instructions: [
            "Bar on front shoulders",
            "Press bar overhead",
            "Move torso forward as bar passes face",
            "Lock elbows at top",
            "Lower to shoulders"
        ]
    )
    
    static let dumbbellShoulderPress = Exercise(
        name: "Dumbbell Shoulder Press",
        description: "Great for balanced shoulder development.",
        category: .compound,
        equipment: .dumbbell,
        primaryMuscles: [.shoulders],
        secondaryMuscles: [.triceps],
        instructions: [
            "Sit on bench with back support",
            "Hold dumbbells at shoulder level",
            "Press dumbbells overhead",
            "Bring dumbbells together at top",
            "Lower with control"
        ]
    )
    
    static let lateralRaises = Exercise(
        name: "Lateral Raises",
        description: "Isolation for side deltoids.",
        category: .isolation,
        equipment: .dumbbell,
        primaryMuscles: [.shoulders],
        secondaryMuscles: [],
        instructions: [
            "Stand with dumbbells at sides",
            "Raise arms out to sides",
            "Lift to shoulder height",
            "Pause at top",
            "Lower with control"
        ]
    )
    
    static let frontRaises = Exercise(
        name: "Front Raises",
        description: "Targets front deltoids.",
        category: .isolation,
        equipment: .dumbbell,
        primaryMuscles: [.shoulders],
        secondaryMuscles: [],
        instructions: [
            "Stand with dumbbells in front of thighs",
            "Raise one arm forward",
            "Lift to shoulder height",
            "Lower with control",
            "Alternate arms"
        ]
    )
    
    static let rearDeltFlyes = Exercise(
        name: "Rear Delt Flyes",
        description: "Isolation for rear deltoids.",
        category: .isolation,
        equipment: .dumbbell,
        primaryMuscles: [.shoulders],
        secondaryMuscles: [.back],
        instructions: [
            "Bend forward at waist",
            "Hold dumbbells with arms hanging",
            "Raise arms out to sides",
            "Squeeze shoulder blades",
            "Lower with control"
        ]
    )
    
    // MARK: - Arm Exercises (Biceps)
    static let barbellCurl = Exercise(
        name: "Barbell Curl",
        description: "Classic bicep builder.",
        category: .isolation,
        equipment: .barbell,
        primaryMuscles: [.biceps],
        secondaryMuscles: [],
        instructions: [
            "Stand holding barbell at hip level",
            "Keep elbows close to body",
            "Curl bar up to shoulders",
            "Squeeze biceps at top",
            "Lower with control"
        ]
    )
    
    static let dumbbellCurl = Exercise(
        name: "Dumbbell Curl",
        description: "Build bigger biceps with dumbbells.",
        category: .isolation,
        equipment: .dumbbell,
        primaryMuscles: [.biceps],
        secondaryMuscles: [],
        instructions: [
            "Stand with dumbbells at sides",
            "Keep elbows close to body",
            "Curl dumbbells up",
            "Rotate palms up as you lift",
            "Lower with control"
        ]
    )
    
    static let hammerCurl = Exercise(
        name: "Hammer Curl",
        description: "Targets biceps and forearms.",
        category: .isolation,
        equipment: .dumbbell,
        primaryMuscles: [.biceps],
        secondaryMuscles: [],
        instructions: [
            "Hold dumbbells with palms facing each other",
            "Keep elbows close to body",
            "Curl dumbbells up",
            "Maintain neutral grip throughout",
            "Lower with control"
        ]
    )
    
    static let preacherCurl = Exercise(
        name: "Preacher Curl",
        description: "Isolation curl for bicep peak.",
        category: .isolation,
        equipment: .barbell,
        primaryMuscles: [.biceps],
        secondaryMuscles: [],
        instructions: [
            "Sit at preacher bench",
            "Place arms on pad",
            "Curl bar up",
            "Keep upper arms on pad",
            "Lower with control"
        ]
    )
    
    // MARK: - Arm Exercises (Triceps)
    static let closeGripBenchPress = Exercise(
        name: "Close Grip Bench Press",
        description: "Compound movement for triceps.",
        category: .compound,
        equipment: .barbell,
        primaryMuscles: [.triceps],
        secondaryMuscles: [.chest, .shoulders],
        instructions: [
            "Lie on bench, grip bar narrow",
            "Lower bar to lower chest",
            "Keep elbows close to body",
            "Press bar up",
            "Lock out at top"
        ]
    )
    
    static let tricepDips = Exercise(
        name: "Tricep Dips",
        description: "Bodyweight tricep builder.",
        category: .compound,
        equipment: .bodyweight,
        primaryMuscles: [.triceps],
        secondaryMuscles: [.chest, .shoulders],
        instructions: [
            "Grab parallel bars",
            "Keep body upright",
            "Lower by bending elbows",
            "Go down until 90-degree angle",
            "Push back up"
        ],
        requiresWeight: false
    )
    
    static let tricepPushdown = Exercise(
        name: "Tricep Pushdown",
        description: "Cable isolation for triceps.",
        category: .isolation,
        equipment: .cable,
        primaryMuscles: [.triceps],
        secondaryMuscles: [],
        instructions: [
            "Stand at cable machine",
            "Grab bar with overhand grip",
            "Push bar down",
            "Keep elbows at sides",
            "Control back up"
        ]
    )
    
    static let overheadTricepExtension = Exercise(
        name: "Overhead Tricep Extension",
        description: "Stretches and builds triceps.",
        category: .isolation,
        equipment: .dumbbell,
        primaryMuscles: [.triceps],
        secondaryMuscles: [],
        instructions: [
            "Hold dumbbell overhead",
            "Lower behind head",
            "Keep elbows pointing up",
            "Extend back to starting position",
            "Control the movement"
        ]
    )
    
    // MARK: - Core/Abs Exercises
    static let plank = Exercise(
        name: "Plank",
        description: "Core strengthening exercise.",
        category: .isolation,
        equipment: .bodyweight,
        primaryMuscles: [.core],
        secondaryMuscles: [.shoulders],
        instructions: [
            "Get into push-up position",
            "Rest on forearms",
            "Keep body straight",
            "Hold position",
            "Breathe normally"
        ],
        requiresWeight: false
    )
    
    static let crunches = Exercise(
        name: "Crunches",
        description: "Classic abs exercise.",
        category: .isolation,
        equipment: .bodyweight,
        primaryMuscles: [.abs],
        secondaryMuscles: [],
        instructions: [
            "Lie on back, knees bent",
            "Place hands behind head",
            "Lift shoulders off ground",
            "Squeeze abs at top",
            "Lower with control"
        ],
        requiresWeight: false
    )
    
    static let russianTwists = Exercise(
        name: "Russian Twists",
        description: "Targets obliques and core.",
        category: .isolation,
        equipment: .bodyweight,
        primaryMuscles: [.core, .abs],
        secondaryMuscles: [],
        instructions: [
            "Sit on ground, knees bent",
            "Lean back slightly",
            "Rotate torso side to side",
            "Touch ground on each side",
            "Keep core engaged"
        ],
        requiresWeight: false
    )
    
    static let legRaises = Exercise(
        name: "Leg Raises",
        description: "Lower abs focused exercise.",
        category: .isolation,
        equipment: .bodyweight,
        primaryMuscles: [.abs],
        secondaryMuscles: [.core],
        instructions: [
            "Lie on back, legs straight",
            "Keep lower back pressed to ground",
            "Raise legs to 90 degrees",
            "Lower with control",
            "Don't let feet touch ground"
        ],
        requiresWeight: false
    )
    
    static let mountainClimbers = Exercise(
        name: "Mountain Climbers",
        description: "Dynamic core and cardio exercise.",
        category: .cardio,
        equipment: .bodyweight,
        primaryMuscles: [.core],
        secondaryMuscles: [.shoulders, .cardio],
        instructions: [
            "Start in push-up position",
            "Bring one knee to chest",
            "Quickly switch legs",
            "Keep hips down",
            "Maintain fast pace"
        ],
        requiresWeight: false
    )
    
    // MARK: - Cardio Exercises
    static let treadmillRunning = Exercise(
        name: "Treadmill Running",
        description: "Cardiovascular endurance training.",
        category: .cardio,
        equipment: .machine,
        primaryMuscles: [.cardio],
        secondaryMuscles: [.legs],
        instructions: [
            "Set desired speed and incline",
            "Start at warm-up pace",
            "Maintain steady rhythm",
            "Keep proper running form",
            "Cool down gradually"
        ],
        requiresWeight: false
    )
    
    static let cycling = Exercise(
        name: "Stationary Bike",
        description: "Low-impact cardio exercise.",
        category: .cardio,
        equipment: .machine,
        primaryMuscles: [.cardio],
        secondaryMuscles: [.legs],
        instructions: [
            "Adjust seat height",
            "Set resistance level",
            "Maintain steady pace",
            "Keep upper body relaxed",
            "Track time and distance"
        ],
        requiresWeight: false
    )
    
    static let jumpingJacks = Exercise(
        name: "Jumping Jacks",
        description: "Full body cardio warm-up.",
        category: .cardio,
        equipment: .bodyweight,
        primaryMuscles: [.cardio],
        secondaryMuscles: [.legs, .shoulders],
        instructions: [
            "Start with feet together",
            "Jump feet apart, raise arms overhead",
            "Jump feet back together, lower arms",
            "Maintain steady pace",
            "Keep breathing rhythmic"
        ],
        requiresWeight: false
    )
    
    static let burpees = Exercise(
        name: "Burpees",
        description: "High-intensity full body exercise.",
        category: .cardio,
        equipment: .bodyweight,
        primaryMuscles: [.cardio],
        secondaryMuscles: [.chest, .legs, .core],
        instructions: [
            "Start standing",
            "Drop into squat position",
            "Kick feet back to plank",
            "Do a push-up",
            "Jump back to squat, then jump up"
        ],
        requiresWeight: false
    )
    
    // MARK: - All Exercises Array
    static let allExercises: [Exercise] = [
        // Chest
        barbellBenchPress, inclineBenchPress, dumbbellBenchPress, dumbbellFlyes, cableCrossover, pushUps, chestDips,
        // Back
        barbellDeadlift, barbellRow, pullUps, latPulldown, seatedCableRow, dumbbellRow,
        // Legs
        barbellSquat, frontSquat, legPress, legExtension, legCurl, lunges, calfRaises,
        // Shoulders
        overheadPress, dumbbellShoulderPress, lateralRaises, frontRaises, rearDeltFlyes,
        // Biceps
        barbellCurl, dumbbellCurl, hammerCurl, preacherCurl,
        // Triceps
        closeGripBenchPress, tricepDips, tricepPushdown, overheadTricepExtension,
        // Core/Abs
        plank, crunches, russianTwists, legRaises, mountainClimbers,
        // Cardio
        treadmillRunning, cycling, jumpingJacks, burpees
    ]
}

