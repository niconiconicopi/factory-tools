import Foundation
import FactoryToolsCore

enum ToolRegistry {
    static let all: [ToolDefinition] = [
        ToolDefinition(
            id: .productionCounter,
            titleKey: "tool.counter.title",
            category: .production,
            accessTier: .free,
            isAvailable: true,
            homeCardRoute: .productionCounter,
            sessionPolicy: .productionCounter
        ),
        ToolDefinition(id: .cycleTime, titleKey: "tool.cycleTime.title", category: .production, accessTier: .free, isAvailable: true, homeCardRoute: .cycleTime),
        ToolDefinition(id: .taktTime, titleKey: "tool.taktTime.title", category: .production, accessTier: .free, isAvailable: true, homeCardRoute: .taktTime),
        ToolDefinition(id: .oee, titleKey: "tool.oee.title", category: .production, accessTier: .pro, isAvailable: true, homeCardRoute: .oee),
        ToolDefinition(id: .productionProgress, titleKey: "tool.progress.title", category: .production, accessTier: .pro, isAvailable: true, homeCardRoute: .productionProgress, sessionPolicy: .productionCounter),
        ToolDefinition(id: .defectCounter, titleKey: "tool.defect.title", category: .quality, accessTier: .free, isAvailable: true, homeCardRoute: .defectCounter, sessionPolicy: .defectCounter),
        ToolDefinition(id: .defectRate, titleKey: "tool.defectRate.title", category: .quality, accessTier: .free, isAvailable: true, homeCardRoute: .defectRate),
        ToolDefinition(id: .boxCalculator, titleKey: "tool.box.title", category: .packing, accessTier: .free, isAvailable: true, homeCardRoute: .boxCalculator),
        ToolDefinition(id: .unitConverter, titleKey: "tool.unitConverter.title", category: .utility, accessTier: .free, isAvailable: true, homeCardRoute: .unitConverter)
    ]

    static var hasProAssignments: Bool {
        FeatureAccessRegistry.hasProFeatures || all.contains { $0.accessTier == .pro }
    }

    static func definition(for id: ToolID) -> ToolDefinition? {
        all.first { $0.id == id }
    }

    static func matching(_ query: String, category: ToolCategory? = nil, locale: Locale) -> [ToolDefinition] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { tool in
            guard category == nil || tool.category == category else { return false }
            guard !normalizedQuery.isEmpty else { return true }
            let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            let searchLocales = [locale, Locale(identifier: "ja"), Locale(identifier: "en")]
            let matchesLocalizedName = searchLocales.contains { searchLocale in
                let localizedTitle = String(
                    localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: tool.titleKey)),
                    locale: searchLocale
                )
                let localizedCategory = String(
                    localized: LocalizedStringResource(
                        String.LocalizationValue(stringLiteral: tool.category.titleKey)
                    ),
                    locale: searchLocale
                )
                return localizedTitle.range(of: normalizedQuery, options: options, locale: searchLocale) != nil
                    || localizedCategory.range(of: normalizedQuery, options: options, locale: searchLocale) != nil
            }
            return matchesLocalizedName
                || tool.id.rawValue.range(of: normalizedQuery, options: options, locale: locale) != nil
        }
    }
}
