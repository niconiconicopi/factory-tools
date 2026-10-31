import Foundation
import SwiftData
import FactoryToolsCore

@MainActor
struct CycleTimeSampleService {
    let modelContext: ModelContext

    @discardableResult
    func save(
        totalSeconds: Int,
        quantity: Int,
        for homeID: UUID,
        createdAt: Date = .now,
        id: UUID = UUID()
    ) throws -> CycleTimeSample {
        guard CycleTimeCalculator.secondsPerUnit(totalSeconds: totalSeconds, quantity: quantity) != nil else {
            throw CycleTimeSampleServiceError.invalidInput
        }
        guard PersistedTimestamp.isSupported(createdAt) else {
            throw CycleTimeSampleServiceError.invalidTimestamp
        }

        var homeDescriptor = FetchDescriptor<HomeProfile>()
        homeDescriptor.includePendingChanges = true
        let homes = try modelContext.fetch(homeDescriptor)
        guard homes.contains(where: { $0.id == homeID }) else {
            throw CycleTimeSampleServiceError.homeNotFound
        }

        let sample = CycleTimeSample(
            id: id,
            homeProfileID: homeID,
            totalSeconds: totalSeconds,
            quantity: quantity,
            createdAt: createdAt
        )
        modelContext.insert(sample)
        do {
            try modelContext.save()
            return sample
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func delete(_ sample: CycleTimeSample, from homeID: UUID) throws {
        guard sample.homeProfileID == homeID else {
            throw CycleTimeSampleServiceError.wrongHome
        }
        modelContext.delete(sample)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            modelContext.insert(sample)
            throw error
        }
    }
}

enum CycleTimeSampleServiceError: Error, Equatable {
    case invalidInput
    case homeNotFound
    case wrongHome
    case invalidTimestamp
}
