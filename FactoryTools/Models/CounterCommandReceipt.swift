import Foundation
import SwiftData

@Model
final class CounterCommandReceipt {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var processedAt: Date
    var payloadSignature: String?

    init(id: UUID, sessionID: UUID, processedAt: Date = .now, payloadSignature: String? = nil) {
        self.id = id
        self.sessionID = sessionID
        self.processedAt = processedAt
        self.payloadSignature = payloadSignature
    }
}
