import Foundation

struct OEEHistoryPoint: Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let overall: Double
}

struct OEEHistorySummary: Equatable {
    let runCount: Int
    let latestOverall: Double
    let averageOverall: Double
    let bestOverall: Double
    let changeFromPrevious: Double?
}

enum OEEHistoryPeriod: String, CaseIterable, Identifiable {
    case days7
    case days30
    case days90
    case all

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .days7: "oee.period.days7"
        case .days30: "oee.period.days30"
        case .days90: "oee.period.days90"
        case .all: "oee.period.all"
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

enum OEEHistoryMath {
    static func points(
        _ points: [OEEHistoryPoint],
        within period: OEEHistoryPeriod,
        asOf date: Date,
        calendar: Calendar
    ) -> [OEEHistoryPoint] {
        let finitePoints = points.filter { $0.overall.isFinite }
        guard let days = period.dayCount,
              let window = HistoryDateWindow.trailingCalendarDays(days, endingAt: date, calendar: calendar) else {
            return finitePoints
        }
        return finitePoints.filter { window.contains($0.createdAt) }
    }

    static func summary(from points: [OEEHistoryPoint]) -> OEEHistorySummary? {
        var latest: OEEHistoryPoint?
        var previous: OEEHistoryPoint?
        var best = -Double.infinity
        var average = 0.0
        var count = 0
        for point in points where point.overall.isFinite {
            count += 1
            average += (point.overall - average) / Double(count)
            best = max(best, point.overall)

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

        return OEEHistorySummary(
            runCount: count,
            latestOverall: latest.overall,
            averageOverall: average,
            bestOverall: best,
            changeFromPrevious: previous.map { latest.overall - $0.overall }
        )
    }

    private static func isNewer(_ first: OEEHistoryPoint, than second: OEEHistoryPoint) -> Bool {
        if first.createdAt != second.createdAt { return first.createdAt > second.createdAt }
        return first.id.uuidString < second.id.uuidString
    }
}
