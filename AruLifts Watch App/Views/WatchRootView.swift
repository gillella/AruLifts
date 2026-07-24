import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    @ObservedObject private var connectivity = ConnectivityManager.shared

    var body: some View {
        NavigationStack {
            if active.isActive {
                WatchActiveView()
            } else {
                idle
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

                    ForEach(active.watchPlans) { plan in
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
