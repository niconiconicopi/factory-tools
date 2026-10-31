import FactoryToolsCore
import Foundation
import SwiftData

@MainActor
struct CounterService {
    let modelContext: ModelContext

    func increment(session: ProductionSession) throws {
        let command = CounterCommand(sessionID: session.id, operation: .increment)
        _ = try apply(command, to: session)
    }

    func decrement(session: ProductionSession) throws {
        let command = CounterCommand(sessionID: session.id, operation: .decrement)
        _ = try apply(command, to: session)
    }

    func quickAdd(_ amount: Int, to session: ProductionSession) throws {
        let command = CounterCommand(sessionID: session.id, operation: .quickAdd(amount))
        _ = try apply(command, to: session)
    }

    func reset(session: ProductionSession) throws {
        let command = CounterCommand(sessionID: session.id, operation: .reset)
        _ = try apply(command, to: session)
    }

    func undo(session: ProductionSession) throws {
        guard let latest = CounterHistoryOrdering.latestUndoableEvent(in: try events(for: session)) else { return }

        let command = CounterCommand(sessionID: session.id, operation: .undo(eventID: latest.id))
        _ = try apply(command, to: session)
    }

    @discardableResult
    func apply(_ command: CounterCommand, to session: ProductionSession) throws -> CounterCommandApplyResult {
        guard command.sessionID == session.id else { throw CounterServiceError.sessionMismatch }
        if let existingReceipt = try receipt(withID: command.id) {
            guard try event(withID: command.id) == nil else {
                throw CounterServiceError.commandIdentifierConflict
            }
            guard existingReceipt.sessionID == session.id else {
                throw CounterServiceError.commandIdentifierConflict
            }
            try validate(existingReceipt.payloadSignature, matches: command)
            return .alreadyApplied
        }
        if let existingEvent = try event(withID: command.id) {
            guard existingEvent.sessionID == session.id else {
                throw CounterServiceError.commandIdentifierConflict
            }
            try validate(existingEvent.payloadSignature, matches: command)
            return .alreadyApplied
        }
        guard PersistedTimestamp.isSupported(command.createdAt) else {
            throw CounterServiceError.invalidTimestamp
        }
        if case .setTarget(let target) = command.operation {
            return try applyTarget(target, command: command, to: session)
        }

        let delta: Int
        let kind: CounterEventKind
        let reversedEventID: UUID?
        switch command.operation {
        case .increment:
            delta = 1
            kind = .increment
            reversedEventID = nil
        case .decrement:
            delta = -1
            kind = .decrement
            reversedEventID = nil
        case .quickAdd(let amount):
            guard amount > 0 else { return try recordNoChange(command, to: session) }
            delta = amount
            kind = .quickAdd
            reversedEventID = nil
        case .reset:
            guard session.currentCount > 0 else { return try recordNoChange(command, to: session) }
            delta = -session.currentCount
            kind = .reset
            reversedEventID = nil
        case .undo(let eventID):
            let events = try events(for: session)
            guard let original = CounterHistoryOrdering.latestUndoableEvent(in: events), original.id == eventID else {
                return try recordNoChange(command, to: session)
            }
            guard original.delta != Int.min else { throw CounterServiceError.eventDeltaCannotBeReversed }
            delta = -original.delta
            kind = .undo
            reversedEventID = original.id
        case .setTarget:
            throw CounterServiceError.invalidTarget
        }

        return try record(
            delta,
            kind: kind,
            reversing: reversedEventID,
            command: command,
            to: session
        )
    }

    private func applyTarget(
        _ target: Int,
        command: CounterCommand,
        to session: ProductionSession
    ) throws -> CounterCommandApplyResult {
        guard target >= 0 else { throw CounterServiceError.invalidTarget }
        guard session.targetCount != target else { return try recordNoChange(command, to: session) }
        let previousTarget = session.targetCount
        let receipt = CounterCommandReceipt(
            id: command.id,
            sessionID: session.id,
            processedAt: .now,
            payloadSignature: command.payloadSignature
        )
        session.targetCount = target
        modelContext.insert(receipt)
        do {
            try modelContext.save()
            WatchConnectivityReceiver.shared.publishCatalog()
            LocalPeerCounterTransport.shared.publishCatalog()
        } catch {
            modelContext.rollback()
            modelContext.delete(receipt)
            session.targetCount = previousTarget
            throw error
        }
        return .applied
    }

    func setTarget(_ target: Int, for session: ProductionSession) throws {
        let previousTarget = session.targetCount
        let updatedTarget = max(0, target)
        guard previousTarget != updatedTarget else { return }
        session.targetCount = updatedTarget
        do {
            try modelContext.save()
            WatchConnectivityReceiver.shared.publishCatalog()
            LocalPeerCounterTransport.shared.publishCatalog()
        } catch {
            modelContext.rollback()
            session.targetCount = previousTarget
            throw error
        }
    }

    private func record(
        _ delta: Int,
        kind: CounterEventKind,
        reversing eventID: UUID?,
        command: CounterCommand,
        to session: ProductionSession
    ) throws -> CounterCommandApplyResult {
        let appliedDelta = boundedDelta(delta, currentCount: session.currentCount)
        guard appliedDelta != 0 else { return try recordNoChange(command, to: session) }
        let previousSequence = session.nextEventSequence
        guard previousSequence < Int.max else { throw CounterServiceError.eventSequenceExhausted }
        let event = CountEvent(
            id: command.id,
            sessionID: session.id,
            delta: appliedDelta,
            sequence: previousSequence,
            occurredAt: command.createdAt,
            reversesEventID: eventID,
            kind: kind,
            payloadSignature: command.payloadSignature
        )
        modelContext.insert(event)
        session.currentCount += appliedDelta
        session.nextEventSequence += 1
        do {
            try modelContext.save()
            WatchConnectivityReceiver.shared.publishCatalog()
            LocalPeerCounterTransport.shared.publishCatalog()
        } catch {
            modelContext.rollback()
            modelContext.delete(event)
            session.currentCount -= appliedDelta
            session.nextEventSequence = previousSequence
            throw error
        }
        return .applied
    }

    private func recordNoChange(
        _ command: CounterCommand,
        to session: ProductionSession
    ) throws -> CounterCommandApplyResult {
        let receipt = CounterCommandReceipt(
            id: command.id,
            sessionID: session.id,
            processedAt: .now,
            payloadSignature: command.payloadSignature
        )
        modelContext.insert(receipt)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            modelContext.delete(receipt)
            throw error
        }
        return .noChange
    }

    private func validate(_ storedSignature: String?, matches command: CounterCommand) throws {
        guard let storedSignature else { return }
        guard storedSignature == command.payloadSignature else {
            throw CounterServiceError.commandIdentifierConflict
        }
    }

    private func boundedDelta(_ delta: Int, currentCount: Int) -> Int {
        guard currentCount >= 0 else { return 0 }
        return delta > 0
            ? min(delta, Int.max - currentCount)
            : max(delta, -currentCount)
    }

    func events(for session: ProductionSession) throws -> [CountEvent] {
        let sessionID = session.id
        let descriptor = FetchDescriptor<CountEvent>(
            predicate: #Predicate<CountEvent> { $0.sessionID == sessionID }
        )
        return try modelContext.fetch(descriptor)
    }

    private func event(withID eventID: UUID) throws -> CountEvent? {
        let selectedEventID = eventID
        var descriptor = FetchDescriptor<CountEvent>(
            predicate: #Predicate<CountEvent> { $0.id == selectedEventID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func receipt(withID commandID: UUID) throws -> CounterCommandReceipt? {
        let selectedCommandID = commandID
        var descriptor = FetchDescriptor<CounterCommandReceipt>(
            predicate: #Predicate<CounterCommandReceipt> { $0.id == selectedCommandID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

enum CounterServiceError: Error, Equatable {
    case eventSequenceExhausted
    case eventDeltaCannotBeReversed
    case sessionMismatch
    case commandIdentifierConflict
    case invalidTimestamp
    case invalidTarget
}

enum CounterHistoryOrdering {
    static func ordered(_ events: [CountEvent]) -> [CountEvent] {
        events.sorted { first, second in
            if first.sequence != second.sequence { return first.sequence > second.sequence }
            if first.occurredAt != second.occurredAt { return first.occurredAt > second.occurredAt }
            return first.id.uuidString > second.id.uuidString
        }
    }

    static func ordered(_ events: [CounterHistoryCSVRecord]) -> [CounterHistoryCSVRecord] {
        events.sorted { first, second in
            if first.sequence != second.sequence { return first.sequence > second.sequence }
            if first.occurredAt != second.occurredAt { return first.occurredAt > second.occurredAt }
            return first.id.uuidString > second.id.uuidString
        }
    }

    static func latestUndoableEvent(in events: [CountEvent]) -> CountEvent? {
        let reversedEventIDs = Set(events.compactMap(\.reversesEventID))
        return events
            .filter { $0.reversesEventID == nil && !reversedEventIDs.contains($0.id) }
            .max(by: { first, second in
                if first.sequence != second.sequence { return first.sequence < second.sequence }
                if first.occurredAt != second.occurredAt { return first.occurredAt < second.occurredAt }
                return first.id.uuidString < second.id.uuidString
            })
    }
}

enum CounterHistoryBalances {
    static func afterEachEvent(events: [CountEvent], currentCount: Int) -> [UUID: Int]? {
        afterEachEvent(
            orderedEvents: CounterHistoryOrdering.ordered(events),
            currentCount: currentCount
        )
    }

    static func afterEachEvent(orderedEvents: [CountEvent], currentCount: Int) -> [UUID: Int]? {
        reconstruct(orderedEvents.map { (id: $0.id, delta: $0.delta) }, currentCount: currentCount)
    }

    static func afterEachEvent(orderedEvents: [CounterHistoryCSVRecord], currentCount: Int) -> [UUID: Int]? {
        reconstruct(orderedEvents.map { (id: $0.id, delta: $0.delta) }, currentCount: currentCount)
    }

    private static func reconstruct(_ events: [(id: UUID, delta: Int)], currentCount: Int) -> [UUID: Int]? {
        guard currentCount >= 0 else { return nil }
        var runningCount = currentCount
        var counts: [UUID: Int] = [:]

        for event in events {
            counts[event.id] = runningCount
            let (previousCount, overflow) = runningCount.subtractingReportingOverflow(event.delta)
            guard !overflow, previousCount >= 0 else { return nil }
            runningCount = previousCount
        }

        return counts
    }
}

struct CounterHistoryCSVRecord: Sendable {
    let id: UUID
    let sessionID: UUID
    let delta: Int
    let sequence: Int
    let occurredAt: Date
    let reversesEventID: UUID?
    let kindRawValue: String?

    init(_ event: CountEvent) {
        id = event.id
        sessionID = event.sessionID
        delta = event.delta
        sequence = event.sequence
        occurredAt = event.occurredAt
        reversesEventID = event.reversesEventID
        kindRawValue = event.kindRawValue
    }
}

enum CounterHistoryCSV {
    static func make(sessionID: UUID, currentCount: Int, events: [CountEvent]) -> String {
        make(sessionID: sessionID, currentCount: currentCount, records: events.map(CounterHistoryCSVRecord.init))
    }

    static func make(sessionID: UUID, currentCount: Int, records: [CounterHistoryCSVRecord]) -> String {
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let sessionEvents = CounterHistoryOrdering.ordered(records.filter { $0.sessionID == sessionID })
        let balances = CounterHistoryBalances.afterEachEvent(orderedEvents: sessionEvents, currentCount: currentCount)
        let header = "session_id,event_id,sequence,timestamp_utc,kind,delta,count_after,reverses_event_id"
        let rows = sessionEvents.reversed().map { event in
            [
                sessionID.uuidString,
                event.id.uuidString,
                String(event.sequence),
                timestampFormatter.string(from: event.occurredAt),
                event.kindRawValue ?? "",
                String(event.delta),
                balances.map { String($0[event.id] ?? currentCount) } ?? "",
                event.reversesEventID?.uuidString ?? ""
            ].enumerated().map { index, value in
                csvField(value, neutralizeFormula: index == 4)
            }.joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\r\n") + "\r\n"
    }

    private static func csvField(_ value: String, neutralizeFormula: Bool) -> String {
        let hasFormulaPrefix = neutralizeFormula && (value.trimmingCharacters(in: .whitespacesAndNewlines)
            .first
            .map { "=+-@".contains($0) } ?? false)
        let safeValue = hasFormulaPrefix ? "'" + value : value
        guard safeValue.contains(",") || safeValue.contains("\"") || safeValue.contains("\r") || safeValue.contains("\n") else {
            return safeValue
        }
        let escapedValue = safeValue.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"" + escapedValue + "\""
    }
}
