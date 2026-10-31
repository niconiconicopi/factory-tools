import Foundation

/// A transport-independent, ordered queue of counter commands awaiting acknowledgement.
/// Persist the encoded value on the sending platform and retry its head after relaunch.
public struct CounterCommandOutbox: Codable, Equatable {
    public static let currentSchemaVersion = 1
    public static let maximumPendingCommandCount = 5_000

    public private(set) var schemaVersion: Int
    public private(set) var pendingCommands: [CounterCommand]

    public init() {
        schemaVersion = Self.currentSchemaVersion
        pendingCommands = []
    }

    public var nextCommand: CounterCommand? { pendingCommands.first }
    public var count: Int { pendingCommands.count }
    public var isEmpty: Bool { pendingCommands.isEmpty }

    /// Returns true when added, false for an exact retry, and throws on ID reuse with changed content.
    @discardableResult
    public mutating func enqueue(_ command: CounterCommand) throws -> Bool {
        if let existing = pendingCommands.first(where: { $0.id == command.id }) {
            guard existing == command else {
                throw CounterCommandOutboxError.identifierConflict(commandID: command.id)
            }
            return false
        }
        guard pendingCommands.count < Self.maximumPendingCommandCount else {
            throw CounterCommandOutboxError.pendingLimitReached(maximumCount: Self.maximumPendingCommandCount)
        }

        pendingCommands.append(command)
        return true
    }

    /// Removes only the acknowledged head, keeping delivery ordered across retries and relaunches.
    @discardableResult
    public mutating func acknowledgeHead(commandID: UUID) -> Bool {
        guard pendingCommands.first?.id == commandID else { return false }
        pendingCommands.removeFirst()
        return true
    }

    /// Consumes a final acknowledgement only when it belongs to the current queue head.
    @discardableResult
    public mutating func acknowledgeHead(_ acknowledgement: CounterCommandAcknowledgement) -> Bool {
        acknowledgeHead(commandID: acknowledgement.commandID)
    }

    /// Drops queued commands for a session after the authority confirms that the session is unavailable.
    @discardableResult
    public mutating func discardCommands(for sessionID: UUID) -> Int {
        let originalCount = pendingCommands.count
        pendingCommands.removeAll { $0.sessionID == sessionID }
        return originalCount - pendingCommands.count
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, pendingCommands
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard decodedVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: values,
                debugDescription: "Unsupported counter-command outbox schema version."
            )
        }
        let commands = try values.decode([CounterCommand].self, forKey: .pendingCommands)
        guard commands.count <= Self.maximumPendingCommandCount else {
            throw DecodingError.dataCorruptedError(
                forKey: .pendingCommands,
                in: values,
                debugDescription: "Outbox exceeds its maximum pending command count."
            )
        }
        let uniqueIDs = Set(commands.map(\.id))
        guard uniqueIDs.count == commands.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .pendingCommands,
                in: values,
                debugDescription: "Outbox contains duplicate command identifiers."
            )
        }
        schemaVersion = decodedVersion
        pendingCommands = commands
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(pendingCommands, forKey: .pendingCommands)
    }
}

public enum CounterCommandOutboxError: Error, Equatable {
    case identifierConflict(commandID: UUID)
    case pendingLimitReached(maximumCount: Int)
}

public enum CounterCommandOutboxTransactionError: Error, Equatable {
    case commandIsNotHead
    case invalidResponse
}

/// Builds and persists a candidate queue before returning it to the caller to commit in memory.
public enum CounterCommandOutboxTransaction {
    public static func enqueue(
        _ command: CounterCommand,
        into current: CounterCommandOutbox,
        persist: (CounterCommandOutbox) throws -> Void
    ) throws -> CounterCommandOutbox {
        var candidate = current
        try candidate.enqueue(command)
        try persist(candidate)
        return candidate
    }

    public static func acknowledge(
        _ acknowledgement: CounterCommandAcknowledgement,
        snapshot: WatchCounterSessionSnapshot?,
        command: CounterCommand,
        in current: CounterCommandOutbox,
        persist: (CounterCommandOutbox) throws -> Void
    ) throws -> CounterCommandOutbox {
        guard current.nextCommand?.id == command.id else {
            throw CounterCommandOutboxTransactionError.commandIsNotHead
        }
        guard CounterCommandResponseValidator.isComplete(
            acknowledgement,
            snapshot: snapshot,
            matches: command
        ) else {
            throw CounterCommandOutboxTransactionError.invalidResponse
        }

        var candidate = current
        if CounterCommandResponseValidator.indicatesUnavailableSession(
            acknowledgement,
            snapshot: snapshot,
            matches: command
        ) {
            _ = candidate.discardCommands(for: command.sessionID)
        } else if !candidate.acknowledgeHead(acknowledgement) {
            throw CounterCommandOutboxTransactionError.commandIsNotHead
        }
        try persist(candidate)
        return candidate
    }
}

/// Bounded exponential retry schedule shared by offline command transports.
public enum CounterCommandRetryPolicy {
    public static func delaySeconds(forAttempt attempt: Int) -> UInt64 {
        let exponent = min(max(attempt, 0), 5)
        return min(UInt64(1) << UInt64(exponent), 30)
    }
}

/// File-backed persistence for apps that want the same crash-safe outbox behavior.
/// The host app supplies a URL inside its own sandbox and serializes access to this store.
public struct CounterCommandOutboxFileStore {
    public static let maximumFileSizeBytes = 4 * 1_048_576
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// A missing file means no commands are pending; malformed files throw and are left untouched.
    public func load() throws -> CounterCommandOutbox {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return CounterCommandOutbox()
        }
        let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = resourceValues.fileSize,
              fileSize >= 0,
              fileSize <= Self.maximumFileSizeBytes else {
            throw CounterCommandOutboxFileStoreError.fileTooLarge
        }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard data.count <= Self.maximumFileSizeBytes else {
            throw CounterCommandOutboxFileStoreError.fileTooLarge
        }
        return try JSONDecoder().decode(CounterCommandOutbox.self, from: data)
    }

    /// Writes through an atomic same-directory replacement so interruption does not truncate the prior queue.
    public func save(_ outbox: CounterCommandOutbox) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let data = try JSONEncoder().encode(outbox)
        guard data.count <= Self.maximumFileSizeBytes else {
            throw CounterCommandOutboxFileStoreError.fileTooLarge
        }
        try data.write(to: fileURL, options: .atomic)
    }
}

public enum CounterCommandOutboxFileStoreError: Error, Equatable {
    case fileTooLarge
}
