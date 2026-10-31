import Foundation

public enum WatchCommandWireKey {
    public static let command = "factoryTools.command.v1"
    public static let acknowledgement = "factoryTools.acknowledgement.v1"
    public static let session = "factoryTools.session.v1"
    public static let catalog = "factoryTools.catalog.v1"
    public static let requestCatalog = "factoryTools.requestCatalog.v1"
    public static let retry = "factoryTools.retry.v1"
    public static let cycleTimeCommand = "factoryTools.cycleTime.command.v1"
    public static let cycleTimeAcknowledgement = "factoryTools.cycleTime.acknowledgement.v1"
}

/// One iPhone-owned counter projection presented on Watch.
public struct WatchCounterSessionSnapshot: Codable, Equatable, Identifiable {
    public let sessionID: UUID
    public let homeProfileID: UUID
    public let homeName: String
    /// `true` means the companion should localize the name using its display locale.
    /// `nil` keeps older version-1 catalogs and custom names verbatim.
    public let homeNameIsDefault: Bool?
    public let toolID: ToolID
    public let sessionName: String
    public let defaultSessionNameToolID: ToolID?
    public let currentCount: Int
    public let targetCount: Int
    public let latestUndoableEventID: UUID?

    public var id: UUID { sessionID }

    public init(
        sessionID: UUID,
        homeProfileID: UUID,
        homeName: String,
        toolID: ToolID,
        sessionName: String,
        currentCount: Int,
        targetCount: Int,
        latestUndoableEventID: UUID? = nil,
        defaultSessionNameToolID: ToolID? = nil,
        homeNameIsDefault: Bool? = nil
    ) {
        self.sessionID = sessionID
        self.homeProfileID = homeProfileID
        self.homeName = homeName
        self.homeNameIsDefault = homeNameIsDefault
        self.toolID = toolID
        self.sessionName = sessionName
        self.defaultSessionNameToolID = defaultSessionNameToolID
        self.currentCount = currentCount
        self.targetCount = targetCount
        self.latestUndoableEventID = latestUndoableEventID
    }
}

/// The selected iPhone home that has Cycle Time enabled for Apple Watch.
public struct WatchCycleTimeHomeSnapshot: Codable, Equatable, Identifiable {
    public let homeProfileID: UUID
    public let homeName: String
    public let homeNameIsDefault: Bool?

    public var id: UUID { homeProfileID }

    public init(homeProfileID: UUID, homeName: String, homeNameIsDefault: Bool? = nil) {
        self.homeProfileID = homeProfileID
        self.homeName = homeName
        self.homeNameIsDefault = homeNameIsDefault
    }
}

/// Read-only Pro progress card sent from the selected iPhone home to Apple Watch.
public struct WatchProductionProgressSnapshot: Codable, Equatable, Identifiable {
    public let cardID: UUID
    public let sessionID: UUID
    public let homeProfileID: UUID
    public let homeName: String
    public let homeNameIsDefault: Bool?
    public let currentCount: Int
    public let targetCount: Int

    public var id: UUID { cardID }

    public init(
        cardID: UUID,
        sessionID: UUID,
        homeProfileID: UUID,
        homeName: String,
        currentCount: Int,
        targetCount: Int,
        homeNameIsDefault: Bool? = nil
    ) {
        self.cardID = cardID
        self.sessionID = sessionID
        self.homeProfileID = homeProfileID
        self.homeName = homeName
        self.homeNameIsDefault = homeNameIsDefault
        self.currentCount = currentCount
        self.targetCount = targetCount
    }
}

/// App language selected on iPhone and applied to the companion Watch UI.
public enum WatchDisplayLanguage: String, Codable, Equatable {
    case system
    case japanese
    case english
}

/// Versioned snapshot of Watch-enabled counters, Cycle Time, and Pro progress cards.
public struct WatchCounterCatalog: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public private(set) var schemaVersion: Int
    public let sessions: [WatchCounterSessionSnapshot]
    public let cycleTimeHome: WatchCycleTimeHomeSnapshot?
    public let progressCards: [WatchProductionProgressSnapshot]
    public let displayLanguage: WatchDisplayLanguage

    public init(
        sessions: [WatchCounterSessionSnapshot],
        cycleTimeHome: WatchCycleTimeHomeSnapshot? = nil,
        progressCards: [WatchProductionProgressSnapshot] = [],
        displayLanguage: WatchDisplayLanguage = .system
    ) throws {
        try Self.validate(sessions, cycleTimeHome: cycleTimeHome, progressCards: progressCards)
        schemaVersion = Self.currentSchemaVersion
        self.sessions = sessions
        self.cycleTimeHome = cycleTimeHome
        self.progressCards = progressCards
        self.displayLanguage = displayLanguage
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, sessions, cycleTimeHome, progressCards, displayLanguage
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: values,
                debugDescription: "Unsupported Watch counter catalog schema version."
            )
        }
        let decodedSessions = try values.decode([WatchCounterSessionSnapshot].self, forKey: .sessions)
        let decodedCycleTimeHome = try values.decodeIfPresent(WatchCycleTimeHomeSnapshot.self, forKey: .cycleTimeHome)
        // Additive optional field: older Watch catalogs remain valid and decode as an empty Pro section.
        let decodedProgressCards = try values.decodeIfPresent([WatchProductionProgressSnapshot].self, forKey: .progressCards) ?? []
        let decodedDisplayLanguage = try values.decodeIfPresent(WatchDisplayLanguage.self, forKey: .displayLanguage) ?? .system
        do {
            try Self.validate(
                decodedSessions,
                cycleTimeHome: decodedCycleTimeHome,
                progressCards: decodedProgressCards
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .sessions,
                in: values,
                debugDescription: "Watch counter catalog contains invalid sessions."
            )
        }
        schemaVersion = version
        sessions = decodedSessions
        cycleTimeHome = decodedCycleTimeHome
        progressCards = decodedProgressCards
        displayLanguage = decodedDisplayLanguage
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(sessions, forKey: .sessions)
        try values.encodeIfPresent(cycleTimeHome, forKey: .cycleTimeHome)
        try values.encode(progressCards, forKey: .progressCards)
        try values.encode(displayLanguage, forKey: .displayLanguage)
    }

    private static func validate(
        _ sessions: [WatchCounterSessionSnapshot],
        cycleTimeHome: WatchCycleTimeHomeSnapshot?,
        progressCards: [WatchProductionProgressSnapshot]
    ) throws {
        guard Set(sessions.map(\.sessionID)).count == sessions.count,
              Set(progressCards.map(\.cardID)).count == progressCards.count,
              progressCards.allSatisfy({
                  $0.currentCount >= 0
                      && $0.targetCount >= 0
                      && !$0.homeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }),
              cycleTimeHome.map({ !$0.homeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true,
              sessions.allSatisfy({
                  [.productionCounter, .defectCounter].contains($0.toolID)
                      && ($0.defaultSessionNameToolID == nil || $0.defaultSessionNameToolID == $0.toolID)
                      && $0.currentCount >= 0
                      && $0.targetCount >= 0
                      && !$0.homeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !$0.sessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
            throw WatchCounterCatalogError.invalidSessions
        }
    }
}

public enum WatchCounterCatalogError: Error, Equatable {
    case invalidSessions
}

/// Checks a decoded peer response against the exact command sent by the Watch.
public enum WatchCounterCommandResponseValidator {
    public static func acknowledgement(
        _ acknowledgement: CounterCommandAcknowledgement,
        matches command: CounterCommand
    ) -> Bool {
        acknowledgement.commandID == command.id
    }

    public static func snapshot(
        _ snapshot: WatchCounterSessionSnapshot,
        matches command: CounterCommand
    ) -> Bool {
        guard snapshot.sessionID == command.sessionID,
              (try? WatchCounterCatalog(sessions: [snapshot])) != nil else { return false }
        return true
    }
}

/// Validates the complete acknowledgement/snapshot pair returned for a queued counter command.
public enum CounterCommandResponseValidator {
    public static func isComplete(
        _ acknowledgement: CounterCommandAcknowledgement,
        snapshot: WatchCounterSessionSnapshot?,
        matches command: CounterCommand
    ) -> Bool {
        guard WatchCounterCommandResponseValidator.acknowledgement(acknowledgement, matches: command) else {
            return false
        }
        guard let snapshot else {
            return !acknowledgement.status.requiresAuthoritativeSnapshot
        }
        return WatchCounterCommandResponseValidator.snapshot(snapshot, matches: command)
    }

    /// A matching rejection without a snapshot means the iPhone no longer has this counter session.
    public static func indicatesUnavailableSession(
        _ acknowledgement: CounterCommandAcknowledgement,
        snapshot: WatchCounterSessionSnapshot?,
        matches command: CounterCommand
    ) -> Bool {
        isComplete(acknowledgement, snapshot: snapshot, matches: command)
            && acknowledgement.status == .rejected
            && snapshot == nil
    }
}
