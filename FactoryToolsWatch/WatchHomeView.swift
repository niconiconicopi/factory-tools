import FactoryToolsCore
import SwiftUI

struct WatchHomeView: View {
    @EnvironmentObject private var model: WatchCounterModel
    @Environment(\.scenePhase) private var scenePhase

    private var displayLocale: Locale {
        switch model.displayLanguage {
        case .system: .current
        case .japanese: Locale(identifier: "ja")
        case .english: Locale(identifier: "en")
        }
    }

    var body: some View {
        NavigationStack {
            if model.storageUnavailable {
                ContentUnavailableView {
                    Label("watch.storageUnavailable", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("watch.storageUnavailable.message")
                } actions: {
                    Button {
                        model.retryStorage()
                    } label: {
                        Label("watch.refresh", systemImage: "arrow.clockwise")
                    }
                }
            } else if model.sessions.isEmpty && model.cycleTimeHome == nil && model.progressCards.isEmpty {
                ContentUnavailableView {
                    Label("watch.noCounters", systemImage: "counterclockwise")
                } description: {
                    Text(model.queueLimitReached
                        ? "watch.queueFull.message"
                        : (model.latestStatus?.messageKey ?? "watch.noCounters.message"))
                } actions: {
                    Button {
                        model.refreshCatalog()
                    } label: {
                        Label("watch.refresh", systemImage: "arrow.clockwise")
                    }
                }
            } else {
                List {
                        Section {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(model.isReachable ? WatchTheme.accent : WatchTheme.secondaryText)
                                    .frame(width: 6, height: 6)
                                Text(LocalizedStringKey(
                                    model.isReachable ? "watch.connection.connected" : "watch.connection.waiting"
                                ))
                                    .font(.caption2)
                                    .foregroundStyle(WatchTheme.secondaryText)
                                Spacer(minLength: 2)
                                if model.pendingCount > 0 {
                                    HStack(spacing: 3) {
                                        Text("watch.pending")
                                        Text(model.pendingCount, format: .number)
                                    }
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(WatchTheme.accent)
                                }
                            }
                            if model.queueLimitReached {
                                Label("watch.queueFull.message", systemImage: "exclamationmark.triangle")
                                    .font(.caption2)
                                    .foregroundStyle(WatchTheme.warning)
                            }
                            if model.latestStatus == .rejected {
                                HStack {
                                    Label("watch.status.rejected", systemImage: "exclamationmark.triangle")
                                        .font(.caption2)
                                        .foregroundStyle(WatchTheme.warning)
                                    Spacer()
                                    Button {
                                        model.refreshCatalog()
                                    } label: {
                                        Label("watch.refresh", systemImage: "arrow.clockwise")
                                    }
                                    .labelStyle(.iconOnly)
                                }
                            }
                        }
                        if !model.progressCards.isEmpty {
                            Section("watch.productionProgress") {
                                ForEach(model.progressCards) { progress in
                                    NavigationLink {
                                        WatchProductionProgressDetailView(progress: progress)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("watch.productionProgress")
                                                .font(.headline)
                                                .foregroundStyle(WatchTheme.primaryText)
                                            watchHomeNameText(progress.homeName, isDefault: progress.homeNameIsDefault)
                                                .font(.caption2)
                                                .foregroundStyle(WatchTheme.secondaryText)
                                                .lineLimit(1)
                                            HStack(spacing: 3) {
                                                Text(progress.currentCount, format: .number)
                                                    .monospacedDigit()
                                                if progress.targetCount > 0 {
                                                    Text("/")
                                                    Text(progress.targetCount, format: .number)
                                                        .monospacedDigit()
                                                }
                                            }
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(WatchTheme.accent)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                        }
                        if let cycleTimeHome = model.cycleTimeHome {
                            Section("watch.cycleTime") {
                                NavigationLink {
                                    WatchCycleTimeDetailView(home: cycleTimeHome)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("watch.cycleTime.title")
                                            .font(.headline)
                                            .foregroundStyle(WatchTheme.primaryText)
                                        watchHomeNameText(cycleTimeHome.homeName, isDefault: cycleTimeHome.homeNameIsDefault)
                                            .font(.caption2)
                                            .foregroundStyle(WatchTheme.secondaryText)
                                        if model.cycleTimerRunning {
                                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                                Text(model.cycleElapsed(at: context.date), format: .number.precision(.fractionLength(1)))
                                                    .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                                                    .foregroundStyle(WatchTheme.accent)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        ForEach(model.sessions) { session in
                            NavigationLink {
                                WatchCounterDetailView(sessionID: session.sessionID)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    watchSessionNameText(session)
                                        .font(.headline)
                                        .foregroundStyle(WatchTheme.primaryText)
                                        .lineLimit(1)
                                    watchHomeNameText(session.homeName, isDefault: session.homeNameIsDefault)
                                        .font(.caption2)
                                        .foregroundStyle(WatchTheme.secondaryText)
                                    Text(session.currentCount, format: .number)
                                        .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                                        .foregroundStyle(WatchTheme.accent)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .refreshable { model.refreshCatalog() }
                }
            }
            .navigationTitle("watch.title")
            .toolbarColorScheme(.dark)
            .background(WatchTheme.background)
            .task { model.refreshCatalog() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.refreshCatalog() }
            }
        .environment(\.locale, displayLocale)
        .tint(WatchTheme.accent)
        .preferredColorScheme(.dark)
    }
}

private struct WatchProductionProgressDetailView: View {
    @Environment(\.locale) private var locale
    let progress: WatchProductionProgressSnapshot

    var body: some View {
        let progressFraction = ProductionProgressMath.fraction(
            currentCount: progress.currentCount,
            targetCount: progress.targetCount
        )
        let formattedProgress = progressFraction.formatted(.percent.precision(.fractionLength(0...1)).locale(locale))
        ScrollView {
            VStack(spacing: 10) {
                watchHomeNameText(progress.homeName, isDefault: progress.homeNameIsDefault)
                    .font(.caption2)
                    .foregroundStyle(WatchTheme.secondaryText)
                    .lineLimit(1)
                Text("watch.productionProgress")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(progress.currentCount, format: .number)
                    .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(WatchTheme.accent)
                    .accessibilityLabel("watch.progress.current")
                    .accessibilityValue(Text(progress.currentCount, format: .number))
                if progress.targetCount > 0 {
                    ProgressView(value: progressFraction)
                        .tint(WatchTheme.accent)
                        .accessibilityLabel("watch.progress.fraction")
                        .accessibilityValue(Text(formattedProgress))
                    Text(formattedProgress)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(WatchTheme.accent)
                    HStack(spacing: 3) {
                        Text("watch.target")
                        Text(progress.targetCount, format: .number)
                            .monospacedDigit()
                    }
                    .font(.caption2)
                    .foregroundStyle(WatchTheme.secondaryText)
                } else {
                    Text("watch.productionProgress.noTarget")
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
        }
        .navigationTitle("watch.productionProgress")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private func watchSessionNameText(_ session: WatchCounterSessionSnapshot) -> Text {
    if session.defaultSessionNameToolID == .productionCounter {
        Text("counter.defaultSessionName")
    } else if session.defaultSessionNameToolID == .defectCounter {
        Text("defect.defaultSessionName")
    } else {
        Text(verbatim: session.sessionName)
    }
}

private func watchHomeNameText(_ name: String, isDefault: Bool?) -> Text {
    isDefault == true ? Text("home.defaultName") : Text(verbatim: name)
}

private struct WatchCycleTimeDetailView: View {
    @EnvironmentObject private var model: WatchCounterModel
    @State private var showingResetConfirmation = false
    let home: WatchCycleTimeHomeSnapshot

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                watchHomeNameText(home.homeName, isDefault: home.homeNameIsDefault)
                    .font(.caption2)
                    .foregroundStyle(WatchTheme.secondaryText)
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    Text(model.cycleElapsed(at: context.date), format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(WatchTheme.accent)
                        .contentTransition(.numericText())
                }
                Text("watch.cycleTime.unitNote")
                    .font(.caption2)
                    .foregroundStyle(WatchTheme.secondaryText)
                if !model.cycleTimerCanUse(homeProfileID: home.homeProfileID) {
                    Text("watch.cycleTime.homeChanged")
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.warning)
                }
                if model.cycleTimePendingCount > 0 {
                    HStack(spacing: 3) {
                        Text("watch.pending")
                        Text(model.cycleTimePendingCount, format: .number)
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(WatchTheme.accent)
                }
                if model.cycleTimeQueueLimitReached {
                    Label("watch.queueFull.message", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.warning)
                }
                if let status = model.latestCycleTimeStatus {
                    Text(status.messageKey)
                        .font(.caption2)
                        .foregroundStyle(status == .rejected ? WatchTheme.warning : WatchTheme.secondaryText)
                }
                HStack(spacing: 8) {
                    Button {
                        if model.cycleElapsed(at: .now) > 0 {
                            showingResetConfirmation = true
                        } else {
                            model.resetCycleTimer()
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .tint(WatchTheme.panel)
                    .accessibilityLabel("watch.cycleTime.reset")
                    .accessibilityHint("watch.cycleTime.reset.hint")
                    Button {
                        if model.cycleTimerRunning {
                            model.pauseCycleTimer()
                        } else {
                            model.startCycleTimer(for: home)
                        }
                    } label: {
                        Image(systemName: model.cycleTimerRunning ? "pause.fill" : "play.fill")
                    }
                    .tint(WatchTheme.accent)
                    .accessibilityLabel(model.cycleTimerRunning
                        ? "watch.cycleTime.pause"
                        : "watch.cycleTime.startOrResume")
                    .disabled(!model.cycleTimerRunning && !model.cycleTimerCanUse(homeProfileID: home.homeProfileID))
                }
                Button("watch.cycleTime.finish", systemImage: "stop.fill") {
                    model.finishCycleTimer()
                }
                .buttonStyle(.bordered)
                .tint(WatchTheme.accent)
                .disabled(model.cycleElapsed(at: .now) < 0.5 || model.cycleTimeQueueLimitReached)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
        }
        .navigationTitle("watch.cycleTime")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "watch.cycleTime.reset.confirmation",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("watch.cycleTime.reset", role: .destructive) {
                model.resetCycleTimer()
            }
            Button("watch.cycleTime.cancel", role: .cancel) {}
        }
    }
}

struct WatchCounterDetailView: View {
    @EnvironmentObject private var model: WatchCounterModel
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let sessionID: UUID

    private var session: WatchCounterSessionSnapshot? { model.session(id: sessionID) }
    private var counterAccent: Color { isLuminanceReduced ? WatchTheme.primaryText : WatchTheme.accent }
    private var progressTrack: Color {
        isLuminanceReduced ? WatchTheme.secondaryText.opacity(0.25) : WatchTheme.panel
    }

    var body: some View {
        if let session {
            ScrollView {
                VStack(spacing: 8) {
                    watchSessionNameText(session)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    // Keep the count stable across watchOS locale-specific number
                    // transitions. The production count uses ASCII digits in both
                    // supported languages, just like the target below.
                    Text(verbatim: String(session.currentCount))
                        .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(counterAccent)
                        .accessibilityLabel("watch.progress.current")
                    if session.targetCount > 0 {
                        let completion = min(Double(session.currentCount) / Double(session.targetCount), 1)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(progressTrack)
                                Capsule()
                                    .fill(counterAccent)
                                    .frame(width: geometry.size.width * completion)
                            }
                        }
                        .frame(height: 8)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("watch.progress.fraction")
                        .accessibilityValue(Text(completion.formatted(.percent.precision(.fractionLength(0...1)))))
                        HStack(spacing: 3) {
                            Text("watch.target")
                            Text(verbatim: String(session.targetCount))
                        }
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.secondaryText)
                    }
                    if model.pendingCount > 0 {
                        Label {
                            HStack(spacing: 3) {
                                Text("watch.pending")
                                Text(model.pendingCount, format: .number)
                            }
                        } icon: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                            .font(.caption2)
                            .foregroundStyle(WatchTheme.accent)
                    }
                    if model.queueLimitReached {
                        Label("watch.queueFull.message", systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(WatchTheme.warning)
                    }
                    if let status = model.latestStatus {
                        Text(status.messageKey)
                            .font(.caption2)
                            .foregroundStyle(status == .rejected ? WatchTheme.warning : WatchTheme.secondaryText)
                    }
                    HStack(spacing: 8) {
                        Button {
                            model.subtractOne(from: session)
                        } label: {
                            Text("−1").font(.headline)
                        }
                        .tint(WatchTheme.panel)
                        Button {
                            model.addOne(to: session)
                        } label: {
                            Text("+1").font(.headline)
                        }
                        .tint(counterAccent)
                    }
                    Button {
                        model.addFive(to: session)
                    } label: {
                        Text("watch.quickAddFive")
                    }
                    .buttonStyle(.bordered)
                    .tint(counterAccent)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 3)
            }
            .navigationTitle(watchHomeNameText(session.homeName, isDefault: session.homeNameIsDefault))
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView {
                Label("watch.sessionUnavailable", systemImage: "exclamationmark.triangle")
            } description: {
                if model.queueLimitReached {
                    Text("watch.queueFull.message")
                } else if let status = model.latestStatus {
                    Text(status.messageKey)
                } else {
                    Text("watch.noCounters.message")
                }
            } actions: {
                Button {
                    model.refreshCatalog()
                } label: {
                    Label("watch.refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

private extension CounterCommandAcknowledgementStatus {
    var messageKey: LocalizedStringKey {
        switch self {
        case .applied: "watch.status.applied"
        case .alreadyApplied: "watch.status.alreadyApplied"
        case .noChange: "watch.status.noChange"
        case .staleUndo: "watch.status.staleUndo"
        case .rejected: "watch.status.rejected"
        }
    }
}

private extension WatchCycleTimeAcknowledgementStatus {
    var messageKey: LocalizedStringKey {
        switch self {
        case .applied: "watch.cycleTime.status.applied"
        case .alreadyApplied: "watch.cycleTime.status.alreadyApplied"
        case .rejected: "watch.status.rejected"
        }
    }
}
