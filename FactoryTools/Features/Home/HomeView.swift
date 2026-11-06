import FactoryToolsCore
import SwiftData
import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var proPurchases: ProPurchaseManager
    @Query private var cards: [ToolCard]
    @Query private var homes: [HomeProfile]
    @Query private var settings: [AppSettings]
    @State private var activeSheet: HomeSheetDestination?
    @State private var showingSaveError = false

    let home: HomeProfile
    let screenshotDemoScenario: ScreenshotDemoScenario?

    init(home: HomeProfile, screenshotDemoScenario: ScreenshotDemoScenario? = nil) {
        self.home = home
        self.screenshotDemoScenario = screenshotDemoScenario
        let selectedHomeID = home.id
        _cards = Query(filter: #Predicate<ToolCard> { $0.homeProfileID == selectedHomeID })
#if targetEnvironment(simulator)
        let startsOnPeerDashboard = UIDevice.current.userInterfaceIdiom == .pad
            && screenshotDemoScenario?.peerCounterScreenshotMode != nil
        _activeSheet = State(initialValue: startsOnPeerDashboard ? .peerCounters : nil)
#endif
    }

    private var homeCards: [ToolCard] {
        HomeCardOrdering.ordered(cards)
    }

    private var canCreateAnotherHome: Bool {
        homes.count == 0 || FeatureAccessRegistry.allows(.multipleHomeProfiles, isPro: proPurchases.hasPro)
    }

    private var gridMinimumWidth: CGFloat {
        HomeGridLayout.minimumColumnWidth(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    private var peerDashboardSheetDetents: Set<PresentationDetent> {
#if targetEnvironment(simulator)
        screenshotDemoScenario?.peerCounterScreenshotMode == nil ? [.medium, .large] : [.large]
#else
        [.medium, .large]
#endif
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let contentWidth = min(geometry.size.width, HomeGridLayout.maximumContentWidth) -
                    HomeGridLayout.horizontalPadding * 2
                let columnCount = HomeGridLayout.columnCount(
                    availableWidth: contentWidth,
                    minimumColumnWidth: gridMinimumWidth,
                    spacing: HomeGridLayout.itemSpacing
                )
                let rows = HomeGridLayout.rows(for: homeCards, columnCount: columnCount)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        homeTitle
                        if homeCards.isEmpty {
                            ContentUnavailableView(
                                "home.empty.title",
                                systemImage: "square.grid.2x2",
                                description: Text("home.empty.message")
                            )
                            .foregroundStyle(theme.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 220)
                        }
                        LazyVStack(spacing: HomeGridLayout.itemSpacing) {
                            ForEach(rows) { row in
                                HStack(alignment: .top, spacing: HomeGridLayout.itemSpacing) {
                                    ForEach(row.cards) { card in
                                        cardView(card)
                                            .frame(maxWidth: .infinity)
                                    }
                                    if !row.isFullWidth {
                                        ForEach(0..<max(0, columnCount - row.cards.count), id: \.self) { _ in
                                            Spacer(minLength: 0)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        Button { activeSheet = .toolPicker } label: {
                            Label("home.addTool", systemImage: "plus.circle.fill")
                                .font(theme.actionFont)
                                .frame(maxWidth: .infinity, minHeight: 54)
                        }
                        .buttonStyle(.bordered)
                        .tint(theme.accent)
                    }
                    .padding(HomeGridLayout.horizontalPadding)
                    .frame(maxWidth: HomeGridLayout.maximumContentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .background(theme.background.ignoresSafeArea())
            }
            .navigationTitle("app.title")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Section("home.profiles") {
                            ForEach(HomeProfileOrdering.ordered(homes)) { profile in
                                let canAccessProfile = HomeProfileAccess.canAccess(
                                    profile.id,
                                    in: homes,
                                    isPro: proPurchases.hasPro
                                )
                                Button {
                                    guard canAccessProfile else {
                                        activeSheet = .settings
                                        return
                                    }
                                    do {
                                        try HomeProfileService(modelContext: modelContext).selectHome(
                                            profile.id,
                                            isPro: proPurchases.hasPro
                                        )
                                    } catch {
                                        showingSaveError = true
                                    }
                                } label: {
                                    HStack {
                                        if profile.usesDefaultName {
                                            Text("home.defaultName")
                                        } else {
                                            Text(verbatim: profile.name)
                                        }
                                        if !canAccessProfile {
                                            Image(systemName: "lock.fill")
                                        }
                                    }
                                }
                                .disabled(home.id == profile.id)
                                .accessibilityHint(canAccessProfile
                                    ? Text(home.id == profile.id ? "home.current" : "home.select")
                                    : Text("home.additionalProfilesLocked"))
                            }
                        }
                        Button {
                            activeSheet = canCreateAnotherHome ? .createHome : .settings
                        } label: {
                            Label("home.create", systemImage: canCreateAnotherHome ? "plus" : "lock.fill")
                        }
                        Button { activeSheet = .manageHomes } label: {
                            Label("home.manage", systemImage: "list.bullet")
                        }
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .accessibilityLabel("home.switch")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if UIDevice.current.userInterfaceIdiom == .pad,
                       FeatureAccessRegistry.allows(.ipadCounterControl, isPro: proPurchases.hasPro) {
                        Button { activeSheet = .peerCounters } label: {
                            Image(systemName: "dot.radiowaves.left.and.right")
                        }
                        .accessibilityLabel("peer.dashboard")
                    }
                    Button { activeSheet = .settings } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("settings.title")
                }
            }
            .sheet(item: $activeSheet) { destination in
                switch destination {
                case .toolPicker:
                    ToolPickerView(home: home)
                case .settings:
                    AppSettingsView(home: home)
                case .peerCounters:
                    NavigationStack {
#if targetEnvironment(simulator)
                        PeerCounterView(screenshotDemoMode: screenshotDemoScenario?.peerCounterScreenshotMode)
#else
                        PeerCounterView()
#endif
                    }
                    .presentationDetents(peerDashboardSheetDetents)
                case .createHome:
                    CreateHomeView()
                case .manageHomes:
                    ManageHomesView {
                        activeSheet = .settings
                    }
                }
            }
            .alert("error.saveFailed", isPresented: $showingSaveError) {
                Button("common.done", role: .cancel) {}
            } message: {
                Text("error.saveMessage")
            }
        }
        .tint(theme.accent)
    }

    private func delete(_ card: ToolCard) {
        do {
            try HomeCardService(modelContext: modelContext).remove(card)
        } catch {
            showingSaveError = true
        }
    }

    private func moveCard(_ sourceID: UUID, before destinationID: UUID) -> Bool {
        do {
            return try HomeCardService(modelContext: modelContext).move(sourceID, before: destinationID, in: home.id)
        } catch {
            showingSaveError = true
            return false
        }
    }

    private func cardView(_ card: ToolCard) -> some View {
        let index = homeCards.firstIndex { $0.id == card.id } ?? 0
        return HomeToolCardView(
            card: card,
            home: home,
            canMoveEarlier: index > 0,
            canMoveLater: index + 1 < homeCards.count,
            onMoveEarlier: {
                guard index > 0 else { return }
                moveCard(card.id, before: homeCards[index - 1].id)
            },
            onMoveLater: {
                guard index + 1 < homeCards.count else { return }
                moveCard(homeCards[index + 1].id, before: card.id)
            },
            onDelete: { delete(card) },
            initialSheet: screenshotSheet(for: card)
        )
        .draggable(card.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let value = items.first, let sourceID = UUID(uuidString: value) else { return false }
            return moveCard(sourceID, before: card.id)
        }
    }

    private func screenshotSheet(for card: ToolCard) -> HomeToolCardSheet? {
        guard let screenshotDemoScenario else { return nil }
        switch screenshotDemoScenario {
        case .cycleTime where card.toolID == ToolID.cycleTime.rawValue:
            return .cycleTime
        case .taktTime where card.toolID == ToolID.taktTime.rawValue:
            return .taktTime
        case .counterHistory where card.toolID == ToolID.productionCounter.rawValue:
            return .history
        default:
            return nil
        }
    }

    @ViewBuilder
    private var homeTitle: some View {
        if home.usesDefaultName {
            Text("home.defaultName")
                .font(theme.homeTitleFont)
                .foregroundStyle(theme.primaryText)
        } else {
            Text(verbatim: home.name)
                .font(theme.homeTitleFont)
                .foregroundStyle(theme.primaryText)
        }
    }
}

enum HomeGridLayout {
    static let maximumContentWidth: CGFloat = 1020
    static let maximumColumnCount = 5
    static let horizontalPadding: CGFloat = 18
    static let itemSpacing: CGFloat = 14

    static func minimumColumnWidth(isAccessibilitySize: Bool) -> CGFloat {
        isAccessibilitySize ? 280 : 160
    }

    static func columnCount(availableWidth: CGFloat, minimumColumnWidth: CGFloat, spacing: CGFloat) -> Int {
        guard availableWidth.isFinite,
              minimumColumnWidth.isFinite,
              minimumColumnWidth > 0,
              spacing.isFinite else { return 1 }
        let boundedWidth = min(max(0, availableWidth), maximumContentWidth)
        let nonnegativeSpacing = max(0, spacing)
        let fittingCount = (boundedWidth + nonnegativeSpacing) / (minimumColumnWidth + nonnegativeSpacing)
        guard fittingCount.isFinite else { return maximumColumnCount }
        guard fittingCount < CGFloat(maximumColumnCount) else { return maximumColumnCount }
        return max(1, Int(fittingCount))
    }

    static func rows(for cards: [ToolCard], columnCount: Int) -> [HomeGridRow] {
        let columns = max(1, columnCount)
        var rows: [HomeGridRow] = []
        var currentRow: [ToolCard] = []

        for card in cards {
            if card.size == .large {
                if !currentRow.isEmpty {
                    rows.append(HomeGridRow(cards: currentRow, isFullWidth: false))
                    currentRow = []
                }
                rows.append(HomeGridRow(cards: [card], isFullWidth: true))
                continue
            }

            currentRow.append(card)
            if currentRow.count == columns {
                rows.append(HomeGridRow(cards: currentRow, isFullWidth: false))
                currentRow = []
            }
        }

        if !currentRow.isEmpty {
            rows.append(HomeGridRow(cards: currentRow, isFullWidth: false))
        }
        return rows
    }
}

struct HomeGridRow: Identifiable {
    let cards: [ToolCard]
    let isFullWidth: Bool

    fileprivate init(cards: [ToolCard], isFullWidth: Bool) {
        self.cards = cards
        self.isFullWidth = isFullWidth
    }

    var id: UUID { cards[0].id }
}

private enum HomeSheetDestination: String, Identifiable {
    case toolPicker
    case settings
    case peerCounters
    case createHome
    case manageHomes

    var id: String { rawValue }
}
