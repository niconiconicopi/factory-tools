import FactoryToolsCore
import SwiftData
import SwiftUI

struct ToolPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @EnvironmentObject private var proPurchases: ProPurchaseManager
    @Query private var cards: [ToolCard]
    @State private var showingSaveError = false
    @State private var showingProSettings = false
    @State private var searchText = ""

    let home: HomeProfile

    init(home: HomeProfile) {
        self.home = home
        let selectedHomeID = home.id
        _cards = Query(filter: #Predicate<ToolCard> { $0.homeProfileID == selectedHomeID })
    }

    private var isAssemblyPresetApplied: Bool {
        let existingIDs = Set(cards.compactMap { ToolID(rawValue: $0.toolID) })
        return accessibleToolIDs(in: AssemblyPreset.toolIDs).allSatisfy(existingIDs.contains)
    }

    private var isPackagingPresetApplied: Bool {
        let existingIDs = Set(cards.compactMap { ToolID(rawValue: $0.toolID) })
        return accessibleToolIDs(in: PackagingPreset.toolIDs).allSatisfy(existingIDs.contains)
    }

    private func accessibleToolIDs(in toolIDs: [ToolID]) -> [ToolID] {
        toolIDs.filter { id in
            guard let tool = ToolRegistry.definition(for: id) else { return false }
            return FeatureAccessRegistry.allows(tool.accessTier, isPro: proPurchases.hasPro)
        }
    }

    private func containsLockedTools(_ toolIDs: [ToolID]) -> Bool {
        toolIDs.contains { id in
            guard let tool = ToolRegistry.definition(for: id) else { return false }
            return !FeatureAccessRegistry.allows(tool.accessTier, isPro: proPurchases.hasPro)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    presetSection
                }

                if filteredTools.isEmpty {
                    ContentUnavailableView(
                        "tool.noSearchResults",
                        systemImage: "magnifyingglass",
                        description: Text("tool.noSearchResultsHint")
                    )
                } else {
                    toolSections
                }
            }
            .searchable(text: $searchText, prompt: Text("tool.searchPrompt"))
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("home.addTool")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") { dismiss() }
                }
            }
            .alert("error.saveFailed", isPresented: $showingSaveError) {
                Button("common.done", role: .cancel) {}
            } message: {
                Text("error.saveMessage")
            }
            .sheet(isPresented: $showingProSettings) {
                AppSettingsView(home: home)
            }
        }
    }

    private var filteredTools: [ToolDefinition] {
        ToolRegistry.matching(searchText, locale: locale)
    }

    @ViewBuilder
    private var presetSection: some View {
        Section {
            Button(action: applyAssemblyPreset) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(LocalizedStringKey(AssemblyPreset.titleKey), systemImage: "square.grid.2x2.fill")
                        .foregroundStyle(theme.primaryText)
                    Text(LocalizedStringKey(AssemblyPreset.descriptionKey))
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                    if containsLockedTools(AssemblyPreset.toolIDs) {
                        Text("home.preset.proToolsRequirePro")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                    if isAssemblyPresetApplied {
                        Label("home.preset.applied", systemImage: "checkmark.circle.fill")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            .disabled(isAssemblyPresetApplied)
            .listRowBackground(theme.cardBackground)
            Button(action: applyPackagingPreset) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(LocalizedStringKey(PackagingPreset.titleKey), systemImage: "shippingbox.fill")
                        .foregroundStyle(theme.primaryText)
                    Text(LocalizedStringKey(PackagingPreset.descriptionKey))
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                    if containsLockedTools(PackagingPreset.toolIDs) {
                        Text("home.preset.proToolsRequirePro")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                    if isPackagingPresetApplied {
                        Label("home.preset.applied", systemImage: "checkmark.circle.fill")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            .disabled(isPackagingPresetApplied)
            .listRowBackground(theme.cardBackground)
        } header: {
            Text("home.presets")
        }
    }

    @ViewBuilder
    private var toolSections: some View {
        ForEach(ToolCategory.allCases) { category in
            let categoryTools = ToolRegistry.matching(searchText, category: category, locale: locale)
            if !categoryTools.isEmpty {
                Section {
                    ForEach(categoryTools, content: toolRow)
                } header: {
                    Text(LocalizedStringKey(category.titleKey))
                }
            }
        }
    }

    @ViewBuilder
    private func toolRow(_ tool: ToolDefinition) -> some View {
        let canAccess = FeatureAccessRegistry.allows(tool.accessTier, isPro: proPurchases.hasPro)
        Button {
            if canAccess { add(tool) }
            else { showingProSettings = true }
        } label: {
            HStack {
                Label(LocalizedStringKey(tool.titleKey), systemImage: symbol(for: tool.id))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                if !tool.isAvailable {
                    Text("tool.comingSoon")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                } else {
                    if !canAccess {
                        Label("pro.title", systemImage: "lock.fill")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                    if cards.contains(where: { $0.toolID == tool.id.rawValue }) {
                        Text("tool.alreadyOnHome")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                    Image(systemName: "plus")
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .disabled(!tool.isAvailable)
        .accessibilityHint(!tool.isAvailable ? Text("tool.comingSoon") : (!canAccess ? Text("pro.title") : Text("tool.addHint")))
        .listRowBackground(theme.cardBackground)
    }

    private func add(_ tool: ToolDefinition) {
        do {
            try HomeToolService(modelContext: modelContext).add(tool, to: home.id, locale: locale, isPro: proPurchases.hasPro)
        } catch {
            showingSaveError = true
        }
    }

    private func applyAssemblyPreset() {
        do {
            try HomeToolService(modelContext: modelContext).applyAssemblyPreset(to: home.id, locale: locale, isPro: proPurchases.hasPro)
        } catch {
            showingSaveError = true
        }
    }

    private func applyPackagingPreset() {
        do {
            try HomeToolService(modelContext: modelContext).applyPackagingPreset(to: home.id, locale: locale, isPro: proPurchases.hasPro)
        } catch {
            showingSaveError = true
        }
    }

    private func symbol(for id: ToolID) -> String {
        switch id {
        case .productionCounter: "number.circle"
        case .productionProgress: "chart.bar.fill"
        case .defectCounter: "exclamationmark.circle"
        case .defectRate: "percent"
        case .boxCalculator: "shippingbox"
        case .unitConverter: "arrow.left.arrow.right"
        case .cycleTime: "timer"
        case .taktTime: "clock"
        case .oee: "gauge"
        default: "wrench.and.screwdriver"
        }
    }
}
