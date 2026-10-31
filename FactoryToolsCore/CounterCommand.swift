import Foundation

public enum PersistedTimestamp {
    public static func isSupported(_ date: Date) -> Bool {
        let timestamp = date.timeIntervalSince1970
        // Keep persisted dates inside the four-digit year range used by ISO 8601 exports.
        return timestamp.isFinite
            && timestamp >= -62_135_596_800
            && timestamp < 253_402_300_800
    }
}

public enum CounterEventKind: String, CaseIterable, Identifiable {
    case increment
    case decrement
    case quickAdd
    case reset
    case undo

    public var id: String { rawValue }

    public var titleKey: String {
        "counter.history.kind.\(rawValue)"
    }
}

public enum CounterCommandOperation: Codable, Equatable {
    case increment
    case decrement
    case quickAdd(Int)
    case reset
    case undo(eventID: UUID)
    case setTarget(Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case amount
        case eventID
    }

    private enum Kind: String, Codable {
        case increment = "increment"
        case decrement = "decrement"
        case quickAdd = "quickAdd"
        case reset = "reset"
        case undo = "undo"
        case setTarget = "setTarget"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .increment:
            self = .increment
        case .decrement:
            self = .decrement
        case .quickAdd:
            self = .quickAdd(try values.decode(Int.self, forKey: .amount))
        case .reset:
            self = .reset
        case .undo:
            self = .undo(eventID: try values.decode(UUID.self, forKey: .eventID))
        case .setTarget:
            self = .setTarget(try values.decode(Int.self, forKey: .amount))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .increment:
            try values.encode(Kind.increment, forKey: .kind)
        case .decrement:
            try values.encode(Kind.decrement, forKey: .kind)
        case .quickAdd(let amount):
            try values.encode(Kind.quickAdd, forKey: .kind)
            try values.encode(amount, forKey: .amount)
        case .reset:
            try values.encode(Kind.reset, forKey: .kind)
        case .undo(let eventID):
            try values.encode(Kind.undo, forKey: .kind)
            try values.encode(eventID, forKey: .eventID)
        case .setTarget(let target):
            try values.encode(Kind.setTarget, forKey: .kind)
            try values.encode(target, forKey: .amount)
        }
    }
}

public struct CounterCommand: Codable, Equatable, Identifiable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: UUID
    public let sessionID: UUID
    public let operation: CounterCommandOperation
    public let createdAt: Date

    public var payloadSignature: String {
        let operationValue: String
        switch operation {
        case .increment:
            operationValue = "increment"
        case .decrement:
            operationValue = "decrement"
        case .quickAdd(let amount):
            operationValue = "quickAdd:\(amount)"
        case .reset:
            operationValue = "reset"
        case .undo(let eventID):
            operationValue = "undo:\(eventID.uuidString.lowercased())"
        case .setTarget(let target):
            operationValue = "setTarget:\(target)"
        }
        let timestampBits = String(createdAt.timeIntervalSince1970.bitPattern, radix: 16)
        return "schema=\(schemaVersion)|operation=\(operationValue)|date=\(timestampBits)"
    }

    public static func isWellFormedPayloadSignature(_ signature: String) -> Bool {
        guard signature.count <= 512 else { return false }
        let components = signature.split(separator: "|", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0].hasPrefix("schema="),
              components[1].hasPrefix("operation="),
              components[2].hasPrefix("date=") else {
            return false
        }

        let schemaValue = String(components[0].dropFirst("schema=".count))
        guard let schema = Int(schemaValue), schema > 0, String(schema) == schemaValue else {
            return false
        }
        let operationValue = String(components[1].dropFirst("operation=".count))
        guard !operationValue.isEmpty else { return false }
        if operationValue.hasPrefix("quickAdd:") {
            let amountValue = String(operationValue.dropFirst("quickAdd:".count))
            guard let amount = Int(amountValue), String(amount) == amountValue else { return false }
        } else if operationValue.hasPrefix("undo:") {
            let eventIDValue = String(operationValue.dropFirst("undo:".count))
            guard let eventID = UUID(uuidString: eventIDValue),
                  eventID.uuidString.lowercased() == eventIDValue else { return false }
        } else if operationValue.hasPrefix("setTarget:") {
            let targetValue = String(operationValue.dropFirst("setTarget:".count))
            guard let target = Int(targetValue), target >= 0, String(target) == targetValue else { return false }
        } else if !["increment", "decrement", "reset"].contains(operationValue) {
            // Unknown future operation names remain importable with this stable identifier alphabet.
            guard operationValue.allSatisfy({ character in
                character.unicodeScalars.allSatisfy({ $0.isASCII })
                    && (character.isLetter || character.isNumber || "._:-".contains(character))
            }) else { return false }
        }

        let dateValue = String(components[2].dropFirst("date=".count))
        guard !dateValue.isEmpty,
              let bits = UInt64(dateValue, radix: 16),
              String(bits, radix: 16) == dateValue else {
            return false
        }
        return PersistedTimestamp.isSupported(Date(timeIntervalSince1970: Double(bitPattern: bits)))
    }

    public static func payloadSignature(
        _ signature: String,
        matches eventKindRawValue: String?,
        delta: Int,
        reversesEventID: UUID?,
        occurredAt: Date
    ) -> Bool {
        guard isWellFormedPayloadSignature(signature) else { return false }
        let components = signature.split(separator: "|", omittingEmptySubsequences: false)
        let operationValue = String(components[1].dropFirst("operation=".count))
        let dateBitsValue = String(components[2].dropFirst("date=".count))
        guard let dateBits = UInt64(dateBitsValue, radix: 16),
              occurredAt.timeIntervalSince1970.bitPattern == dateBits else {
            return false
        }

        switch operationValue {
        case "increment":
            return eventKindRawValue == CounterEventKind.increment.rawValue
                && delta == 1
                && reversesEventID == nil
        case "decrement":
            return eventKindRawValue == CounterEventKind.decrement.rawValue
                && delta == -1
                && reversesEventID == nil
        case "reset":
            return eventKindRawValue == CounterEventKind.reset.rawValue
                && delta < 0
                && reversesEventID == nil
        case let value where value.hasPrefix("setTarget:"):
            return false
        default:
            if operationValue.hasPrefix("quickAdd:"),
               let amount = Int(String(operationValue.dropFirst("quickAdd:".count))) {
                return eventKindRawValue == CounterEventKind.quickAdd.rawValue
                    && delta > 0
                    && delta <= amount
                    && reversesEventID == nil
            }
            if operationValue.hasPrefix("undo:"),
               let eventID = UUID(uuidString: String(operationValue.dropFirst("undo:".count))) {
                return eventKindRawValue == CounterEventKind.undo.rawValue
                    && reversesEventID == eventID
            }
            // Keep unknown future operation identifiers portable without imposing current event semantics.
            return true
        }
    }

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        operation: CounterCommandOperation,
        createdAt: Date = .now
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.sessionID = sessionID
        self.operation = operation
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, sessionID, operation, createdAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard decodedVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: values,
                debugDescription: "Unsupported counter-command schema version."
            )
        }
        schemaVersion = decodedVersion
        id = try values.decode(UUID.self, forKey: .id)
        sessionID = try values.decode(UUID.self, forKey: .sessionID)
        operation = try values.decode(CounterCommandOperation.self, forKey: .operation)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(sessionID, forKey: .sessionID)
        try values.encode(operation, forKey: .operation)
        try values.encode(createdAt, forKey: .createdAt)
    }
}

public enum CounterCommandApplyResult: Equatable {
    case applied
    case alreadyApplied
    case noChange
}
