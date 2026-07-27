import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var connectivity = ConnectivityManager.shared

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

    private var idle: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                Text("AruLifts")
                    .font(.headline)

                if active.watchPlans.isEmpty {
                    Text("Your workouts will appear here after the iPhone sends them once.")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Ready on Watch")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)

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

                HStack(spacing: 6) {
                    Image(systemName: connectivity.isReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                    Text(connectivity.isReachable ? "iPhone connected" : "Plans saved on Watch")
                        .font(.caption2)
                }
                .foregroundStyle(connectivity.isReachable ? .green : .secondary)
            }
            .padding()
        }
    }
}
