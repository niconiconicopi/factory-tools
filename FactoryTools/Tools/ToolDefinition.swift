import Foundation
import FactoryToolsCore

enum ToolCardRoute: String, CaseIterable, Hashable {
    case productionCounter
    case cycleTime
    case taktTime
    case oee
    case productionProgress
    case defectCounter
    case defectRate
    case boxCalculator
    case unitConverter
    case comingSoon

    var showsTargetSettings: Bool {
        self == .productionCounter || self == .productionProgress
    }
}

extension ToolSessionPolicy {
    var defaultSessionNameKey: String {
        switch self {
        case .productionCounter: "counter.defaultSessionName"
        case .defectCounter: "defect.defaultSessionName"
        }
    }
}

struct ToolDefinition: Identifiable {
    let id: ToolID
    let titleKey: String
    let category: ToolCategory
    let accessTier: FeatureAccessTier
    var isPro: Bool { accessTier == .pro }
    let isAvailable: Bool
    let homeCardRoute: ToolCardRoute
    let sessionPolicy: ToolSessionPolicy?

    var supportsWatch: Bool { id.capabilities.supportsWatch }
    var supportedCardSizes: Set<ToolCardSize> { id.capabilities.supportedCardSizes }

    init(
        id: ToolID,
        titleKey: String,
        category: ToolCategory,
        accessTier: FeatureAccessTier,
        isAvailable: Bool,
        homeCardRoute: ToolCardRoute,
        sessionPolicy: ToolSessionPolicy? = nil
    ) {
        self.id = id
        self.titleKey = titleKey
        self.category = category
        self.accessTier = accessTier
        self.isAvailable = isAvailable
        self.homeCardRoute = homeCardRoute
        self.sessionPolicy = sessionPolicy
    }
}
