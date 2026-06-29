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
        VStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 38))
                .foregroundStyle(.orange)
            Text("AruLifts")
                .font(.headline)
            Text("Start a workout on your iPhone — it'll appear here.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: connectivity.isReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                Text(connectivity.isReachable ? "Connected" : "Open the app on iPhone")
                    .font(.caption2)
            }
            .foregroundStyle(connectivity.isReachable ? .green : .secondary)
            .padding(.top, 4)
        }
        .padding()
    }
}
