import Foundation
import CoreTransferable
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import FactoryToolsCore

struct CounterSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @Bindable var session: ProductionSession
    @State private var targetText = ""
    @State private var showingSaveError = false

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
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save", action: save)
                        .disabled(parsedTarget == nil || (parsedTarget ?? -1) < 0)
                }
            }
            .onAppear { targetText = String(session.targetCount) }
            .alert("error.saveFailed", isPresented: $showingSaveError) {
                Button("common.done", role: .cancel) {}
            } message: {
                Text("error.saveMessage")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard let target = parsedTarget, target >= 0 else { return }
        do {
            try CounterService(modelContext: modelContext).setTarget(target, for: session)
            dismiss()
        } catch {
            showingSaveError = true
        }
    }

    private var parsedTarget: Int? {
        LocalizedNumberParser.parseInteger(targetText, locale: locale)
    }
}

struct CounterQuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @Bindable var session: ProductionSession
    @State private var amountText = ""
    @State private var showingSaveError = false
    @State private var errorMessageKey = "error.saveMessage"

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
                    Button("counter.quickAddApply", action: apply)
                        .disabled(parsedAmount == nil || session.currentCount == Int.max)
                }
            }
            .alert("error.saveFailed", isPresented: $showingSaveError) {
                Button("common.done", role: .cancel) {}
            } message: {
                Text(LocalizedStringKey(errorMessageKey))
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var parsedAmount: Int? {
        guard let value = LocalizedNumberParser.parseInteger(amountText, locale: locale), value > 0 else {
            return nil
        }
        return value
    }

    private func apply() {
        guard let amount = parsedAmount else { return }
        do {
            try CounterService(modelContext: modelContext).quickAdd(amount, to: session)
            dismiss()
        } catch CounterServiceError.eventSequenceExhausted {
            errorMessageKey = "error.counterEventLimit"
            showingSaveError = true
        } catch {
            errorMessageKey = "error.saveMessage"
            showingSaveError = true
        }
    }
}

struct CounterHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @Query private var events: [CountEvent]

    let session: ProductionSession

    init(session: ProductionSession) {
        self.session = session
        let selectedSessionID = session.id
        _events = Query(filter: #Predicate<CountEvent> { $0.sessionID == selectedSessionID })
    }

    var body: some View {
        let orderedEvents = CounterHistoryOrdering.ordered(events)
        let balances = CounterHistoryBalances.afterEachEvent(
            orderedEvents: orderedEvents,
            currentCount: session.currentCount
        )
        NavigationStack {
            Group {
                if orderedEvents.isEmpty {
                    ContentUnavailableView(
                        "counter.history.empty.title",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("counter.history.empty.message")
                    )
                    .foregroundStyle(theme.secondaryText)
                } else {
                    List {
                        Section {
                            LabeledContent("counter.currentCount") {
                                Text(session.currentCount.formatted(.number.locale(locale)))
                                    .font(theme.calloutFont)
                                    .foregroundStyle(theme.accent)
                            }
                        }
                        Section("counter.history") {
                            if balances == nil {
                                Label("counter.history.balanceUnavailable", systemImage: "exclamationmark.triangle")
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.warning)
                            }
                            ForEach(orderedEvents) { event in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.occurredAt.formatted(
                                            .dateTime.year().month().day().hour().minute().locale(locale)
                                        ))
                                            .font(theme.subheadlineFont)
                                            .foregroundStyle(theme.primaryText)
                                        Text(LocalizedStringKey(eventKindTitleKey(for: event)))
                                            .font(theme.captionFont)
                                            .foregroundStyle(theme.secondaryText)
                                    }
                                    Spacer(minLength: 8)
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(formattedDelta(event.delta))
                                            .font(theme.calloutFont)
                                            .foregroundStyle(event.delta >= 0 ? theme.accent : theme.warning)
                                            .monospacedDigit()
                                        if let countAfter = balances?[event.id] {
                                            HStack(spacing: 3) {
                                                Text("counter.history.balanceAfter")
                                                Text(formattedCount(countAfter))
                                            }
                                            .font(theme.captionFont)
                                            .foregroundStyle(theme.secondaryText)
                                            .monospacedDigit()
                                        }
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(theme.background)
            .navigationTitle("counter.history")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: CSVExportFile(
                            makeContent: { [sessionID = session.id, currentCount = session.currentCount,
                                            records = orderedEvents.map(CounterHistoryCSVRecord.init)] in
                                CounterHistoryCSV.make(
                                    sessionID: sessionID,
                                    currentCount: currentCount,
                                    records: records
                                )
                            }
                        ),
                        preview: SharePreview(Text("counter.history.exportPreview"))
                    ) {
                        Label("counter.history.export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(orderedEvents.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func formattedDelta(_ delta: Int) -> String {
        let formatted = delta.formatted(.number.locale(locale))
        return delta > 0 ? "+\(formatted)" : formatted
    }

    private func formattedCount(_ count: Int) -> String {
        count.formatted(.number.locale(locale))
    }

    private func eventKindTitleKey(for event: CountEvent) -> String {
        if let kind = event.kind { return kind.titleKey }
        return event.reversesEventID == nil ? "counter.history.kind.unknown" : "counter.history.kind.undo"
    }
}

struct CSVExportFile: Transferable, Sendable {
    let makeContent: @Sendable () -> String

    init(makeContent: @escaping @Sendable () -> String) {
        self.makeContent = makeContent
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            Data(file.makeContent().utf8)
        }
    }
}
