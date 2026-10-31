import FactoryToolsCore
import SwiftData
import SwiftUI

struct ManageHomesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @EnvironmentObject private var proPurchases: ProPurchaseManager
    @Query private var homes: [HomeProfile]
    @Query private var settings: [AppSettings]
    @State private var showingSaveError = false
    @State private var showingDeleteConfirmation = false
    @State private var editingHome: HomeProfile?
    @State private var homePendingDeletion: HomeProfile?
    let onRequestPro: () -> Void

    private var orderedHomes: [HomeProfile] {
        HomeProfileOrdering.ordered(homes)
    }

    private var selectedHomeID: UUID? {
        HomeProfileAccess.selectedHome(
            from: homes,
            selectedID: AppSettingsOrdering.primary(in: settings)?.selectedHomeProfileID,
            isPro: proPurchases.hasPro
        )?.id
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(orderedHomes) { home in
                    let index = orderedHomes.firstIndex { $0.id == home.id } ?? 0
                    let canAccessHome = HomeProfileAccess.canAccess(home.id, in: homes, isPro: proPurchases.hasPro)
                    HStack(spacing: 12) {
                        Button {
                            if canAccessHome { select(home) } else { onRequestPro() }
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    if home.usesDefaultName {
                                        Text("home.defaultName")
                                    } else {
                                        Text(verbatim: home.name)
                                    }
                                    Text(selectedHomeID == home.id ? "home.current" : "home.select")
                                        .font(theme.captionFont)
                                        .foregroundStyle(theme.secondaryText)
                                }
                                Spacer(minLength: 4)
                                if selectedHomeID == home.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(theme.accent)
                                } else if !canAccessHome {
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(theme.secondaryText)
                                }
                            }
                            .foregroundStyle(theme.primaryText)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(!canAccessHome
                            ? Text("home.additionalProfilesLocked")
                            : Text(selectedHomeID == home.id ? "home.current" : "home.select"))

                        Button {
                            if canAccessHome { editingHome = home } else { onRequestPro() }
                        } label: {
                            Image(systemName: "pencil")
                                .frame(width: 44, height: 44)
                        }
                        .disabled(!canAccessHome)
                        .accessibilityLabel(Text("home.renameNamed \(displayName(for: home))"))

                        Button {
                            guard index > 0 else { return }
                            move(home.id, before: orderedHomes[index - 1].id)
                        } label: {
                            Image(systemName: "arrow.up")
                                .frame(width: 44, height: 44)
                        }
                        .disabled(index == 0 || !FeatureAccessRegistry.allows(.multipleHomeProfiles, isPro: proPurchases.hasPro))
                        .accessibilityLabel(Text("home.moveEarlierNamed \(displayName(for: home))"))

                        Button {
                            guard index + 1 < orderedHomes.count else { return }
                            move(orderedHomes[index + 1].id, before: home.id)
                        } label: {
                            Image(systemName: "arrow.down")
                                .frame(width: 44, height: 44)
                        }
                        .disabled(index + 1 >= orderedHomes.count || !FeatureAccessRegistry.allows(.multipleHomeProfiles, isPro: proPurchases.hasPro))
                        .accessibilityLabel(Text("home.moveLaterNamed \(displayName(for: home))"))

                        Button(role: .destructive) {
                            homePendingDeletion = home
                            showingDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 44, height: 44)
                        }
                        .disabled(orderedHomes.count <= 1)
                        .accessibilityLabel(Text("home.deleteNamed \(displayName(for: home))"))
                    }
                    .listRowBackground(theme.cardBackground)
                }
                if orderedHomes.count > 1 && !proPurchases.hasPro {
                    Section {
                        Label("home.additionalProfilesLocked", systemImage: "lock.fill")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                        Button("pro.purchaseAction", action: onRequestPro)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("home.manage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
            .alert("error.saveFailed", isPresented: $showingSaveError) {
                Button("common.done", role: .cancel) {}
            } message: {
                Text("error.saveMessage")
            }
            .confirmationDialog(
                "home.deleteConfirmation.title",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("home.delete", role: .destructive) {
                    if let homePendingDeletion { delete(homePendingDeletion) }
                    self.homePendingDeletion = nil
                }
                Button("common.cancel", role: .cancel) { homePendingDeletion = nil }
            } message: {
                Text("home.deleteConfirmation.message")
            }
            .sheet(item: $editingHome) { home in
            RenameHomeView(home: home, isPro: proPurchases.hasPro)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func select(_ home: HomeProfile) {
        do {
            try HomeProfileService(modelContext: modelContext).selectHome(home.id, isPro: proPurchases.hasPro)
            dismiss()
        } catch {
            showingSaveError = true
        }
    }

    private func displayName(for home: HomeProfile) -> String {
        home.usesDefaultName ? String(localized: "home.defaultName", locale: locale) : home.name
    }

    private func move(_ homeID: UUID, before destinationID: UUID) {
        do {
            _ = try HomeProfileService(modelContext: modelContext).move(
                homeID,
                before: destinationID,
                isPro: proPurchases.hasPro
            )
        } catch {
            showingSaveError = true
        }
    }

    private func delete(_ home: HomeProfile) {
        do {
            try HomeProfileService(modelContext: modelContext).deleteHome(home.id)
        } catch {
            showingSaveError = true
        }
    }
}
