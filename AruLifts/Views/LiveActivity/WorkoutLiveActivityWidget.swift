import SwiftUI

#if os(iOS)
import ActivityKit
import WidgetKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundColor(.blue)
                    Text(context.attributes.workoutTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    if context.state.isResting, let endDate = context.state.restTimerEndDate {
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                                .foregroundColor(.orange)
                            Text(endDate, style: .timer)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                    } else {
                        Text(context.state.workoutStartDate, style: .timer)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.currentExerciseName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text("Set \(context.state.currentSetIndex) of \(context.state.totalSets)  •  \(context.state.weightText) × \(context.state.repsText)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if context.state.isResting {
                        Button(intent: AddRestTimeIntent()) {
                            Text("+30s")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(intent: SkipRestIntent()) {
                            Text("Skip")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(intent: CompleteSetIntent()) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Complete")
                            }
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .activityBackgroundTint(Color(uiColor: .systemBackground))
            .activitySystemActionForegroundColor(Color.blue)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text(context.state.currentExerciseName)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .lineLimit(1)
                            Text("Set \(context.state.currentSetIndex) of \(context.state.totalSets)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        Text("\(context.state.weightText) × \(context.state.repsText)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        if context.state.isResting, let endDate = context.state.restTimerEndDate {
                            Text(endDate, style: .timer)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.orange)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if context.state.isResting {
                            Button(intent: AddRestTimeIntent()) {
                                Label("+30s", systemImage: "plus.circle")
                            }
                            .font(.caption)
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)

                            Spacer()

                            Button(intent: SkipRestIntent()) {
                                Label("Skip Rest", systemImage: "forward.fill")
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        } else {
                            Button(intent: CompleteSetIntent()) {
                                Label("Log Set", systemImage: "checkmark.circle.fill")
                            }
                            .font(.caption)
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundColor(.blue)
            } compactTrailing: {
                if context.state.isResting, let endDate = context.state.restTimerEndDate {
                    Text(endDate, style: .timer)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.orange)
                        .frame(width: 40)
                } else {
                    Text("S\(context.state.currentSetIndex)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
            } minimal: {
                if context.state.isResting, let endDate = context.state.restTimerEndDate {
                    Text(endDate, style: .timer)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundColor(.blue)
                }
            }
        }
    }
}
#endif
