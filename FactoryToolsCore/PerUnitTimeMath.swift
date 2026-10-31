import Foundation

public enum PerUnitTimeMath {
    public static func secondsPerUnit(numeratorSeconds: Int, denominatorUnits: Int) -> Double? {
        guard numeratorSeconds > 0, denominatorUnits > 0 else { return nil }
        return Double(numeratorSeconds) / Double(denominatorUnits)
    }
}

public enum CycleTimeCalculator {
    public static func secondsPerUnit(totalSeconds: Int, quantity: Int) -> Double? {
        PerUnitTimeMath.secondsPerUnit(numeratorSeconds: totalSeconds, denominatorUnits: quantity)
    }
}

public enum CycleTimeMeasurement {
    public static func roundedWholeSeconds(from elapsedSeconds: Double) -> Int? {
        guard elapsedSeconds.isFinite, elapsedSeconds > 0, elapsedSeconds < Double(Int.max) else { return nil }
        let roundedSeconds = Int(elapsedSeconds.rounded())
        return roundedSeconds > 0 ? roundedSeconds : nil
    }
}

public enum TaktTimeCalculator {
    public static func secondsPerUnit(netAvailableSeconds: Int, customerDemand: Int) -> Double? {
        PerUnitTimeMath.secondsPerUnit(
            numeratorSeconds: netAvailableSeconds,
            denominatorUnits: customerDemand
        )
    }
}

public struct OEECalculation: Equatable {
    public let availability: Double
    public let performance: Double
    public let quality: Double
    public let overall: Double

    public init(availability: Double, performance: Double, quality: Double, overall: Double) {
        self.availability = availability
        self.performance = performance
        self.quality = quality
        self.overall = overall
    }
}

public enum OEECalculator {
    public static func calculate(
        plannedProductionMinutes: Int,
        downtimeMinutes: Int,
        idealCycleTimeSeconds: Int,
        goodUnits: Int,
        defectiveUnits: Int
    ) -> OEECalculation? {
        guard plannedProductionMinutes > 0,
              downtimeMinutes >= 0,
              downtimeMinutes < plannedProductionMinutes,
              idealCycleTimeSeconds > 0,
              goodUnits >= 0,
              defectiveUnits >= 0 else { return nil }
        let (totalUnits, overflow) = goodUnits.addingReportingOverflow(defectiveUnits)
        guard !overflow, totalUnits > 0 else { return nil }

        let operatingMinutes = plannedProductionMinutes - downtimeMinutes
        let availability = Double(operatingMinutes) / Double(plannedProductionMinutes)
        let operatingSeconds = Double(operatingMinutes) * 60
        let performance = Double(idealCycleTimeSeconds) * Double(totalUnits) / operatingSeconds
        let quality = Double(goodUnits) / Double(totalUnits)
        let overall = availability * performance * quality
        guard availability.isFinite, performance.isFinite, quality.isFinite, overall.isFinite else { return nil }

        return OEECalculation(
            availability: availability,
            performance: performance,
            quality: quality,
            overall: overall
        )
    }
}
