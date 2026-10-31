import SwiftUI
import FactoryToolsCore

struct UnitConverterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @State private var category: UnitCategory = .length
    @State private var sourceUnit: MeasurementUnit = .millimeter
    @State private var targetUnit: MeasurementUnit = .centimeter
    @State private var valueText = ""

    private var convertedValue: Double? {
        guard let value = parsedValue else { return nil }
        return UnitConversion.convert(value, from: sourceUnit, to: targetUnit)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("unitConverter.categorySection") {
                    Picker("unitConverter.category", selection: $category) {
                        ForEach(UnitCategory.allCases) { option in
                            Text(LocalizedStringKey(option.titleKey)).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("unitConverter.conversion") {
                    TextField("unitConverter.value", text: $valueText)
                        .keyboardType(category == .temperature ? .numbersAndPunctuation : .decimalPad)
                    Picker("unitConverter.from", selection: $sourceUnit) {
                        ForEach(category.units) { unit in
                            HStack(spacing: 4) {
                                Text(LocalizedStringKey(unit.titleKey))
                                Text("(\(unit.symbol))")
                                    .foregroundStyle(theme.secondaryText)
                            }
                                .tag(unit)
                        }
                    }
                    Picker("unitConverter.to", selection: $targetUnit) {
                        ForEach(category.units) { unit in
                            HStack(spacing: 4) {
                                Text(LocalizedStringKey(unit.titleKey))
                                Text("(\(unit.symbol))")
                                    .foregroundStyle(theme.secondaryText)
                            }
                                .tag(unit)
                        }
                    }
                    Button {
                        let previousSource = sourceUnit
                        sourceUnit = targetUnit
                        targetUnit = previousSource
                    } label: {
                        Label("unitConverter.swap", systemImage: "arrow.left.arrow.right")
                    }
                    .tint(theme.accent)
                }
                Section("unitConverter.resultSection") {
                    if let convertedValue {
                        LabeledContent("unitConverter.result") {
                            Text("\(convertedValue.formatted(
                                .number.precision(.fractionLength(0...8)).locale(locale)
                            )) \(targetUnit.symbol)")
                                .font(theme.homeTitleFont)
                                .foregroundStyle(theme.accent)
                        }
                    } else {
                        Text("unitConverter.invalidInput")
                            .font(theme.subheadlineFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .onChange(of: category) { _, newCategory in
                sourceUnit = newCategory.units[0]
                targetUnit = newCategory.units[1]
            }
            .navigationTitle("tool.unitConverter.title")
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

    private var parsedValue: Double? {
        LocalizedNumberParser.parse(valueText, locale: locale)
    }
}
