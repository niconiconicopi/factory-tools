import FactoryToolsCore
import Foundation
import SwiftData

@MainActor
struct HomeToolService {
    let modelContext: ModelContext

    @discardableResult
    func add(_ tool: ToolDefinition, to homeID: UUID, locale: Locale, isPro: Bool = false) throws -> ToolCard {
        let cards = try addTools([tool.id], to: homeID, locale: locale, skippingExisting: false, isPro: isPro)
        guard let card = cards.first else { throw HomeToolServiceError.unavailableTool }
        return card
    }

    @discardableResult
    func applyAssemblyPreset(to homeID: UUID, locale: Locale, isPro: Bool = false) throws -> [ToolCard] {
        try addTools(AssemblyPreset.toolIDs, to: homeID, locale: locale, skippingExisting: true, isPro: isPro)
    }

    @discardableResult
    func applyPackagingPreset(to homeID: UUID, locale: Locale, isPro: Bool = false) throws -> [ToolCard] {
        try addTools(PackagingPreset.toolIDs, to: homeID, locale: locale, skippingExisting: true, isPro: isPro)
    }

    private func addTools(
        _ toolIDs: [ToolID],
        to homeID: UUID,
        locale: Locale,
        skippingExisting: Bool,
        isPro: Bool
    ) throws -> [ToolCard] {
        let registeredTools = try toolIDs.map { id -> ToolDefinition in
            guard let definition = ToolRegistry.definition(for: id), definition.isAvailable else {
                throw HomeToolServiceError.unavailableTool
            }
            return definition
        }
        let accessibleTools = registeredTools.filter {
            FeatureAccessRegistry.allows($0.accessTier, isPro: isPro)
        }
        guard skippingExisting || accessibleTools.count == registeredTools.count else {
            throw HomeToolServiceError.proRequired
        }
        var homeDescriptor = FetchDescriptor<HomeProfile>()
        homeDescriptor.includePendingChanges = true
        let homes = try modelContext.fetch(homeDescriptor)
        guard homes.contains(where: { $0.id == homeID }) else { throw HomeToolServiceError.homeNotFound }

        var sessions: [ProductionSession] = []
        var existingSessionIDs = Set<UUID>()
        var homeCards: [ToolCard] = []
        var addedCards: [ToolCard] = []
        do {
            var sessionDescriptor = FetchDescriptor<ProductionSession>()
            sessionDescriptor.includePendingChanges = true
            sessions = try modelContext.fetch(sessionDescriptor)
            existingSessionIDs = Set(sessions.map(\.id))
            var cardDescriptor = FetchDescriptor<ToolCard>()
            cardDescriptor.includePendingChanges = true
            let allCards = try modelContext.fetch(cardDescriptor)
            homeCards = HomeCardOrdering.ordered(allCards.filter { $0.homeProfileID == homeID })
            let existingToolIDs = Set(homeCards.compactMap { ToolID(rawValue: $0.toolID) })
            let toolsToAdd = skippingExisting
                ? accessibleTools.filter { !existingToolIDs.contains($0.id) }
                : accessibleTools

            guard !toolsToAdd.isEmpty else { return [] }

            for tool in toolsToAdd {
                let card = makeCard(
                    for: tool,
                    homeID: homeID,
                    sortOrder: homeCards.count,
                    sessions: &sessions,
                    locale: locale
                )
                modelContext.insert(card)
                homeCards.append(card)
                addedCards.append(card)
            }

            HomeCardOrdering.assignSortOrders(homeCards)
            try modelContext.save()
            WatchConnectivityReceiver.shared.publishCatalog()
            LocalPeerCounterTransport.shared.publishCatalog()
            return addedCards
        } catch {
            for card in addedCards { modelContext.delete(card) }
            for session in sessions where !existingSessionIDs.contains(session.id) {
                modelContext.delete(session)
            }
            modelContext.rollback()
            throw error
        }
    }

    private func makeCard(
        for tool: ToolDefinition,
        homeID: UUID,
        sortOrder: Int,
        sessions: inout [ProductionSession],
        locale: Locale
    ) -> ToolCard {
        var productionSession: ProductionSession?
        if let sessionPolicy = tool.sessionPolicy {
            let sessionToolID = sessionPolicy.sessionToolID
            productionSession = ToolSessionAssignment.session(for: homeID, toolID: sessionToolID, in: sessions)
            if productionSession == nil {
                let created = ProductionSession(
                    homeProfileID: homeID,
                    toolID: sessionToolID.rawValue,
                    name: String(localized: LocalizedStringResource(
                        String.LocalizationValue(stringLiteral: sessionPolicy.defaultSessionNameKey),
                        locale: locale
                    )),
                    targetCount: sessionPolicy.defaultTargetCount
                )
                modelContext.insert(created)
                sessions.append(created)
                productionSession = created
            }
        }

        return ToolCard(
            homeProfileID: homeID,
            toolID: tool.id,
            sortOrder: sortOrder,
            showsOnWatch: tool.supportsWatch,
            productionSessionID: productionSession?.id
        )
    }
}

@MainActor
struct HomeCardService {
    let modelContext: ModelContext

    @discardableResult
    func move(_ cardID: UUID, before destinationID: UUID, in homeID: UUID) throws -> Bool {
        let orderedCards = try orderedCards(in: homeID)
        guard let movedCards = HomeCardOrdering.moving(cardID, before: destinationID, in: orderedCards) else { return false }
        HomeCardOrdering.assignSortOrders(movedCards)
        do {
            try saveChanges()
        } catch {
            HomeCardOrdering.assignSortOrders(orderedCards)
            throw error
        }
        return true
    }

    func remove(_ card: ToolCard) throws {
        let orderedCards = try orderedCards(in: card.homeProfileID)
        guard orderedCards.contains(where: { $0.id == card.id }) else { return }
        modelContext.delete(card)
        HomeCardOrdering.assignSortOrders(orderedCards.filter { $0.id != card.id })
        do {
            try saveChanges()
        } catch {
            modelContext.insert(card)
            HomeCardOrdering.assignSortOrders(orderedCards)
            throw error
        }
    }

    func setSize(_ size: ToolCardSize, for card: ToolCard) throws {
        if let toolID = ToolID(rawValue: card.toolID),
           let definition = ToolRegistry.definition(for: toolID),
           !definition.supportedCardSizes.contains(size) {
            throw HomeCardServiceError.unsupportedCardSize
        }
        guard card.size != size else { return }
        let previousSize = card.size
        card.size = size
        do {
            try saveChanges()
        } catch {
            card.size = previousSize
            throw error
        }
    }

    private func orderedCards(in homeID: UUID) throws -> [ToolCard] {
        let selectedHomeID = homeID
        var descriptor = FetchDescriptor<ToolCard>(
            predicate: #Predicate<ToolCard> { $0.homeProfileID == selectedHomeID }
        )
        descriptor.includePendingChanges = true
        return HomeCardOrdering.ordered(try modelContext.fetch(descriptor))
    }

    private func saveChanges() throws {
        do {
            try modelContext.save()
            WatchConnectivityReceiver.shared.publishCatalog()
            LocalPeerCounterTransport.shared.publishCatalog()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

enum HomeCardServiceError: Error {
    case unsupportedCardSize
}

@MainActor
struct HomeProfileService {
    let modelContext: ModelContext

    @discardableResult
    func createHome(named draft: String, isPro: Bool = false) throws -> HomeProfile {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw HomeProfileServiceError.emptyName }
        let homes = try modelContext.fetch(FetchDescriptor<HomeProfile>())
        guard homes.isEmpty || FeatureAccessRegistry.allows(.multipleHomeProfiles, isPro: isPro) else {
            throw HomeProfileServiceError.proRequired
        }
        let settings = try modelContext.fetch(FetchDescriptor<AppSettings>())
        guard let primarySettings = AppSettingsOrdering.primary(in: settings) else {
            throw HomeProfileServiceError.settingsNotFound
        }

        let orderedHomes = HomeProfileOrdering.ordered(homes)
        let previousSortOrders = Dictionary(uniqueKeysWithValues: homes.map { ($0.id, $0.sortOrder) })
        HomeProfileOrdering.assignSortOrders(orderedHomes)
        let home = HomeProfile(name: name, usesDefaultName: false, sortOrder: orderedHomes.count)
        let previousSelection = primarySettings.selectedHomeProfileID
        modelContext.insert(home)
        primarySettings.selectedHomeProfileID = home.id
        do {
            try modelContext.save()
            WatchConnectivityReceiver.shared.publishCatalog()
            LocalPeerCounterTransport.shared.publishCatalog()
            return home
        } catch {
            modelContext.rollback()
            for existingHome in homes {
                if let previousSortOrder = previousSortOrders[existingHome.id] {
                    existingHome.sortOrder = previousSortOrder
                }
            }
            primarySettings.selectedHomeProfileID = previousSelection
            throw error
        }
    }

    func selectHome(_ homeID: UUID, isPro: Bool = false) throws {
        let homes = try modelContext.fetch(FetchDescriptor<HomeProfile>())
        guard homes.contains(where: { $0.id == homeID }) else { throw HomeProfileServiceError.homeNotFound }
        guard HomeProfileAccess.canAccess(homeID, in: homes, isPro: isPro) else {
            throw HomeProfileServiceError.proRequired
        }
        let settings = try modelContext.fetch(FetchDescriptor<AppSettings>())
        guard let primarySettings = AppSettingsOrdering.primary(in: settings) else {
            throw HomeProfileServiceError.settingsNotFound
        }
        let previousSelection = primarySettings.selectedHomeProfileID
        guard previousSelection != homeID else { return }
        primarySettings.selectedHomeProfileID = homeID
        do {
            try modelContext.save()
            WatchConnectivityReceiver.shared.publishCatalog()
            LocalPeerCounterTransport.shared.publishCatalog()
        } catch {
            primarySettings.selectedHomeProfileID = previousSelection
            throw error
        }
    }

    @discardableResult
    func move(_ homeID: UUID, before destinationID: UUID, isPro: Bool = false) throws -> Bool {
        let homes = HomeProfileOrdering.ordered(try modelContext.fetch(FetchDescriptor<HomeProfile>()))
        guard homes.count <= 1 || FeatureAccessRegistry.allows(.multipleHomeProfiles, isPro: isPro) else {
            throw HomeProfileServiceError.proRequired
        }
        guard let reorderedHomes = HomeProfileOrdering.moving(homeID, before: destinationID, in: homes) else {
            return false
        }
        let previousSortOrders = Dictionary(uniqueKeysWithValues: homes.map { ($0.id, $0.sortOrder) })
        HomeProfileOrdering.assignSortOrders(reorderedHomes)
        do {
            try modelContext.save()
            return true
        } catch {
            for home in homes {
                if let previousSortOrder = previousSortOrders[home.id] {
                    home.sortOrder = previousSortOrder
                }
            }
            throw error
        }
    }

    func setName(_ draft: String, for home: HomeProfile, isPro: Bool = false) throws {
        let homes = try modelContext.fetch(FetchDescriptor<HomeProfile>())
        guard HomeProfileAccess.canAccess(home.id, in: homes, isPro: isPro) else {
            throw HomeProfileServiceError.proRequired
        }
        let previousName = home.name
        let previouslyUsedDefaultName = home.usesDefaultName
        let resolvedName = HomeNameResolution.resolve(draft)
        guard home.name != resolvedName.name || home.usesDefaultName != resolvedName.usesDefaultName else { return }

        home.name = resolvedName.name
        home.usesDefaultName = resolvedName.usesDefaultName
        do {
            try modelContext.save()
            WatchConnectivityReceiver.shared.publishCatalog()
            LocalPeerCounterTransport.shared.publishCatalog()
        } catch {
            home.name = previousName
            home.usesDefaultName = previouslyUsedDefaultName
            throw error
        }
    }

    func deleteHome(_ homeID: UUID) throws {
        let homes = HomeProfileOrdering.ordered(try modelContext.fetch(FetchDescriptor<HomeProfile>()))
        guard let home = homes.first(where: { $0.id == homeID }) else {
            throw HomeProfileServiceError.homeNotFound
        }
        guard homes.count > 1 else { throw HomeProfileServiceError.lastHome }

        let remainingHomes = homes.filter { $0.id != homeID }
        let fallbackHomeID = remainingHomes[0].id
        let allCards = try modelContext.fetch(FetchDescriptor<ToolCard>())
        let cards = allCards.filter { $0.homeProfileID == homeID }
        let removedCardSessionIDs = Set(cards.compactMap(\.productionSessionID))
        let remainingCardSessionIDs = Set(allCards.filter { $0.homeProfileID != homeID }.compactMap(\.productionSessionID))
        let sessions = try modelContext.fetch(FetchDescriptor<ProductionSession>()).filter { session in
            session.homeProfileID == homeID
                || (session.homeProfileID == nil
                    && removedCardSessionIDs.contains(session.id)
                    && !remainingCardSessionIDs.contains(session.id))
        }
        let sessionIDs = Set(sessions.map(\.id))
        let events = try modelContext.fetch(FetchDescriptor<CountEvent>()).filter { sessionIDs.contains($0.sessionID) }
        let commandReceipts = try modelContext.fetch(FetchDescriptor<CounterCommandReceipt>())
            .filter { sessionIDs.contains($0.sessionID) }
        let samples = try modelContext.fetch(FetchDescriptor<CycleTimeSample>()).filter { $0.homeProfileID == homeID }
        let oeeRuns = try modelContext.fetch(FetchDescriptor<OEERun>()).filter { $0.homeProfileID == homeID }
        let settings = try modelContext.fetch(FetchDescriptor<AppSettings>())
        let previouslySelectedHomeIDs = Dictionary(uniqueKeysWithValues: settings.map { ($0.id, $0.selectedHomeProfileID) })
        let previousSortOrders = Dictionary(uniqueKeysWithValues: homes.map { ($0.id, $0.sortOrder) })

        events.forEach(modelContext.delete)
        commandReceipts.forEach(modelContext.delete)
        cards.forEach(modelContext.delete)
        sessions.forEach(modelContext.delete)
        samples.forEach(modelContext.delete)
        oeeRuns.forEach(modelContext.delete)
        settings.forEach { setting in
            if setting.selectedHomeProfileID == homeID {
                setting.selectedHomeProfileID = fallbackHomeID
            }
        }
        modelContext.delete(home)
        HomeProfileOrdering.assignSortOrders(remainingHomes)

        do {
            try modelContext.save()
            WatchConnectivityReceiver.shared.publishCatalog()
            LocalPeerCounterTransport.shared.publishCatalog()
        } catch {
            modelContext.rollback()
            for event in events { modelContext.insert(event) }
            for receipt in commandReceipts { modelContext.insert(receipt) }
            for card in cards { modelContext.insert(card) }
            for session in sessions { modelContext.insert(session) }
            for sample in samples { modelContext.insert(sample) }
            for run in oeeRuns { modelContext.insert(run) }
            modelContext.insert(home)
            for setting in settings {
                setting.selectedHomeProfileID = previouslySelectedHomeIDs[setting.id] ?? nil
            }
            for remainingHome in remainingHomes {
                if let previousSortOrder = previousSortOrders[remainingHome.id] {
                    remainingHome.sortOrder = previousSortOrder
                }
            }
            throw error
        }
    }
}

enum HomeProfileServiceError: Error, Equatable {
    case emptyName
    case proRequired
    case homeNotFound
    case settingsNotFound
    case lastHome
}

enum HomeNameResolution {
    static func resolve(_ draft: String) -> (name: String, usesDefaultName: Bool) {
        let trimmedName = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return ("Production", true) }
        return (trimmedName, false)
    }
}

enum HomeProfileOrdering {
    static func ordered(_ homes: [HomeProfile]) -> [HomeProfile] {
        homes.sorted { first, second in
            if first.sortOrder != second.sortOrder { return first.sortOrder < second.sortOrder }
            return first.id.uuidString < second.id.uuidString
        }
    }

    static func moving(_ homeID: UUID, before destinationID: UUID, in homes: [HomeProfile]) -> [HomeProfile]? {
        guard homeID != destinationID,
              let sourceIndex = homes.firstIndex(where: { $0.id == homeID }),
              let destinationIndex = homes.firstIndex(where: { $0.id == destinationID }) else { return nil }
        var ordered = homes
        let home = ordered.remove(at: sourceIndex)
        let adjustedDestination = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        guard adjustedDestination != sourceIndex else { return nil }
        ordered.insert(home, at: adjustedDestination)
        return ordered
    }

    static func assignSortOrders(_ homes: [HomeProfile]) {
        for (index, home) in homes.enumerated() {
            home.sortOrder = index
        }
    }
}

enum HomeProfileAccess {
    static func accessibleHomes(from homes: [HomeProfile], isPro: Bool) -> [HomeProfile] {
        let ordered = HomeProfileOrdering.ordered(homes)
        guard !FeatureAccessRegistry.allows(.multipleHomeProfiles, isPro: isPro) else { return ordered }
        return Array(ordered.prefix(1))
    }

    static func canAccess(_ homeID: UUID, in homes: [HomeProfile], isPro: Bool) -> Bool {
        accessibleHomes(from: homes, isPro: isPro).contains { $0.id == homeID }
    }

    static func selectedHome(from homes: [HomeProfile], selectedID: UUID?, isPro: Bool) -> HomeProfile? {
        let accessible = accessibleHomes(from: homes, isPro: isPro)
        return accessible.first(where: { $0.id == selectedID }) ?? accessible.first
    }
}

enum HomeToolServiceError: Error, Equatable {
    case unavailableTool
    case proRequired
    case homeNotFound
}

enum ToolSessionAssignment {
    static func sessionToolID(for cardToolID: ToolID) -> ToolID? {
        ToolRegistry.definition(for: cardToolID)?.sessionPolicy?.sessionToolID
    }

    static func session(for homeID: UUID, toolID: ToolID, in sessions: [ProductionSession]) -> ProductionSession? {
        sessions
            .filter { $0.homeProfileID == homeID && $0.toolID == toolID.rawValue }
            .min { first, second in
                if first.startedAt != second.startedAt { return first.startedAt < second.startedAt }
                return first.id.uuidString < second.id.uuidString
            }
    }

    static func session(for card: ToolCard, in sessions: [ProductionSession]) -> ProductionSession? {
        guard let cardToolID = ToolID(rawValue: card.toolID) else { return nil }
        guard let sessionToolID = sessionToolID(for: cardToolID) else { return nil }
        if let sessionID = card.productionSessionID,
           let linked = sessions.first(where: { $0.id == sessionID }),
           linked.homeProfileID == card.homeProfileID,
           linked.toolID == sessionToolID.rawValue {
            return linked
        }
        return session(for: card.homeProfileID, toolID: sessionToolID, in: sessions)
    }
}

enum HomeCardOrdering {
    static func ordered(_ cards: [ToolCard]) -> [ToolCard] {
        cards.sorted { first, second in
            if first.sortOrder != second.sortOrder { return first.sortOrder < second.sortOrder }
            return first.id.uuidString < second.id.uuidString
        }
    }

    static func moving(_ cardID: UUID, before destinationID: UUID, in cards: [ToolCard]) -> [ToolCard]? {
        guard cardID != destinationID,
              let sourceIndex = cards.firstIndex(where: { $0.id == cardID }),
              let destinationIndex = cards.firstIndex(where: { $0.id == destinationID }) else { return nil }
        var ordered = cards
        let card = ordered.remove(at: sourceIndex)
        let adjustedDestination = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        guard adjustedDestination != sourceIndex else { return nil }
        ordered.insert(card, at: adjustedDestination)
        return ordered
    }

    static func assignSortOrders(_ cards: [ToolCard]) {
        for (index, card) in cards.enumerated() {
            card.sortOrder = index
        }
    }
}
