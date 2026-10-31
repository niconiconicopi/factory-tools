import SwiftData
import SwiftUI
import UIKit

@main
struct FactoryToolsApp: App {
    @StateObject private var proPurchases = ProPurchaseManager.shared
    @State private var container: ModelContainer?
    @State private var showingRetryError = false

    init() {
        do {
            let container = try Self.makeContainer()
            _container = State(initialValue: container)
            WatchConnectivityReceiver.shared.start(modelContainer: container)
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

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: FactoryToolsSchemaV1.self)
        let localConfiguration = ModelConfiguration(
            "FactoryTools",
            schema: schema,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: FactoryToolsMigrationPlan.self,
            configurations: [localConfiguration]
        )
    }

    private func retryStoreInitialization() {
        do {
            container = try Self.makeContainer()
            if let container {
                WatchConnectivityReceiver.shared.start(modelContainer: container)
            }
            showingRetryError = false
        } catch {
            showingRetryError = true
        }
    }
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
