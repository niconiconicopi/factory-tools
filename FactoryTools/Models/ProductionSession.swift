import Foundation
import SwiftData

@Model
final class ProductionSession {
    @Attribute(.unique) var id: UUID
    var homeProfileID: UUID?
    var toolID: String?
    var name: String
    var currentCount: Int
    var targetCount: Int
    var nextEventSequence: Int
    var startedAt: Date

    init(
        id: UUID = UUID(),
        homeProfileID: UUID? = nil,
        toolID: String? = nil,
        name: String,
        currentCount: Int = 0,
        targetCount: Int = 600,
        nextEventSequence: Int = 0,
        startedAt: Date = .now
    ) {
        self.id = id
        self.homeProfileID = homeProfileID
        self.toolID = toolID
        self.name = name
        self.currentCount = max(0, currentCount)
        self.targetCount = max(0, targetCount)
        self.nextEventSequence = max(0, nextEventSequence)
        self.startedAt = startedAt
    }
}
