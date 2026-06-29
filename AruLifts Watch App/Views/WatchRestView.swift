import SwiftUI

/// Full-screen rest countdown on the watch with a progress ring and quick
/// actions. A haptic fires when the timer completes (handled by the manager).
struct WatchRestView: View {
    @ObservedObject var timer: RestTimerManager

    var body: some View {
        VStack(spacing: 10) {
            Text("REST")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: timer.progress)
                Text(timer.formattedRemaining)
                    .font(.title.monospacedDigit().bold())
            }
            .frame(width: 110, height: 110)

            HStack(spacing: 8) {
                Button { timer.add(seconds: 30) } label: {
                    Text("+30s").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button { timer.skip() } label: {
                    Text("Skip").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(.horizontal, 6)
    }
}
