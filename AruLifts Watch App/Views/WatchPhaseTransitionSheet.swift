import SwiftUI

/// Watch interactive transition sheet displayed when a timed phase timer finishes (reaches 0:00).
struct WatchPhaseTransitionSheet: View {
    @EnvironmentObject private var active: ActiveWorkoutManager

    private var currentPhase: GymSessionLogPhase? {
        active.session?.currentPhase
    }

    private var nextPhase: GymSessionLogPhase? {
        guard let session = active.session,
              session.phases.indices.contains(session.currentPhaseIndex + 1) else { return nil }
        return session.phases[session.currentPhaseIndex + 1]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)

                Text("\(currentPhase?.name ?? "Phase") Complete!")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if let nextPhase {
                    VStack(spacing: 2) {
                        Text("Next Up:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Image(systemName: nextPhase.phaseType.iconSymbol)
                                .foregroundStyle(nextPhase.phaseType.color)
                            Text(nextPhase.name)
                                .font(.caption.bold())
                                .lineLimit(1)
                        }
                    }
                    .padding(6)
                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }

                VStack(spacing: 6) {
                    Button {
                        active.startNextPhaseFromModal()
                    } label: {
                        Label("Start Next Phase", systemImage: "play.fill")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button {
                        active.extendPhaseTimerFiveMinutes()
                    } label: {
                        Label("+5 Minutes", systemImage: "goforward.5")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)

                    Button {
                        active.skipPhaseFromModal()
                    } label: {
                        Label("Skip Phase", systemImage: "forward.fill")
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(6)
        }
    }
}
