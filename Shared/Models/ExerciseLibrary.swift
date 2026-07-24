import Foundation

/// The built-in catalogue of exercises with form instructions. Users can also
/// add their own via `WorkoutStore`.
enum ExerciseLibrary {

    /// Stable UUIDs so templates that reference built-ins survive relaunches.
    private static func uid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "0000A000-0000-0000-0000-%012d", n))!
    }

    private static let rawAll: [Exercise] = [
        // MARK: - Chest
        Exercise(
            id: uid(1),
            name: "Barbell Bench Press",
            primaryMuscle: .chest,
            secondaryMuscles: [.triceps, .shoulders],
            equipment: .barbell,
            instructions: [
                "Lie flat, eyes under the bar, feet planted firmly on the floor.",
                "Grip slightly wider than shoulder width; squeeze shoulder blades together.",
                "Unrack and lower the bar to mid-chest with elbows ~45° from your torso.",
                "Press the bar back up and slightly toward your face until arms lock out."
            ],
            tips: [
                "Keep wrists stacked over elbows.",
                "Maintain a slight arch and tight upper back."
            ],
            symbol: "figure.strengthtraining.traditional"
        ),
        Exercise(
            id: uid(2),
            name: "Incline Dumbbell Press",
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders, .triceps],
            equipment: .dumbbell,
            instructions: [
                "Set the bench to ~30°. Sit back with a dumbbell in each hand at shoulder level.",
                "Press the dumbbells up and slightly together until arms are extended.",
                "Lower under control until you feel a stretch across the upper chest."
            ],
            tips: ["Don't clang the dumbbells at the top.", "Keep a neutral wrist."],
            symbol: "dumbbell.fill"
        ),
        Exercise(
            id: uid(3),
            name: "Push-Up",
            primaryMuscle: .chest,
            secondaryMuscles: [.triceps, .core],
            equipment: .bodyweight,
            instructions: [
                "Hands slightly wider than shoulders, body in a straight line.",
                "Lower until your chest is just above the floor, elbows ~45°.",
                "Press back up, keeping your core and glutes tight."
            ],
            tips: ["Don't let the hips sag.", "Full range of motion each rep."],
            symbol: "figure.core.training",
            usesWeight: false
        ),

        // MARK: - Back
        Exercise(
            id: uid(10),
            name: "Deadlift",
            primaryMuscle: .back,
            secondaryMuscles: [.glutes, .hamstrings, .core],
            equipment: .barbell,
            instructions: [
                "Stand with mid-foot under the bar, shins close.",
                "Hinge and grip just outside the knees; chest up, flat back.",
                "Drive through the floor, keeping the bar against your legs.",
                "Lock out hips and knees together; reverse to lower."
            ],
            tips: ["Brace your core before each rep.", "Keep the bar path vertical."],
            symbol: "figure.strengthtraining.traditional"
        ),
        Exercise(
            id: uid(11),
            name: "Barbell Row",
            primaryMuscle: .back,
            secondaryMuscles: [.biceps, .core],
            equipment: .barbell,
            instructions: [
                "Hinge to ~45°, flat back, bar hanging at arm's length.",
                "Pull the bar to your lower ribs, driving elbows back.",
                "Squeeze the shoulder blades, then lower under control."
            ],
            tips: ["Avoid jerking with your lower back.", "Keep the neck neutral."],
            symbol: "figure.rower"
        ),
        Exercise(
            id: uid(12),
            name: "Pull-Up",
            primaryMuscle: .back,
            secondaryMuscles: [.biceps, .forearms],
            equipment: .bodyweight,
            instructions: [
                "Hang from the bar with an overhand grip, shoulders engaged.",
                "Pull until your chin clears the bar, driving elbows down.",
                "Lower all the way to a full hang under control."
            ],
            tips: ["No kipping for strict reps.", "Think 'elbows to hips'."],
            symbol: "figure.play",
            usesWeight: false
        ),
        Exercise(
            id: uid(13),
            name: "Lat Pulldown",
            primaryMuscle: .back,
            secondaryMuscles: [.biceps],
            equipment: .cable,
            instructions: [
                "Grip the bar wider than shoulders; sit with thighs pinned.",
                "Pull the bar to your upper chest, leading with the elbows.",
                "Control the bar back up to a full stretch."
            ],
            tips: ["Don't lean back excessively.", "Keep the chest proud."],
            symbol: "cable.connector"
        ),

        // MARK: - Shoulders
        Exercise(
            id: uid(20),
            name: "Overhead Press",
            primaryMuscle: .shoulders,
            secondaryMuscles: [.triceps, .core],
            equipment: .barbell,
            instructions: [
                "Bar on front delts, grip just outside shoulders, elbows slightly forward.",
                "Brace, then press overhead, moving your head 'through the window'.",
                "Lock out with the bar over mid-foot; lower to the collarbone."
            ],
            tips: ["Squeeze glutes to avoid leaning back.", "Full lockout each rep."],
            symbol: "figure.strengthtraining.traditional"
        ),
        Exercise(
            id: uid(21),
            name: "Dumbbell Lateral Raise",
            primaryMuscle: .shoulders,
            secondaryMuscles: [],
            equipment: .dumbbell,
            instructions: [
                "Stand with dumbbells at your sides, slight bend in the elbows.",
                "Raise to shoulder height, leading with the elbows.",
                "Lower slowly; resist the urge to swing."
            ],
            tips: ["Pour-the-jug motion at the top.", "Light weight, strict form."],
            symbol: "dumbbell.fill"
        ),

        // MARK: - Biceps
        Exercise(
            id: uid(30),
            name: "Barbell Curl",
            primaryMuscle: .biceps,
            secondaryMuscles: [.forearms],
            equipment: .barbell,
            instructions: [
                "Stand tall, shoulder-width grip, elbows at your sides.",
                "Curl the bar up by flexing the biceps, keeping elbows still.",
                "Lower under control to a full stretch."
            ],
            tips: ["Don't swing the hips.", "Squeeze at the top."],
            symbol: "dumbbell.fill"
        ),
        Exercise(
            id: uid(31),
            name: "Dumbbell Hammer Curl",
            primaryMuscle: .biceps,
            secondaryMuscles: [.forearms],
            equipment: .dumbbell,
            instructions: [
                "Hold dumbbells with a neutral (palms-facing) grip.",
                "Curl up keeping the thumbs up; elbows pinned.",
                "Lower slowly to full extension."
            ],
            tips: ["Great for forearm and brachialis development."],
            symbol: "dumbbell.fill"
        ),

        // MARK: - Triceps
        Exercise(
            id: uid(40),
            name: "Triceps Pushdown",
            primaryMuscle: .triceps,
            secondaryMuscles: [],
            equipment: .cable,
            instructions: [
                "Grip the bar/rope, elbows pinned to your sides.",
                "Extend down until your arms lock out, squeezing the triceps.",
                "Return under control without flaring the elbows."
            ],
            tips: ["Keep your torso upright.", "Only the forearms move."],
            symbol: "cable.connector"
        ),
        Exercise(
            id: uid(41),
            name: "Close-Grip Bench Press",
            primaryMuscle: .triceps,
            secondaryMuscles: [.chest, .shoulders],
            equipment: .barbell,
            instructions: [
                "Grip about shoulder width; tuck elbows on the descent.",
                "Lower to the lower chest, then press up to lockout."
            ],
            tips: ["Keep wrists straight.", "Elbows close, not flared."],
            symbol: "figure.strengthtraining.traditional"
        ),
        Exercise(
            id: uid(42),
            name: "Triceps Dip",
            primaryMuscle: .triceps,
            secondaryMuscles: [.chest, .shoulders],
            equipment: .bodyweight,
            instructions: [
                "Support yourself on parallel bars, arms locked.",
                "Lower until elbows reach ~90°, torso slightly forward.",
                "Press back up to lockout."
            ],
            tips: ["Avoid shrugging the shoulders.", "Control the descent."],
            symbol: "figure.play",
            usesWeight: false
        ),

        // MARK: - Legs
        Exercise(
            id: uid(50),
            name: "Back Squat",
            primaryMuscle: .quads,
            secondaryMuscles: [.glutes, .hamstrings, .core],
            equipment: .barbell,
            instructions: [
                "Bar on upper traps, feet shoulder-width, toes slightly out.",
                "Brace, break at the hips and knees together.",
                "Descend until thighs are at least parallel; keep the chest up.",
                "Drive through mid-foot to stand tall."
            ],
            tips: ["Knees track over toes.", "Maintain a neutral spine."],
            symbol: "figure.strengthtraining.traditional"
        ),
        Exercise(
            id: uid(51),
            name: "Romanian Deadlift",
            primaryMuscle: .hamstrings,
            secondaryMuscles: [.glutes, .back],
            equipment: .barbell,
            instructions: [
                "Hold the bar at the hips, soft knees.",
                "Push the hips back, lowering the bar along the legs.",
                "Feel a hamstring stretch, then drive the hips forward to stand."
            ],
            tips: ["Keep the bar close.", "Flat back throughout."],
            symbol: "figure.strengthtraining.traditional"
        ),
        Exercise(
            id: uid(52),
            name: "Leg Press",
            primaryMuscle: .quads,
            secondaryMuscles: [.glutes, .hamstrings],
            equipment: .machine,
            instructions: [
                "Feet shoulder-width on the platform, back flat against the pad.",
                "Lower until knees reach ~90°.",
                "Press back without locking the knees harshly."
            ],
            tips: ["Don't let the lower back round.", "Control the negative."],
            symbol: "gearshape.fill"
        ),
        Exercise(
            id: uid(53),
            name: "Walking Lunge",
            primaryMuscle: .quads,
            secondaryMuscles: [.glutes, .hamstrings],
            equipment: .dumbbell,
            instructions: [
                "Hold dumbbells at your sides, step forward into a lunge.",
                "Lower the back knee toward the floor, front shin vertical.",
                "Drive through the front heel and step into the next rep."
            ],
            tips: ["Keep your torso upright.", "Even stride length."],
            symbol: "figure.walk"
        ),
        Exercise(
            id: uid(54),
            name: "Standing Calf Raise",
            primaryMuscle: .calves,
            secondaryMuscles: [],
            equipment: .machine,
            instructions: [
                "Balls of the feet on the platform, shoulders under the pads.",
                "Rise onto your toes as high as possible.",
                "Lower slowly to a deep stretch."
            ],
            tips: ["Pause at the top.", "Full range each rep."],
            symbol: "figure.walk"
        ),

        // MARK: - Glutes
        Exercise(
            id: uid(60),
            name: "Hip Thrust",
            primaryMuscle: .glutes,
            secondaryMuscles: [.hamstrings],
            equipment: .barbell,
            instructions: [
                "Upper back on a bench, bar across the hips.",
                "Drive through your heels to lift the hips to full extension.",
                "Squeeze the glutes hard, then lower under control."
            ],
            tips: ["Chin tucked, ribs down.", "Avoid hyperextending the back."],
            symbol: "figure.strengthtraining.traditional"
        ),

        // MARK: - Core
        Exercise(
            id: uid(70),
            name: "Plank",
            primaryMuscle: .core,
            secondaryMuscles: [.shoulders],
            equipment: .bodyweight,
            instructions: [
                "Forearms under shoulders, body in a straight line.",
                "Brace the abs and squeeze the glutes.",
                "Hold for the prescribed time, breathing steadily."
            ],
            tips: ["Don't let the hips sag or pike."],
            symbol: "figure.core.training",
            usesWeight: false
        ),
        Exercise(
            id: uid(71),
            name: "Hanging Leg Raise",
            primaryMuscle: .core,
            secondaryMuscles: [.forearms],
            equipment: .bodyweight,
            instructions: [
                "Hang from a bar, shoulders engaged.",
                "Raise your legs to hip height (or higher) without swinging.",
                "Lower under control."
            ],
            tips: ["Move slowly to avoid momentum."],
            symbol: "figure.play",
            usesWeight: false
        ),
        Exercise(
            id: uid(72),
            name: "Cable Crunch",
            primaryMuscle: .core,
            secondaryMuscles: [],
            equipment: .cable,
            instructions: [
                "Kneel below a high pulley, rope behind your head.",
                "Crunch down by flexing the abs, hips fixed.",
                "Return under control."
            ],
            tips: ["Round the spine; don't just hip-hinge."],
            symbol: "cable.connector"
        ),

        // MARK: - Cardio / Full body
        Exercise(
            id: uid(80),
            name: "Kettlebell Swing",
            primaryMuscle: .fullBody,
            secondaryMuscles: [.glutes, .hamstrings, .core],
            equipment: .kettlebell,
            instructions: [
                "Hinge and hike the bell back between your legs.",
                "Snap the hips forward to swing it to chest height.",
                "Let it fall, absorbing with a hip hinge."
            ],
            tips: ["Power comes from the hips, not the arms."],
            symbol: "figure.strengthtraining.functional",
            usesWeight: true
        ),

        // MARK: - Cardio machines (timed)
        Exercise(
            id: uid(90),
            name: "Treadmill",
            primaryMuscle: .cardio,
            secondaryMuscles: [.fullBody],
            equipment: .machine,
            instructions: [
                "Start at an easy walk to warm up for the first minute.",
                "Build to your target pace or incline and hold it.",
                "Ease back to a walk to cool down before stopping."
            ],
            tips: ["Aim for a pace you can sustain and still breathe.", "Great as a 10–15 min opener."],
            symbol: "figure.run",
            usesWeight: false,
            isTimed: true
        ),
        Exercise(
            id: uid(91),
            name: "Stationary Bike",
            primaryMuscle: .cardio,
            secondaryMuscles: [.quads, .hamstrings],
            equipment: .machine,
            instructions: [
                "Set the seat so your knee is slightly bent at the bottom.",
                "Spin at a steady cadence against a moderate resistance.",
                "Drop the resistance for the last minute to cool down."
            ],
            tips: ["Keep your core engaged and shoulders relaxed."],
            symbol: "figure.indoor.cycle",
            usesWeight: false,
            isTimed: true
        ),
        Exercise(
            id: uid(92),
            name: "Elliptical",
            primaryMuscle: .cardio,
            secondaryMuscles: [.fullBody],
            equipment: .machine,
            instructions: [
                "Stand tall, drive through the heels, and use the handles lightly.",
                "Hold a smooth, continuous stride at your target effort."
            ],
            tips: ["Low impact — good on days your joints need a break."],
            symbol: "figure.elliptical",
            usesWeight: false,
            isTimed: true
        ),
        Exercise(
            id: uid(93),
            name: "Rowing Machine",
            primaryMuscle: .cardio,
            secondaryMuscles: [.back, .fullBody],
            equipment: .machine,
            instructions: [
                "Drive with the legs first, then swing back and pull to the ribs.",
                "Reverse the order to return: arms, body, then legs.",
                "Keep a steady stroke rate for the duration."
            ],
            tips: ["Power is legs → hips → arms, in that order."],
            symbol: "figure.rower",
            usesWeight: false,
            isTimed: true
        ),

        // MARK: - Stretching / Mobility (timed)
        Exercise(
            id: uid(100),
            name: "Hamstring Stretch",
            primaryMuscle: .mobility,
            secondaryMuscles: [.hamstrings],
            equipment: .bodyweight,
            instructions: [
                "Sit or stand and hinge forward with a flat back.",
                "Reach toward your toes until you feel a gentle stretch.",
                "Hold and breathe; don't bounce."
            ],
            tips: ["Ease deeper on each exhale.", "Stretch both legs evenly."],
            symbol: "figure.flexibility",
            usesWeight: false,
            isTimed: true
        ),
        Exercise(
            id: uid(101),
            name: "Quad Stretch",
            primaryMuscle: .mobility,
            secondaryMuscles: [.quads],
            equipment: .bodyweight,
            instructions: [
                "Stand tall, pull one heel toward your glute.",
                "Keep the knees together and hips pushed slightly forward.",
                "Hold, then switch sides."
            ],
            tips: ["Hold a wall for balance if needed."],
            symbol: "figure.flexibility",
            usesWeight: false,
            isTimed: true
        ),
        Exercise(
            id: uid(102),
            name: "Chest Doorway Stretch",
            primaryMuscle: .mobility,
            secondaryMuscles: [.chest, .shoulders],
            equipment: .bodyweight,
            instructions: [
                "Place your forearms on a doorframe, elbows at shoulder height.",
                "Step through gently until you feel a stretch across the chest.",
                "Hold and breathe."
            ],
            tips: ["Great after pushing sessions."],
            symbol: "figure.flexibility",
            usesWeight: false,
            isTimed: true
        ),
        Exercise(
            id: uid(103),
            name: "Shoulder Cross-Body Stretch",
            primaryMuscle: .mobility,
            secondaryMuscles: [.shoulders],
            equipment: .bodyweight,
            instructions: [
                "Bring one arm across your body at chest height.",
                "Use the other arm to gently draw it closer.",
                "Hold, then switch sides."
            ],
            tips: ["Keep the shoulder down, away from your ear."],
            symbol: "figure.cooldown",
            usesWeight: false,
            isTimed: true
        ),
        Exercise(
            id: uid(104),
            name: "Hip Flexor Stretch",
            primaryMuscle: .mobility,
            secondaryMuscles: [.glutes, .quads],
            equipment: .bodyweight,
            instructions: [
                "Kneel in a half-lunge, back knee on the floor.",
                "Tuck the pelvis and push the hips forward.",
                "Hold, then switch sides."
            ],
            tips: ["Squeeze the back glute to deepen the stretch."],
            symbol: "figure.flexibility",
            usesWeight: false,
            isTimed: true
        ),
        Exercise(
            id: uid(105),
            name: "Child's Pose",
            primaryMuscle: .mobility,
            secondaryMuscles: [.back],
            equipment: .bodyweight,
            instructions: [
                "Kneel and sit back onto your heels.",
                "Reach your arms forward and lower your chest toward the floor.",
                "Relax and breathe into your lower back."
            ],
            tips: ["A calm finisher for the whole session."],
            symbol: "figure.cooldown",
            usesWeight: false,
            isTimed: true
        )
    ]

    private struct DemoMetadata {
        let imageName: String
        let videoURL: String
        let videoName: String?
        let localTechniqueVideoName: String?

        init(imageName: String, videoURL: String, videoName: String? = nil, localTechniqueVideoName: String? = nil) {
            self.imageName = imageName
            self.videoURL = videoURL
            self.videoName = videoName ?? imageName
            self.localTechniqueVideoName = localTechniqueVideoName ?? (imageName + "_technique")
        }
    }

    /// Original, offline illustrations and video demos are bundled with the app.
    /// Full-fledged offline technique videos replace external YouTube links.
    private static let demosByExercise: [String: DemoMetadata] = [
        "Barbell Bench Press": .init(imageName: "barbell_bench_press", videoURL: "https://www.youtube.com/watch?v=rT7DgCr-3pg"),
        "Incline Dumbbell Press": .init(imageName: "incline_dumbbell_press", videoURL: "https://www.youtube.com/watch?v=8iPEnn-ltC8"),
        "Push-Up": .init(imageName: "push_up", videoURL: "https://www.youtube.com/watch?v=wxhNoKZlfY8"),
        "Deadlift": .init(imageName: "deadlift", videoURL: "https://www.youtube.com/watch?v=n454SpMZRt8"),
        "Barbell Row": .init(imageName: "barbell_row", videoURL: "https://www.youtube.com/watch?v=9efgcAjQe7E"),
        "Pull-Up": .init(imageName: "pull_up", videoURL: "https://www.youtube.com/watch?v=ylVmNQlKdAI"),
        "Lat Pulldown": .init(imageName: "lat_pulldown", videoURL: "https://www.youtube.com/watch?v=CAwf7n6Luuc"),
        "Overhead Press": .init(imageName: "overhead_press", videoURL: "https://www.youtube.com/watch?v=2yjwXTZQDDI"),
        "Dumbbell Lateral Raise": .init(imageName: "dumbbell_lateral_raise", videoURL: "https://www.youtube.com/watch?v=3VcKaXpzqRo"),
        "Barbell Curl": .init(imageName: "barbell_curl", videoURL: "https://www.youtube.com/watch?v=QZEqB6wUPxQ"),
        "Dumbbell Hammer Curl": .init(imageName: "dumbbell_hammer_curl", videoURL: "https://www.youtube.com/watch?v=8XLxfXROrTo"),
        "Triceps Pushdown": .init(imageName: "triceps_pushdown", videoURL: "https://www.youtube.com/watch?v=_w-HpW70nSQ"),
        "Close-Grip Bench Press": .init(imageName: "close_grip_bench_press", videoURL: "https://www.youtube.com/watch?v=UYJsFzqdgK4"),
        "Triceps Dip": .init(imageName: "triceps_dip", videoURL: "https://www.youtube.com/watch?v=8UugSoVJLag"),
        "Back Squat": .init(imageName: "back_squat", videoURL: "https://www.youtube.com/watch?v=1oed-UmAxFs"),
        "Romanian Deadlift": .init(imageName: "romanian_deadlift", videoURL: "https://www.youtube.com/watch?v=JCXUYuzwNrM"),
        "Leg Press": .init(imageName: "leg_press", videoURL: "https://www.youtube.com/watch?v=oujca3_Shgw"),
        "Walking Lunge": .init(imageName: "walking_lunge", videoURL: "https://www.youtube.com/watch?v=D7KaRcUTQeE"),
        "Standing Calf Raise": .init(imageName: "standing_calf_raise", videoURL: "https://www.youtube.com/watch?v=YMmgqO8Jo-k"),
        "Hip Thrust": .init(imageName: "hip_thrust", videoURL: "https://www.youtube.com/watch?v=SEdqd1n0cvg"),
        "Plank": .init(imageName: "plank", videoURL: "https://www.youtube.com/watch?v=pSHjTRCQxIw"),
        "Hanging Leg Raise": .init(imageName: "hanging_leg_raise", videoURL: "https://www.youtube.com/watch?v=hdng3Nm1x_E"),
        "Cable Crunch": .init(imageName: "cable_crunch", videoURL: "https://www.youtube.com/watch?v=2fbujeH3F0E"),
        "Kettlebell Swing": .init(imageName: "kettlebell_swing", videoURL: "https://www.youtube.com/watch?v=YSxHifyI6s8"),
        "Treadmill": .init(imageName: "treadmill", videoURL: "https://www.youtube.com/watch?v=8i3VroHA8hE", videoName: "treadmill"),
        "Stationary Bike": .init(imageName: "stationary_bike", videoURL: "https://www.youtube.com/watch?v=vVw-Ua99VdQ", videoName: "stationary_bike"),
        "Elliptical": .init(imageName: "elliptical", videoURL: "https://www.youtube.com/watch?v=33K16298nFk", videoName: "elliptical"),
        "Rowing Machine": .init(imageName: "rowing_machine", videoURL: "https://www.youtube.com/watch?v=H0r_ZStB5kI", videoName: "rowing_machine"),
        "Hamstring Stretch": .init(imageName: "hamstring_stretch", videoURL: "https://www.youtube.com/watch?v=52aYgJqR7_0", videoName: "hamstring_stretch"),
        "Quad Stretch": .init(imageName: "quad_stretch", videoURL: "https://www.youtube.com/watch?v=2L1E1S0R4J0", videoName: "quad_stretch"),
        "Chest Doorway Stretch": .init(imageName: "chest_doorway_stretch", videoURL: "https://www.youtube.com/watch?v=N6Lp6fW0M88", videoName: "chest_doorway_stretch"),
        "Shoulder Cross-Body Stretch": .init(imageName: "shoulder_cross_body_stretch", videoURL: "https://www.youtube.com/watch?v=I7X1vY3t0bM", videoName: "shoulder_cross_body_stretch"),
        "Hip Flexor Stretch": .init(imageName: "hip_flexor_stretch", videoURL: "https://www.youtube.com/watch?v=YQmpO9VTk4E", videoName: "hip_flexor_stretch"),
        "Child's Pose": .init(imageName: "childs_pose", videoURL: "https://www.youtube.com/watch?v=eqVMAPM00DM", videoName: "childs_pose")
    ]

    static let all: [Exercise] = rawAll.map { raw in
        guard let demo = demosByExercise[raw.name] else { return raw }
        var exercise = raw
        exercise.demoImageName = demo.imageName
        exercise.videoName = demo.videoName ?? demo.imageName
        exercise.localTechniqueVideoName = demo.localTechniqueVideoName ?? (demo.imageName + "_technique")
        exercise.techniqueVideoURL = URL(string: demo.videoURL)
        return exercise
    }

    /// Quick lookup by id.
    static let byID: [UUID: Exercise] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    // MARK: - Default starter templates

    static func defaultTemplates() -> [WorkoutTemplate] {
        func te(_ id: Int, _ name: String, sets: Int, reps: Int, weight: Double = 0, rest: Int = 180) -> TemplateExercise {
            TemplateExercise(exerciseID: uid(id), name: name, targetSets: sets, targetReps: reps, weight: weight, restSeconds: rest)
        }
        func timed(_ id: Int, _ name: String, seconds: Int) -> TemplateExercise {
            TemplateExercise(exerciseID: uid(id), name: name, targetSets: 1, targetReps: 0, restSeconds: 0, durationSeconds: seconds)
        }

        return [
            WorkoutTemplate(
                name: "Upper Body",
                category: .upperBody,
                exercises: [
                    te(1, "Barbell Bench Press", sets: 4, reps: 8, weight: 60),
                    te(11, "Barbell Row", sets: 4, reps: 8, weight: 50),
                    te(20, "Overhead Press", sets: 3, reps: 10, weight: 35),
                    te(13, "Lat Pulldown", sets: 3, reps: 12, weight: 45),
                    te(21, "Dumbbell Lateral Raise", sets: 3, reps: 15, weight: 8, rest: 90)
                ]
            ),
            WorkoutTemplate(
                name: "Lower Body",
                category: .lowerBody,
                exercises: [
                    te(50, "Back Squat", sets: 4, reps: 6, weight: 80),
                    te(51, "Romanian Deadlift", sets: 3, reps: 10, weight: 60),
                    te(52, "Leg Press", sets: 3, reps: 12, weight: 120),
                    te(54, "Standing Calf Raise", sets: 4, reps: 15, weight: 40, rest: 90)
                ]
            ),
            WorkoutTemplate(
                name: "Arms",
                category: .arms,
                exercises: [
                    te(30, "Barbell Curl", sets: 4, reps: 10, weight: 25, rest: 120),
                    te(40, "Triceps Pushdown", sets: 4, reps: 12, weight: 25, rest: 120),
                    te(31, "Dumbbell Hammer Curl", sets: 3, reps: 12, weight: 12, rest: 90),
                    te(42, "Triceps Dip", sets: 3, reps: 10, rest: 90)
                ]
            ),
            WorkoutTemplate(
                name: "Cool-Down Stretch",
                category: .stretching,
                exercises: [
                    timed(100, "Hamstring Stretch", seconds: 45),
                    timed(101, "Quad Stretch", seconds: 45),
                    timed(104, "Hip Flexor Stretch", seconds: 45),
                    timed(102, "Chest Doorway Stretch", seconds: 45),
                    timed(105, "Child's Pose", seconds: 60)
                ]
            )
        ]
    }
}
