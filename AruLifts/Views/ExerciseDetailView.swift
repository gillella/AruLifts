import SwiftUI
import AVKit
import AVFoundation

struct ExerciseDetailView: View {
    @EnvironmentObject private var store: WorkoutStore
    let exercise: Exercise
    @State private var showingAddToWorkout = false
    @State private var showingExpandedMedia = false

    /// Whether a bundled clip actually exists in the app bundle. Combined with
    /// `videoURL`/`demoImageName` by `Exercise.formMediaKind` to decide what the
    /// expand button opens.
    private var hasBundledVideo: Bool {
        guard let name = exercise.videoName else { return false }
        return ["mp4", "mov", "m4v"].contains { Bundle.main.url(forResource: name, withExtension: $0) != nil }
    }

    private var mediaKind: Exercise.FormMediaKind {
        exercise.formMediaKind(hasBundledVideo: hasBundledVideo)
    }

    /// The concrete media handed to the full-screen viewer, or nil when the
    /// exercise only has the placeholder symbol (nothing to expand).
    private var expandableContent: FormMediaViewer.Content? {
        switch mediaKind {
        case .video:
            guard let url = ExerciseDemoView.resolveVideoURL(for: exercise) else { return nil }
            return .video(url)
        case .image:
            guard let name = exercise.demoImageName else { return nil }
            return .image(name)
        case .none:
            return nil
        }
    }

    private var mediaAccessibilityLabel: String {
        switch mediaKind {
        case .video: return "Form video demo for \(exercise.name)"
        case .image: return "Form illustration for \(exercise.name)"
        case .none: return "Form demo placeholder for \(exercise.name)"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZStack(alignment: .topTrailing) {
                    ExerciseDemoView(exercise: exercise)
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if expandableContent != nil {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.footnote.weight(.semibold))
                            .padding(8)
                            .background(.thinMaterial, in: Circle())
                            .padding(10)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onTapGesture {
                    if expandableContent != nil { showingExpandedMedia = true }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(mediaAccessibilityLabel)
                .accessibilityAddTraits(expandableContent != nil ? .isButton : [])
                .accessibilityHint(expandableContent != nil ? "Opens a full-screen viewer you can zoom and pan" : "")
                // VoiceOver's activate gesture drives this action; the plain
                // onTapGesture alone is not reliably invoked by VoiceOver.
                .accessibilityAction {
                    if expandableContent != nil { showingExpandedMedia = true }
                }

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

                if let techniqueURL = exercise.techniqueVideoURL {
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
        .fullScreenCover(isPresented: $showingExpandedMedia) {
            if let content = expandableContent {
                FormMediaViewer(content: content, exerciseName: exercise.name)
            }
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
        guard player == nil, let url = ExerciseDemoView.resolveVideoURL(for: exercise) else { return }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(playerItem: item)
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
    }

    /// Resolves a directly playable clip: a bundled file matching `videoName`
    /// first, then the optional remote `videoURL`. Shared with the full-screen
    /// viewer so both agree on what "has a video" means.
    static func resolveVideoURL(for exercise: Exercise) -> URL? {
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

/// Full-screen viewer for a single exercise's form media, presented as a
/// `fullScreenCover`. Still illustrations are zoomable/pannable; video demos
/// play with standard transport controls. Both adapt to portrait and landscape
/// and provide a Done control. Only presented when media actually exists, so it
/// never shows a broken/empty viewer.
struct FormMediaViewer: View {
    enum Content {
        case image(String)   // asset-catalogue image name
        case video(URL)      // directly playable clip
    }

    let content: Content
    let exerciseName: String

    var body: some View {
        switch content {
        case .image(let name):
            ZoomableImageViewer(imageName: name, exerciseName: exerciseName)
        case .video(let url):
            FullScreenVideoViewer(url: url, exerciseName: exerciseName)
        }
    }
}

/// Pinch-to-zoom / drag-to-pan image viewer over a black backdrop. Double-tap
/// toggles a 2.5× zoom; a Reset control appears once zoomed. `scaledToFit`
/// keeps the whole illustration visible at 1× in any orientation, so important
/// form positions are never cropped until the user deliberately zooms in.
private struct ZoomableImageViewer: View {
    let imageName: String
    let exerciseName: String
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geo in
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnification(in: geo.size))
                    .simultaneousGesture(pan(in: geo.size))
                    .onTapGesture(count: 2) { toggleZoom() }
            }
            .accessibilityElement()
            .accessibilityLabel("Full screen form illustration for \(exerciseName)")
            .accessibilityHint("Pinch to zoom, drag to pan, double tap to reset")
        }
        .overlay(alignment: .topLeading) {
            if scale > minScale { controlButton("Reset zoom", systemImage: "arrow.counterclockwise") { resetZoom() } }
        }
        .overlay(alignment: .topTrailing) {
            controlButton("Close full screen viewer", systemImage: "xmark") { dismiss() }
        }
    }

    private func magnification(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, minScale), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= minScale { offset = .zero }
                clamp(in: size)
                lastOffset = offset
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > minScale else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                clamp(in: size)
                lastOffset = offset
            }
    }

    /// Limits panning to the overflow the current zoom produces, so the image
    /// cannot be dragged entirely off-screen.
    private func clamp(in size: CGSize) {
        let maxX = max(0, (size.width * scale - size.width) / 2)
        let maxY = max(0, (size.height * scale - size.height) / 2)
        offset.width = min(max(offset.width, -maxX), maxX)
        offset.height = min(max(offset.height, -maxY), maxY)
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if scale > minScale {
                scale = minScale; lastScale = minScale; offset = .zero; lastOffset = .zero
            } else {
                scale = 2.5; lastScale = 2.5
            }
        }
    }

    private func resetZoom() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            scale = minScale; lastScale = minScale; offset = .zero; lastOffset = .zero
        }
    }

    private func controlButton(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: Circle())
        }
        .padding()
        .accessibilityLabel(label)
    }
}

/// Full-screen, user-controllable playback of a demo clip (standard scrubber
/// and play/pause come from `VideoPlayer`). Unlike the muted inline loop, this
/// plays with sound and full transport controls.
private struct FullScreenVideoViewer: View {
    let url: URL
    let exerciseName: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()
                .accessibilityLabel("Form video demo for \(exerciseName)")
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: Circle())
            }
            .padding()
            .accessibilityLabel("Close full screen viewer")
        }
        .onAppear {
            if player == nil { player = AVPlayer(url: url) }
            player?.play()
        }
        .onDisappear { player?.pause() }
    }
}

#Preview {
    NavigationStack {
        ExerciseDetailView(exercise: ExerciseLibrary.all[0])
    }
}
