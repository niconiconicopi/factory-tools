import Foundation

/// Stable, locale-independent result returned after a command has been processed.
public enum CounterCommandAcknowledgementStatus: String, Codable, Equatable, CaseIterable {
    case applied
    case alreadyApplied
    case noChange
    case staleUndo
    case rejected

    public var requiresAuthoritativeSnapshot: Bool {
        switch self {
        case .applied, .alreadyApplied, .noChange, .staleUndo:
            return true
        case .rejected:
            return false
        }
    }
}

public struct CounterCommandAcknowledgement: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public private(set) var schemaVersion: Int
    public let commandID: UUID
    public let status: CounterCommandAcknowledgementStatus

    public init(commandID: UUID, status: CounterCommandAcknowledgementStatus) {
        schemaVersion = Self.currentSchemaVersion
        self.commandID = commandID
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, commandID, status
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard decodedVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: values,
                debugDescription: "Unsupported counter-command acknowledgement schema version."
            )
        }
        schemaVersion = decodedVersion
        commandID = try values.decode(UUID.self, forKey: .commandID)
        status = try values.decode(CounterCommandAcknowledgementStatus.self, forKey: .status)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(commandID, forKey: .commandID)
        try values.encode(status, forKey: .status)
    }
}
