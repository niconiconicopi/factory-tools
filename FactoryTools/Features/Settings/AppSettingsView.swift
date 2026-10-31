import Foundation
import FactoryToolsCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isSceneCaptured) private var isSceneCaptured
    @EnvironmentObject private var proPurchases: ProPurchaseManager
    @Query private var settings: [AppSettings]
    @Bindable var home: HomeProfile
    @State private var homeNameDraft = ""
    @State private var showingSaveError = false
    @State private var showingBackupError = false
    @State private var backupFile: FactoryToolsBackupFile?
    @State private var showingImportPicker = false
    @State private var showingImportPreview = false
    @State private var importedBackup: FactoryToolsBackup?
    @State private var lastImportResult: FactoryToolsBackupImportResult?
    @State private var backupErrorMessageKey = "settings.backup.errorMessage"
    @State private var pairingCode: String?
    @State private var pairingCodeDraft = ""
    @State private var showingPeerError = false
    @State private var showingLegacyOutboxConfirmation = false
    @State private var showingPairingCodeChangeConfirmation = false
    @State private var showingPairingCodeReplacementConfirmation = false
    @State private var showingPairingCodeRemovalConfirmation = false
    @State private var showingPairingCodeRestoreConfirmation = false
    @ObservedObject private var peerTransport = LocalPeerCounterTransport.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("settings.home") {
                    TextField("settings.homeName", text: $homeNameDraft, prompt: Text("home.defaultName"))
                }
                Section {
                    if let settings = AppSettingsOrdering.primary(in: settings) {
                        Picker("settings.language", selection: Binding(
                            get: { AppLanguage.resolve(settings.language) },
                            set: {
                                do {
                                    try AppSettingsService(modelContext: modelContext).setLanguage($0, for: settings)
                                } catch {
                                    showingSaveError = true
                                }
                            }
                        )) {
                            Text("settings.language.system").tag(AppLanguage.system)
                            Text("settings.language.japanese").tag(AppLanguage.japanese)
                            Text("settings.language.english").tag(AppLanguage.english)
                        }
                    }
                }
                Section("settings.theme") {
                    LabeledContent("settings.currentTheme") {
                        Text("theme.industrialDark.name")
                    }
                }
                Section("pro.title") {
                    if proPurchases.hasPro {
                        Label("pro.unlocked", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(theme.accent)
                        Text("pro.unlockedDescription")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                    } else {
                        Text("pro.description")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                        if let product = proPurchases.product, ToolRegistry.hasProAssignments {
                            Button {
                                Task { await proPurchases.purchase() }
                            } label: {
                                HStack {
                                    Label("pro.purchase", systemImage: "cart")
                                    Spacer()
                                    Text(product.displayPrice)
                                }
                            }
                            .disabled(proPurchases.isLoading || !proPurchases.canPurchase)
                        } else {
                            if proPurchases.isConfigured {
                                if proPurchases.isLoading {
                                    Text("pro.loading")
                                        .font(theme.captionFont)
                                        .foregroundStyle(theme.secondaryText)
                                }
                                Button("pro.retry") {
                                    Task { await proPurchases.refresh() }
                                }
                                .disabled(proPurchases.isLoading)
                            } else {
                                Text("pro.setupPending")
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.secondaryText)
                            }
                        }
                        if proPurchases.isConfigured {
                            Button("pro.restore") {
                                Task { await proPurchases.restorePurchases() }
                            }
                            .disabled(proPurchases.isLoading)
                        }
                        if let statusMessageKey = proPurchases.statusMessageKey {
                            Text(LocalizedStringKey(statusMessageKey))
                                .font(theme.captionFont)
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                    if let product = proPurchases.product, ToolRegistry.hasProAssignments {
                        Label(
                            LocalizedStringKey(product.isFamilyShareable
                                ? "pro.familySharing.available"
                                : "pro.familySharing.unavailable"),
                            systemImage: product.isFamilyShareable ? "person.2.fill" : "person.fill"
                        )
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                    }
                }
                Section("settings.peer.title") {
                    Text("settings.peer.description")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                    if FeatureAccessRegistry.allows(.ipadCounterControl, isPro: proPurchases.hasPro) {
                        if UIDevice.current.userInterfaceIdiom == .pad {
                            TextField("settings.peer.enterCode", text: $pairingCodeDraft)
                                .font(theme.bodyFont.monospaced())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.asciiCapable)
                                .privacySensitive()
                                .redacted(reason: shouldRedactPairingSecrets ? .privacy : [])
                            Button("settings.peer.activate", action: requestPairingCodeSave)
                                .disabled(pairingCodeDraft.isEmpty)
                            if peerTransport.hasUnassignedLegacyOutboxError {
                                Text("settings.peer.unassignedCommandsError")
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.secondaryText)
                            }
                            if peerTransport.unassignedLegacyCommandCount > 0 {
                                Text("settings.peer.unassignedCommandsNotice")
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.secondaryText)
                                LabeledContent("settings.peer.unassignedCommands", value: "\(peerTransport.unassignedLegacyCommandCount)")
                                Button("settings.peer.reassignLegacy", systemImage: "arrowshape.turn.up.right") {
                                    showingLegacyOutboxConfirmation = true
                                }
                                .disabled(pairingCode == nil)
                            }
                            if pairingCode != nil {
                                Label("settings.peer.paired", systemImage: "checkmark.shield.fill")
                                    .foregroundStyle(theme.accent)
                                Button("settings.peer.connect", action: peerTransport.connectAsClient)
                                NavigationLink("settings.peer.dashboard") { PeerCounterView() }
                            }
                        } else {
                            if let pairingCode {
                                Text(pairingCode)
                                    .font(theme.captionFont.monospaced())
                                    .textSelection(.enabled)
                                    .foregroundStyle(theme.primaryText)
                                    .privacySensitive()
                                    .redacted(reason: shouldRedactPairingSecrets ? .privacy : [])
                                ShareLink(item: pairingCode) {
                                    Label("settings.peer.shareCode", systemImage: "square.and.arrow.up")
                                }
                            }
                            Button("settings.peer.generateCode", action: requestPairingCodeGeneration)
                            TextField("settings.peer.enterExistingCode", text: $pairingCodeDraft)
                                .font(theme.bodyFont.monospaced())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.asciiCapable)
                                .privacySensitive()
                                .redacted(reason: shouldRedactPairingSecrets ? .privacy : [])
                            Button("settings.peer.restoreCode", action: requestPairingCodeRestore)
                                .disabled(pairingCodeDraft.isEmpty)
                            if pairingCode != nil {
                                Button("settings.peer.enable", action: startPeerAuthority)
                            }
                        }
                    } else {
                        Label("pro.companionLocked", systemImage: "lock.fill")
                            .foregroundStyle(theme.secondaryText)
                        Button("pro.purchaseAction") {
                            Task { await proPurchases.purchase() }
                        }
                        .disabled(proPurchases.isLoading || !proPurchases.canPurchase)
                    }
                    Text(LocalizedStringKey(peerTransport.statusKey))
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                    if pairingCode != nil {
                        Button("settings.peer.remove", role: .destructive, action: requestPairingCodeRemoval)
                    }
                }
                Section("settings.privacy") {
                    Label("settings.privacy.localStorage", systemImage: "iphone")
                        .foregroundStyle(theme.primaryText)
                    Text("settings.privacy.localStorageDescription")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                    Text("settings.privacy.sharingDescription")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                    NavigationLink {
                        PrivacyDetailsView(policyURL: privacyPolicyURL)
                    } label: {
                        Label("settings.privacy.details", systemImage: "hand.raised")
                    }
                }
                Section("settings.support") {
                    if let supportURL {
                        Link(destination: supportURL) {
                            Label("settings.support.contact", systemImage: "questionmark.circle")
                        }
                    } else {
                        Text("settings.support.notConfigured")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                Section("settings.backup") {
                    Button(action: prepareBackup) {
                        Label("settings.backup.prepare", systemImage: "externaldrive")
                    }
                    .alert("settings.backup.error", isPresented: $showingBackupError) {
                        Button("common.done", role: .cancel) {}
                    } message: {
                        Text(LocalizedStringKey(backupErrorMessageKey))
                    }
                    Text("settings.backup.description")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                    Button {
                        showingImportPicker = true
                    } label: {
                        Label("settings.backup.chooseImport", systemImage: "square.and.arrow.down")
                    }
                    .fileImporter(
                        isPresented: $showingImportPicker,
                        allowedContentTypes: [.json],
                        allowsMultipleSelection: false,
                        onCompletion: handleBackupFileSelection
                    )
                    .confirmationDialog(
                        "settings.backup.importPreview.title",
                        isPresented: $showingImportPreview,
                        titleVisibility: .visible
                    ) {
                        Button(
                            proPurchases.hasPro ? "settings.backup.addCopy" : "settings.backup.restoreFreeCopy",
                            action: addBackupCopy
                        )
                        Button("common.cancel", role: .cancel) { importedBackup = nil }
                    } message: {
                        if let importedBackup {
                            Text(importPreviewMessage(for: importedBackup))
                        }
                    }
                    .alert("settings.backup.error", isPresented: $showingBackupError) {
                        Button("common.done", role: .cancel) {}
                    } message: {
                        Text(LocalizedStringKey(backupErrorMessageKey))
                    }
                    if let lastImportResult {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("settings.backup.importComplete", systemImage: "checkmark.circle.fill")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.accent)
                            Text(importResultSummary(lastImportResult))
                                .font(theme.captionFont)
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .onAppear {
                homeNameDraft = home.usesDefaultName ? "" : home.name
                pairingCode = LocalPeerPairingKeyStore.loadCode()
            }
            .navigationTitle("settings.title")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") {
                        do {
                            try HomeProfileService(modelContext: modelContext).setName(
                                homeNameDraft,
                                for: home,
                                isPro: proPurchases.hasPro
                            )
                            dismiss()
                        } catch {
                            showingSaveError = true
                        }
                    }
                }
            }
            .alert("error.saveFailed", isPresented: $showingSaveError) {
                Button("common.done", role: .cancel) {}
            } message: {
                Text("error.saveMessage")
            }
            .alert("settings.peer.error", isPresented: $showingPeerError) {
                Button("common.done", role: .cancel) {}
            } message: {
                Text("settings.peer.errorMessage")
            }
            .confirmationDialog(
                "settings.peer.reassignLegacy.title",
                isPresented: $showingLegacyOutboxConfirmation,
                titleVisibility: .visible
            ) {
                Button("settings.peer.reassignLegacy.confirm") {
                    peerTransport.reassignLegacyCommandsToCurrentPeer()
                }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("settings.peer.reassignLegacy.message")
            }
            .confirmationDialog(
                "settings.peer.changeCode.title",
                isPresented: $showingPairingCodeChangeConfirmation,
                titleVisibility: .visible
            ) {
                Button("settings.peer.changeCode.confirm", action: savePairingCode)
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("settings.peer.changeCode.message")
            }
            .confirmationDialog(
                "settings.peer.replaceCode.title",
                isPresented: $showingPairingCodeReplacementConfirmation,
                titleVisibility: .visible
            ) {
                Button("settings.peer.replaceCode.confirm", action: generatePairingCode)
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("settings.peer.replaceCode.message")
            }
            .confirmationDialog(
                "settings.peer.removeCode.title",
                isPresented: $showingPairingCodeRemovalConfirmation,
                titleVisibility: .visible
            ) {
                Button("settings.peer.removeCode.confirm", role: .destructive, action: removePairingCode)
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("settings.peer.removeCode.message")
            }
            .confirmationDialog(
                "settings.peer.restoreCode.title",
                isPresented: $showingPairingCodeRestoreConfirmation,
                titleVisibility: .visible
            ) {
                Button("settings.peer.restoreCode.confirm", action: restorePairingCode)
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("settings.peer.restoreCode.message")
            }
            .sheet(item: $backupFile) { file in
                NavigationStack {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("settings.backup.ready")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.primaryText)
                        ShareLink(item: file, preview: SharePreview(Text("settings.backup.preview"))) {
                            Label("settings.backup.share", systemImage: "square.and.arrow.up")
                                .font(theme.actionFont)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.accent)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(theme.background)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("common.done") { backupFile = nil }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func prepareBackup() {
        do {
            let data = try FactoryToolsBackupService(modelContext: modelContext).makeJSON()
            backupFile = FactoryToolsBackupFile(data: data)
        } catch {
            backupErrorMessageKey = (error as? FactoryToolsBackupError) == .backupTooLarge
                ? "settings.backup.tooLarge"
                : "settings.backup.errorMessage"
            showingBackupError = true
        }
    }

    private func requestPairingCodeGeneration() {
        guard LocalPeerPairingCodeChangePolicy.requiresConfirmationBeforeReset(currentCode: pairingCode) else {
            generatePairingCode()
            return
        }
        showingPairingCodeReplacementConfirmation = true
    }

    private func generatePairingCode() {
        do {
            let code = try LocalPeerPairingKeyStore.generateCode()
            try LocalPeerPairingKeyStore.save(code: code)
            peerTransport.stopAuthority()
            pairingCode = code
            if UIDevice.current.userInterfaceIdiom != .pad {
                startPeerAuthority()
            }
        } catch {
            showingPeerError = true
        }
    }

    private func savePairingCode() {
        let code = pairingCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            _ = try LocalPeerPairingKeyStore.keyData(from: code)
            try LocalPeerPairingKeyStore.save(code: code)
            peerTransport.disconnectClient()
            pairingCode = code
            pairingCodeDraft = ""
        } catch {
            showingPeerError = true
        }
    }

    private func requestPairingCodeSave() {
        let code = pairingCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            _ = try LocalPeerPairingKeyStore.keyData(from: code)
        } catch {
            showingPeerError = true
            return
        }
        if pairingCode != nil, !peerTransport.loadCurrentPairingOutboxForCodeChange() {
            showingPeerError = true
            return
        }
        guard LocalPeerPairingCodeChangePolicy.requiresConfirmation(
            currentCode: pairingCode,
            proposedCode: code,
            pendingCommandCount: peerTransport.pendingCommandCount
        ) else {
            savePairingCode()
            return
        }
        showingPairingCodeChangeConfirmation = true
    }

    private func removePairingCode() {
        do {
            try LocalPeerPairingKeyStore.remove()
            peerTransport.stopAuthority()
            peerTransport.disconnectClient()
            pairingCode = nil
            pairingCodeDraft = ""
        } catch {
            showingPeerError = true
        }
    }

    private func requestPairingCodeRemoval() {
        guard LocalPeerPairingCodeChangePolicy.requiresConfirmationBeforeReset(currentCode: pairingCode) else { return }
        showingPairingCodeRemovalConfirmation = true
    }

    private func requestPairingCodeRestore() {
        let code = pairingCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            _ = try LocalPeerPairingKeyStore.keyData(from: code)
        } catch {
            showingPeerError = true
            return
        }
        if pairingCode == code {
            pairingCodeDraft = ""
            startPeerAuthority()
            return
        }
        guard LocalPeerPairingCodeChangePolicy.requiresConfirmationBeforeAuthorityCodeChange(
            currentCode: pairingCode,
            proposedCode: code
        ) else {
            restorePairingCode()
            return
        }
        showingPairingCodeRestoreConfirmation = true
    }

    private func restorePairingCode() {
        let code = pairingCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            _ = try LocalPeerPairingKeyStore.keyData(from: code)
            try LocalPeerPairingKeyStore.save(code: code)
            peerTransport.stopAuthority()
            peerTransport.disconnectClient()
            pairingCode = code
            pairingCodeDraft = ""
            if UIDevice.current.userInterfaceIdiom != .pad {
                startPeerAuthority()
            }
        } catch {
            showingPeerError = true
        }
    }

    private func startPeerAuthority() {
        guard let container = modelContext.container else {
            showingPeerError = true
            return
        }
        peerTransport.startAuthority(modelContainer: container)
    }

    private func handleBackupFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessedSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if accessedSecurityScope { url.stopAccessingSecurityScopedResource() }
            }
            do {
                importedBackup = try FactoryToolsBackupService.readAndValidate(from: url)
                showingImportPreview = true
            } catch {
                backupErrorMessageKey = (error as? FactoryToolsBackupError) == .backupTooLarge
                    ? "settings.backup.tooLarge"
                    : "settings.backup.invalidFileMessage"
                showingBackupError = true
            }
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled { return }
            backupErrorMessageKey = "settings.backup.invalidFileMessage"
            showingBackupError = true
        }
    }

    private func addBackupCopy() {
        guard let importedBackup else { return }
        do {
            let result = try FactoryToolsBackupImportService(modelContext: modelContext).addCopy(
                from: importedBackup,
                importedHomeSuffix: localized("settings.backup.importedHomeSuffix"),
                defaultHomeName: localized("home.defaultName"),
                isPro: proPurchases.hasPro
            )
            lastImportResult = result
            self.importedBackup = nil
        } catch {
            backupErrorMessageKey = "settings.backup.importErrorMessage"
            showingBackupError = true
        }
    }

    private func importPreviewMessage(for backup: FactoryToolsBackup) -> String {
        let homeNames = backup.homes.map { home in
            home.usesDefaultName ? localized("home.defaultName") : home.name
        }.joined(separator: ", ")
        var rows = [
            "\(localized("settings.backup.exportedAt")): \(backup.exportedAt.formatted(.dateTime.year().month().day().hour().minute().locale(locale)))",
            "\(localized("settings.backup.homeNames")): \(homeNames)",
            "\(localized("settings.backup.homes")): \(backup.homes.count.formatted(.number.locale(locale)))",
            "\(localized("settings.backup.cards")): \(backup.cards.count.formatted(.number.locale(locale)))",
            "\(localized("settings.backup.sessions")): \(backup.sessions.count.formatted(.number.locale(locale)))",
            "\(localized("settings.backup.events")): \(backup.events.count.formatted(.number.locale(locale)))",
            "\(localized("settings.backup.commandReceipts")): \(backup.commandReceipts.count.formatted(.number.locale(locale)))",
            "\(localized("settings.backup.samples")): \(backup.cycleTimeSamples.count.formatted(.number.locale(locale)))",
            "\(localized("settings.backup.oeeRuns")): \(backup.oeeRuns.count.formatted(.number.locale(locale)))",
            localized("settings.backup.importPreview.message"),
            localized("settings.backup.preferencesKept")
        ]
        if !proPurchases.hasPro {
            rows.append(localized("settings.backup.freeRestoreNotice"))
        }
        rows.append(localized("settings.backup.reimportNotice"))
        return rows.joined(separator: "\n")
    }

    private func importResultSummary(_ result: FactoryToolsBackupImportResult) -> String {
        [
            "\(localized("settings.backup.homes")): \(result.homes.formatted(.number.locale(locale)))",
            "\(localized("settings.backup.cards")): \(result.cards.formatted(.number.locale(locale)))",
            "\(localized("settings.backup.sessions")): \(result.sessions.formatted(.number.locale(locale)))",
            "\(localized("settings.backup.events")): \(result.events.formatted(.number.locale(locale)))",
            "\(localized("settings.backup.commandReceipts")): \(result.commandReceipts.formatted(.number.locale(locale)))",
            "\(localized("settings.backup.samples")): \(result.cycleTimeSamples.formatted(.number.locale(locale)))",
            "\(localized("settings.backup.oeeRuns")): \(result.oeeRuns.formatted(.number.locale(locale)))"
        ].joined(separator: " · ")
    }

    private func localized(_ key: String) -> String {
        String(localized: LocalizedStringResource(
            String.LocalizationValue(stringLiteral: key),
            locale: locale
        ))
    }

    private var shouldRedactPairingSecrets: Bool {
        PairingSecretVisibilityPolicy.shouldRedact(
            sceneIsActive: scenePhase == .active,
            isScreenCaptured: isSceneCaptured
        )
    }

    private var privacyPolicyURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "FactoryToolsPrivacyPolicyURL") as? String else {
            return nil
        }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmedValue),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil else {
            return nil
        }
        return components.url
    }

    private var supportURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "FactoryToolsSupportURL") as? String else {
            return nil
        }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmedValue),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil else {
            return nil
        }
        return components.url
    }

}

private struct PrivacyDetailsView: View {
    @Environment(\.appTheme) private var theme
    let policyURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                detailSection("settings.privacy.details.local.title", bodyKey: "settings.privacy.details.local.body")
                detailSection("settings.privacy.details.devices.title", bodyKey: "settings.privacy.details.devices.body")
                detailSection("settings.privacy.details.export.title", bodyKey: "settings.privacy.details.export.body")
                detailSection("settings.privacy.details.delete.title", bodyKey: "settings.privacy.details.delete.body")
                if let policyURL {
                    Link(destination: policyURL) {
                        Label("settings.privacy.policyLink", systemImage: "arrow.up.right.square")
                            .font(theme.actionFont)
                    }
                    .tint(theme.accent)
                } else {
                    Text("settings.privacy.policyNotConfigured")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("settings.privacy.details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailSection(_ titleKey: String, bodyKey: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(titleKey))
                .font(theme.cardTitleFont)
                .foregroundStyle(theme.primaryText)
            Text(LocalizedStringKey(bodyKey))
                .font(theme.bodyFont)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .stroke(theme.border, lineWidth: theme.borderWidth)
        }
    }
}

struct FactoryToolsBackupFile: Transferable, Identifiable {
    let id = UUID()
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { file in
            file.data
        }
    }
}
