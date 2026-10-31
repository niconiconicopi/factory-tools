import FactoryToolsCore
import Foundation
import SwiftData

@Model
final class ToolCard {
    @Attribute(.unique) var id: UUID
    var homeProfileID: UUID
    var toolID: String
    var sizeRawValue: String
    var sortOrder: Int
    var showsOnWatch: Bool
    var productionSessionID: UUID?

    var size: ToolCardSize {
        get { ToolCardSize(rawValue: sizeRawValue) ?? .medium }
        set { sizeRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        homeProfileID: UUID,
        toolID: ToolID,
        size: ToolCardSize = .medium,
        sortOrder: Int,
        showsOnWatch: Bool = true,
        productionSessionID: UUID? = nil
    ) {
        self.id = id
        self.homeProfileID = homeProfileID
        self.toolID = toolID.rawValue
        self.sizeRawValue = size.rawValue
        self.sortOrder = sortOrder
        self.showsOnWatch = showsOnWatch
        self.productionSessionID = productionSessionID
    }
}
