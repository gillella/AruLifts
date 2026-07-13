import SwiftUI

/// Month calendar marking days with completed workouts. Tap a marked day to
/// open that session (or pick one when there are several).
struct WorkoutCalendarView: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var monthAnchor = Date()

    private var calendar: Calendar { Calendar.current }

    /// Finished sessions grouped by start-of-day.
    private var sessionsByDay: [Date: [WorkoutSession]] {
        Dictionary(grouping: store.history.filter { $0.isFinished }) {
            calendar.startOfDay(for: $0.startedAt)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            monthHeader
            weekdayHeader
            dayGrid
            Spacer(minLength: 0)
        }
        .padding()
    }

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(monthAnchor.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .disabled(calendar.isDate(monthAnchor, equalTo: Date(), toGranularity: .month))
        }
        .padding(.horizontal, 4)
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(calendar.veryShortWeekdaySymbols.indices, id: \.self) { i in
                // Rotate symbols so the row starts on the locale's first weekday.
                let symbol = calendar.veryShortWeekdaySymbols[(i + calendar.firstWeekday - 1) % 7]
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        let days = monthDays()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(days.indices, id: \.self) { i in
                if let day = days[i] {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let sessions = sessionsByDay[calendar.startOfDay(for: day)] ?? []
        let isToday = calendar.isDateInToday(day)
        let label = VStack(spacing: 3) {
            Text("\(calendar.component(.day, from: day))")
                .font(.subheadline.monospacedDigit())
                .fontWeight(isToday ? .bold : .regular)
            Circle()
                .fill(sessions.isEmpty ? Color.clear : Color.orange)
                .frame(width: 6, height: 6)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isToday ? Color.orange.opacity(0.12) : Color.clear)
        )

        if sessions.count == 1 {
            NavigationLink { SessionDetailView(session: sessions[0]) } label: { label }
                .buttonStyle(.plain)
        } else if sessions.count > 1 {
            NavigationLink { DaySessionsList(day: day, sessions: sessions) } label: { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    /// Days of the anchor month padded with nils to align the first weekday.
    private func monthDays() -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: monthAnchor),
              let dayCount = calendar.range(of: .day, in: .month, for: monthAnchor)?.count
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days: [Date?] = (0..<dayCount).map {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
        return Array(repeating: nil, count: leading) + days
    }

    private func shiftMonth(_ delta: Int) {
        if let shifted = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = shifted
        }
    }
}

/// Sessions for one calendar day (when there's more than one).
struct DaySessionsList: View {
    @EnvironmentObject private var store: WorkoutStore
    let day: Date
    let sessions: [WorkoutSession]

    var body: some View {
        List(sessions) { session in
            NavigationLink {
                SessionDetailView(session: session)
            } label: {
                HistoryRow(session: session, units: store.settings.units)
            }
        }
        .navigationTitle(day.formatted(date: .abbreviated, time: .omitted))
    }
}
