import Foundation

enum HistoryDateWindow {
    static func trailingCalendarDays(
        _ dayCount: Int,
        endingAt date: Date,
        calendar: Calendar
    ) -> ClosedRange<Date>? {
        guard dayCount > 0,
              let currentDay = calendar.dateInterval(of: .day, for: date),
              let start = calendar.date(byAdding: .day, value: 1 - dayCount, to: currentDay.start) else {
            return nil
        }
        return start...date
    }
}
