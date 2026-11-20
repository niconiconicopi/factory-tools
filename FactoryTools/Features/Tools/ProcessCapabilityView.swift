import SwiftUI
import FactoryToolsCore

struct ProcessCapabilityView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @State private var lowerSpecLimitText = ""
    @State private var upperSpecLimitText = ""
    @State private var processMeanText = ""
    @State private var standardDeviationText = ""

    init(screenshotDemoValues: Bool = false) {
        _lowerSpecLimitText = State(initialValue: screenshotDemoValues ? "9" : "")
        _upperSpecLimitText = State(initialValue: screenshotDemoValues ? "11" : "")
        _processMeanText = State(initialValue: screenshotDemoValues ? "10.2" : "")
        _standardDeviationText = State(initialValue: screenshotDemoValues ? "0.25" : "")
    }

    private var result: ProcessCapabilityResult? {
        guard let lowerSpecLimit = LocalizedNumberParser.parse(lowerSpecLimitText, locale: locale),
              let upperSpecLimit = LocalizedNumberParser.parse(upperSpecLimitText, locale: locale),
              let processMean = LocalizedNumberParser.parse(processMeanText, locale: locale),
              let standardDeviation = LocalizedNumberParser.parse(standardDeviationText, locale: locale) else {
            return nil
        }
        return ProcessCapabilityMath.calculate(
            lowerSpecLimit: lowerSpecLimit,
            upperSpecLimit: upperSpecLimit,
            processMean: processMean,
            standardDeviation: standardDeviation
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("processCapability.inputs") {
                    input("processCapability.lowerLimit", text: $lowerSpecLimitText)
                    input("processCapability.upperLimit", text: $upperSpecLimitText)
                    input("processCapability.mean", text: $processMeanText)
                    input("processCapability.standardDeviation", text: $standardDeviationText)
                    Text("processCapability.sigmaNote")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                }
                Section("processCapability.results") {
                    if let result {
                        capabilityValue("processCapability.cp", value: result.cp)
                        capabilityValue("processCapability.cpk", value: result.cpk)
                        Text("processCapability.formula")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                    } else {
                        Text("processCapability.invalidInput")
                            .font(theme.subheadlineFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                Section {
                    Text("processCapability.caveat")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("tool.processCapability.title")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func input(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField(title, text: text)
                .labelsHidden()
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(title)
        }
    }

    private func capabilityValue(_ title: LocalizedStringKey, value: Double) -> some View {
        LabeledContent(title) {
            Text(value.formatted(.number.precision(.fractionLength(0...3)).locale(locale)))
                .font(theme.homeTitleFont)
                .foregroundStyle(theme.accent)
        }
    }
}
