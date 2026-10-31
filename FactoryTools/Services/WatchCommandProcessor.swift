import FactoryToolsCore
import Foundation
import SwiftData

struct WatchCommandProcessingResult {
    let acknowledgement: CounterCommandAcknowledgement
    let session: WatchCounterSessionSnapshot?
}

@MainActor
struct WatchCommandProcessor {
    let modelContext: ModelContext

    func catalog(isPro: Bool = false) throws -> WatchCounterCatalog {
        try makeCatalog(includeCardsHiddenFromWatch: false, feature: .watchCounterControl, isPro: isPro)
    }

    func peerCatalog(isPro: Bool = false) throws -> WatchCounterCatalog {
        try makeCatalog(includeCardsHiddenFromWatch: true, feature: .ipadCounterControl, isPro: isPro)
    }

    private func makeCatalog(
        includeCardsHiddenFromWatch: Bool,
        feature: FactoryFeature,
        isPro: Bool
    ) throws -> WatchCounterCatalog {
        let settings = try modelContext.fetch(FetchDescriptor<AppSettings>())
        let displayLanguage = AppSettingsOrdering.primary(in: settings)
            .map { WatchDisplayLanguage(rawValue: $0.language) ?? .system } ?? .system
        guard FeatureAccessRegistry.allows(feature, isPro: isPro) else {
            return try WatchCounterCatalog(sessions: [], displayLanguage: displayLanguage)
        }
        let homes = try modelContext.fetch(FetchDescriptor<HomeProfile>())
        let selectedID = AppSettingsOrdering.primary(in: settings)?.selectedHomeProfileID
        guard let home = HomeProfileAccess.selectedHome(from: homes, selectedID: selectedID, isPro: isPro) else {
            return try WatchCounterCatalog(sessions: [], displayLanguage: displayLanguage)
        }

        let homeID = home.id
        let includeAllCards = includeCardsHiddenFromWatch
        let cards = try modelContext.fetch(FetchDescriptor<ToolCard>(
            predicate: #Predicate<ToolCard> { $0.homeProfileID == homeID && (includeAllCards || $0.showsOnWatch) }
        )).sorted { $0.sortOrder < $1.sortOrder }
        let sessions = try modelContext.fetch(FetchDescriptor<ProductionSession>())
        var sessionByID: [UUID: ProductionSession] = [:]
        for session in sessions where sessionByID[session.id] == nil {
            sessionByID[session.id] = session
        }
        var seenSessionIDs = Set<UUID>()
        var snapshots: [WatchCounterSessionSnapshot] = []
        var progressCards: [WatchProductionProgressSnapshot] = []

        for card in cards {
            guard let toolID = ToolID(rawValue: card.toolID),
                  let definition = ToolRegistry.definition(for: toolID),
                  definition.isAvailable,
                  FeatureAccessRegistry.allows(definition.accessTier, isPro: isPro),
                  let sessionID = card.productionSessionID,
                  let session = sessionByID[sessionID],
                  session.homeProfileID == home.id else { continue }

            if toolID == .productionProgress {
                guard !includeCardsHiddenFromWatch,
                      FeatureAccessRegistry.allows(.additionalWatchTools, isPro: isPro),
                      session.toolID == ToolID.productionCounter.rawValue else { continue }
                progressCards.append(WatchProductionProgressSnapshot(
                    cardID: card.id,
                    sessionID: session.id,
                    homeProfileID: home.id,
                    homeName: home.name,
                    currentCount: session.currentCount,
                    targetCount: session.targetCount,
                    homeNameIsDefault: home.usesDefaultName ? true : nil
                ))
                continue
            }

            guard [.productionCounter, .defectCounter].contains(toolID),
                  seenSessionIDs.insert(sessionID).inserted,
                  session.toolID == toolID.rawValue else { continue }
            let latestUndoableEventID = CounterHistoryOrdering.latestUndoableEvent(in: try CounterService(modelContext: modelContext).events(for: session))?.id
            snapshots.append(WatchCounterSessionSnapshot(
                sessionID: session.id,
                homeProfileID: home.id,
                homeName: home.name,
                toolID: toolID,
                sessionName: session.name,
                currentCount: session.currentCount,
                targetCount: session.targetCount,
                latestUndoableEventID: latestUndoableEventID,
                defaultSessionNameToolID: defaultSessionNameToolID(session, toolID: toolID),
                homeNameIsDefault: home.usesDefaultName ? true : nil
            ))
        }
        let cycleTimeHome: WatchCycleTimeHomeSnapshot?
        if includeCardsHiddenFromWatch || !FeatureAccessRegistry.allows(.watchCounterControl, isPro: isPro) {
            cycleTimeHome = nil
        } else if cards.contains(where: { $0.toolID == ToolID.cycleTime.rawValue && $0.showsOnWatch }) {
            cycleTimeHome = WatchCycleTimeHomeSnapshot(
                homeProfileID: home.id,
                homeName: home.name,
                homeNameIsDefault: home.usesDefaultName ? true : nil
            )
        } else {
            cycleTimeHome = nil
        }
        return try WatchCounterCatalog(
            sessions: snapshots,
            cycleTimeHome: cycleTimeHome,
            progressCards: progressCards,
            displayLanguage: displayLanguage
        )
    }

    func process(_ command: WatchCycleTimeCommand, isPro: Bool = false) throws -> WatchCycleTimeAcknowledgement {
        let commandID = command.id
        var sampleDescriptor = FetchDescriptor<CycleTimeSample>(
            predicate: #Predicate<CycleTimeSample> { $0.id == commandID }
        )
        sampleDescriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(sampleDescriptor).first {
            let matches = existing.homeProfileID == command.homeProfileID
                && existing.totalSeconds == command.totalSeconds
                && existing.quantity == 1
                && existing.createdAt == command.createdAt
            return WatchCycleTimeAcknowledgement(
                commandID: command.id,
                status: matches ? .alreadyApplied : .rejected
            )
        }

        guard FeatureAccessRegistry.allows(.watchCounterControl, isPro: isPro),
              try hasAuthorizedCycleTimeCard(homeID: command.homeProfileID, isPro: isPro) else {
            return WatchCycleTimeAcknowledgement(commandID: command.id, status: .rejected)
        }

        do {
            try CycleTimeSampleService(modelContext: modelContext).save(
                totalSeconds: command.totalSeconds,
                quantity: 1,
                for: command.homeProfileID,
                createdAt: command.createdAt,
                id: command.id
            )
            return WatchCycleTimeAcknowledgement(commandID: command.id, status: .applied)
        } catch CycleTimeSampleServiceError.invalidInput,
                CycleTimeSampleServiceError.homeNotFound,
                CycleTimeSampleServiceError.invalidTimestamp {
            return WatchCycleTimeAcknowledgement(commandID: command.id, status: .rejected)
        }
    }

    private func hasAuthorizedCycleTimeCard(homeID: UUID, isPro: Bool) throws -> Bool {
        let homes = try modelContext.fetch(FetchDescriptor<HomeProfile>())
        guard HomeProfileAccess.canAccess(homeID, in: homes, isPro: isPro) else { return false }
        let toolID = ToolID.cycleTime.rawValue
        return try modelContext.fetch(FetchDescriptor<ToolCard>(
            predicate: #Predicate<ToolCard> { $0.homeProfileID == homeID && $0.toolID == toolID && $0.showsOnWatch }
        )).contains(where: { $0.toolID == toolID })
    }

    func process(
        _ command: CounterCommand,
        allowNonWatchSessions: Bool = false,
        isPro: Bool = false
    ) throws -> WatchCommandProcessingResult {
        let feature: FactoryFeature = allowNonWatchSessions ? .ipadCounterControl : .watchCounterControl
        guard FeatureAccessRegistry.allows(feature, isPro: isPro),
              let session = try findAuthorizedSession(
                id: command.sessionID,
                allowNonWatchSessions: allowNonWatchSessions,
                isPro: isPro
              ) else {
            return WatchCommandProcessingResult(
                acknowledgement: CounterCommandAcknowledgement(commandID: command.id, status: .rejected),
                session: nil
            )
        }

        let status: CounterCommandAcknowledgementStatus
        do {
            switch try CounterService(modelContext: modelContext).apply(command, to: session) {
            case .applied:
                status = .applied
            case .alreadyApplied:
                status = .alreadyApplied
            case .noChange:
                status = .noChange
            }
        } catch is CounterServiceError {
            status = .rejected
        }

        return WatchCommandProcessingResult(
            acknowledgement: CounterCommandAcknowledgement(commandID: command.id, status: status),
            session: try snapshot(for: session)
        )
    }

    private func findAuthorizedSession(id: UUID, allowNonWatchSessions: Bool, isPro: Bool) throws -> ProductionSession? {
        if allowNonWatchSessions {
            return try findPeerSession(id: id, isPro: isPro)
        }
        guard try catalog(isPro: isPro).sessions.contains(where: { $0.sessionID == id }) else { return nil }
        let sessionID = id
        var descriptor = FetchDescriptor<ProductionSession>(
            predicate: #Predicate<ProductionSession> { $0.id == sessionID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func findPeerSession(id: UUID, isPro: Bool) throws -> ProductionSession? {
        let sessionID = id
        var sessionDescriptor = FetchDescriptor<ProductionSession>(
            predicate: #Predicate<ProductionSession> { $0.id == sessionID }
        )
        sessionDescriptor.fetchLimit = 1
        let homes = try modelContext.fetch(FetchDescriptor<HomeProfile>())
        guard let session = try modelContext.fetch(sessionDescriptor).first,
              let homeID = session.homeProfileID,
              let toolID = session.toolID.flatMap({ ToolID(rawValue: $0) }),
              [.productionCounter, .defectCounter].contains(toolID),
              HomeProfileAccess.canAccess(homeID, in: homes, isPro: isPro) else {
            return nil
        }

        let sessionToolID = toolID.rawValue
        let authorizedCardExists = try modelContext.fetch(FetchDescriptor<ToolCard>(
            predicate: #Predicate<ToolCard> {
                $0.productionSessionID == sessionID
                    && $0.homeProfileID == homeID
                    && $0.toolID == sessionToolID
            }
        )).contains(where: { card in
            guard let cardToolID = ToolID(rawValue: card.toolID) else { return false }
            return cardToolID == toolID
        })
        return authorizedCardExists ? session : nil
    }

    private func snapshot(for session: ProductionSession) throws -> WatchCounterSessionSnapshot? {
        guard let homeID = session.homeProfileID,
              let toolID = session.toolID.flatMap({ ToolID(rawValue: $0) }),
              [.productionCounter, .defectCounter].contains(toolID) else { return nil }
        let selectedHomeID = homeID
        var descriptor = FetchDescriptor<HomeProfile>(predicate: #Predicate<HomeProfile> { $0.id == selectedHomeID })
        descriptor.fetchLimit = 1
        guard let home = try modelContext.fetch(descriptor).first else { return nil }
        let latestUndoableEventID = CounterHistoryOrdering.latestUndoableEvent(in: try CounterService(modelContext: modelContext).events(for: session))?.id
        return WatchCounterSessionSnapshot(
            sessionID: session.id,
            homeProfileID: home.id,
            homeName: home.name,
            toolID: toolID,
            sessionName: session.name,
            currentCount: session.currentCount,
            targetCount: session.targetCount,
            latestUndoableEventID: latestUndoableEventID,
            defaultSessionNameToolID: defaultSessionNameToolID(session, toolID: toolID),
            homeNameIsDefault: home.usesDefaultName ? true : nil
        )
    }

    private func defaultSessionNameToolID(_ session: ProductionSession, toolID: ToolID) -> ToolID? {
        guard let definition = ToolRegistry.definition(for: toolID),
              let sessionPolicy = definition.sessionPolicy else { return nil }
        let knownDefaultNames = ["ja", "en"].map { languageCode in
            String(localized: LocalizedStringResource(
                String.LocalizationValue(stringLiteral: sessionPolicy.defaultSessionNameKey),
                locale: Locale(identifier: languageCode)
            ))
        }
        return knownDefaultNames.contains(session.name) ? toolID : nil
    }
}
