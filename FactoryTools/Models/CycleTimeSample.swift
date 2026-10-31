import Foundation
import SwiftData
import FactoryToolsCore

@Model
final class CycleTimeSample {
    @Attribute(.unique) var id: UUID
    var homeProfileID: UUID
    var totalSeconds: Int
    var quantity: Int
    var createdAt: Date

    var secondsPerUnit: Double? {
        CycleTimeCalculator.secondsPerUnit(totalSeconds: totalSeconds, quantity: quantity)
    }

    init(
        id: UUID = UUID(),
        homeProfileID: UUID,
        totalSeconds: Int,
        quantity: Int,
        createdAt: Date = .now
    ) {
        self.id = id
        self.homeProfileID = homeProfileID
        self.totalSeconds = totalSeconds
        self.quantity = quantity
        self.createdAt = createdAt
    }
}
