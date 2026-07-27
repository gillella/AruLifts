import SwiftUI

/// iOS interactive transition sheet displayed when a timed phase timer finishes.
struct PhaseTransitionSheet: View {
    @EnvironmentObject private var active: ActiveWorkoutManager
    @Environment(\.dismiss) private var dismiss

    private var currentPhase: GymSessionLogPhase? {
        active.session?.currentPhase
    }

    private var nextPhase: GymSessionLogPhase? {
        guard let session = active.session,
              session.phases.indices.contains(session.currentPhaseIndex + 1) else { return nil }
        return session.phases[session.currentPhaseIndex + 1]
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 90, height: 90)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 6) {
                Text("\(currentPhase?.name ?? "Phase") Complete!")
                    .font(.title2.bold())
                Text("Great work on completing this phase!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let nextPhase {
                VStack(spacing: 8) {
                    Text("NEXT PHASE")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Image(systemName: nextPhase.phaseType.iconSymbol)
                            .font(.title2)
                            .foregroundStyle(nextPhase.phaseType.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nextPhase.name)
                                .font(.headline)
                            if !nextPhase.exerciseNames.isEmpty {
                                Text(nextPhase.exerciseNames.joined(separator: " • "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    active.startNextPhaseFromModal()
                    dismiss()
                } label: {
                    Label("Start Next Phase", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    active.extendPhaseTimerFiveMinutes()
                    dismiss()
                } label: {
                    Label("Add +5 Minutes", systemImage: "goforward.5")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                Button {
                    active.skipPhaseFromModal()
                    dismiss()
                } label: {
                    Text("Skip Phase")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .padding()
    }
}
