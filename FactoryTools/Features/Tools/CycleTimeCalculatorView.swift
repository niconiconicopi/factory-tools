import Foundation
import SwiftData
import SwiftUI
import Charts
import FactoryToolsCore

struct CycleTimeCalculatorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @EnvironmentObject private var proPurchases: ProPurchaseManager
    @Query private var samples: [CycleTimeSample]
    @Query private var homes: [HomeProfile]
    @State private var totalSecondsText = ""
    @State private var quantityText = ""
    @State private var showingSaveError = false
    @State private var showingDeleteConfirmation = false
    @State private var samplePendingDeletion: CycleTimeSample?
    @State private var timerStartedAt: ContinuousClock.Instant?
    @State private var accumulatedDuration: Duration = .zero
    @State private var historyPeriod = CycleTimeHistoryPeriod.days30
    @State private var showingProSettings = false

    let homeProfileID: UUID

    init(homeProfileID: UUID) {
        self.homeProfileID = homeProfileID
        let selectedHomeID = homeProfileID
        _samples = Query(
            filter: #Predicate<CycleTimeSample> { $0.homeProfileID == selectedHomeID },
            sort: \CycleTimeSample.createdAt,
            order: .reverse
        )
        _homes = Query(filter: #Predicate<HomeProfile> { $0.id == selectedHomeID })
    }

    private var secondsPerUnit: Double? {
        guard let totalSeconds = LocalizedNumberParser.parseInteger(totalSecondsText, locale: locale),
              let quantity = LocalizedNumberParser.parseInteger(quantityText, locale: locale) else { return nil }
        return CycleTimeCalculator.secondsPerUnit(totalSeconds: totalSeconds, quantity: quantity)
    }

    var body: some View {
        let orderedSamples = self.orderedSamples
        let historyPoints = orderedSamples.compactMap { sample in
            sample.secondsPerUnit.map {
                CycleTimeHistoryPoint(id: sample.id, createdAt: sample.createdAt, secondsPerUnit: $0)
            }
        }
        .sorted { first, second in
            if first.createdAt != second.createdAt { return first.createdAt < second.createdAt }
            return first.id.uuidString < second.id.uuidString
        }
        let visibleHistoryPoints = CycleTimeHistoryMath.points(
            historyPoints,
            within: historyPeriod,
            asOf: .now,
            calendar: .current
        )
        let historySummary = CycleTimeHistoryMath.summary(from: visibleHistoryPoints)
        let visibleIDs = Set(visibleHistoryPoints.map(\.id))
        let canReviewDetailedHistory = FeatureAccessRegistry.allows(.detailedHistoryAnalysis, isPro: proPurchases.hasPro)
        let visibleSamples = canReviewDetailedHistory
            ? orderedSamples.filter { visibleIDs.contains($0.id) }
            : orderedSamples
        let exportRecords = orderedSamples.map(CycleTimeCSVRecord.init)
        NavigationStack {
            Form {
                Section("cycleTime.inputs") {
                    TextField("cycleTime.totalSeconds", text: $totalSecondsText)
                        .keyboardType(.numberPad)
                    TextField("cycleTime.quantity", text: $quantityText)
                        .keyboardType(.numberPad)
                }
                Section("cycleTime.timer") {
                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        let elapsed = elapsedSeconds(at: .now)
                        LabeledContent("cycleTime.elapsedTime") {
                            Text(elapsed.formatted(
                                .number.precision(.fractionLength(1)).locale(locale)
                            ))
                            .font(theme.homeTitleFont)
                            .foregroundStyle(theme.accent)
                            .monospacedDigit()
                        }
                    }
                    HStack {
                        Button {
                            toggleTimer()
                        } label: {
                            Label(
                                timerStartedAt == nil ? "cycleTime.timerStart" : "cycleTime.timerPause",
                                systemImage: timerStartedAt == nil ? "play.fill" : "pause.fill"
                            )
                        }
                        .tint(theme.accent)
                        Button("cycleTime.timerReset", systemImage: "arrow.counterclockwise") {
                            resetTimer()
                        }
                        .disabled(timerStartedAt == nil && accumulatedDuration == .zero)
                    }
                    Button("cycleTime.useMeasuredTime", systemImage: "arrow.down.to.line") {
                        useMeasuredTime()
                    }
                    .disabled(measuredWholeSeconds == nil)
                    Text("cycleTime.timerRoundingNote")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                }
                Section("cycleTime.result") {
                    if let secondsPerUnit {
                        LabeledContent("cycleTime.secondsPerUnit") {
                            Text(secondsPerUnit.formatted(
                                .number.precision(.fractionLength(0...2)).locale(locale)
                            ))
                            .font(theme.homeTitleFont)
                            .foregroundStyle(theme.accent)
                        }
                        Text("cycleTime.formula")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                        Button("cycleTime.saveSample", systemImage: "bookmark") {
                            saveSample()
                        }
                    } else {
                        Text("cycleTime.invalidInput")
                            .font(theme.subheadlineFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                if !orderedSamples.isEmpty {
                    Section("cycleTime.historySummary") {
                        if canReviewDetailedHistory {
                        Picker("cycleTime.historyPeriod", selection: $historyPeriod) {
                            ForEach(CycleTimeHistoryPeriod.allCases) { period in
                                Text(LocalizedStringKey(period.titleKey)).tag(period)
                            }
                        }
                        .pickerStyle(.segmented)
                        if let historySummary {
                        Chart(visibleHistoryPoints) { point in
                            LineMark(
                                x: .value("cycleTime.chartDate", point.createdAt),
                                y: .value("cycleTime.secondsPerUnit", point.secondsPerUnit)
                            )
                            .foregroundStyle(theme.accent)
                            .interpolationMethod(.linear)
                            PointMark(
                                x: .value("cycleTime.chartDate", point.createdAt),
                                y: .value("cycleTime.secondsPerUnit", point.secondsPerUnit)
                            )
                            .foregroundStyle(theme.accent)
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                                AxisGridLine()
                                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { _ in
                                AxisGridLine()
                                AxisValueLabel()
                            }
                        }
                        .frame(height: 160)
                        .accessibilityLabel("cycleTime.historyChart")
                        LabeledContent("cycleTime.sampleCount") {
                            Text(historySummary.sampleCount.formatted(.number.locale(locale)))
                                .monospacedDigit()
                        }
                        historyRow("cycleTime.latest", value: historySummary.latestSecondsPerUnit)
                        historyRow("cycleTime.average", value: historySummary.averageSecondsPerUnit)
                        historyRow("cycleTime.best", value: historySummary.bestSecondsPerUnit)
                        LabeledContent("cycleTime.changeFromPrevious") {
                            if let change = historySummary.changeFromPrevious {
                                Text(signedSeconds(change))
                                    .foregroundStyle(change <= 0 ? theme.accent : theme.secondaryText)
                                    .monospacedDigit()
                            } else {
                                Text("cycleTime.noPrevious")
                                    .foregroundStyle(theme.secondaryText)
                            }
                        }
                        } else {
                            Text("cycleTime.noSamplesForPeriod")
                                .font(theme.subheadlineFont)
                                .foregroundStyle(theme.secondaryText)
                        }
                        } else {
                            Label("pro.description", systemImage: "lock.fill")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.secondaryText)
                            if homes.first != nil {
                                Button("pro.openSettings") { showingProSettings = true }
                            }
                        }
                    }
                }
                if !orderedSamples.isEmpty && !visibleSamples.isEmpty {
                    Section("cycleTime.savedSamples") {
                        ForEach(visibleSamples) { sample in
                            sampleRow(sample)
                        }
                    }
                } else if orderedSamples.isEmpty {
                    Section("cycleTime.savedSamples") {
                        Text("cycleTime.noSamples")
                            .font(theme.subheadlineFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("tool.cycleTime.title")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: CSVExportFile(makeContent: { [homeID = homeProfileID, records = exportRecords] in
                            CycleTimeHistoryCSV.make(homeID: homeID, records: records)
                        }),
                        preview: SharePreview(Text("cycleTime.historyExportPreview"))
                    ) {
                        Label("cycleTime.historyExport", systemImage: "square.and.arrow.up")
                    }
                    .disabled(orderedSamples.isEmpty)
                }
            }
            .alert("error.saveFailed", isPresented: $showingSaveError) {
                Button("common.done", role: .cancel) {}
            } message: {
                Text("error.saveMessage")
            }
            .sheet(isPresented: $showingProSettings) {
                if let home = homes.first { AppSettingsView(home: home) }
            }
            .confirmationDialog(
                "cycleTime.deleteConfirmation.title",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("common.remove", role: .destructive) {
                    if let samplePendingDeletion { delete(samplePendingDeletion) }
                    samplePendingDeletion = nil
                }
                Button("common.cancel", role: .cancel) { samplePendingDeletion = nil }
            } message: {
                Text("cycleTime.deleteConfirmation.message")
            }
            .onDisappear(perform: pauseTimer)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var orderedSamples: [CycleTimeSample] {
        samples.sorted { first, second in
            if first.createdAt != second.createdAt { return first.createdAt > second.createdAt }
            return first.id.uuidString < second.id.uuidString
        }
    }

    @ViewBuilder
    private func sampleRow(_ sample: CycleTimeSample) -> some View {
        let sampleDate = sample.createdAt.formatted(
            .dateTime.year().month().day().hour().minute().locale(locale)
        )
        Button {
            load(sample)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(sampleDate)
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)
                HStack(spacing: 4) {
                    Text("cycleTime.totalSeconds")
                    Text(sample.totalSeconds.formatted(.number.locale(locale)))
                    Text("cycleTime.quantity")
                    Text(sample.quantity.formatted(.number.locale(locale)))
                }
                .font(theme.subheadlineFont)
                .foregroundStyle(theme.primaryText)
                if let value = sample.secondsPerUnit {
                    LabeledContent("cycleTime.secondsPerUnit") {
                        Text(value.formatted(
                            .number.precision(.fractionLength(0...2)).locale(locale)
                        ))
                        .foregroundStyle(theme.accent)
                    }
                    .font(theme.captionFont)
                }
            }
        }
        .accessibilityHint("cycleTime.sampleLoadHint")
        .listRowBackground(theme.cardBackground)
        .swipeActions {
            Button(role: .destructive) {
                samplePendingDeletion = sample
                showingDeleteConfirmation = true
            } label: {
                Label("common.remove", systemImage: "trash")
            }
            .accessibilityLabel(Text("cycleTime.removeSampleNamed \(sampleDate)"))
        }
    }

    private func signedSeconds(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return sign + value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
            + " " + String(localized: "cycleTime.secondsUnit", locale: locale)
    }

    private func historyRow(_ titleKey: String, value: Double) -> some View {
        LabeledContent(LocalizedStringKey(titleKey)) {
            Text(value.formatted(.number.precision(.fractionLength(0...2)).locale(locale)))
                .foregroundStyle(theme.primaryText)
                .monospacedDigit()
        }
    }

    private var measuredWholeSeconds: Int? {
        CycleTimeMeasurement.roundedWholeSeconds(from: elapsedSeconds(at: .now))
    }

    private func elapsedSeconds(at now: ContinuousClock.Instant) -> Double {
        var elapsed = accumulatedDuration
        if let timerStartedAt {
            elapsed += timerStartedAt.duration(to: now)
        }
        let components = elapsed.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private func toggleTimer() {
        if timerStartedAt == nil {
            timerStartedAt = .now
        } else {
            pauseTimer()
        }
    }

    private func pauseTimer() {
        guard let timerStartedAt else { return }
        accumulatedDuration += timerStartedAt.duration(to: .now)
        self.timerStartedAt = nil
    }

    private func resetTimer() {
        timerStartedAt = nil
        accumulatedDuration = .zero
    }

    private func useMeasuredTime() {
        guard let measuredWholeSeconds else { return }
        totalSecondsText = String(measuredWholeSeconds)
    }

    private func saveSample() {
        guard let totalSeconds = LocalizedNumberParser.parseInteger(totalSecondsText, locale: locale),
              let quantity = LocalizedNumberParser.parseInteger(quantityText, locale: locale) else { return }
        do {
            try CycleTimeSampleService(modelContext: modelContext).save(
                totalSeconds: totalSeconds,
                quantity: quantity,
                for: homeProfileID
            )
        } catch {
            showingSaveError = true
        }
    }

    private func load(_ sample: CycleTimeSample) {
        totalSecondsText = String(sample.totalSeconds)
        quantityText = String(sample.quantity)
    }

    private func delete(_ sample: CycleTimeSample) {
        do {
            try CycleTimeSampleService(modelContext: modelContext).delete(sample, from: homeProfileID)
        } catch {
            showingSaveError = true
        }
    }
}
