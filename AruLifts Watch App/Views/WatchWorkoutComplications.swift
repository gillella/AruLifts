import SwiftUI

#if os(watchOS)
import WidgetKit

struct WorkoutComplicationEntry: TimelineEntry {
    let date: Date
    let exerciseName: String
    let setProgressText: String
    let isResting: Bool
    let restTimerEndDate: Date?
}

struct WorkoutComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutComplicationEntry {
        WorkoutComplicationEntry(
            date: Date(),
            exerciseName: "Bench Press",
            setProgressText: "1/4",
            isResting: false,
            restTimerEndDate: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutComplicationEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutComplicationEntry>) -> Void) {
        let entry = WorkoutComplicationEntry(
            date: Date(),
            exerciseName: "AruLifts",
            setProgressText: "Active",
            isResting: false,
            restTimerEndDate: nil
        )
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

struct WatchWorkoutComplicationView: View {
    @Environment(\.widgetFamily) var family
    var entry: WorkoutComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCorner:
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.title2)
                .widgetLabel {
                    Text(entry.exerciseName)
                }

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.caption)
                    Text(entry.setProgressText)
                        .font(.system(size: 10, weight: .bold))
                }
            }

        case .accessoryInline:
            HStack(spacing: 4) {
                Image(systemName: "figure.strengthtraining.traditional")
                Text(entry.exerciseName)
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundColor(.blue)
                    Text("AruLifts")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                Text(entry.exerciseName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if entry.isResting, let endDate = entry.restTimerEndDate {
                    Text(endDate, style: .timer)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.orange)
                } else {
                    Text(entry.setProgressText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

        default:
            Image(systemName: "figure.strengthtraining.traditional")
        }
    }
}

struct WatchWorkoutComplicationWidget: Widget {
    let kind: String = "WatchWorkoutComplicationWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutComplicationProvider()) { entry in
            WatchWorkoutComplicationView(entry: entry)
        }
        .configurationDisplayName("AruLifts Workout")
        .description("Displays current workout status and rest timer on your watch face.")
        .supportedFamilies([
            .accessoryCorner,
            .accessoryCircular,
            .accessoryInline,
            .accessoryRectangular
        ])
    }
}
#endif
