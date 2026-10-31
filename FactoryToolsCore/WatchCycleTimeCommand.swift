import Foundation

/// A single measured unit-cycle captured on Apple Watch and recorded by iPhone.
public struct WatchCycleTimeCommand: Codable, Equatable, Identifiable {
    public static let currentSchemaVersion = 1
    public static let maximumDurationSeconds = 86_400

    public let schemaVersion: Int
    public let id: UUID
    public let homeProfileID: UUID
    public let totalSeconds: Int
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        homeProfileID: UUID,
        totalSeconds: Int,
        createdAt: Date = .now
    ) throws {
        guard (1...Self.maximumDurationSeconds).contains(totalSeconds),
              PersistedTimestamp.isSupported(createdAt) else {
            throw WatchCycleTimeCommandError.invalidMeasurement
        }
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.homeProfileID = homeProfileID
        self.totalSeconds = totalSeconds
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, homeProfileID, totalSeconds, createdAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .schemaVersion)
        let id = try values.decode(UUID.self, forKey: .id)
        let homeID = try values.decode(UUID.self, forKey: .homeProfileID)
        let seconds = try values.decode(Int.self, forKey: .totalSeconds)
        let date = try values.decode(Date.self, forKey: .createdAt)
        guard version == Self.currentSchemaVersion,
              (1...Self.maximumDurationSeconds).contains(seconds),
              PersistedTimestamp.isSupported(date) else {
            throw DecodingError.dataCorruptedError(
                forKey: .totalSeconds,
                in: values,
                debugDescription: "Invalid Watch cycle-time command."
            )
        }
        schemaVersion = version
        self.id = id
        homeProfileID = homeID
        totalSeconds = seconds
        createdAt = date
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(homeProfileID, forKey: .homeProfileID)
        try values.encode(totalSeconds, forKey: .totalSeconds)
        try values.encode(createdAt, forKey: .createdAt)
    }
}

public enum WatchCycleTimeCommandError: Error, Equatable {
    case invalidMeasurement
}

public enum WatchCycleTimeAcknowledgementStatus: String, Codable, Equatable {
    case applied
    case alreadyApplied
    case rejected
}

public struct WatchCycleTimeAcknowledgement: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let commandID: UUID
    public let status: WatchCycleTimeAcknowledgementStatus

    public init(commandID: UUID, status: WatchCycleTimeAcknowledgementStatus) {
        schemaVersion = Self.currentSchemaVersion
        self.commandID = commandID
        self.status = status
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, commandID, status }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: values,
                debugDescription: "Unsupported Watch cycle-time acknowledgement version."
            )
        }
        schemaVersion = version
        commandID = try values.decode(UUID.self, forKey: .commandID)
        status = try values.decode(WatchCycleTimeAcknowledgementStatus.self, forKey: .status)
    }
}

/// Durable Watch-side cycle timer state and FIFO of samples awaiting the iPhone.
public struct WatchCycleTimeOutbox: Codable, Equatable {
    public static let currentSchemaVersion = 1
    public static let maximumPendingCommandCount = 5_000
    private static let maximumDurationMilliseconds: Int64 = Int64(WatchCycleTimeCommand.maximumDurationSeconds) * 1_000

    public private(set) var schemaVersion: Int
    public private(set) var pendingCommands: [WatchCycleTimeCommand]
    public private(set) var accumulatedMilliseconds: Int64
    public private(set) var startedAt: Date?
    public private(set) var activeHomeProfileID: UUID?

    public init() {
        schemaVersion = Self.currentSchemaVersion
        pendingCommands = []
        accumulatedMilliseconds = 0
        startedAt = nil
        activeHomeProfileID = nil
    }

    public var nextCommand: WatchCycleTimeCommand? { pendingCommands.first }
    public var count: Int { pendingCommands.count }
    public var isRunning: Bool { startedAt != nil }

    public func elapsedMilliseconds(at date: Date = .now) -> Int64 {
        let runningMilliseconds: Int64
        if let startedAt, date >= startedAt {
            let interval = (date.timeIntervalSince(startedAt) * 1_000).rounded()
            runningMilliseconds = interval.isFinite && interval <= Double(Self.maximumDurationMilliseconds)
                ? max(0, Int64(interval))
                : Self.maximumDurationMilliseconds
        } else {
            runningMilliseconds = 0
        }
        return min(accumulatedMilliseconds + runningMilliseconds, Self.maximumDurationMilliseconds)
    }

    public func elapsedSeconds(at date: Date = .now) -> Double {
        Double(elapsedMilliseconds(at: date)) / 1_000
    }

    public mutating func start(homeProfileID: UUID, at date: Date = .now) {
        guard startedAt == nil,
              PersistedTimestamp.isSupported(date),
              activeHomeProfileID == nil || activeHomeProfileID == homeProfileID else { return }
        activeHomeProfileID = homeProfileID
        startedAt = date
    }

    public mutating func pause(at date: Date = .now) {
        guard let startedAt, date >= startedAt else { return }
        let milliseconds = (date.timeIntervalSince(startedAt) * 1_000).rounded()
        guard milliseconds.isFinite, milliseconds >= 0,
              milliseconds <= Double(Self.maximumDurationMilliseconds - accumulatedMilliseconds) else {
            accumulatedMilliseconds = Self.maximumDurationMilliseconds
            self.startedAt = nil
            return
        }
        accumulatedMilliseconds += Int64(milliseconds)
        self.startedAt = nil
        if accumulatedMilliseconds == 0 { activeHomeProfileID = nil }
    }

    /// Stops a running timer using a monotonic elapsed-time total computed by the host app.
    public mutating func pause(totalElapsedMilliseconds: Int64) {
        guard startedAt != nil,
              (accumulatedMilliseconds...Self.maximumDurationMilliseconds).contains(totalElapsedMilliseconds) else { return }
        accumulatedMilliseconds = totalElapsedMilliseconds
        startedAt = nil
        if accumulatedMilliseconds == 0 { activeHomeProfileID = nil }
    }

    public mutating func resetTimer() {
        accumulatedMilliseconds = 0
        startedAt = nil
        activeHomeProfileID = nil
    }

    /// Creates a command from the measured timer and clears the timer only after validation.
    public mutating func finish(at date: Date = .now) throws -> WatchCycleTimeCommand? {
        try finish(totalElapsedMilliseconds: elapsedMilliseconds(at: date), createdAt: date)
    }

    /// Creates a sample from a monotonic elapsed-time total while retaining the wall-clock sample timestamp.
    public mutating func finish(
        totalElapsedMilliseconds: Int64,
        createdAt date: Date = .now
    ) throws -> WatchCycleTimeCommand? {
        guard let homeID = activeHomeProfileID,
              (accumulatedMilliseconds...Self.maximumDurationMilliseconds).contains(totalElapsedMilliseconds) else { return nil }
        let duration = Double(totalElapsedMilliseconds) / 1_000
        guard let roundedSeconds = CycleTimeMeasurement.roundedWholeSeconds(from: duration) else { return nil }
        let command = try WatchCycleTimeCommand(
            homeProfileID: homeID,
            totalSeconds: roundedSeconds,
            createdAt: date
        )
        resetTimer()
        return command
    }

    /// Returns false for an exact retry and throws if an ID is reused with different content.
    @discardableResult
    public mutating func enqueue(_ command: WatchCycleTimeCommand) throws -> Bool {
        if let existing = pendingCommands.first(where: { $0.id == command.id }) {
            guard existing == command else {
                throw WatchCycleTimeOutboxError.identifierConflict(commandID: command.id)
            }
            return false
        }
        guard pendingCommands.count < Self.maximumPendingCommandCount else {
            throw WatchCycleTimeOutboxError.pendingLimitReached(maximumCount: Self.maximumPendingCommandCount)
        }
        pendingCommands.append(command)
        return true
    }

    @discardableResult
    public mutating func acknowledgeHead(_ acknowledgement: WatchCycleTimeAcknowledgement) -> Bool {
        guard pendingCommands.first?.id == acknowledgement.commandID else { return false }
        pendingCommands.removeFirst()
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, pendingCommands, accumulatedMilliseconds, startedAt, activeHomeProfileID
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .schemaVersion)
        let commands = try values.decode([WatchCycleTimeCommand].self, forKey: .pendingCommands)
        let accumulated = try values.decode(Int64.self, forKey: .accumulatedMilliseconds)
        let start = try values.decodeIfPresent(Date.self, forKey: .startedAt)
        let homeID = try values.decodeIfPresent(UUID.self, forKey: .activeHomeProfileID)
        guard version == Self.currentSchemaVersion,
              Set(commands.map(\.id)).count == commands.count,
              commands.count <= Self.maximumPendingCommandCount,
              (0...Self.maximumDurationMilliseconds).contains(accumulated),
              start.map(PersistedTimestamp.isSupported) ?? true,
              (start == nil && accumulated == 0 && homeID == nil)
                || (homeID != nil && (start != nil || accumulated > 0)) else {
            throw DecodingError.dataCorruptedError(
                forKey: .pendingCommands,
                in: values,
                debugDescription: "Invalid Watch cycle-time outbox."
            )
        }
        schemaVersion = version
        pendingCommands = commands
        accumulatedMilliseconds = accumulated
        startedAt = start
        activeHomeProfileID = homeID
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(pendingCommands, forKey: .pendingCommands)
        try values.encode(accumulatedMilliseconds, forKey: .accumulatedMilliseconds)
        try values.encodeIfPresent(startedAt, forKey: .startedAt)
        try values.encodeIfPresent(activeHomeProfileID, forKey: .activeHomeProfileID)
    }
}

public enum WatchCycleTimeOutboxError: Error, Equatable {
    case identifierConflict(commandID: UUID)
    case pendingLimitReached(maximumCount: Int)
}

public enum WatchCycleTimeCommandResponseValidator {
    public static func accepts(
        _ acknowledgement: WatchCycleTimeAcknowledgement,
        for command: WatchCycleTimeCommand
    ) -> Bool {
        acknowledgement.commandID == command.id
    }
}

public struct WatchCycleTimeOutboxFileStore {
    public static let maximumFileSizeBytes = 4 * 1_048_576
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() throws -> WatchCycleTimeOutbox {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return WatchCycleTimeOutbox() }
        let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = resourceValues.fileSize,
              fileSize >= 0,
              fileSize <= Self.maximumFileSizeBytes else {
            throw WatchCycleTimeOutboxFileStoreError.fileTooLarge
        }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard data.count <= Self.maximumFileSizeBytes else {
            throw WatchCycleTimeOutboxFileStoreError.fileTooLarge
        }
        return try JSONDecoder().decode(WatchCycleTimeOutbox.self, from: data)
    }

    public func save(_ outbox: WatchCycleTimeOutbox) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let data = try JSONEncoder().encode(outbox)
        guard data.count <= Self.maximumFileSizeBytes else {
            throw WatchCycleTimeOutboxFileStoreError.fileTooLarge
        }
        try data.write(to: fileURL, options: .atomic)
    }
}

public enum WatchCycleTimeOutboxFileStoreError: Error, Equatable {
    case fileTooLarge
}
