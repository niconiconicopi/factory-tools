import Foundation
import SwiftData
import FactoryToolsCore

@Model
final class OEERun {
    @Attribute(.unique) var id: UUID
    var homeProfileID: UUID
    var plannedProductionMinutes: Int
    var downtimeMinutes: Int
    var idealCycleTimeSeconds: Int
    var goodUnits: Int
    var defectiveUnits: Int
    var createdAt: Date

    var calculation: OEECalculation? {
        OEECalculator.calculate(
            plannedProductionMinutes: plannedProductionMinutes,
            downtimeMinutes: downtimeMinutes,
            idealCycleTimeSeconds: idealCycleTimeSeconds,
            goodUnits: goodUnits,
            defectiveUnits: defectiveUnits
        )
    }

    init(
        id: UUID = UUID(),
        homeProfileID: UUID,
        plannedProductionMinutes: Int,
        downtimeMinutes: Int,
        idealCycleTimeSeconds: Int,
        goodUnits: Int,
        defectiveUnits: Int,
        createdAt: Date = .now
    ) {
        self.id = id
        self.homeProfileID = homeProfileID
        self.plannedProductionMinutes = plannedProductionMinutes
        self.downtimeMinutes = downtimeMinutes
        self.idealCycleTimeSeconds = idealCycleTimeSeconds
        self.goodUnits = goodUnits
        self.defectiveUnits = defectiveUnits
        self.createdAt = createdAt
    }
}
