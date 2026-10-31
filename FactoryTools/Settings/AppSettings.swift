import Foundation
import SwiftData
import FactoryToolsCore

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case japanese
    case english

    var id: String { rawValue }

    static func resolve(_ rawValue: String?) -> AppLanguage {
        guard let rawValue else { return .system }
        return AppLanguage(rawValue: rawValue) ?? .system
    }

    var locale: Locale {
        switch self {
        case .system: .current
        case .japanese: Locale(identifier: "ja")
        case .english: Locale(identifier: "en")
        }
    }
}

@Model
final class AppSettings {
    @Attribute(.unique) var id: UUID
    var language: String
    var themeID: String
    var selectedHomeProfileID: UUID?

    init(
        id: UUID = UUID(),
        language: String = AppLanguage.system.rawValue,
        themeID: String = ThemeID.industrialDark.rawValue,
        selectedHomeProfileID: UUID? = nil
    ) {
        self.id = id
        self.language = language
        self.themeID = themeID
        self.selectedHomeProfileID = selectedHomeProfileID
    }
}

@MainActor
struct AppSettingsService {
    let modelContext: ModelContext

    func setLanguage(_ language: AppLanguage, for settings: AppSettings) throws {
        let previousLanguage = settings.language
        guard previousLanguage != language.rawValue else { return }
        settings.language = language.rawValue
        do {
            try modelContext.save()
        } catch {
            settings.language = previousLanguage
            throw error
        }
        WatchConnectivityReceiver.shared.publishCatalog()
    }
}

enum AppSettingsOrdering {
    static func primary(in settings: [AppSettings]) -> AppSettings? {
        settings.min { first, second in
            first.id.uuidString < second.id.uuidString
        }
    }
}

struct FactoryToolsBackup: Codable, Equatable {
    struct Home: Codable, Equatable {
        let id: UUID
        let name: String
        let usesDefaultName: Bool
        let sortOrder: Int
        let createdAt: Date

        init(_ value: HomeProfile) {
            id = value.id
            name = value.name
            usesDefaultName = value.usesDefaultName
            sortOrder = value.sortOrder
            createdAt = value.createdAt
        }
    }

    struct Card: Codable, Equatable {
        let id: UUID
        let homeProfileID: UUID
        let toolID: String
        let sizeRawValue: String
        let sortOrder: Int
        let showsOnWatch: Bool
        let productionSessionID: UUID?

        init(_ value: ToolCard) {
            self.init(value, resolvedProductionSessionID: value.productionSessionID)
        }

        init(_ value: ToolCard, resolvedProductionSessionID: UUID?) {
            id = value.id
            homeProfileID = value.homeProfileID
            toolID = value.toolID
            sizeRawValue = value.sizeRawValue
            sortOrder = value.sortOrder
            showsOnWatch = value.showsOnWatch
            productionSessionID = resolvedProductionSessionID
        }
    }

    struct Session: Codable, Equatable {
        let id: UUID
        let homeProfileID: UUID?
        let toolID: String?
        let name: String
        let currentCount: Int
        let targetCount: Int
        let nextEventSequence: Int
        let startedAt: Date

        init(_ value: ProductionSession) {
            id = value.id
            homeProfileID = value.homeProfileID
            toolID = value.toolID
            name = value.name
            currentCount = value.currentCount
            targetCount = value.targetCount
            nextEventSequence = value.nextEventSequence
            startedAt = value.startedAt
        }
    }

    struct Event: Codable, Equatable {
        let id: UUID
        let sessionID: UUID
        let delta: Int
        let sequence: Int
        let occurredAt: Date
        let reversesEventID: UUID?
        let kindRawValue: String?
        let payloadSignature: String?

        init(_ value: CountEvent) {
            id = value.id
            sessionID = value.sessionID
            delta = value.delta
            sequence = value.sequence
            occurredAt = value.occurredAt
            reversesEventID = value.reversesEventID
            kindRawValue = value.kindRawValue
            payloadSignature = value.payloadSignature
        }
    }

    struct CommandReceipt: Codable, Equatable {
        let id: UUID
        let sessionID: UUID
        let processedAt: Date
        let payloadSignature: String?

        init(_ value: CounterCommandReceipt) {
            id = value.id
            sessionID = value.sessionID
            processedAt = value.processedAt
            payloadSignature = value.payloadSignature
        }
    }

    struct CycleSample: Codable, Equatable {
        let id: UUID
        let homeProfileID: UUID
        let totalSeconds: Int
        let quantity: Int
        let createdAt: Date

        init(_ value: CycleTimeSample) {
            id = value.id
            homeProfileID = value.homeProfileID
            totalSeconds = value.totalSeconds
            quantity = value.quantity
            createdAt = value.createdAt
        }
    }

    struct OEERecord: Codable, Equatable {
        let id: UUID
        let homeProfileID: UUID
        let plannedProductionMinutes: Int
        let downtimeMinutes: Int
        let idealCycleTimeSeconds: Int
        let goodUnits: Int
        let defectiveUnits: Int
        let createdAt: Date

        init(_ value: OEERun) {
            id = value.id
            homeProfileID = value.homeProfileID
            plannedProductionMinutes = value.plannedProductionMinutes
            downtimeMinutes = value.downtimeMinutes
            idealCycleTimeSeconds = value.idealCycleTimeSeconds
            goodUnits = value.goodUnits
            defectiveUnits = value.defectiveUnits
            createdAt = value.createdAt
        }
    }

    struct Settings: Codable, Equatable {
        let id: UUID
        let language: String
        let themeID: String
        let selectedHomeProfileID: UUID?

        init(_ value: AppSettings) {
            id = value.id
            language = value.language
            themeID = value.themeID
            selectedHomeProfileID = value.selectedHomeProfileID
        }
    }

    let schemaVersion: Int
    let exportedAt: Date
    let homes: [Home]
    let cards: [Card]
    let sessions: [Session]
    let events: [Event]
    let commandReceipts: [CommandReceipt]
    let cycleTimeSamples: [CycleSample]
    let oeeRuns: [OEERecord]
    let settings: [Settings]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, exportedAt, homes, cards, sessions, events, commandReceipts, cycleTimeSamples, oeeRuns, settings
    }

    init(
        schemaVersion: Int,
        exportedAt: Date,
        homes: [Home],
        cards: [Card],
        sessions: [Session],
        events: [Event],
        commandReceipts: [CommandReceipt] = [],
        cycleTimeSamples: [CycleSample],
        oeeRuns: [OEERecord] = [],
        settings: [Settings]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.homes = homes
        self.cards = cards
        self.sessions = sessions
        self.events = events
        self.commandReceipts = commandReceipts
        self.cycleTimeSamples = cycleTimeSamples
        self.oeeRuns = oeeRuns
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        exportedAt = try values.decode(Date.self, forKey: .exportedAt)
        homes = try values.decode([Home].self, forKey: .homes)
        cards = try values.decode([Card].self, forKey: .cards)
        sessions = try values.decode([Session].self, forKey: .sessions)
        events = try values.decode([Event].self, forKey: .events)
        if (3...4).contains(schemaVersion) {
            commandReceipts = try values.decode([CommandReceipt].self, forKey: .commandReceipts)
        } else {
            commandReceipts = try values.decodeIfPresent([CommandReceipt].self, forKey: .commandReceipts) ?? []
        }
        cycleTimeSamples = try values.decode([CycleSample].self, forKey: .cycleTimeSamples)
        if (2...4).contains(schemaVersion) {
            oeeRuns = try values.decode([OEERecord].self, forKey: .oeeRuns)
        } else {
            oeeRuns = try values.decodeIfPresent([OEERecord].self, forKey: .oeeRuns) ?? []
        }
        settings = try values.decode([Settings].self, forKey: .settings)
    }
}

enum FactoryToolsBackupError: Error, Equatable {
    case unsupportedVersion
    case backupTooLarge
    case duplicateIdentifier
    case duplicateSequence
    case invalidRelationship
    case invalidStoredValue
}

struct FactoryToolsBackupImportResult: Equatable {
    let homes: Int
    let cards: Int
    let sessions: Int
    let events: Int
    let commandReceipts: Int
    let cycleTimeSamples: Int
    let oeeRuns: Int
}

@MainActor
struct FactoryToolsBackupService {
    nonisolated static let maximumBackupSizeInBytes = 64 * 1024 * 1024
    nonisolated static let maximumBackupRecordCount = 500_000

    let modelContext: ModelContext

    static func readAndValidate(
        from url: URL,
        maximumSizeInBytes: Int = maximumBackupSizeInBytes
    ) throws -> FactoryToolsBackup {
        try validateBackupByteCount(0, maximumSizeInBytes: maximumSizeInBytes)
        let file = try FileHandle(forReadingFrom: url)
        defer { file.closeFile() }

        var data = Data()
        while true {
            let remainingBytes = maximumSizeInBytes - data.count
            let readLimit = min(64 * 1024, remainingBytes + 1)
            let chunk = try file.read(upToCount: readLimit) ?? Data()
            guard !chunk.isEmpty else { break }
            guard chunk.count <= remainingBytes else { throw FactoryToolsBackupError.backupTooLarge }
            data.append(chunk)
        }
        return try decodeAndValidate(data, maximumSizeInBytes: maximumSizeInBytes)
    }

    static func decodeAndValidate(
        _ data: Data,
        maximumSizeInBytes: Int = maximumBackupSizeInBytes
    ) throws -> FactoryToolsBackup {
        try validateBackupByteCount(data.count, maximumSizeInBytes: maximumSizeInBytes)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let backup = try decoder.decode(FactoryToolsBackup.self, from: data)
        try validate(backup)
        return backup
    }

    static func validateBackupByteCount(_ byteCount: Int, maximumSizeInBytes: Int) throws {
        guard byteCount >= 0,
              maximumSizeInBytes >= 0,
              maximumSizeInBytes < Int.max,
              byteCount <= maximumSizeInBytes else {
            throw FactoryToolsBackupError.backupTooLarge
        }
    }

    static func validate(
        _ backup: FactoryToolsBackup,
        maximumRecordCount: Int = maximumBackupRecordCount
    ) throws {
        try validateBackupRecordLimitAndCounterHistory(backup, maximumRecordCount: maximumRecordCount)
        guard (1...4).contains(backup.schemaVersion) else { throw FactoryToolsBackupError.unsupportedVersion }
        guard !backup.homes.isEmpty, !backup.settings.isEmpty else {
            throw FactoryToolsBackupError.invalidRelationship
        }
        guard PersistedTimestamp.isSupported(backup.exportedAt),
              backup.homes.allSatisfy({ PersistedTimestamp.isSupported($0.createdAt) }),
              backup.sessions.allSatisfy({ PersistedTimestamp.isSupported($0.startedAt) }),
              backup.events.allSatisfy({ PersistedTimestamp.isSupported($0.occurredAt) }),
              backup.commandReceipts.allSatisfy({ PersistedTimestamp.isSupported($0.processedAt) }),
              backup.cycleTimeSamples.allSatisfy({ PersistedTimestamp.isSupported($0.createdAt) }),
              backup.oeeRuns.allSatisfy({ PersistedTimestamp.isSupported($0.createdAt) }) else {
            throw FactoryToolsBackupError.invalidStoredValue
        }
        let payloadSignatures = backup.events.compactMap(\.payloadSignature)
            + backup.commandReceipts.compactMap(\.payloadSignature)
        guard payloadSignatures.allSatisfy({ CounterCommand.isWellFormedPayloadSignature($0) }) else {
            throw FactoryToolsBackupError.invalidStoredValue
        }
        guard backup.events.allSatisfy({ event in
            guard let signature = event.payloadSignature else { return true }
            return CounterCommand.payloadSignature(
                signature,
                matches: event.kindRawValue,
                delta: event.delta,
                reversesEventID: event.reversesEventID,
                occurredAt: event.occurredAt
            )
        }) else {
            throw FactoryToolsBackupError.invalidStoredValue
        }
        guard hasUniqueIDs(backup.homes, id: \.id),
              hasUniqueIDs(backup.cards, id: \.id),
              hasUniqueIDs(backup.sessions, id: \.id),
              hasUniqueIDs(backup.events, id: \.id),
              hasUniqueIDs(backup.commandReceipts, id: \.id),
              hasUniqueIDs(backup.cycleTimeSamples, id: \.id),
              hasUniqueIDs(backup.oeeRuns, id: \.id),
              hasUniqueIDs(backup.settings, id: \.id) else {
            throw FactoryToolsBackupError.duplicateIdentifier
        }

        let homeIDs = Set(backup.homes.map(\.id))
        let sessionsByID = Dictionary(uniqueKeysWithValues: backup.sessions.map { ($0.id, $0) })
        let eventIDs = Set(backup.events.map(\.id))
        let invalidHomeIDsInSessions = backup.sessions.compactMap { session in
            session.homeProfileID.flatMap { homeIDs.contains($0) ? nil : $0 }
        }
        let orphanEventSessionIDs = backup.events.map(\.sessionID).filter { sessionsByID[$0] == nil }
        let orphanReceiptSessionIDs = backup.commandReceipts.map(\.sessionID).filter { sessionsByID[$0] == nil }
        let invalidSelectedHomeIDs = backup.settings.compactMap { setting in
            setting.selectedHomeProfileID.flatMap { homeIDs.contains($0) ? nil : $0 }
        }
        guard backup.cards.allSatisfy({ homeIDs.contains($0.homeProfileID) && ToolID(rawValue: $0.toolID) != nil }),
              backup.cycleTimeSamples.allSatisfy({ homeIDs.contains($0.homeProfileID) }),
              backup.oeeRuns.allSatisfy({ homeIDs.contains($0.homeProfileID) }),
              invalidSelectedHomeIDs.isEmpty,
              invalidHomeIDsInSessions.isEmpty,
              orphanEventSessionIDs.isEmpty,
              orphanReceiptSessionIDs.isEmpty else {
            print("Backup relationship diagnostic: homes=\(homeIDs.count), sessions=\(backup.sessions.count), events=\(backup.events.count), settings=\(backup.settings.count), invalidSessionHomes=\(invalidHomeIDsInSessions.count), orphanEvents=\(orphanEventSessionIDs.count), orphanReceipts=\(orphanReceiptSessionIDs.count), invalidSelectedHomes=\(invalidSelectedHomeIDs.count)")
            throw FactoryToolsBackupError.invalidRelationship
        }
        guard backup.commandReceipts.allSatisfy({ !eventIDs.contains($0.id) }) else {
            throw FactoryToolsBackupError.duplicateIdentifier
        }
        guard backup.sessions.allSatisfy({ $0.currentCount >= 0 && $0.targetCount >= 0 && $0.nextEventSequence >= 0 }),
              backup.sessions.allSatisfy({ session in
                  guard let rawToolID = session.toolID else { return true }
                  guard let toolID = ToolID(rawValue: rawToolID),
                        let sessionPolicy = ToolRegistry.definition(for: toolID)?.sessionPolicy else { return false }
                  return sessionPolicy.sessionToolID == toolID
              }),
              backup.homes.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              backup.sessions.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              backup.cards.allSatisfy({ card in
                  guard let toolID = ToolID(rawValue: card.toolID),
                        let size = ToolCardSize(rawValue: card.sizeRawValue) else { return false }
                  return ToolRegistry.definition(for: toolID)?.supportedCardSizes.contains(size) == true
              }),
              backup.events.allSatisfy({ $0.sequence >= 0 && $0.delta != 0 && $0.delta != Int.min }),
              backup.cycleTimeSamples.allSatisfy({ $0.totalSeconds > 0 && $0.quantity > 0 }),
              backup.oeeRuns.allSatisfy({ run in
                  OEECalculator.calculate(
                      plannedProductionMinutes: run.plannedProductionMinutes,
                      downtimeMinutes: run.downtimeMinutes,
                      idealCycleTimeSeconds: run.idealCycleTimeSeconds,
                      goodUnits: run.goodUnits,
                      defectiveUnits: run.defectiveUnits
                  ) != nil
              }) else {
            throw FactoryToolsBackupError.invalidStoredValue
        }
        guard backup.events.allSatisfy({ event in
            guard let kindRawValue = event.kindRawValue,
                  let kind = CounterEventKind(rawValue: kindRawValue) else { return true }
            return switch kind {
            case .increment: event.delta == 1 && event.reversesEventID == nil
            case .decrement: event.delta == -1 && event.reversesEventID == nil
            case .quickAdd: event.delta > 0 && event.reversesEventID == nil
            case .reset: event.delta < 0 && event.reversesEventID == nil
            case .undo: event.reversesEventID != nil
            }
        }) else {
            throw FactoryToolsBackupError.invalidStoredValue
        }

        var inferredSessionHomes: [UUID: UUID] = [:]
        var inferredSessionTools: [UUID: String] = [:]
        for card in backup.cards {
            guard let sessionID = card.productionSessionID else { continue }
            guard let session = sessionsByID[sessionID],
                  let cardToolID = ToolID(rawValue: card.toolID),
                  let expectedToolID = ToolSessionAssignment.sessionToolID(for: cardToolID) else {
                throw FactoryToolsBackupError.invalidRelationship
            }
            if let sessionHomeID = session.homeProfileID, sessionHomeID != card.homeProfileID {
                throw FactoryToolsBackupError.invalidRelationship
            }
            if let storedToolID = session.toolID, storedToolID != expectedToolID.rawValue {
                throw FactoryToolsBackupError.invalidRelationship
            }
            if let inferredHomeID = inferredSessionHomes[sessionID], inferredHomeID != card.homeProfileID {
                throw FactoryToolsBackupError.invalidRelationship
            }
            if let inferredToolID = inferredSessionTools[sessionID], inferredToolID != expectedToolID.rawValue {
                throw FactoryToolsBackupError.invalidRelationship
            }
            inferredSessionHomes[sessionID] = card.homeProfileID
            inferredSessionTools[sessionID] = expectedToolID.rawValue
        }
    }

    static func validateBackupRecordLimitAndCounterHistory(
        _ backup: FactoryToolsBackup,
        maximumRecordCount: Int
    ) throws {
        try validateRecordCounts(
            [backup.homes.count, backup.cards.count, backup.sessions.count, backup.events.count,
             backup.commandReceipts.count, backup.cycleTimeSamples.count, backup.oeeRuns.count,
             backup.settings.count],
            maximumRecordCount: maximumRecordCount
        )
        var sequencesBySession: [UUID: Set<Int>] = [:]
        var deltaTotalsBySession: [UUID: Int] = [:]
        var eventsBySession: [UUID: [FactoryToolsBackup.Event]] = [:]
        for event in backup.events {
            guard sequencesBySession[event.sessionID, default: []].insert(event.sequence).inserted else {
                throw FactoryToolsBackupError.duplicateSequence
            }
            let (newTotal, overflow) = (deltaTotalsBySession[event.sessionID] ?? 0).addingReportingOverflow(event.delta)
            guard !overflow else {
                throw FactoryToolsBackupError.invalidStoredValue
            }
            deltaTotalsBySession[event.sessionID] = newTotal
            eventsBySession[event.sessionID, default: []].append(event)
        }
        for session in backup.sessions {
            if let latestSequence = sequencesBySession[session.id]?.max(),
               session.nextEventSequence <= latestSequence {
                throw FactoryToolsBackupError.invalidStoredValue
            }
            let (initialCount, overflow) = session.currentCount.subtractingReportingOverflow(
                deltaTotalsBySession[session.id] ?? 0
            )
            guard !overflow, initialCount >= 0 else { throw FactoryToolsBackupError.invalidStoredValue }

            var runningCount = initialCount
            for event in (eventsBySession[session.id] ?? []).sorted(by: { $0.sequence < $1.sequence }) {
                if event.kindRawValue.flatMap(CounterEventKind.init(rawValue:)) == .reset,
                   event.delta != -runningCount {
                    throw FactoryToolsBackupError.invalidStoredValue
                }
                let (updatedCount, additionOverflow) = runningCount.addingReportingOverflow(event.delta)
                guard !additionOverflow, updatedCount >= 0 else {
                    throw FactoryToolsBackupError.invalidStoredValue
                }
                runningCount = updatedCount
            }
            guard runningCount == session.currentCount else {
                throw FactoryToolsBackupError.invalidStoredValue
            }
        }
        let eventsByID = Dictionary(uniqueKeysWithValues: backup.events.map { ($0.id, $0) })
        var reversedEventIDs = Set<UUID>()
        for event in backup.events {
            guard let reversedID = event.reversesEventID else { continue }
            guard let original = eventsByID[reversedID],
                  original.sessionID == event.sessionID,
                  original.sequence < event.sequence,
                  original.reversesEventID == nil,
                  reversedEventIDs.insert(original.id).inserted,
                  event.delta == -original.delta else {
                throw FactoryToolsBackupError.invalidRelationship
            }
        }
        for sessionEvents in eventsBySession.values {
            var undoableEventIDs: [UUID] = []
            for event in sessionEvents.sorted(by: { $0.sequence < $1.sequence }) {
                if let reversedID = event.reversesEventID {
                    guard undoableEventIDs.last == reversedID else {
                        throw FactoryToolsBackupError.invalidRelationship
                    }
                    undoableEventIDs.removeLast()
                } else {
                    undoableEventIDs.append(event.id)
                }
            }
        }
    }

    static func validateRecordCounts(_ counts: [Int], maximumRecordCount: Int) throws {
        guard maximumRecordCount >= 0 else { throw FactoryToolsBackupError.backupTooLarge }
        var totalRecordCount = 0
        for count in counts {
            guard count >= 0 else { throw FactoryToolsBackupError.backupTooLarge }
            let (updatedTotal, overflow) = totalRecordCount.addingReportingOverflow(count)
            guard !overflow, updatedTotal <= maximumRecordCount else {
                throw FactoryToolsBackupError.backupTooLarge
            }
            totalRecordCount = updatedTotal
        }
    }

    private static func hasUniqueIDs<Value>(_ values: [Value], id: (Value) -> UUID) -> Bool {
        let identifiers = values.map(id)
        return identifiers.count == Set(identifiers).count
    }

    func makeJSON(exportedAt: Date = .now) throws -> Data {
        try Self.validateRecordCounts(
            [
                try modelContext.fetchCount(FetchDescriptor<HomeProfile>()),
                try modelContext.fetchCount(FetchDescriptor<ToolCard>()),
                try modelContext.fetchCount(FetchDescriptor<ProductionSession>()),
                try modelContext.fetchCount(FetchDescriptor<CountEvent>()),
                try modelContext.fetchCount(FetchDescriptor<CounterCommandReceipt>()),
                try modelContext.fetchCount(FetchDescriptor<CycleTimeSample>()),
                try modelContext.fetchCount(FetchDescriptor<OEERun>()),
                try modelContext.fetchCount(FetchDescriptor<AppSettings>())
            ],
            maximumRecordCount: Self.maximumBackupRecordCount
        )
        let homes = try modelContext.fetch(FetchDescriptor<HomeProfile>())
            .sorted { first, second in
                if first.sortOrder != second.sortOrder { return first.sortOrder < second.sortOrder }
                return first.id.uuidString < second.id.uuidString
            }
        let cards = try modelContext.fetch(FetchDescriptor<ToolCard>())
            .sorted { first, second in
                if first.homeProfileID != second.homeProfileID {
                    return first.homeProfileID.uuidString < second.homeProfileID.uuidString
                }
                if first.sortOrder != second.sortOrder { return first.sortOrder < second.sortOrder }
                return first.id.uuidString < second.id.uuidString
            }
        let sessions = try modelContext.fetch(FetchDescriptor<ProductionSession>())
            .sorted { first, second in
                if first.homeProfileID != second.homeProfileID {
                    return (first.homeProfileID?.uuidString ?? "") < (second.homeProfileID?.uuidString ?? "")
                }
                if first.startedAt != second.startedAt { return first.startedAt < second.startedAt }
                return first.id.uuidString < second.id.uuidString
            }
        let events = try modelContext.fetch(FetchDescriptor<CountEvent>())
            .sorted { first, second in
                if first.sessionID != second.sessionID {
                    return first.sessionID.uuidString < second.sessionID.uuidString
                }
                if first.sequence != second.sequence { return first.sequence < second.sequence }
                return first.id.uuidString < second.id.uuidString
            }
        let commandReceipts = try modelContext.fetch(FetchDescriptor<CounterCommandReceipt>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let samples = try modelContext.fetch(FetchDescriptor<CycleTimeSample>())
            .sorted { first, second in
                if first.homeProfileID != second.homeProfileID {
                    return first.homeProfileID.uuidString < second.homeProfileID.uuidString
                }
                if first.createdAt != second.createdAt { return first.createdAt < second.createdAt }
                return first.id.uuidString < second.id.uuidString
            }
        let oeeRuns = try modelContext.fetch(FetchDescriptor<OEERun>())
            .sorted { first, second in
                if first.homeProfileID != second.homeProfileID {
                    return first.homeProfileID.uuidString < second.homeProfileID.uuidString
                }
                if first.createdAt != second.createdAt { return first.createdAt < second.createdAt }
                return first.id.uuidString < second.id.uuidString
            }
        let settings = try modelContext.fetch(FetchDescriptor<AppSettings>())
            .sorted { $0.id.uuidString < $1.id.uuidString }

        let backup = FactoryToolsBackup(
            schemaVersion: 4,
            exportedAt: exportedAt,
            homes: homes.map(FactoryToolsBackup.Home.init),
            cards: cards.map { card in
                FactoryToolsBackup.Card(
                    card,
                    resolvedProductionSessionID: sessions.first(where: { $0.id == card.productionSessionID })?.id
                        ?? ToolSessionAssignment.session(for: card, in: sessions)?.id
                )
            },
            sessions: sessions.map(FactoryToolsBackup.Session.init),
            events: events.map(FactoryToolsBackup.Event.init),
            commandReceipts: commandReceipts.map(FactoryToolsBackup.CommandReceipt.init),
            cycleTimeSamples: samples.map(FactoryToolsBackup.CycleSample.init),
            oeeRuns: oeeRuns.map(FactoryToolsBackup.OEERecord.init),
            settings: settings.map(FactoryToolsBackup.Settings.init)
        )
        try Self.validate(backup)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(backup)
        try Self.validateBackupByteCount(data.count, maximumSizeInBytes: Self.maximumBackupSizeInBytes)
        return data
    }
}

@MainActor
struct FactoryToolsBackupImportService {
    let modelContext: ModelContext

    func addCopy(
        from backup: FactoryToolsBackup,
        importedHomeSuffix: String,
        defaultHomeName: String,
        isPro: Bool = false
    ) throws -> FactoryToolsBackupImportResult {
        try FactoryToolsBackupService.validate(backup)

        let existingHomes = try modelContext.fetch(FetchDescriptor<HomeProfile>())
        let existingSettings = try modelContext.fetch(FetchDescriptor<AppSettings>())
        let existingCards = try modelContext.fetch(FetchDescriptor<ToolCard>())
        let existingSessions = try modelContext.fetch(FetchDescriptor<ProductionSession>())
        let existingEvents = try modelContext.fetch(FetchDescriptor<CountEvent>())
        let existingCommandReceipts = try modelContext.fetch(FetchDescriptor<CounterCommandReceipt>())
        let existingSamples = try modelContext.fetch(FetchDescriptor<CycleTimeSample>())
        let existingOEERuns = try modelContext.fetch(FetchDescriptor<OEERun>())

        let homeIDMap = remappedIDs(backup.homes.map(\.id), occupied: Set(existingHomes.map(\.id)))
        let cardIDMap = remappedIDs(backup.cards.map(\.id), occupied: Set(existingCards.map(\.id)))
        let sessionIDMap = remappedIDs(backup.sessions.map(\.id), occupied: Set(existingSessions.map(\.id)))
        let occupiedCommandIDs = Set(existingEvents.map(\.id)).union(existingCommandReceipts.map(\.id))
        let eventIDMap = remappedIDs(backup.events.map(\.id), occupied: occupiedCommandIDs)
        let receiptIDMap = remappedIDs(backup.commandReceipts.map(\.id), occupied: occupiedCommandIDs.union(eventIDMap.values))
        let sampleIDMap = remappedIDs(backup.cycleTimeSamples.map(\.id), occupied: Set(existingSamples.map(\.id)))
        let oeeRunIDMap = remappedIDs(backup.oeeRuns.map(\.id), occupied: Set(existingOEERuns.map(\.id)))
        let homeOrder = HomeProfileOrdering.ordered(existingHomes)
        let previousHomeSortOrders = Dictionary(uniqueKeysWithValues: existingHomes.map { ($0.id, $0.sortOrder) })
        let previousSelectedHomeID = AppSettingsOrdering.primary(in: existingSettings)?.selectedHomeProfileID
        var inferredSessionHomes: [UUID: UUID] = [:]
        var inferredSessionTools: [UUID: String] = [:]
        for card in backup.cards {
            guard let sessionID = card.productionSessionID,
                  let cardToolID = ToolID(rawValue: card.toolID),
                  let sessionToolID = ToolSessionAssignment.sessionToolID(for: cardToolID) else { continue }
            inferredSessionHomes[sessionID] = card.homeProfileID
            inferredSessionTools[sessionID] = sessionToolID.rawValue
        }

        let orderedSourceHomes = backup.homes.sorted { first, second in
            if first.sortOrder != second.sortOrder { return first.sortOrder < second.sortOrder }
            return first.id.uuidString < second.id.uuidString
        }
        let importedHomes = try orderedSourceHomes.enumerated().map { index, value in
            HomeProfile(
                id: try mappedID(value.id, using: homeIDMap),
                name: "\(value.usesDefaultName ? defaultHomeName : value.name)\(importedHomeSuffix)",
                usesDefaultName: false,
                sortOrder: isPro ? homeOrder.count + index : index,
                createdAt: value.createdAt
            )
        }
        let importedSessions = try backup.sessions.map { value in
            ProductionSession(
                id: try mappedID(value.id, using: sessionIDMap),
                homeProfileID: try mappedOptionalID(value.homeProfileID ?? inferredSessionHomes[value.id], using: homeIDMap),
                toolID: value.toolID ?? inferredSessionTools[value.id],
                name: value.name,
                currentCount: value.currentCount,
                targetCount: value.targetCount,
                nextEventSequence: value.nextEventSequence,
                startedAt: value.startedAt
            )
        }
        let importedCards = try backup.cards.map { value -> ToolCard in
            guard let toolID = ToolID(rawValue: value.toolID) else {
                throw FactoryToolsBackupError.invalidRelationship
            }
            let homeID = try mappedID(value.homeProfileID, using: homeIDMap)
            let linkedSessionID = try mappedOptionalID(value.productionSessionID, using: sessionIDMap)
            let card = ToolCard(
                id: try mappedID(value.id, using: cardIDMap),
                homeProfileID: homeID,
                toolID: toolID,
                size: ToolCardSize(rawValue: value.sizeRawValue) ?? .medium,
                sortOrder: value.sortOrder,
                showsOnWatch: value.showsOnWatch,
                productionSessionID: linkedSessionID
            )
            card.sizeRawValue = value.sizeRawValue
            return card
        }
        let importedCardsByID = Dictionary(uniqueKeysWithValues: importedCards.map { ($0.id, $0) })
        for sourceHome in backup.homes {
            let sourceCards = backup.cards
                .filter { $0.homeProfileID == sourceHome.id }
                .sorted { first, second in
                    if first.sortOrder != second.sortOrder { return first.sortOrder < second.sortOrder }
                    return first.id.uuidString < second.id.uuidString
                }
            for (sortOrder, sourceCard) in sourceCards.enumerated() {
                let importedCardID = try mappedID(sourceCard.id, using: cardIDMap)
                guard let importedCard = importedCardsByID[importedCardID] else {
                    throw FactoryToolsBackupError.invalidRelationship
                }
                importedCard.sortOrder = sortOrder
            }
        }

        let importedEvents = try backup.events.map { value in
            let event = CountEvent(
                id: try mappedID(value.id, using: eventIDMap),
                sessionID: try mappedID(value.sessionID, using: sessionIDMap),
                delta: value.delta,
                sequence: value.sequence,
                occurredAt: value.occurredAt,
                reversesEventID: try mappedOptionalID(value.reversesEventID, using: eventIDMap),
                kind: value.kindRawValue.flatMap(CounterEventKind.init(rawValue:)),
                payloadSignature: value.payloadSignature
            )
            event.kindRawValue = value.kindRawValue
            return event
        }
        let importedCommandReceipts = try backup.commandReceipts.map { value in
            CounterCommandReceipt(
                id: try mappedID(value.id, using: receiptIDMap),
                sessionID: try mappedID(value.sessionID, using: sessionIDMap),
                processedAt: value.processedAt,
                payloadSignature: value.payloadSignature
            )
        }
        let importedSamples = try backup.cycleTimeSamples.map { value in
            CycleTimeSample(
                id: try mappedID(value.id, using: sampleIDMap),
                homeProfileID: try mappedID(value.homeProfileID, using: homeIDMap),
                totalSeconds: value.totalSeconds,
                quantity: value.quantity,
                createdAt: value.createdAt
            )
        }
        let importedOEERuns = try backup.oeeRuns.map { value in
            OEERun(
                id: try mappedID(value.id, using: oeeRunIDMap),
                homeProfileID: try mappedID(value.homeProfileID, using: homeIDMap),
                plannedProductionMinutes: value.plannedProductionMinutes,
                downtimeMinutes: value.downtimeMinutes,
                idealCycleTimeSeconds: value.idealCycleTimeSeconds,
                goodUnits: value.goodUnits,
                defectiveUnits: value.defectiveUnits,
                createdAt: value.createdAt
            )
        }

        do {
            if !isPro, let firstImportedHome = importedHomes.first,
               let primarySettings = AppSettingsOrdering.primary(in: existingSettings) {
                primarySettings.selectedHomeProfileID = firstImportedHome.id
            }
            importedHomes.forEach(modelContext.insert)
            importedSessions.forEach(modelContext.insert)
            importedCards.forEach(modelContext.insert)
            importedEvents.forEach(modelContext.insert)
            importedCommandReceipts.forEach(modelContext.insert)
            importedSamples.forEach(modelContext.insert)
            importedOEERuns.forEach(modelContext.insert)
            HomeProfileOrdering.assignSortOrders(isPro ? homeOrder + importedHomes : importedHomes + homeOrder)
            try modelContext.save()
        } catch {
            for importedRecord in importedHomes { modelContext.delete(importedRecord) }
            for importedRecord in importedSessions { modelContext.delete(importedRecord) }
            for importedRecord in importedCards { modelContext.delete(importedRecord) }
            for importedRecord in importedEvents { modelContext.delete(importedRecord) }
            for importedRecord in importedCommandReceipts { modelContext.delete(importedRecord) }
            for importedRecord in importedSamples { modelContext.delete(importedRecord) }
            for importedRecord in importedOEERuns { modelContext.delete(importedRecord) }
            modelContext.rollback()
            for existingHome in existingHomes {
                existingHome.sortOrder = previousHomeSortOrders[existingHome.id] ?? existingHome.sortOrder
            }
            if let primarySettings = AppSettingsOrdering.primary(in: existingSettings) {
                primarySettings.selectedHomeProfileID = previousSelectedHomeID
            }
            throw error
        }

        return FactoryToolsBackupImportResult(
            homes: importedHomes.count,
            cards: importedCards.count,
            sessions: importedSessions.count,
            events: importedEvents.count,
            commandReceipts: importedCommandReceipts.count,
            cycleTimeSamples: importedSamples.count,
            oeeRuns: importedOEERuns.count
        )
    }

    private func remappedIDs(_ identifiers: [UUID], occupied: Set<UUID>) -> [UUID: UUID] {
        var used = occupied
        var mapping: [UUID: UUID] = [:]
        for identifier in identifiers {
            var destination = UUID()
            while used.contains(destination) { destination = UUID() }
            used.insert(destination)
            mapping[identifier] = destination
        }
        return mapping
    }

    private func mappedID(_ sourceID: UUID, using mapping: [UUID: UUID]) throws -> UUID {
        guard let mappedID = mapping[sourceID] else { throw FactoryToolsBackupError.invalidRelationship }
        return mappedID
    }

    private func mappedOptionalID(_ sourceID: UUID?, using mapping: [UUID: UUID]) throws -> UUID? {
        guard let sourceID else { return nil }
        return try mappedID(sourceID, using: mapping)
    }
}
