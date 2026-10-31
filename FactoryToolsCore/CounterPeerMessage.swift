import Foundation

/// Versioned, locale-neutral message envelope for a direct iPhone/iPad counter connection.
public struct CounterPeerMessage: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public enum Kind: String, Codable, Equatable {
        case catalogRequest
        case catalog
        case command
        case commandResult
    }

    public private(set) var schemaVersion: Int
    public let messageID: UUID
    public let kind: Kind
    public let command: CounterCommand?
    public let catalog: WatchCounterCatalog?
    public let acknowledgement: CounterCommandAcknowledgement?
    public let session: WatchCounterSessionSnapshot?

    private init(
        messageID: UUID,
        kind: Kind,
        command: CounterCommand? = nil,
        catalog: WatchCounterCatalog? = nil,
        acknowledgement: CounterCommandAcknowledgement? = nil,
        session: WatchCounterSessionSnapshot? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.messageID = messageID
        self.kind = kind
        self.command = command
        self.catalog = catalog
        self.acknowledgement = acknowledgement
        self.session = session
    }

    public static func catalogRequest(messageID: UUID = UUID()) -> Self {
        Self(messageID: messageID, kind: .catalogRequest)
    }

    public static func catalog(_ catalog: WatchCounterCatalog, messageID: UUID = UUID()) -> Self {
        Self(messageID: messageID, kind: .catalog, catalog: catalog)
    }

    public static func command(_ command: CounterCommand, messageID: UUID = UUID()) -> Self {
        Self(messageID: messageID, kind: .command, command: command)
    }

    public static func commandResult(
        _ acknowledgement: CounterCommandAcknowledgement,
        session: WatchCounterSessionSnapshot?,
        messageID: UUID = UUID()
    ) -> Self {
        Self(messageID: messageID, kind: .commandResult, acknowledgement: acknowledgement, session: session)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, messageID, kind, command, catalog, acknowledgement, session
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: values, debugDescription: "Unsupported counter peer message schema version.")
        }
        let messageID = try values.decode(UUID.self, forKey: .messageID)
        let kind = try values.decode(Kind.self, forKey: .kind)
        let command = try values.decodeIfPresent(CounterCommand.self, forKey: .command)
        let catalog = try values.decodeIfPresent(WatchCounterCatalog.self, forKey: .catalog)
        let acknowledgement = try values.decodeIfPresent(CounterCommandAcknowledgement.self, forKey: .acknowledgement)
        let session = try values.decodeIfPresent(WatchCounterSessionSnapshot.self, forKey: .session)
        guard Self.payloadMatches(kind: kind, command: command, catalog: catalog, acknowledgement: acknowledgement, session: session) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Counter peer message payload does not match its kind.")
        }
        schemaVersion = version
        self.messageID = messageID
        self.kind = kind
        self.command = command
        self.catalog = catalog
        self.acknowledgement = acknowledgement
        self.session = session
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(messageID, forKey: .messageID)
        try values.encode(kind, forKey: .kind)
        try values.encodeIfPresent(command, forKey: .command)
        try values.encodeIfPresent(catalog, forKey: .catalog)
        try values.encodeIfPresent(acknowledgement, forKey: .acknowledgement)
        try values.encodeIfPresent(session, forKey: .session)
    }

    private static func payloadMatches(
        kind: Kind,
        command: CounterCommand?,
        catalog: WatchCounterCatalog?,
        acknowledgement: CounterCommandAcknowledgement?,
        session: WatchCounterSessionSnapshot?
    ) -> Bool {
        switch kind {
        case .catalogRequest:
            command == nil && catalog == nil && acknowledgement == nil && session == nil
        case .catalog:
            command == nil && catalog != nil && acknowledgement == nil && session == nil
        case .command:
            command != nil && catalog == nil && acknowledgement == nil && session == nil
        case .commandResult:
            command == nil && catalog == nil && acknowledgement != nil
        }
    }
}

/// The iPhone authority serves one paired iPad connection at a time.
/// A new connection must not evict a pending or established peer.
public enum CounterPeerConnectionPolicy {
    public static func shouldAcceptIncomingConnection(
        isAuthority: Bool,
        hasPendingOrActiveConnection: Bool
    ) -> Bool {
        isAuthority && !hasPendingOrActiveConnection
    }
}

