import Foundation

struct CycleTimeCSVRecord: Sendable {
    let id: UUID
    let homeProfileID: UUID
    let totalSeconds: Int
    let quantity: Int
    let createdAt: Date
    let secondsPerUnit: Double?

    init(_ sample: CycleTimeSample) {
        id = sample.id
        homeProfileID = sample.homeProfileID
        totalSeconds = sample.totalSeconds
        quantity = sample.quantity
        createdAt = sample.createdAt
        secondsPerUnit = sample.secondsPerUnit
    }
}

enum CycleTimeHistoryCSV {
    static func make(homeID: UUID, samples: [CycleTimeSample]) -> String {
        make(homeID: homeID, records: samples.map(CycleTimeCSVRecord.init))
    }

    static func make(homeID: UUID, records: [CycleTimeCSVRecord]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let header = "home_id,sample_id,recorded_at_utc,total_seconds,quantity,seconds_per_unit"
        let rows = records
            .filter { $0.homeProfileID == homeID }
            .sorted { first, second in
                if first.createdAt != second.createdAt { return first.createdAt < second.createdAt }
                return first.id.uuidString < second.id.uuidString
            }
            .compactMap { sample -> String? in
                guard let secondsPerUnit = sample.secondsPerUnit else { return nil }
                return [
                    homeID.uuidString,
                    sample.id.uuidString,
                    formatter.string(from: sample.createdAt),
                    String(sample.totalSeconds),
                    String(sample.quantity),
                    String(secondsPerUnit)
                ].joined(separator: ",")
            }
        return ([header] + rows).joined(separator: "\r\n") + "\r\n"
    }
}
