//
//  ExerciseLibraryView.swift
//  AruLifts
//
//  Created by Aravind Gillella on 9/30/25.
//

import SwiftUI
import AVKit

struct ExerciseLibraryView: View {
    @EnvironmentObject var workoutManager: CustomWorkoutManager
    @State private var searchText = ""
    @State private var selectedCategory: ExerciseCategory? = nil
    @State private var selectedMuscleGroup: MuscleGroup? = nil
    
    var filteredExercises: [Exercise] {
        var exercises = workoutManager.exerciseLibrary
        
        if !searchText.isEmpty {
            exercises = exercises.filter { exercise in
                exercise.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        if let category = selectedCategory {
            exercises = exercises.filter { $0.category == category }
        }
        
        if let muscleGroup = selectedMuscleGroup {
            exercises = exercises.filter { exercise in
                exercise.primaryMuscles.contains(muscleGroup) ||
                exercise.secondaryMuscles.contains(muscleGroup)
            }
        }
        
        return exercises
    }
    
    var body: some View {
        NavigationView {
            List {
                // Search bar
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Search exercises...", text: $searchText)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }

                // Filters
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            FilterChip(
                                title: "All",
                                isSelected: selectedCategory == nil && selectedMuscleGroup == nil,
                                action: {
                                    selectedCategory = nil
                                    selectedMuscleGroup = nil
                                }
                            )

                            ForEach(ExerciseCategory.allCases, id: \.self) { category in
                                FilterChip(
                                    title: category.rawValue,
                                    isSelected: selectedCategory == category,
                                    action: {
                                        selectedCategory = selectedCategory == category ? nil : category
                                        selectedMuscleGroup = nil
                                    }
                                )
                            }

                            Divider()
                                .frame(height: 20)

                            ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                                FilterChip(
                                    title: muscle.rawValue,
                                    isSelected: selectedMuscleGroup == muscle,
                                    action: {
                                        selectedMuscleGroup = selectedMuscleGroup == muscle ? nil : muscle
                                        selectedCategory = nil
                                    }
                                )
                            }
                        }
                    }
                }

                // Exercise list
                Section(header: Text("\(filteredExercises.count) Exercises")) {
                    ForEach(filteredExercises) { exercise in
                        NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name)
                                    .font(.headline)
                                Text(exercise.category.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Exercise Library")
        }
        .navigationViewStyle(.stack)
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.orange : Color(.systemGray6))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
}

struct ExerciseCard: View {
    let exercise: Exercise
    @EnvironmentObject var workoutManager: CustomWorkoutManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        Text(exercise.category.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                        
                        ForEach(exercise.primaryMuscles, id: \.self) { muscle in
                            Text(muscle.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }
                }
                
                Spacer()
                
                if let weight = workoutManager.exerciseWeights[exercise.name] {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(workoutManager.formatWeight(weight))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                        Text("lbs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Text(exercise.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct ExerciseDetailView: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var showingVideo = false
    
    var body: some View {
        ScrollView {
                VStack(spacing: 0) {
                    // Header with exercise image
                    ExerciseHeaderView(exercise: exercise, showingVideo: $showingVideo)
                    
                    // Tab selector
                    TabSelectorView(selectedTab: $selectedTab)
                    
                    // Content based on selected tab
                    TabContentView(exercise: exercise, selectedTab: selectedTab)
                }
            }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showingVideo) {
            VideoPlayerView(exercise: exercise)
        }
    }
}

struct ExerciseHeaderView: View {
    let exercise: Exercise
    @Binding var showingVideo: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            // Exercise image placeholder
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 200)
                .overlay(
                    VStack(spacing: 16) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text(exercise.name)
                            .font(.headline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                )
                        .overlay(
                            // Video play button
                            Button(action: { showingVideo = true }) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.white)
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(Circle())
                            }
                            .opacity(exercise.videoURL != nil ? 1 : 0)
                            .allowsHitTesting(exercise.videoURL != nil)
                        )
            
            // Exercise info cards
            HStack(spacing: 12) {
                InfoCard(
                    icon: "dumbbell.fill",
                    title: "Equipment",
                    value: exercise.equipment.rawValue,
                    color: .blue
                )
                
                InfoCard(
                    icon: "star.fill",
                    title: "Level",
                    value: "Intermediate",
                    color: .orange
                )
                
                InfoCard(
                    icon: "figure.strengthtraining.traditional",
                    title: "Type",
                    value: exercise.category.rawValue,
                    color: .orange
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

struct InfoCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct TabSelectorView: View {
    @Binding var selectedTab: Int
    
    private let tabs = ["Instructions", "Form Tips", "Safety", "Muscles"]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                Button(action: { selectedTab = index }) {
                    Text(tabs[index])
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(selectedTab == index ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == index ? Color.orange : Color.clear)
                        )
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
    }
}

struct TabContentView: View {
    let exercise: Exercise
    let selectedTab: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch selectedTab {
            case 0:
                InstructionsView(exercise: exercise)
            case 1:
                FormTipsView(exercise: exercise)
            case 2:
                SafetyView(exercise: exercise)
            case 3:
                MusclesView(exercise: exercise)
            default:
                InstructionsView(exercise: exercise)
            }
        }
        .padding()
    }
}

struct InstructionsView: View {
    let exercise: Exercise
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to Perform")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(exercise.description)
                .font(.body)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Color.orange)
                            .clipShape(Circle())
                        
                        Text(instruction)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            
            BreathingPatternView(pattern: "Inhale on the way down, exhale forcefully on the way up")
        }
    }
}

struct FormTipsView: View {
    let exercise: Exercise
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Form Tips")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                    
                    Text("Keep proper form throughout the movement")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                    
                    Text("Control the weight - don't use momentum")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                    
                    Text("Breathe properly during the exercise")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Divider()
            
            Text("Common Mistakes to Avoid")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                    
                    Text("Using too much weight with poor form")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                    
                    Text("Not maintaining proper breathing")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct SafetyView: View {
    let exercise: Exercise
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Safety Guidelines")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "shield.checkered")
                        .foregroundColor(.blue)
                        .font(.title3)
                    
                    Text("Always use proper form and control")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "shield.checkered")
                        .foregroundColor(.blue)
                        .font(.title3)
                    
                    Text("Start with lighter weight to perfect technique")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "shield.checkered")
                        .foregroundColor(.blue)
                        .font(.title3)
                    
                    Text("Stop if you feel sharp pain")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Divider()
            
            Text("Alternative Exercises")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                Text("Bodyweight Version")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .cornerRadius(8)
                
                Text("Machine Alternative")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .cornerRadius(8)
            }
        }
    }
}

struct MusclesView: View {
    let exercise: Exercise
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Muscle Groups")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 16) {
                MuscleGroupSection(
                    title: "Primary Muscles",
                    muscles: exercise.primaryMuscles,
                    color: .orange
                )
                
                if !exercise.secondaryMuscles.isEmpty {
                    MuscleGroupSection(
                        title: "Secondary Muscles",
                        muscles: exercise.secondaryMuscles,
                        color: .blue
                    )
                }
            }
        }
    }
}

struct MuscleGroupSection: View {
    let title: String
    let muscles: [MuscleGroup]
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(muscles, id: \.self) { muscle in
                    Text(muscle.rawValue)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(color.opacity(0.2))
                        .foregroundColor(color)
                        .cornerRadius(8)
                }
            }
        }
    }
}

struct BreathingPatternView: View {
    let pattern: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lungs.fill")
                    .foregroundColor(.blue)
                Text("Breathing Pattern")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            Text(pattern)
                .font(.body)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
        }
    }
}

struct VideoPlayerView: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var showError = false
    @State private var isLoading = true
    @State private var videoLoadAttempted = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if let player = player, !showError {
                    // Custom Video Player
                    CustomVideoPlayer(player: player, isPlaying: $isPlaying, isLoading: $isLoading)
                        .aspectRatio(16/9, contentMode: .fit)
                        .background(Color.black)
                        .overlay(
                            // Loading indicator
                            Group {
                                if isLoading {
                                    VStack {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(1.5)
                                        Text("Loading video...")
                                            .foregroundColor(.white)
                                            .font(.caption)
                                            .padding(.top, 8)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.black.opacity(0.7))
                                }
                            }
                        )
                } else {
                    // Fallback: Professional Exercise Demo Interface
                    ExerciseDemoFallbackView(exercise: exercise, showRetryButton: videoLoadAttempted) {
                        // Retry loading video
                        videoLoadAttempted = false
                        showError = false
                        loadVideo()
                    }
                }
            }
            .navigationTitle("Exercise Demo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        player?.pause()
                        dismiss()
                    }
                }
                
                if player != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            if isPlaying {
                                player?.pause()
                            } else {
                                player?.play()
                            }
                            isPlaying.toggle()
                        }) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        }
        .onAppear {
            if !videoLoadAttempted {
                loadVideo()
            }
        }
        .onDisappear {
            player?.pause()
        }
    }
    
    private func loadVideo() {
        videoLoadAttempted = true
        guard let videoName = exercise.videoURL else { 
            showError = true
            return 
        }
        
        // Try to load from app bundle first
        if let videoURL = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
            player = AVPlayer(url: videoURL)
            return
        }
        
        // Try alternative formats
        let formats = ["mov", "m4v", "mp4"]
        for format in formats {
            if let videoURL = Bundle.main.url(forResource: videoName, withExtension: format) {
                player = AVPlayer(url: videoURL)
                return
            }
        }
        
        // ⚠️ PLACEHOLDER VIDEO - SEE VIDEO_SETUP.md FOR IMPLEMENTATION ⚠️
        //
        // CURRENT STATUS: Using sample video for all exercises
        //
        // TO IMPLEMENT REAL EXERCISE VIDEOS:
        // 1. Download exercise videos from:
        //    - Pexels.com (free, royalty-free)
        //    - Videvo.net (free with attribution)
        //    - Mixkit.co (free, no watermark)
        //
        // 2. Host videos on:
        //    - AWS S3 + CloudFront
        //    - Firebase Storage
        //    - Your own CDN
        //
        // 3. Update URLs below with your hosted video URLs
        //
        // See VIDEO_SETUP.md for detailed instructions

        let defaultVideo = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"

        let exerciseVideoMap: [String: String] = [
            // TODO: Replace these with actual exercise demonstration videos
            "bench_press_demo": defaultVideo,
            "incline_bench_demo": defaultVideo,
            "dumbbell_bench_demo": defaultVideo,
            "flyes_demo": defaultVideo,
            "cable_crossover_demo": defaultVideo,
            "squat_demo": defaultVideo,
            "pullup_demo": defaultVideo,
            "exercise_demo": defaultVideo
        ]

        // Get video URL for this exercise
        let videoURLString = exerciseVideoMap[videoName] ?? defaultVideo

        // Try sample video URL
        if let url = URL(string: videoURLString) {
            let playerItem = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: playerItem)

            // Monitor player status
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { _ in
                print("Video failed to load: \(videoURLString)")
                self.showError = true
            }

            // Monitor loading status
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if let status = playerItem.status as AVPlayerItem.Status?, status == .readyToPlay {
                    self.isLoading = false
                } else if self.isLoading {
                    self.isLoading = false
                }
            }
            return
        }
        
        // If no video found, show error
        showError = true
    }
}

struct CustomVideoPlayer: UIViewRepresentable {
    let player: AVPlayer
    @Binding var isPlaying: Bool
    @Binding var isLoading: Bool
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(playerLayer)
        
        // Store player layer for updates
        context.coordinator.playerLayer = playerLayer
        context.coordinator.isLoading = isLoading
        
        // Add observer for player status
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.playerDidFinishLoading),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
        
        // Start loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.isLoading = false
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.playerLayer?.frame = uiView.bounds
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var playerLayer: AVPlayerLayer?
        var isLoading: Bool = true
        
        @objc func playerDidFinishLoading() {
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
    }
}

struct ExerciseDemoFallbackView: View {
    let exercise: Exercise
    let showRetryButton: Bool
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Professional Exercise Icon
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [Color.orange.opacity(0.3), Color.red.opacity(0.3)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 120, height: 120)
                
                Image(systemName: getExerciseIcon())
                    .font(.system(size: 50, weight: .medium))
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: 16) {
                Text("Exercise Demonstration")
                    .font(.title2)
                    .fontWeight(.bold)
                
                if showRetryButton {
                    Text("Video temporarily unavailable")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    Button(action: onRetry) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry Video")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(10)
                    }
                } else {
                    Text("Professional video demonstration coming soon!")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
            }
            
            // Exercise Instructions Preview
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Instructions")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                ForEach(Array(exercise.instructions.prefix(3).enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.orange)
                            .clipShape(Circle())
                        
                        Text(instruction)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
    
    private func getExerciseIcon() -> String {
        switch exercise.equipment {
        case .barbell:
            return "dumbbell.fill"
        case .dumbbell:
            return "dumbbell.fill"
        case .machine:
            return "gearshape.fill"
        case .cable:
            return "cable.connector"
        case .bodyweight:
            return "figure.strengthtraining.traditional"
        case .kettlebell:
            return "dumbbell.fill"
        case .band:
            return "bandage.fill"
        }
    }
}

#Preview {
    ExerciseLibraryView()
        .environmentObject(CustomWorkoutManager.shared)
}

