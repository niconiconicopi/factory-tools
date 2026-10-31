import SwiftUI
import FactoryToolsCore

struct TaktTimeCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @State private var netAvailableSecondsText = ""
    @State private var customerDemandText = ""

    private var secondsPerUnit: Double? {
        guard let availableSeconds = LocalizedNumberParser.parseInteger(netAvailableSecondsText, locale: locale),
              let customerDemand = LocalizedNumberParser.parseInteger(customerDemandText, locale: locale) else { return nil }
        return TaktTimeCalculator.secondsPerUnit(
            netAvailableSeconds: availableSeconds,
            customerDemand: customerDemand
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("taktTime.inputs") {
                    TextField("taktTime.netSeconds", text: $netAvailableSecondsText)
                        .keyboardType(.numberPad)
                    Text("taktTime.netTimeNote")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                    TextField("taktTime.demand", text: $customerDemandText)
                        .keyboardType(.numberPad)
                }
                Section("taktTime.result") {
                    if let secondsPerUnit {
                        LabeledContent("taktTime.secondsPerUnit") {
                            Text(secondsPerUnit.formatted(
                                .number.precision(.fractionLength(0...2)).locale(locale)
                            ))
                            .font(theme.homeTitleFont)
                            .foregroundStyle(theme.accent)
                        }
                        Text("taktTime.formula")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                    } else {
                        Text("taktTime.invalidInput")
                            .font(theme.subheadlineFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("tool.taktTime.title")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
