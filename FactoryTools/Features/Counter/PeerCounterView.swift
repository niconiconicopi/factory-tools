import FactoryToolsCore
import Foundation
import SwiftUI

#if targetEnvironment(simulator)
enum PeerCounterScreenshotMode: Equatable {
    case connected
    case offline
}
#endif

struct PeerCounterView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var transport = LocalPeerCounterTransport.shared
    @State private var activeSheet: PeerCounterSheet?
    @State private var sessionPendingReset: WatchCounterSessionSnapshot?
#if targetEnvironment(simulator)
    private let screenshotDemoMode: PeerCounterScreenshotMode?
    init(screenshotDemoMode: PeerCounterScreenshotMode? = nil) {
        self.screenshotDemoMode = screenshotDemoMode
    }
#else
    init() {}
#endif

    private var displayedStatusKey: String {
#if targetEnvironment(simulator)
        switch screenshotDemoMode {
        case .connected: "peer.status.connected"
        case .offline: "peer.status.reconnecting"
        case nil: transport.statusKey
        }
#else
        transport.statusKey
#endif
    }

    private var displayedCatalog: [WatchCounterSessionSnapshot] {
#if targetEnvironment(simulator)
        screenshotDemoMode == nil ? transport.catalog : Self.screenshotDemoCatalog
#else
        transport.catalog
#endif
    }

    private var displayedPendingCommandCount: Int {
#if targetEnvironment(simulator)
        switch screenshotDemoMode {
        case .offline: 2
        case .connected: 0
        case nil: transport.pendingCommandCount
        }
#else
        transport.pendingCommandCount
#endif
    }

#if targetEnvironment(simulator)
    private static let screenshotDemoCatalog = [
        WatchCounterSessionSnapshot(
            sessionID: UUID(),
            homeProfileID: UUID(),
            homeName: "Assembly",
            toolID: .productionCounter,
            sessionName: "Line A",
            currentCount: 286,
            targetCount: 300,
            latestUndoableEventID: UUID(),
            defaultSessionNameToolID: nil,
            homeNameIsDefault: false
        )
    ]
#endif

    var body: some View {
        List {
            Section("peer.connection") {
                Text(LocalizedStringKey(displayedStatusKey))
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                LabeledContent("peer.pendingCommands", value: formattedCount(displayedPendingCommandCount))
                Button("peer.refresh", systemImage: "arrow.clockwise", action: requestCatalog)
            }
            Section("peer.counters") {
                if displayedCatalog.isEmpty {
                    ContentUnavailableView("peer.empty.title", systemImage: "dot.radiowaves.left.and.right", description: Text("peer.empty.message"))
                } else {
                    ForEach(displayedCatalog) { session in
                        counterRow(session)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle("peer.dashboard")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("peer.disconnect", systemImage: "wifi.slash", action: disconnect)
            }
        }
        .sheet(item: $activeSheet) { destination in
            switch destination {
            case .target(let session):
                PeerTargetEditView(session: session)
            case .quickAdd(let session):
                PeerQuickAddView(session: session)
            }
        }
        .confirmationDialog(
            "counter.resetConfirmation.title",
            isPresented: Binding(
                get: { sessionPendingReset != nil },
                set: { if !$0 { sessionPendingReset = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("counter.reset", role: .destructive) {
                if let sessionPendingReset {
                    enqueue(sessionPendingReset, operation: .reset)
                }
                sessionPendingReset = nil
            }
            Button("common.cancel", role: .cancel) { sessionPendingReset = nil }
        } message: {
            Text("counter.resetConfirmation.message")
        }
        .onAppear {
#if targetEnvironment(simulator)
            guard screenshotDemoMode == nil else { return }
#endif
            transport.resumeClient()
        }
        .onChange(of: scenePhase) { _, phase in
#if targetEnvironment(simulator)
            if screenshotDemoMode == nil, phase == .active { transport.resumeClient() }
#else
            if phase == .active { transport.resumeClient() }
#endif
        }
        .tint(theme.accent)
    }

    private func counterRow(_ session: WatchCounterSessionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                peerSessionNameText(session)
                    .font(theme.actionFont)
                    .foregroundStyle(theme.primaryText)
                peerHomeNameText(session.homeName, isDefault: session.homeNameIsDefault)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formattedCount(session.currentCount))
                    .font(theme.counterFont(for: .medium, smallScale: 1, regularScale: 1))
                    .monospacedDigit()
                    .accessibilityLabel("counter.currentCount")
                    .accessibilityValue(Text(formattedCount(session.currentCount)))
                Text("/ \(formattedCount(session.targetCount))")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityLabel("counter.goal")
                    .accessibilityValue(Text(formattedCount(session.targetCount)))
            }
            HStack(spacing: 8) {
                Button {
                    enqueue(session, operation: .decrement)
                } label: {
                    Image(systemName: "minus")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("counter.minusOne")
                .buttonStyle(.bordered)
                Button {
                    enqueue(session, operation: .increment)
                } label: {
                    Label("counter.plusOne", systemImage: "plus")
                        .font(theme.actionFont)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                Menu {
                    Button("counter.quickAddFive") { enqueue(session, operation: .quickAdd(5)) }
                    Button("counter.quickAddTen") { enqueue(session, operation: .quickAdd(10)) }
                    Button("counter.quickAddCustom", systemImage: "plus") {
                        activeSheet = .quickAdd(session)
                    }
                    if let eventID = session.latestUndoableEventID {
                        Button("counter.undo") { enqueue(session, operation: .undo(eventID: eventID)) }
                    }
                    Button("counter.goalSettings", systemImage: "slider.horizontal.3") {
                        activeSheet = .target(session)
                    }
                    Button("counter.reset", systemImage: "arrow.counterclockwise", role: .destructive) {
                        sessionPendingReset = session
                    }
                } label: {
                    Label("counter.quickAdd", systemImage: "plus.forwardslash.minus")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
        .listRowBackground(theme.cardBackground)
    }

    private func enqueue(_ session: WatchCounterSessionSnapshot, operation: CounterCommandOperation) {
#if targetEnvironment(simulator)
        guard screenshotDemoMode == nil else { return }
#endif
        transport.enqueue(CounterCommand(sessionID: session.sessionID, operation: operation))
    }

    private func requestCatalog() {
#if targetEnvironment(simulator)
        guard screenshotDemoMode == nil else { return }
#endif
        transport.requestCatalog()
    }

    private func disconnect() {
#if targetEnvironment(simulator)
        guard screenshotDemoMode == nil else { return }
#endif
        transport.disconnectClient()
    }

    private func formattedCount(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }
}

private func peerSessionNameText(_ session: WatchCounterSessionSnapshot) -> Text {
    if session.defaultSessionNameToolID == .productionCounter {
        Text("counter.defaultSessionName")
    } else if session.defaultSessionNameToolID == .defectCounter {
        Text("defect.defaultSessionName")
    } else {
        Text(verbatim: session.sessionName)
    }
}

private func peerHomeNameText(_ name: String, isDefault: Bool?) -> Text {
    isDefault == true ? Text("home.defaultName") : Text(verbatim: name)
}

private enum PeerCounterSheet: Identifiable {
    case target(WatchCounterSessionSnapshot)
    case quickAdd(WatchCounterSessionSnapshot)

    var id: String {
        switch self {
        case .target(let session): "target-\(session.sessionID.uuidString)"
        case .quickAdd(let session): "quick-add-\(session.sessionID.uuidString)"
        }
    }
}

private struct PeerTargetEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @ObservedObject private var transport = LocalPeerCounterTransport.shared
    @State private var targetText: String

    let session: WatchCounterSessionSnapshot

    init(session: WatchCounterSessionSnapshot) {
        self.session = session
        _targetText = State(initialValue: String(session.targetCount))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("counter.goal", text: $targetText)
                        .keyboardType(.numberPad)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("counter.settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save", action: save)
                        .disabled(parsedTarget == nil || (parsedTarget ?? -1) < 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .tint(theme.accent)
    }

    private var parsedTarget: Int? {
        LocalizedNumberParser.parseInteger(targetText, locale: locale)
    }

    private func save() {
        guard let target = parsedTarget, target >= 0 else { return }
        transport.enqueue(CounterCommand(sessionID: session.sessionID, operation: .setTarget(target)))
        dismiss()
    }
}

private struct PeerQuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @ObservedObject private var transport = LocalPeerCounterTransport.shared
    @State private var amountText = ""

    let session: WatchCounterSessionSnapshot

    var body: some View {
        NavigationStack {
            Form {
                Section("counter.quickAddAmountSection") {
                    TextField("counter.quickAddAmount", text: $amountText)
                        .keyboardType(.numberPad)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("counter.quickAddCustom")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("counter.quickAddApply", action: save)
                        .disabled(parsedAmount == nil || (parsedAmount ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .tint(theme.accent)
    }

    private var parsedAmount: Int? {
        LocalizedNumberParser.parseInteger(amountText, locale: locale)
    }

    private func save() {
        guard let amount = parsedAmount, amount > 0 else { return }
        transport.enqueue(CounterCommand(sessionID: session.sessionID, operation: .quickAdd(amount)))
        dismiss()
    }
}
