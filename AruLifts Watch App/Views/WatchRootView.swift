import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var connectivity = ConnectivityManager.shared
    @State private var showingOfflineStart = false

    var body: some View {
        NavigationStack {
            if active.isActive {
                WatchActiveView()
                    // SwiftUI also creates this view during a background wake.
                    // Clear the alert only when the person is actually looking
                    // at AruLifts, not merely because the session arrived.
                    .onAppear {
                        if scenePhase == .active {
                            WatchWorkoutNotifier.clear()
                        }
                    }
            } else {
                idle
            }
        }
        .task {
            if scenePhase == .active {
                await WatchWorkoutNotifier.requestAuthorizationIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if active.isActive {
                WatchWorkoutNotifier.clear()
            }
            Task {
                await WatchWorkoutNotifier.requestAuthorizationIfNeeded()
            }
        }
    }

    /// Idle leads with the phone-first flow: pick the workout on iPhone and the
    /// Watch starts tracking it. Starting here is the exception, kept for when
    /// the phone is dead or in a locker, so it sits behind a deliberate tap.
    private var idle: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 30))
                    .foregroundStyle(.orange)
                Text("Start on iPhone")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text("Open AruLifts on your iPhone and choose a workout. Tracking begins here automatically.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                if active.watchPlans.isEmpty {
                    Text("Your workouts will appear here after the iPhone sends them once.")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.tertiary)
                } else {
                    Button {
                        showingOfflineStart = true
                    } label: {
                        Label("Start without iPhone", systemImage: "iphone.slash")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .accessibilityHint("Starts a cached workout on Watch alone")
                }

                HStack(spacing: 6) {
                    Image(systemName: connectivity.isReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                    Text(connectivity.isReachable ? "iPhone connected" : "Plans saved on Watch")
                        .font(.caption2)
                }
                .foregroundStyle(connectivity.isReachable ? .green : .secondary)
            }
            .padding()
        }
        .sheet(isPresented: $showingOfflineStart) {
            WatchOfflineStartView()
        }
    }
}

/// The fallback path: cached plans the Watch can start on its own when the
/// iPhone is unavailable.
struct WatchOfflineStartView: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Text("Starting here skips the iPhone. Use it only when your phone isn't available.")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    let routines = active.watchPlans.filter(\.isRoutine)
                    let templates = active.watchPlans.filter { !$0.isRoutine }

                    if !routines.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Gym Session Routines")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            ForEach(routines) { plan in
                                Button {
                                    active.startCachedPlan(plan)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(plan.name)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Text("\(plan.phases.count) phases · \(plan.exercises.count) exercises")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)
                                .accessibilityHint("Starts this gym routine on your Watch")
                            }
                        }
                    }

                    if !templates.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Workout Templates")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            ForEach(templates) { plan in
                                Button {
                                    active.startCachedPlan(plan)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(plan.name)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Text("\(plan.exercises.count) exercises · Start")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                                .accessibilityHint("Starts this workout on your Watch")
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Start without iPhone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
