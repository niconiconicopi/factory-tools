import SwiftUI
import FactoryToolsCore

struct BoxCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @State private var itemLengthText = ""
    @State private var itemWidthText = ""
    @State private var itemHeightText = ""
    @State private var boxLengthText = ""
    @State private var boxWidthText = ""
    @State private var boxHeightText = ""

    private var outcome: BoxPackingOutcome? {
        guard let itemLength = LocalizedNumberParser.parseInteger(itemLengthText, locale: locale),
              let itemWidth = LocalizedNumberParser.parseInteger(itemWidthText, locale: locale),
              let itemHeight = LocalizedNumberParser.parseInteger(itemHeightText, locale: locale),
              let boxLength = LocalizedNumberParser.parseInteger(boxLengthText, locale: locale),
              let boxWidth = LocalizedNumberParser.parseInteger(boxWidthText, locale: locale),
              let boxHeight = LocalizedNumberParser.parseInteger(boxHeightText, locale: locale) else { return nil }
        return BoxCalculator.outcome(
            item: BoxDimensions(length: itemLength, width: itemWidth, height: itemHeight),
            innerBox: BoxDimensions(length: boxLength, width: boxWidth, height: boxHeight)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("boxCalculator.itemDimensions") {
                    TextField("boxCalculator.itemLength", text: $itemLengthText)
                        .keyboardType(.numberPad)
                    TextField("boxCalculator.itemWidth", text: $itemWidthText)
                        .keyboardType(.numberPad)
                    TextField("boxCalculator.itemHeight", text: $itemHeightText)
                        .keyboardType(.numberPad)
                }
                Section("boxCalculator.innerDimensions") {
                    TextField("boxCalculator.boxLength", text: $boxLengthText)
                        .keyboardType(.numberPad)
                    TextField("boxCalculator.boxWidth", text: $boxWidthText)
                        .keyboardType(.numberPad)
                    TextField("boxCalculator.boxHeight", text: $boxHeightText)
                        .keyboardType(.numberPad)
                }
                Section("boxCalculator.result") {
                    switch outcome {
                    case let .some(.fit(result)):
                        LabeledContent("boxCalculator.unitsPerBox") {
                            Text(result.unitsPerBox.formatted(.number.locale(locale)))
                                .font(theme.homeTitleFont)
                                .foregroundStyle(theme.accent)
                        }
                        LabeledContent("boxCalculator.layout") {
                            Text("\(localizedInteger(result.unitsAlongLength)) × \(localizedInteger(result.unitsAlongWidth)) × \(localizedInteger(result.unitsAlongHeight))")
                                .foregroundStyle(theme.primaryText)
                        }
                        LabeledContent("boxCalculator.itemOrientation") {
                            Text("\(localizedInteger(result.itemOrientation.length)) × \(localizedInteger(result.itemOrientation.width)) × \(localizedInteger(result.itemOrientation.height)) mm")
                                .foregroundStyle(theme.primaryText)
                        }
                        Text("boxCalculator.sameOrientationNote")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                    case .some(.countTooLarge):
                        Text("boxCalculator.countTooLarge")
                            .font(theme.subheadlineFont)
                            .foregroundStyle(theme.secondaryText)
                    case .none:
                        Text("boxCalculator.enterDimensions")
                            .font(theme.subheadlineFont)
                            .foregroundStyle(theme.secondaryText)
                    case .some(.noFit):
                        Text("boxCalculator.noFit")
                            .font(theme.subheadlineFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("tool.box.title")
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

    private func localizedInteger(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }
}
