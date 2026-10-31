import Foundation

struct OEECSVRecord: Sendable {
    let id: UUID
    let homeProfileID: UUID
    let plannedProductionMinutes: Int
    let downtimeMinutes: Int
    let idealCycleTimeSeconds: Int
    let goodUnits: Int
    let defectiveUnits: Int
    let createdAt: Date
    let availability: Double?
    let performance: Double?
    let quality: Double?
    let overall: Double?

    init(_ run: OEERun) {
        let calculation = run.calculation
        id = run.id
        homeProfileID = run.homeProfileID
        plannedProductionMinutes = run.plannedProductionMinutes
        downtimeMinutes = run.downtimeMinutes
        idealCycleTimeSeconds = run.idealCycleTimeSeconds
        goodUnits = run.goodUnits
        defectiveUnits = run.defectiveUnits
        createdAt = run.createdAt
        availability = calculation?.availability
        performance = calculation?.performance
        quality = calculation?.quality
        overall = calculation?.overall
    }
}

enum OEEHistoryCSV {
    static func make(homeID: UUID, runs: [OEERun]) -> String {
        make(homeID: homeID, records: runs.map(OEECSVRecord.init))
    }

    static func make(homeID: UUID, records: [OEECSVRecord]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let header = "home_id,run_id,recorded_at_utc,planned_production_minutes,downtime_minutes,ideal_cycle_time_seconds,good_units,defective_units,total_units,availability,performance,quality,oee"
        let rows = records
            .filter { $0.homeProfileID == homeID }
            .sorted { first, second in
                if first.createdAt != second.createdAt { return first.createdAt < second.createdAt }
                return first.id.uuidString < second.id.uuidString
            }
            .compactMap { run -> String? in
                guard let availability = run.availability,
                      let performance = run.performance,
                      let quality = run.quality,
                      let overall = run.overall else { return nil }
                let (totalUnits, overflow) = run.goodUnits.addingReportingOverflow(run.defectiveUnits)
                guard !overflow else { return nil }
                return [
                    homeID.uuidString,
                    run.id.uuidString,
                    formatter.string(from: run.createdAt),
                    String(run.plannedProductionMinutes),
                    String(run.downtimeMinutes),
                    String(run.idealCycleTimeSeconds),
                    String(run.goodUnits),
                    String(run.defectiveUnits),
                    String(totalUnits),
                    String(availability),
                    String(performance),
                    String(quality),
                    String(overall)
                ].joined(separator: ",")
            }
        return ([header] + rows).joined(separator: "\r\n") + "\r\n"
    }
}
