import SwiftData
import SwiftUI
import FactoryToolsCore
#if targetEnvironment(simulator)
import OSLog

private let screenshotCaptureLogger = Logger(subsystem: "com.factorytools.ios", category: "ScreenshotCapture")
#endif

struct HomeToolCardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @EnvironmentObject private var proPurchases: ProPurchaseManager
    @Query private var sessions: [ProductionSession]
    @ScaledMetric(relativeTo: .title) private var smallCounterScale: CGFloat = 1
    @ScaledMetric(relativeTo: .largeTitle) private var regularCounterScale: CGFloat = 1
    @State private var activeSheet: HomeToolCardSheet?
    @State private var showingSaveError = false
    @State private var saveErrorMessageKey = "error.saveMessage"
    @State private var showingResetConfirmation = false
    @State private var sessionPendingReset: ProductionSession?

    let card: ToolCard
    let home: HomeProfile
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let onMoveEarlier: () -> Void
    let onMoveLater: () -> Void
    let onDelete: () -> Void
    private let initialSheet: HomeToolCardSheet?

    init(
        card: ToolCard,
        home: HomeProfile,
        canMoveEarlier: Bool,
        canMoveLater: Bool,
        onMoveEarlier: @escaping () -> Void,
        onMoveLater: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        initialSheet: HomeToolCardSheet? = nil
    ) {
        self.card = card
        self.home = home
        self.canMoveEarlier = canMoveEarlier
        self.canMoveLater = canMoveLater
        self.onMoveEarlier = onMoveEarlier
        self.onMoveLater = onMoveLater
        self.onDelete = onDelete
        self.initialSheet = initialSheet
        _activeSheet = State(initialValue: initialSheet)
        let selectedHomeID = card.homeProfileID
        _sessions = Query(filter: #Predicate<ProductionSession> { $0.homeProfileID == selectedHomeID })
    }

    private var definition: ToolDefinition? {
        ToolID(rawValue: card.toolID).flatMap(ToolRegistry.definition(for:))
    }

    private var homeCardRoute: ToolCardRoute {
        guard let definition, definition.isAvailable else { return .comingSoon }
        return definition.homeCardRoute
    }

    private var canAccessTool: Bool {
        guard let definition, definition.isAvailable else { return true }
        return FeatureAccessRegistry.allows(definition.accessTier, isPro: proPurchases.hasPro)
    }

    private var session: ProductionSession? {
        ToolSessionAssignment.session(for: card, in: sessions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HomeCardPresentation.outerSpacing(for: card.size)) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(definition?.titleKey ?? "tool.unknown"))
                        .font(theme.cardTitleFont)
                        .foregroundStyle(theme.primaryText)
                    if HomeCardPresentation.showsSessionLabel(for: card.size)
                        && homeCardRoute == .productionCounter {
                        Text("counter.sessionLabel")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                Spacer(minLength: 4)
                Menu {
                    Button("home.moveEarlier", systemImage: "arrow.up", action: onMoveEarlier)
                        .disabled(!canMoveEarlier)
                    Button("home.moveLater", systemImage: "arrow.down", action: onMoveLater)
                        .disabled(!canMoveLater)
                    ForEach(supportedCardSizes) { size in
                        Button {
                            saveCardSize(size)
                        } label: {
                            if card.size == size { Label(LocalizedStringKey(size.titleKey), systemImage: "checkmark") }
                            else { Text(LocalizedStringKey(size.titleKey)) }
                        }
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("common.remove", systemImage: "trash")
                    }
                    if homeCardRoute.showsTargetSettings, session != nil {
                        Button("counter.goalSettings", systemImage: "slider.horizontal.3") { activeSheet = .counterSettings }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("common.cardOptions")
            }

            if !canAccessTool {
                Button { activeSheet = .proSettings } label: {
                    Label("pro.openSettings", systemImage: "lock.fill")
                        .font(theme.subheadlineFont)
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                }
            } else {
            switch homeCardRoute {
            case .productionCounter:
                if let session {
                    counterContent(session: session, showsTargetSettings: true)
                } else {
                    Label("counter.sessionUnavailable", systemImage: "exclamationmark.triangle")
                        .font(theme.subheadlineFont)
                        .foregroundStyle(theme.warning)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                }
            case .cycleTime:
                toolAction("cycleTime.open", systemImage: "timer", destination: .cycleTime)
            case .taktTime:
                toolAction("taktTime.open", systemImage: "clock", destination: .taktTime)
            case .oee:
                toolAction("oee.open", systemImage: "gauge", destination: .oee)
            case .productionProgress:
                if let session {
                    progressContent(session: session)
                } else {
                    Label("counter.sessionUnavailable", systemImage: "exclamationmark.triangle")
                        .font(theme.subheadlineFont)
                        .foregroundStyle(theme.warning)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                }
            case .defectCounter:
                if let session {
                    counterContent(session: session, showsTargetSettings: false)
                } else {
                    Label("counter.sessionUnavailable", systemImage: "exclamationmark.triangle")
                        .font(theme.subheadlineFont)
                        .foregroundStyle(theme.warning)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                }
            case .defectRate:
                defectRateContent()
            case .boxCalculator:
                toolAction("boxCalculator.open", systemImage: "shippingbox", destination: .boxCalculator)
            case .unitConverter:
                toolAction("unitConverter.open", systemImage: "arrow.left.arrow.right", destination: .unitConverter)
            case .comingSoon:
                Label("tool.comingSoon", systemImage: "wrench.and.screwdriver")
                    .font(theme.subheadlineFont)
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            }
            }
        }
        .padding(HomeCardPresentation.padding(for: card.size))
        .frame(maxWidth: .infinity, minHeight: HomeCardPresentation.minimumHeight(for: card.size), alignment: .leading)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius).stroke(theme.border, lineWidth: theme.borderWidth))
#if targetEnvironment(simulator)
        .onAppear(perform: logScreenshotCaptureState)
        .onChange(of: sessions.count) { _, _ in logScreenshotCaptureState() }
        .onChange(of: session?.currentCount) { _, _ in logScreenshotCaptureState() }
#endif
        .sheet(item: $activeSheet) { destination in
            Group {
                switch destination {
                case .counterSettings:
                    if let session { CounterSettingsView(session: session) }
                case .customQuickAdd:
                    if let session { CounterQuickAddView(session: session) }
                case .history:
                    if let session { CounterHistoryView(session: session) }
                case .cycleTime:
                    CycleTimeCalculatorView(homeProfileID: card.homeProfileID, screenshotDemoValues: initialSheet == .cycleTime)
                case .taktTime:
                    TaktTimeCalculatorView(screenshotDemoValues: initialSheet == .taktTime)
                case .oee:
                    OEECalculatorView(homeProfileID: card.homeProfileID)
                case .boxCalculator:
                    BoxCalculatorView()
                case .unitConverter:
                    UnitConverterView()
                case .proSettings:
                    AppSettingsView(home: home)
                }
            }
            .presentationDetents(initialSheet == nil ? [.medium, .large] : [.large])
            .presentationDragIndicator(initialSheet == nil ? .visible : .hidden)
        }
        .alert("error.saveFailed", isPresented: $showingSaveError) {
            Button("common.done", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(saveErrorMessageKey))
        }
        .confirmationDialog(
            "counter.resetConfirmation.title",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(role: .destructive, action: confirmReset) {
                Label("counter.reset", systemImage: "arrow.counterclockwise")
            }
            Button("common.cancel", role: .cancel) { sessionPendingReset = nil }
        } message: {
            Text("counter.resetConfirmation.message")
        }
    }

    @ViewBuilder
    private func counterContent(session: ProductionSession, showsTargetSettings: Bool) -> some View {
        let isAtMaximumCount = session.currentCount == Int.max
        VStack(alignment: .leading, spacing: HomeCardPresentation.counterSpacing(for: card.size)) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formattedCount(session.currentCount))
                    .font(theme.counterFont(
                        for: card.size,
                        smallScale: smallCounterScale,
                        regularScale: regularCounterScale
                    ))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(theme.primaryText)
                    .contentTransition(.numericText())
                    .accessibilityLabel("counter.currentCount")
                    .accessibilityValue(Text(formattedCount(session.currentCount)))
                if HomeCardPresentation.showsTarget(for: card.size) && session.targetCount > 0 {
                    Text("/ \(formattedCount(session.targetCount))")
                        .font(theme.calloutFont)
                        .foregroundStyle(theme.secondaryText)
                        .accessibilityLabel("counter.goal")
                        .accessibilityValue(Text(formattedCount(session.targetCount)))
                }
                Spacer()
            }
            if HomeCardPresentation.showsProgress(for: card.size) && session.targetCount > 0 {
                ProgressView(value: ProductionProgressMath.fraction(
                    currentCount: session.currentCount,
                    targetCount: session.targetCount
                ))
                    .tint(theme.accent)
                    .accessibilityLabel("counter.progress")
                    .accessibilityValue(Text(HomeCardPresentation.formattedProgress(
                        currentCount: session.currentCount,
                        targetCount: session.targetCount,
                        locale: locale
                    )))
                HStack(spacing: 4) {
                    Text("counter.remaining")
                    Text(formattedCount(max(session.targetCount - session.currentCount, 0)))
                }
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)
            }
            HStack(spacing: HomeCardPresentation.actionSpacing) {
                Button { performCounterAction { try CounterService(modelContext: modelContext).decrement(session: session) } } label: {
                    Image(systemName: "minus")
                        .foregroundStyle(session.currentCount == 0 ? theme.secondaryText : theme.primaryText)
                        .frame(
                            minWidth: HomeCardPresentation.minimumActionWidth,
                            maxWidth: .infinity,
                            minHeight: HomeCardPresentation.minimumActionWidth
                        )
                        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: theme.cornerRadius / 2))
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.cornerRadius / 2)
                                .stroke(theme.border, lineWidth: theme.borderWidth)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("counter.minusOne")
                .disabled(session.currentCount == 0)
                Button { performCounterAction { try CounterService(modelContext: modelContext).increment(session: session) } } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(isAtMaximumCount ? theme.secondaryText : theme.accentForeground)
                        .frame(
                            minWidth: HomeCardPresentation.minimumActionWidth,
                            maxWidth: .infinity,
                            minHeight: HomeCardPresentation.minimumActionWidth
                        )
                        .background(
                            isAtMaximumCount ? theme.cardBackground : theme.accent,
                            in: RoundedRectangle(cornerRadius: theme.cornerRadius / 2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.cornerRadius / 2)
                                .stroke(theme.border, lineWidth: theme.borderWidth)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("counter.plusOne")
                .disabled(isAtMaximumCount)
                Menu {
                    Button("counter.quickAddFive") { performCounterAction { try CounterService(modelContext: modelContext).quickAdd(5, to: session) } }
                        .disabled(isAtMaximumCount)
                    Button("counter.quickAddTen") { performCounterAction { try CounterService(modelContext: modelContext).quickAdd(10, to: session) } }
                        .disabled(isAtMaximumCount)
                    Button("counter.quickAddCustom", systemImage: "plus") { activeSheet = .customQuickAdd }
                        .disabled(isAtMaximumCount)
                    Button("counter.history", systemImage: "clock.arrow.circlepath") { activeSheet = .history }
                    CounterUndoMenuItem(sessionID: session.id) {
                        performCounterAction { try CounterService(modelContext: modelContext).undo(session: session) }
                    }
                    Button(role: .destructive) {
                        sessionPendingReset = session
                        showingResetConfirmation = true
                    } label: {
                        Label("counter.reset", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(session.currentCount == 0)
                    if showsTargetSettings {
                        Button("counter.goalSettings", systemImage: "slider.horizontal.3") { activeSheet = .counterSettings }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(theme.menuIconFont)
                        .frame(width: HomeCardPresentation.minimumActionWidth, height: HomeCardPresentation.minimumActionWidth)
                }
                .accessibilityLabel("counter.moreActions")
            }
        }
    }

    private func toolAction(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        destination: HomeToolCardSheet
    ) -> some View {
        Button { activeSheet = destination } label: {
            Label(titleKey, systemImage: systemImage)
                .font(theme.actionFont)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(theme.accent)
    }

    private func progressContent(session: ProductionSession) -> some View {
        VStack(alignment: .leading, spacing: HomeCardPresentation.counterSpacing(for: card.size)) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formattedCount(session.currentCount))
                    .font(theme.homeTitleFont)
                    .foregroundStyle(theme.primaryText)
                    .contentTransition(.numericText())
                    .accessibilityLabel("counter.currentCount")
                    .accessibilityValue(Text(formattedCount(session.currentCount)))
                Text("progress.currentCount")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                Spacer(minLength: 4)
                if session.targetCount > 0 {
                    Text("/ \(formattedCount(session.targetCount))")
                        .font(theme.calloutFont)
                        .foregroundStyle(theme.secondaryText)
                        .accessibilityLabel("counter.goal")
                        .accessibilityValue(Text(formattedCount(session.targetCount)))
                }
            }
            if session.targetCount > 0 {
                ProgressView(value: ProductionProgressMath.fraction(
                    currentCount: session.currentCount,
                    targetCount: session.targetCount
                ))
                    .tint(theme.accent)
                    .accessibilityLabel("counter.progress")
                    .accessibilityValue(Text(HomeCardPresentation.formattedProgress(
                        currentCount: session.currentCount,
                        targetCount: session.targetCount,
                        locale: locale
                    )))
                HStack(spacing: 4) {
                    Text("counter.remaining")
                    Text(formattedCount(max(session.targetCount - session.currentCount, 0)))
                    if session.currentCount >= session.targetCount {
                        Text("progress.targetReached")
                            .foregroundStyle(theme.accent)
                    }
                }
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)
            } else {
                Text("progress.targetNotSet")
                    .font(theme.subheadlineFont)
                    .foregroundStyle(theme.secondaryText)
                Button("progress.setTarget", systemImage: "slider.horizontal.3") {
                    activeSheet = .counterSettings
                }
                .font(theme.actionFont)
                .tint(theme.accent)
            }
        }
    }

    @ViewBuilder
    private func defectRateContent() -> some View {
        let production = ToolSessionAssignment.session(for: card.homeProfileID, toolID: .productionCounter, in: sessions)
        let defects = ToolSessionAssignment.session(for: card.homeProfileID, toolID: .defectCounter, in: sessions)
        if let production, let defects,
           let rate = DefectRateMath.fraction(defectCount: defects.currentCount, productionCount: production.currentCount) {
            VStack(alignment: .leading, spacing: 6) {
                Text(rate.formatted(.percent.precision(.fractionLength(1)).locale(locale)))
                    .font(theme.homeTitleFont)
                    .foregroundStyle(theme.primaryText)
                    .contentTransition(.numericText())
                    .accessibilityLabel("defectRate.value")
                    .accessibilityValue(Text(rate.formatted(.percent.precision(.fractionLength(1)).locale(locale))))
                Text("\(formattedCount(defects.currentCount)) / \(formattedCount(production.currentCount))")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityLabel("defectRate.counts")
                    .accessibilityValue(Text("\(formattedCount(defects.currentCount)) / \(formattedCount(production.currentCount))"))
            }
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        } else if let production, let defects, production.currentCount == 0 {
            Label("defectRate.noProduction", systemImage: "chart.bar.xaxis")
                .font(theme.subheadlineFont)
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        } else {
            Label("defectRate.needsCounters", systemImage: "exclamationmark.triangle")
                .font(theme.subheadlineFont)
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        }
    }

    private func saveCardSize(_ size: ToolCardSize) {
        do {
            try HomeCardService(modelContext: modelContext).setSize(size, for: card)
        } catch {
            presentSaveError()
        }
    }

    private func performCounterAction(_ action: () throws -> Void) {
        do {
            try action()
        } catch CounterServiceError.eventSequenceExhausted {
            presentSaveError(messageKey: "error.counterEventLimit")
        } catch CounterServiceError.eventDeltaCannotBeReversed {
            presentSaveError(messageKey: "error.counterEventInvalid")
        } catch {
            presentSaveError()
        }
    }

    private func confirmReset() {
        guard let sessionPendingReset else { return }
        self.sessionPendingReset = nil
        performCounterAction {
            try CounterService(modelContext: modelContext).reset(session: sessionPendingReset)
        }
    }

    private func presentSaveError(messageKey: String = "error.saveMessage") {
        saveErrorMessageKey = messageKey
        showingSaveError = true
    }

    private var supportedCardSizes: [ToolCardSize] {
        guard let definition else { return ToolCardSize.allCases }
        return ToolCardSize.allCases.filter { definition.supportedCardSizes.contains($0) }
    }

    private func formattedCount(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    #if targetEnvironment(simulator)
    private func logScreenshotCaptureState() {
        guard ProcessInfo.processInfo.arguments.contains("--factorytools-screenshot-demo"),
              card.toolID == ToolID.productionCounter.rawValue else { return }
        let captureState = [
            "locale=\(locale.identifier)",
            "home=\(home.id.uuidString)",
            "sessionCount=\(sessions.count)",
            "current=\(session?.currentCount.description ?? "missing")",
            "target=\(session?.targetCount.description ?? "missing")",
        ].joined(separator: " ")
        screenshotCaptureLogger.notice("\(captureState, privacy: .public)")
    }
    #endif

}

private struct CounterUndoMenuItem: View {
    @Query private var events: [CountEvent]

    let action: () -> Void

    init(sessionID: UUID, action: @escaping () -> Void) {
        self.action = action
        let selectedSessionID = sessionID
        _events = Query(filter: #Predicate<CountEvent> { $0.sessionID == selectedSessionID })
    }

    var body: some View {
        Button("counter.undo", systemImage: "arrow.uturn.backward", action: action)
            .disabled(CounterHistoryOrdering.latestUndoableEvent(in: events) == nil)
    }
}

enum HomeCardPresentation {
    static func formattedProgress(currentCount: Int, targetCount: Int, locale: Locale) -> String {
        ProductionProgressMath.fraction(currentCount: currentCount, targetCount: targetCount)
            .formatted(.percent.precision(.fractionLength(1)).locale(locale))
    }
    static let minimumActionWidth: CGFloat = 44
    static let actionSpacing: CGFloat = 2

    static func minimumHeight(for size: ToolCardSize) -> CGFloat {
        switch size {
        case .small: 146
        case .medium: 184
        case .large: 232
        }
    }

    static func outerSpacing(for size: ToolCardSize) -> CGFloat {
        size == .small ? 8 : 14
    }

    static func counterSpacing(for size: ToolCardSize) -> CGFloat {
        size == .small ? 6 : 12
    }

    static func padding(for size: ToolCardSize) -> CGFloat {
        size == .large ? 16 : 12
    }

    static func showsSessionLabel(for size: ToolCardSize) -> Bool {
        size != .small
    }

    static func showsTarget(for size: ToolCardSize) -> Bool {
        size != .small
    }

    static func showsProgress(for size: ToolCardSize) -> Bool {
        size == .large
    }

}

private extension ToolCardSize {
    var titleKey: String {
        switch self {
        case .small: "card.size.small"
        case .medium: "card.size.medium"
        case .large: "card.size.large"
        }
    }
}

enum HomeToolCardSheet: String, Identifiable {
    case counterSettings
    case customQuickAdd
    case history
    case cycleTime
    case taktTime
    case oee
    case boxCalculator
    case unitConverter
    case proSettings

    var id: String { rawValue }
}
