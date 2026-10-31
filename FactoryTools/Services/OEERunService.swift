import Foundation
import SwiftData
import FactoryToolsCore

@MainActor
struct OEERunService {
    let modelContext: ModelContext

    @discardableResult
    func save(
        plannedProductionMinutes: Int,
        downtimeMinutes: Int,
        idealCycleTimeSeconds: Int,
        goodUnits: Int,
        defectiveUnits: Int,
        for homeID: UUID,
        createdAt: Date = .now,
        isPro: Bool = false
    ) throws -> OEERun {
        guard FeatureAccessRegistry.allows(.oeeCalculator, isPro: isPro) else {
            throw OEERunServiceError.proRequired
        }
        guard OEECalculator.calculate(
            plannedProductionMinutes: plannedProductionMinutes,
            downtimeMinutes: downtimeMinutes,
            idealCycleTimeSeconds: idealCycleTimeSeconds,
            goodUnits: goodUnits,
            defectiveUnits: defectiveUnits
        ) != nil else {
            throw OEERunServiceError.invalidInput
        }
        guard PersistedTimestamp.isSupported(createdAt) else {
            throw OEERunServiceError.invalidTimestamp
        }

        var homeDescriptor = FetchDescriptor<HomeProfile>()
        homeDescriptor.includePendingChanges = true
        guard try modelContext.fetch(homeDescriptor).contains(where: { $0.id == homeID }) else {
            throw OEERunServiceError.homeNotFound
        }

        let run = OEERun(
            homeProfileID: homeID,
            plannedProductionMinutes: plannedProductionMinutes,
            downtimeMinutes: downtimeMinutes,
            idealCycleTimeSeconds: idealCycleTimeSeconds,
            goodUnits: goodUnits,
            defectiveUnits: defectiveUnits,
            createdAt: createdAt
        )
        modelContext.insert(run)
        do {
            try modelContext.save()
            return run
        } catch {
            modelContext.rollback()
            modelContext.delete(run)
            throw error
        }
    }

    func delete(_ run: OEERun, from homeID: UUID) throws {
        guard run.homeProfileID == homeID else {
            throw OEERunServiceError.wrongHome
        }
        modelContext.delete(run)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            modelContext.insert(run)
            throw error
        }
    }
}

enum OEERunServiceError: Error, Equatable {
    case proRequired
    case invalidInput
    case homeNotFound
    case wrongHome
    case invalidTimestamp
}
