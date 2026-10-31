import SwiftUI
import SwiftData
import Charts
import FactoryToolsCore

struct OEECalculatorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @EnvironmentObject private var proPurchases: ProPurchaseManager
    @Query private var savedRuns: [OEERun]
    @State private var plannedMinutesText = ""
    @State private var downtimeMinutesText = "0"
    @State private var idealCycleSecondsText = ""
    @State private var goodUnitsText = ""
    @State private var defectiveUnitsText = "0"
    @State private var showingSaveError = false
    @State private var showingDeleteConfirmation = false
    @State private var runPendingDeletion: OEERun?
    @State private var historyPeriod = OEEHistoryPeriod.days30

    let homeProfileID: UUID

    init(homeProfileID: UUID) {
        self.homeProfileID = homeProfileID
        let selectedHomeID = homeProfileID
        _savedRuns = Query(
            filter: #Predicate<OEERun> { $0.homeProfileID == selectedHomeID },
            sort: \OEERun.createdAt,
            order: .reverse
        )
    }

    private var calculation: OEECalculation? {
        guard let plannedMinutes = LocalizedNumberParser.parseInteger(plannedMinutesText, locale: locale),
              let downtimeMinutes = LocalizedNumberParser.parseInteger(downtimeMinutesText, locale: locale),
              let idealCycleSeconds = LocalizedNumberParser.parseInteger(idealCycleSecondsText, locale: locale),
              let goodUnits = LocalizedNumberParser.parseInteger(goodUnitsText, locale: locale),
              let defectiveUnits = LocalizedNumberParser.parseInteger(defectiveUnitsText, locale: locale) else { return nil }
        return OEECalculator.calculate(
            plannedProductionMinutes: plannedMinutes,
            downtimeMinutes: downtimeMinutes,
            idealCycleTimeSeconds: idealCycleSeconds,
            goodUnits: goodUnits,
            defectiveUnits: defectiveUnits
        )
    }

    var body: some View {
        let orderedRuns = self.orderedRuns
        let historyPoints = orderedRuns.compactMap { run in
            run.calculation.map { OEEHistoryPoint(id: run.id, createdAt: run.createdAt, overall: $0.overall) }
        }
        .sorted { first, second in
            if first.createdAt != second.createdAt { return first.createdAt < second.createdAt }
            return first.id.uuidString < second.id.uuidString
        }
        let visibleHistoryPoints = OEEHistoryMath.points(
            historyPoints,
            within: historyPeriod,
            asOf: .now,
            calendar: .current
        )
        let historySummary = OEEHistoryMath.summary(from: visibleHistoryPoints)
        let visibleIDs = Set(visibleHistoryPoints.map(\.id))
        let visibleRuns = orderedRuns.filter { visibleIDs.contains($0.id) }
        let exportRecords = orderedRuns.map(OEECSVRecord.init)
        NavigationStack {
            Form {
                Section("oee.timeInputs") {
                    TextField("oee.plannedMinutes", text: $plannedMinutesText)
                        .keyboardType(.numberPad)
                    Text("oee.plannedTimeNote")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                    TextField("oee.downtimeMinutes", text: $downtimeMinutesText)
                        .keyboardType(.numberPad)
                    TextField("oee.idealCycleSeconds", text: $idealCycleSecondsText)
                        .keyboardType(.numberPad)
                }
                Section("oee.outputInputs") {
                    TextField("oee.goodUnits", text: $goodUnitsText)
                        .keyboardType(.numberPad)
                    TextField("oee.defectiveUnits", text: $defectiveUnitsText)
                        .keyboardType(.numberPad)
                }
                Section("oee.results") {
                    if let calculation {
                        resultRow("oee.availability", value: calculation.availability)
                        resultRow("oee.performance", value: calculation.performance)
                        resultRow("oee.quality", value: calculation.quality)
                        resultRow("oee.overall", value: calculation.overall, isEmphasized: true)
                        Text("oee.formulaNote")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                        Text("oee.performanceNote")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                        Button("oee.saveRun", systemImage: "bookmark") {
                            saveRun()
                        }
                    } else {
                        Text("oee.invalidInput")
                            .font(theme.subheadlineFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                if !orderedRuns.isEmpty {
                    Section("oee.historySummary") {
                        Picker("oee.historyPeriod", selection: $historyPeriod) {
                            ForEach(OEEHistoryPeriod.allCases) { period in
                                Text(LocalizedStringKey(period.titleKey)).tag(period)
                            }
                        }
                        .pickerStyle(.segmented)
                        if let historySummary {
                        Chart(visibleHistoryPoints) { point in
                            LineMark(
                                x: .value("oee.chartDate", point.createdAt),
                                y: .value("oee.overall", point.overall)
                            )
                            .foregroundStyle(theme.accent)
                            .interpolationMethod(.linear)
                            PointMark(
                                x: .value("oee.chartDate", point.createdAt),
                                y: .value("oee.overall", point.overall)
                            )
                            .foregroundStyle(theme.accent)
                        }
                        .chartYScale(domain: 0...max(1, historySummary.bestOverall * 1.1))
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                                AxisGridLine()
                                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { _ in
                                AxisGridLine()
                                AxisValueLabel(format: .percent.precision(.fractionLength(0)))
                            }
                        }
                        .frame(height: 160)
                        .accessibilityLabel("oee.historyChart")
                        LabeledContent("oee.runCount") {
                            Text(historySummary.runCount.formatted(.number.locale(locale)))
                                .monospacedDigit()
                        }
                        resultRow("oee.latest", value: historySummary.latestOverall)
                        resultRow("oee.average", value: historySummary.averageOverall)
                        resultRow("oee.best", value: historySummary.bestOverall)
                        LabeledContent("oee.changeFromPrevious") {
                            if let change = historySummary.changeFromPrevious {
                                Text(signedPercent(change))
                                    .foregroundStyle(theme.accent)
                                    .monospacedDigit()
                            } else {
                                Text("oee.noPrevious")
                                    .foregroundStyle(theme.secondaryText)
                            }
                        }
                        } else {
                            Text("oee.noRunsForPeriod")
                                .font(theme.subheadlineFont)
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                }
                if !orderedRuns.isEmpty && !visibleRuns.isEmpty {
                    Section("oee.savedRuns") {
                        ForEach(visibleRuns) { run in
                            Button {
                                load(run)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(run.createdAt.formatted(
                                        .dateTime.year().month().day().hour().minute().locale(locale)
                                    ))
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.secondaryText)
                                    if let result = run.calculation {
                                        LabeledContent("oee.overall") {
                                            Text(result.overall.formatted(
                                                .percent.precision(.fractionLength(0...1)).locale(locale)
                                            ))
                                            .font(theme.calloutFont)
                                            .foregroundStyle(theme.accent)
                                            .monospacedDigit()
                                        }
                                        Text("\(run.goodUnits.formatted(.number.locale(locale))) / \((run.goodUnits + run.defectiveUnits).formatted(.number.locale(locale))) \(String(localized: "oee.goodOfTotal", locale: locale))")
                                            .font(theme.captionFont)
                                            .foregroundStyle(theme.secondaryText)
                                    }
                                }
                            }
                            .accessibilityHint("oee.savedRunLoadHint")
                            .listRowBackground(theme.cardBackground)
                            .swipeActions {
                                Button(role: .destructive) {
                                    runPendingDeletion = run
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("common.remove", systemImage: "trash")
                                }
                                .accessibilityLabel(Text("oee.removeRunNamed \(run.createdAt.formatted(
                                    .dateTime.year().month().day().hour().minute().locale(locale)
                                ))"))
                            }
                        }
                    }
                } else if orderedRuns.isEmpty {
                    Section("oee.savedRuns") {
                        Text("oee.noSavedRuns")
                            .font(theme.subheadlineFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("tool.oee.title")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: CSVExportFile(makeContent: { [homeID = homeProfileID, records = exportRecords] in
                            OEEHistoryCSV.make(homeID: homeID, records: records)
                        }),
                        preview: SharePreview(Text("oee.historyExportPreview"))
                    ) {
                        Label("oee.historyExport", systemImage: "square.and.arrow.up")
                    }
                    .disabled(orderedRuns.isEmpty)
                }
            }
            .onChange(of: proPurchases.hasPro) { _, hasPro in
                if !hasPro { dismiss() }
            }
            .alert("error.saveFailed", isPresented: $showingSaveError) {
                Button("common.done", role: .cancel) {}
            } message: {
                Text("error.saveMessage")
            }
            .confirmationDialog(
                "oee.deleteConfirmation.title",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("common.remove", role: .destructive) {
                    if let runPendingDeletion { delete(runPendingDeletion) }
                    runPendingDeletion = nil
                }
                Button("common.cancel", role: .cancel) { runPendingDeletion = nil }
            } message: {
                Text("oee.deleteConfirmation.message")
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var orderedRuns: [OEERun] {
        savedRuns.sorted { first, second in
            if first.createdAt != second.createdAt { return first.createdAt > second.createdAt }
            return first.id.uuidString < second.id.uuidString
        }
    }

    private func signedPercent(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return sign + value.formatted(.percent.precision(.fractionLength(0...1)).locale(locale))
    }

    private func saveRun() {
        guard let plannedMinutes = LocalizedNumberParser.parseInteger(plannedMinutesText, locale: locale),
              let downtimeMinutes = LocalizedNumberParser.parseInteger(downtimeMinutesText, locale: locale),
              let idealCycleSeconds = LocalizedNumberParser.parseInteger(idealCycleSecondsText, locale: locale),
              let goodUnits = LocalizedNumberParser.parseInteger(goodUnitsText, locale: locale),
              let defectiveUnits = LocalizedNumberParser.parseInteger(defectiveUnitsText, locale: locale) else { return }
        do {
            try OEERunService(modelContext: modelContext).save(
                plannedProductionMinutes: plannedMinutes,
                downtimeMinutes: downtimeMinutes,
                idealCycleTimeSeconds: idealCycleSeconds,
                goodUnits: goodUnits,
                defectiveUnits: defectiveUnits,
                for: homeProfileID,
                isPro: proPurchases.hasPro
            )
        } catch OEERunServiceError.proRequired {
            dismiss()
        } catch {
            showingSaveError = true
        }
    }

    private func load(_ run: OEERun) {
        plannedMinutesText = String(run.plannedProductionMinutes)
        downtimeMinutesText = String(run.downtimeMinutes)
        idealCycleSecondsText = String(run.idealCycleTimeSeconds)
        goodUnitsText = String(run.goodUnits)
        defectiveUnitsText = String(run.defectiveUnits)
    }

    private func delete(_ run: OEERun) {
        do {
            try OEERunService(modelContext: modelContext).delete(run, from: homeProfileID)
        } catch {
            showingSaveError = true
        }
    }

    private func resultRow(_ titleKey: String, value: Double, isEmphasized: Bool = false) -> some View {
        LabeledContent(LocalizedStringKey(titleKey)) {
            Text(value.formatted(.percent.precision(.fractionLength(0...1)).locale(locale)))
                .font(isEmphasized ? theme.homeTitleFont : theme.calloutFont)
                .foregroundStyle(isEmphasized ? theme.accent : theme.primaryText)
                .monospacedDigit()
        }
    }
}
