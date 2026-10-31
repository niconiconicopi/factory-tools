import Foundation
import SwiftData

@Model
final class HomeProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var usesDefaultName: Bool
    var sortOrder: Int
    var createdAt: Date

    init(id: UUID = UUID(), name: String, usesDefaultName: Bool = false, sortOrder: Int, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.usesDefaultName = usesDefaultName
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
