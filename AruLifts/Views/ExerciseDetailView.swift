import SwiftUI
import AVKit
import AVFoundation

struct ExerciseDetailView: View {
    @EnvironmentObject private var store: WorkoutStore
    let exercise: Exercise
    @State private var showingAddToWorkout = false
    @State private var showingTechniqueVideoModal = false

    private func resolveTechniqueURL() -> URL? {
        if let name = exercise.localTechniqueVideoName {
            for ext in ["mp4", "mov", "m4v"] {
                if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                    return url
                }
            }
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ExerciseDemoView(exercise: exercise)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                if exercise.videoName != nil {
                    Text("AI-generated personalized form video demo")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityLabel("AI generated personalized form video demo")
                } else if exercise.demoImageName != nil {
                    Text("AI-generated personalized form illustration")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityLabel("AI generated personalized form illustration")
                }

                if let localTechniqueURL = resolveTechniqueURL() {
                    Button {
                        showingTechniqueVideoModal = true
                    } label: {
                        Label("Watch technique video", systemImage: "play.rectangle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .accessibilityHint("Plays offline exercise technique video")
                    .sheet(isPresented: $showingTechniqueVideoModal) {
                        FullTechniqueVideoSheet(exercise: exercise, videoURL: localTechniqueURL)
                    }
                } else if let techniqueURL = exercise.techniqueVideoURL {
                    Link(destination: techniqueURL) {
                        Label("Watch technique video", systemImage: "play.rectangle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .accessibilityHint("Opens a public video in YouTube or your web browser")
                }

                HStack(spacing: 8) {
                    CategoryTag(text: exercise.primaryMuscle.displayName, color: .orange)
                    ForEach(exercise.secondaryMuscles, id: \.self) { m in
                        CategoryTag(text: m.displayName, color: .secondary)
                    }
                    CategoryTag(text: exercise.equipment.displayName, color: .blue)
                }

                if !exercise.instructions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to perform")
                            .font(.title3.bold())
                        ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { idx, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(idx + 1)")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(Color.orange))
                                Text(step)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                if !exercise.tips.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Tips", systemImage: "lightbulb.fill")
                            .font(.headline)
                            .foregroundStyle(.yellow)
                        ForEach(exercise.tips, id: \.self) { tip in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.footnote)
                                    .padding(.top, 3)
                                Text(tip).font(.subheadline)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
                }
            }
            .padding()
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    store.toggleFavorite(exercise)
                } label: {
                    Image(systemName: store.isFavorite(exercise) ? "star.fill" : "star")
                        .foregroundStyle(store.isFavorite(exercise) ? .yellow : .primary)
                }
                .accessibilityLabel(store.isFavorite(exercise) ? "Remove from favorites" : "Add to favorites")

                Button {
                    showingAddToWorkout = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel("Add to workout")
            }
        }
        .sheet(isPresented: $showingAddToWorkout) {
            AddExerciseToWorkoutSheet(exercise: exercise)
        }
    }
}

struct CategoryTag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Plays a looping demo clip when one is available, otherwise shows an animated
/// SF Symbol placeholder. Drop an `.mp4`/`.mov` into the app bundle named to
/// match `Exercise.videoName` to enable real footage (see Demo Videos docs).
struct ExerciseDemoView: View {
    let exercise: Exercise
    @State private var looper: AVPlayerLooper?
    @State private var player: AVQueuePlayer?
    @State private var pulse = false

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .disabled(true)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else if let imageName = exercise.demoImageName {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
                    .accessibilityLabel("Start and finish positions for \(exercise.name)")
            } else {
                placeholder
            }
        }
        .onAppear(perform: setupPlayer)
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: exercise.symbol)
                .font(.system(size: 64))
                .foregroundStyle(.orange)
                .scaleEffect(pulse ? 1.08 : 0.94)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            Text("Form demo")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { pulse = true }
    }

    private func setupPlayer() {
        guard player == nil, let url = resolveURL() else { return }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(playerItem: item)
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
    }

    private func resolveURL() -> URL? {
        if let name = exercise.videoName {
            for ext in ["mp4", "mov", "m4v"] {
                if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                    return url
                }
            }
        }
        return exercise.videoURL
    }
}

struct FullTechniqueVideoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    let videoURL: URL
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            VStack {
                if let player {
                    VideoPlayer(player: player)
                        .onAppear { player.play() }
                        .onDisappear { player.pause() }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("\(exercise.name) Technique")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                player = AVPlayer(url: videoURL)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ExerciseDetailView(exercise: ExerciseLibrary.all[0])
    }
}
