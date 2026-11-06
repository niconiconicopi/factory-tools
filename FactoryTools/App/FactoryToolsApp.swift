import SwiftData
import SwiftUI
import UIKit
import FactoryToolsCore

enum ScreenshotDemoScenario: String, CaseIterable {
    case home
    case counterQuickAdd = "counter-quick-add"
    case cycleTime = "cycle-time"
    case taktTime = "takt-time"
    case defectCounter = "defect-counter"
    case counterHistory = "counter-history"
    case ipadDashboard = "ipad-dashboard"
    case ipadOffline = "ipad-offline"

#if targetEnvironment(simulator)
    var peerCounterScreenshotMode: PeerCounterScreenshotMode? {
        switch self {
        case .ipadDashboard: .connected
        case .ipadOffline: .offline
        default: nil
        }
    }
#endif

    var launchArgument: String { "--factorytools-screenshot-\(rawValue)" }

    static func requested(in arguments: [String]) -> Self? {
        allCases.first { arguments.contains($0.launchArgument) }
    }
}

@main
struct FactoryToolsApp: App {
    @StateObject private var proPurchases = ProPurchaseManager.shared
    @State private var container: ModelContainer?
    @State private var showingRetryError = false
    private let screenshotDemoLanguage: AppLanguage?
    private let screenshotDemoScenario: ScreenshotDemoScenario?

    init() {
        #if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        let screenshotDemoLanguage: AppLanguage? = arguments.contains("--factorytools-screenshot-demo")
            ? (arguments.contains("--factorytools-screenshot-japanese") ? .japanese : .english)
            : nil
        let screenshotDemoScenario = screenshotDemoLanguage == nil
            ? nil
            : (ScreenshotDemoScenario.requested(in: arguments) ?? .home)
        #else
        let screenshotDemoLanguage: AppLanguage? = nil
        let screenshotDemoScenario: ScreenshotDemoScenario? = nil
        #endif
        self.screenshotDemoLanguage = screenshotDemoLanguage
        self.screenshotDemoScenario = screenshotDemoScenario
        do {
            let container = try Self.makeContainer(
                screenshotLanguage: screenshotDemoLanguage,
                screenshotScenario: screenshotDemoScenario
            )
            _container = State(initialValue: container)
            if screenshotDemoScenario == nil {
                WatchConnectivityReceiver.shared.start(modelContainer: container)
            }
        } catch {
            _container = State(initialValue: nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                AppBootstrapView(screenshotDemoScenario: screenshotDemoScenario)
                    .modelContainer(container)
                    .environmentObject(proPurchases)
            } else {
                StoreUnavailableView(
                    onRetry: retryStoreInitialization,
                    showingRetryError: $showingRetryError
                )
            }
        }
    }

    private static func makeContainer(
        screenshotLanguage: AppLanguage? = nil,
        screenshotScenario: ScreenshotDemoScenario? = nil
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: FactoryToolsSchemaV1.self)
        let localConfiguration = ModelConfiguration(
            "FactoryTools",
            schema: schema,
            isStoredInMemoryOnly: screenshotLanguage != nil,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: FactoryToolsMigrationPlan.self,
            configurations: [localConfiguration]
        )
        #if targetEnvironment(simulator)
        if let screenshotLanguage, let screenshotScenario {
            try Self.seedScreenshotDemoData(
                in: container.mainContext,
                language: screenshotLanguage,
                scenario: screenshotScenario
            )
        }
        #endif
        return container
    }

    private func retryStoreInitialization() {
        do {
            container = try Self.makeContainer(
                screenshotLanguage: screenshotDemoLanguage,
                screenshotScenario: screenshotDemoScenario
            )
            if let container, screenshotDemoScenario == nil {
                WatchConnectivityReceiver.shared.start(modelContainer: container)
            }
            showingRetryError = false
        } catch {
            showingRetryError = true
        }
    }

    #if targetEnvironment(simulator)
    private static func seedScreenshotDemoData(
        in context: ModelContext,
        language: AppLanguage,
        scenario: ScreenshotDemoScenario
    ) throws {
        let home = HomeProfile(name: "Assembly", usesDefaultName: false, sortOrder: 0)
        let settings = AppSettings(
            language: language.rawValue,
            themeID: ThemeID.industrialDark.rawValue,
            selectedHomeProfileID: home.id
        )
        context.insert(home)
        context.insert(settings)

        switch scenario {
        case .home, .counterQuickAdd, .ipadDashboard, .ipadOffline:
            let production = makeSession(home: home, tool: .productionCounter, count: 286, target: 300, name: "Line A")
            addCounterCard(production, home: home, sortOrder: 0, size: .large, context: context)
            insertEvents(for: production, deltas: [200, 80, 6], context: context)
        case .counterHistory:
            let production = makeSession(home: home, tool: .productionCounter, count: 286, target: 300, name: "Line A")
            production.nextEventSequence = 5
            addCounterCard(production, home: home, sortOrder: 0, size: .large, context: context)
            insertUndoHistoryDemoEvents(for: production, context: context)
        case .cycleTime:
            context.insert(ToolCard(homeProfileID: home.id, toolID: .cycleTime, size: .large, sortOrder: 0))
            let referenceDate = Date(timeIntervalSinceNow: -86_400 * 2)
            context.insert(CycleTimeSample(homeProfileID: home.id, totalSeconds: 110, quantity: 4, createdAt: referenceDate))
            context.insert(CycleTimeSample(homeProfileID: home.id, totalSeconds: 132, quantity: 4, createdAt: referenceDate.addingTimeInterval(86_400)))
            context.insert(CycleTimeSample(homeProfileID: home.id, totalSeconds: 120, quantity: 4, createdAt: referenceDate.addingTimeInterval(172_800)))
        case .taktTime:
            context.insert(ToolCard(homeProfileID: home.id, toolID: .taktTime, size: .large, sortOrder: 0))
        case .defectCounter:
            let production = makeSession(home: home, tool: .productionCounter, count: 286, target: 300, name: "Line A")
            let defects = makeSession(home: home, tool: .defectCounter, count: 8, target: 0, name: "Line A Defects")
            addCounterCard(production, home: home, sortOrder: 0, size: .medium, context: context)
            addCounterCard(defects, home: home, sortOrder: 1, size: .medium, context: context)
            context.insert(ToolCard(homeProfileID: home.id, toolID: .defectRate, size: .medium, sortOrder: 2))
            insertEvents(for: production, deltas: [200, 80, 6], context: context)
            insertEvents(for: defects, deltas: [5, 3], context: context)
        }
        try context.save()
    }

    private static func makeSession(
        home: HomeProfile,
        tool: ToolID,
        count: Int,
        target: Int,
        name: String
    ) -> ProductionSession {
        ProductionSession(
            homeProfileID: home.id,
            toolID: tool.rawValue,
            name: name,
            currentCount: count,
            targetCount: target,
            nextEventSequence: count == 0 ? 0 : (tool == .defectCounter ? 2 : 3)
        )
    }

    private static func addCounterCard(
        _ session: ProductionSession,
        home: HomeProfile,
        sortOrder: Int,
        size: ToolCardSize,
        context: ModelContext
    ) {
        let tool = ToolID(rawValue: session.toolID ?? "") ?? .productionCounter
        context.insert(ToolCard(
            homeProfileID: home.id,
            toolID: tool,
            size: size,
            sortOrder: sortOrder,
            productionSessionID: session.id
        ))
        context.insert(session)
    }

    private static func insertEvents(for session: ProductionSession, deltas: [Int], context: ModelContext) {
        for (sequence, delta) in deltas.enumerated() {
            context.insert(CountEvent(
                sessionID: session.id,
                delta: delta,
                sequence: sequence,
                occurredAt: Date(timeIntervalSinceNow: -86_400 * Double(deltas.count - sequence)),
                kind: sequence == 0 ? .quickAdd : .increment
            ))
        }
    }

    private static func insertUndoHistoryDemoEvents(for session: ProductionSession, context: ModelContext) {
        let referenceDate = Date(timeIntervalSinceNow: -86_400 * 4)
        let quickAdd = CountEvent(
            sessionID: session.id,
            delta: 200,
            sequence: 0,
            occurredAt: referenceDate,
            kind: .quickAdd
        )
        let firstIncrement = CountEvent(
            sessionID: session.id,
            delta: 80,
            sequence: 1,
            occurredAt: referenceDate.addingTimeInterval(3_600),
            kind: .increment
        )
        let undoneIncrement = CountEvent(
            sessionID: session.id,
            delta: 10,
            sequence: 2,
            occurredAt: referenceDate.addingTimeInterval(7_200),
            kind: .increment
        )
        let undo = CountEvent(
            sessionID: session.id,
            delta: -10,
            sequence: 3,
            occurredAt: referenceDate.addingTimeInterval(7_260),
            reversesEventID: undoneIncrement.id,
            kind: .undo
        )
        let finalIncrement = CountEvent(
            sessionID: session.id,
            delta: 6,
            sequence: 4,
            occurredAt: referenceDate.addingTimeInterval(10_800),
            kind: .increment
        )
        for event in [quickAdd, firstIncrement, undoneIncrement, undo, finalIncrement] {
            context.insert(event)
        }
    }
    #endif
}

private struct StoreUnavailableView: View {
    let onRetry: () -> Void
    @Binding var showingRetryError: Bool
    private let theme = ThemeManager().theme(for: .industrialDark)

    var body: some View {
        ContentUnavailableView {
            Label("error.storeUnavailable.title", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("error.storeUnavailable.message")
        } actions: {
            Button("common.retry", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
        }
        .font(theme.bodyFont)
        .foregroundStyle(theme.primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .alert("error.storeUnavailable.title", isPresented: $showingRetryError) {
            Button("common.done", role: .cancel) {}
        } message: {
            Text("error.storeUnavailable.message")
        }
    }
}
