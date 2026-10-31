import FactoryToolsCore
import Foundation
import SwiftData

@Model
final class CountEvent {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var delta: Int
    var sequence: Int
    var occurredAt: Date
    var reversesEventID: UUID?
    var kindRawValue: String?
    var payloadSignature: String?

    var kind: CounterEventKind? {
        get { kindRawValue.flatMap(CounterEventKind.init(rawValue:)) }
        set { kindRawValue = newValue?.rawValue }
    }

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        delta: Int,
        sequence: Int = 0,
        occurredAt: Date = .now,
        reversesEventID: UUID? = nil,
        kind: CounterEventKind? = nil,
        payloadSignature: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.delta = delta
        self.sequence = sequence
        self.occurredAt = occurredAt
        self.reversesEventID = reversesEventID
        self.kindRawValue = kind?.rawValue
        self.payloadSignature = payloadSignature
    }
}
