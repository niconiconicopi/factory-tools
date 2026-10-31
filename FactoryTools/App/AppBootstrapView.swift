import FactoryToolsCore
import SwiftData
import SwiftUI
import UIKit

struct AppBootstrapView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var proPurchases: ProPurchaseManager
    @Query private var homes: [HomeProfile]
    @Query private var settings: [AppSettings]
    @State private var themeManager = ThemeManager()
    @State private var showingSeedError = false

    private var selectedHome: HomeProfile? {
        let selectedID = AppSettingsOrdering.primary(in: settings)?.selectedHomeProfileID
        return HomeProfileAccess.selectedHome(from: homes, selectedID: selectedID, isPro: proPurchases.hasPro)
    }

    var body: some View {
        Group {
            if let home = selectedHome {
                HomeView(home: home)
            } else if showingSeedError {
                ContentUnavailableView {
                    Label("error.saveFailed", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("error.saveMessage")
                } actions: {
                    Button("common.retry", action: seedInitialDataIfNeeded)
                        .buttonStyle(.borderedProminent)
                        .tint(activeTheme.accent)
                }
                .font(activeTheme.bodyFont)
                .foregroundStyle(activeTheme.primaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(activeTheme.background.ignoresSafeArea())
            } else {
                ProgressView()
            }
        }
        .task { seedInitialDataIfNeeded() }
        .onAppear {
            startPeerAuthorityIfAvailable()
            WatchConnectivityReceiver.shared.publishCatalog()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, UIDevice.current.userInterfaceIdiom == .phone else { return }
            startPeerAuthorityIfAvailable()
            WatchConnectivityReceiver.shared.publishCatalog()
        }
        .onChange(of: proPurchases.hasPro) { _, hasPro in
            WatchConnectivityReceiver.shared.publishCatalog()
            guard UIDevice.current.userInterfaceIdiom == .phone else { return }
            if FeatureAccessRegistry.allows(.ipadCounterControl, isPro: hasPro) { startPeerAuthorityIfAvailable() }
            else { LocalPeerCounterTransport.shared.stopAuthority() }
        }
        .onChange(of: proPurchases.hasResolvedEntitlement) { _, _ in
            WatchConnectivityReceiver.shared.publishCatalog()
            startPeerAuthorityIfAvailable()
        }
        .preferredColorScheme(.dark)
        .environment(\.locale, selectedLocale)
        .environment(\.appTheme, activeTheme)
        .environment(\.font, activeTheme.bodyFont)
        .alert("error.saveFailed", isPresented: $showingSeedError) {
            Button("common.retry", action: seedInitialDataIfNeeded)
            Button("common.done", role: .cancel) {}
        } message: {
            Text("error.saveMessage")
        }
    }

    private var selectedLocale: Locale {
        AppLanguage.resolve(AppSettingsOrdering.primary(in: settings)?.language).locale
    }

    private var activeTheme: AppTheme {
        themeManager.theme(for: ThemeID(rawValue: AppSettingsOrdering.primary(in: settings)?.themeID ?? "") ?? .industrialDark)
    }

    private func seedInitialDataIfNeeded() {
        showingSeedError = false
        do {
            try AppBootstrapService(modelContext: modelContext).seedMissingRecords()
        } catch {
            showingSeedError = true
        }
    }

    private func startPeerAuthorityIfAvailable() {
        guard proPurchases.hasResolvedEntitlement,
              UIDevice.current.userInterfaceIdiom == .phone,
              FeatureAccessRegistry.allows(.ipadCounterControl, isPro: proPurchases.hasPro) else { return }
        LocalPeerCounterTransport.shared.startAuthority(modelContainer: modelContext.container)
    }
}

@MainActor
struct AppBootstrapService {
    let modelContext: ModelContext

    func seedMissingRecords() throws {
        var homes = try modelContext.fetch(FetchDescriptor<HomeProfile>())
        var settings = try modelContext.fetch(FetchDescriptor<AppSettings>())
        let cards = try modelContext.fetch(FetchDescriptor<ToolCard>())
        let sessions = try modelContext.fetch(FetchDescriptor<ProductionSession>())
        var hasChanges = false
        var homeToInsert: HomeProfile?
        var settingsToInsert: AppSettings?
        let originalSelectedHomeIDs = Dictionary(uniqueKeysWithValues: settings.map { ($0.id, $0.selectedHomeProfileID) })
        let originalSessionAssignments = Dictionary(uniqueKeysWithValues: sessions.map {
            ($0.id, (homeProfileID: $0.homeProfileID, toolID: $0.toolID))
        })

        if homes.isEmpty {
            let home = HomeProfile(name: "Production", usesDefaultName: true, sortOrder: 0)
            homeToInsert = home
            homes.append(home)
            hasChanges = true
        }
        if settings.isEmpty {
            let settingsRecord = AppSettings(selectedHomeProfileID: HomeProfileOrdering.ordered(homes).first?.id)
            settingsToInsert = settingsRecord
            settings.append(settingsRecord)
            hasChanges = true
        }

        if let primarySettings = AppSettingsOrdering.primary(in: settings) {
            let validHomeIDs = Set(homes.map(\.id))
            if let selectedHomeID = primarySettings.selectedHomeProfileID,
               validHomeIDs.contains(selectedHomeID) {
                // Keep the user's selected home.
            } else {
                primarySettings.selectedHomeProfileID = HomeProfileOrdering.ordered(homes).first?.id
                hasChanges = true
            }
        }

        let validHomeIDs = Set(homes.map(\.id))
        for session in sessions where session.homeProfileID == nil || session.toolID == nil {
            let linkedCards = cards.filter { $0.productionSessionID == session.id }
            guard !linkedCards.isEmpty else { continue }
            let linkedHomeIDs = Set(linkedCards.map(\.homeProfileID))
            let linkedToolIDs = linkedCards.compactMap { card in
                ToolID(rawValue: card.toolID).flatMap(ToolSessionAssignment.sessionToolID(for:))
            }
            guard linkedHomeIDs.count == 1,
                  linkedToolIDs.count == linkedCards.count,
                  Set(linkedToolIDs).count == 1,
                  let linkedHomeID = linkedHomeIDs.first,
                  validHomeIDs.contains(linkedHomeID),
                  let linkedToolID = linkedToolIDs.first,
                  session.homeProfileID.map({ $0 == linkedHomeID }) ?? true,
                  session.toolID.map({ $0 == linkedToolID.rawValue }) ?? true else {
                continue
            }

            if session.homeProfileID == nil {
                session.homeProfileID = linkedHomeID
                hasChanges = true
            }
            if session.toolID == nil {
                session.toolID = linkedToolID.rawValue
                hasChanges = true
            }
        }
        guard hasChanges else { return }

        if let homeToInsert { modelContext.insert(homeToInsert) }
        if let settingsToInsert { modelContext.insert(settingsToInsert) }
        do {
            try modelContext.save()
        } catch {
            if let homeToInsert { modelContext.delete(homeToInsert) }
            if let settingsToInsert { modelContext.delete(settingsToInsert) }
            for setting in settings {
                setting.selectedHomeProfileID = originalSelectedHomeIDs[setting.id] ?? nil
            }
            for session in sessions {
                guard let original = originalSessionAssignments[session.id] else { continue }
                session.homeProfileID = original.homeProfileID
                session.toolID = original.toolID
            }
            throw error
        }
    }
}
