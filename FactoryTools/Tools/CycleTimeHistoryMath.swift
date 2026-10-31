import Foundation

struct CycleTimeHistoryPoint: Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let secondsPerUnit: Double
}

struct CycleTimeHistorySummary: Equatable {
    let sampleCount: Int
    let latestSecondsPerUnit: Double
    let averageSecondsPerUnit: Double
    let bestSecondsPerUnit: Double
    let changeFromPrevious: Double?
}

enum CycleTimeHistoryPeriod: String, CaseIterable, Identifiable {
    case days7
    case days30
    case days90
    case all

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .days7: "cycleTime.period.days7"
        case .days30: "cycleTime.period.days30"
        case .days90: "cycleTime.period.days90"
        case .all: "cycleTime.period.all"
        }
    }

    fileprivate var dayCount: Int? {
        switch self {
        case .days7: 7
        case .days30: 30
        case .days90: 90
        case .all: nil
        }
    }
}

enum CycleTimeHistoryMath {
    static func points(
        _ points: [CycleTimeHistoryPoint],
        within period: CycleTimeHistoryPeriod,
        asOf date: Date,
        calendar: Calendar
    ) -> [CycleTimeHistoryPoint] {
        let validPoints = points.filter { $0.secondsPerUnit.isFinite && $0.secondsPerUnit > 0 }
        guard let days = period.dayCount,
              let window = HistoryDateWindow.trailingCalendarDays(days, endingAt: date, calendar: calendar) else {
            return validPoints
        }
        return validPoints.filter { window.contains($0.createdAt) }
    }

    static func summary(from points: [CycleTimeHistoryPoint]) -> CycleTimeHistorySummary? {
        var latest: CycleTimeHistoryPoint?
        var previous: CycleTimeHistoryPoint?
        var best = Double.infinity
        var average = 0.0
        var count = 0
        for point in points where point.secondsPerUnit.isFinite && point.secondsPerUnit > 0 {
            count += 1
            average += (point.secondsPerUnit - average) / Double(count)
            best = min(best, point.secondsPerUnit)

            if let latestPoint = latest {
                if isNewer(point, than: latestPoint) {
                    previous = latestPoint
                    latest = point
                } else if let previousPoint = previous {
                    if isNewer(point, than: previousPoint) { previous = point }
                } else {
                    previous = point
                }
            } else {
                latest = point
            }
        }
        guard let latest else { return nil }

        return CycleTimeHistorySummary(
            sampleCount: count,
            latestSecondsPerUnit: latest.secondsPerUnit,
            averageSecondsPerUnit: average,
            bestSecondsPerUnit: best,
            changeFromPrevious: previous.map { latest.secondsPerUnit - $0.secondsPerUnit }
        )
    }

    private static func isNewer(_ first: CycleTimeHistoryPoint, than second: CycleTimeHistoryPoint) -> Bool {
        if first.createdAt != second.createdAt { return first.createdAt > second.createdAt }
        return first.id.uuidString < second.id.uuidString
    }
}
