import SwiftData
import SwiftUI
import UIKit
import FactoryToolsCore

@main
struct FactoryToolsApp: App {
    @StateObject private var proPurchases = ProPurchaseManager.shared
    @State private var container: ModelContainer?
    @State private var showingRetryError = false
    private let screenshotDemoLanguage: AppLanguage?

    init() {
        #if targetEnvironment(simulator)
        let screenshotDemoLanguage = Self.screenshotDemoLanguage
        #else
        let screenshotDemoLanguage: AppLanguage? = nil
        #endif
        self.screenshotDemoLanguage = screenshotDemoLanguage
        do {
            let container = try Self.makeContainer(screenshotLanguage: screenshotDemoLanguage)
            _container = State(initialValue: container)
            if screenshotDemoLanguage == nil {
                WatchConnectivityReceiver.shared.start(modelContainer: container)
            }
        } catch {
            _container = State(initialValue: nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                AppBootstrapView()
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

    private static func makeContainer(screenshotLanguage: AppLanguage? = nil) throws -> ModelContainer {
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
        if let screenshotLanguage {
            try Self.seedScreenshotDemoData(in: container.mainContext, language: screenshotLanguage)
        }
        #endif
        return container
    }

    private func retryStoreInitialization() {
        do {
            container = try Self.makeContainer(screenshotLanguage: screenshotDemoLanguage)
            if let container, screenshotDemoLanguage == nil {
                WatchConnectivityReceiver.shared.start(modelContainer: container)
            }
            showingRetryError = false
        } catch {
            showingRetryError = true
        }
    }

    #if targetEnvironment(simulator)
    private static var screenshotDemoLanguage: AppLanguage? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--factorytools-screenshot-demo") else { return nil }
        return arguments.contains("--factorytools-screenshot-japanese") ? .japanese : .english
    }

    private static func seedScreenshotDemoData(in context: ModelContext, language: AppLanguage) throws {
        let home = HomeProfile(name: "Assembly", usesDefaultName: false, sortOrder: 0)
        let session = ProductionSession(
            homeProfileID: home.id,
            toolID: ToolID.productionCounter.rawValue,
            name: "Line A",
            currentCount: 286,
            targetCount: 300,
            nextEventSequence: 1
        )
        let card = ToolCard(
            homeProfileID: home.id,
            toolID: .productionCounter,
            size: .large,
            sortOrder: 0,
            productionSessionID: session.id
        )
        let event = CountEvent(
            sessionID: session.id,
            delta: session.currentCount,
            sequence: 0,
            kind: .quickAdd
        )
        let settings = AppSettings(
            language: language.rawValue,
            themeID: ThemeID.industrialDark.rawValue,
            selectedHomeProfileID: home.id
        )
        context.insert(home)
        context.insert(session)
        context.insert(card)
        context.insert(event)
        context.insert(settings)
        try context.save()
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
