import Foundation

/// Paid access is a product-wide entitlement, while requirements are assigned
/// centrally so feature boundaries can change without rewriting UI flows.
public enum FeatureAccessTier: String, Codable, CaseIterable, Identifiable {
    case free
    case pro

    public var id: String { rawValue }
}

public enum FactoryFeature: String, Codable, CaseIterable, Identifiable {
    case multipleHomeProfiles
    case watchCounterControl
    case ipadCounterControl
    case proThemes
    case advancedWatchSettings
    case detailedHistoryAnalysis
    case detailedDefectAnalysis
    case advancedDashboardCustomization
    case oeeCalculator
    case productionProgress
    case defectCounter
    case downtimeTracking
    case toolLife
    case capabilityAnalysis
    case advancedQualityControl
    case toleranceCalculation
    case machiningConditionCalculation
    case advancedWarnings
    case cycleTimeExclusions
    case multipleBreaks
    case complexShiftSettings
    case detailedNotifications
    case advancedCalculationSettings
    case detailedLogs
    case precisionAndRoundingSettings
    case detailedCharts
    case timeOfDayAnalysis
    case defectCategoryAnalysis
    case additionalWatchTools

    public var id: String { rawValue }
}

public enum FeatureAccessRegistry {
    public static var hasProFeatures: Bool {
        FactoryFeature.allCases.contains { requiredTier(for: $0) == .pro }
    }

    /// Central source for feature gates. These assignments implement the
    /// approved Version 1 Free / Pro boundary.
    public static func requiredTier(for feature: FactoryFeature) -> FeatureAccessTier {
        switch feature {
        case .multipleHomeProfiles, .proThemes, .advancedWatchSettings,
             .detailedHistoryAnalysis, .detailedDefectAnalysis,
             .advancedDashboardCustomization, .oeeCalculator,
             .productionProgress, .downtimeTracking, .toolLife,
             .capabilityAnalysis, .advancedQualityControl, .toleranceCalculation,
             .machiningConditionCalculation, .advancedWarnings, .cycleTimeExclusions,
             .multipleBreaks, .complexShiftSettings, .detailedNotifications,
             .advancedCalculationSettings, .detailedLogs, .precisionAndRoundingSettings,
             .detailedCharts, .timeOfDayAnalysis, .defectCategoryAnalysis,
             .additionalWatchTools:
            .pro
        case .watchCounterControl, .ipadCounterControl, .defectCounter:
            .free
        }
    }

    public static func allows(_ requiredTier: FeatureAccessTier, isPro: Bool) -> Bool {
        requiredTier == .free || isPro
    }

    public static func allows(_ feature: FactoryFeature, isPro: Bool) -> Bool {
        allows(requiredTier(for: feature), isPro: isPro)
    }
}

public enum ProPurchaseOwnership: String, Codable, Sendable {
    case purchased
    case familyShared
}

/// A minimal, platform-neutral view of a StoreKit non-consumable entitlement.
/// Only verified, active ownership of the configured product grants Pro.
public struct ProEntitlementEvidence: Equatable, Sendable {
    public let productID: String
    public let isVerified: Bool
    public let isRevoked: Bool
    public let isUpgraded: Bool
    public let ownership: ProPurchaseOwnership

    public init(
        productID: String,
        isVerified: Bool,
        isRevoked: Bool,
        isUpgraded: Bool,
        ownership: ProPurchaseOwnership
    ) {
        self.productID = productID
        self.isVerified = isVerified
        self.isRevoked = isRevoked
        self.isUpgraded = isUpgraded
        self.ownership = ownership
    }

    public func grantsPro(for configuredProductID: String) -> Bool {
        guard isVerified,
              !configuredProductID.isEmpty,
              productID == configuredProductID,
              !isRevoked,
              !isUpgraded else { return false }
        switch ownership {
        case .purchased:
            return true
        case .familyShared:
            return false
        }
    }
}

public enum ToolID: String, Codable, CaseIterable, Identifiable {
    case productionCounter = "production.counter"
    case cycleTime = "production.cycleTime"
    case taktTime = "production.takt"
    case oee = "production.oee"
    case productionProgress = "production.progress"
    case defectCounter = "quality.defect"
    case defectRate = "quality.defectRate"
    case boxCalculator = "packing.box"
    case unitConverter = "utility.unitConverter"

    public var id: String { rawValue }
}

public enum ToolSessionPolicy: String, Codable, CaseIterable, Hashable, Identifiable {
    case productionCounter
    case defectCounter

    public var id: String { rawValue }

    public var sessionToolID: ToolID {
        switch self {
        case .productionCounter: .productionCounter
        case .defectCounter: .defectCounter
        }
    }

    public var defaultTargetCount: Int {
        switch self {
        case .productionCounter: 600
        case .defectCounter: 0
        }
    }
}

public enum DefectRateMath {
    public static func fraction(defectCount: Int, productionCount: Int) -> Double? {
        guard defectCount >= 0, productionCount > 0 else { return nil }
        return Double(defectCount) / Double(productionCount)
    }
}

public enum ToolCategory: String, Codable, CaseIterable, Identifiable {
    case production
    case quality
    case packing
    case utility

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .production: "tool.category.production"
        case .quality: "tool.category.quality"
        case .packing: "tool.category.packing"
        case .utility: "tool.category.utility"
        }
    }
}

public enum ToolCardSize: String, Codable, CaseIterable, Identifiable {
    case small
    case medium
    case large

    public var id: String { rawValue }
}

public struct ToolCapabilities: Hashable {
    public let supportsWatch: Bool
    public let supportedCardSizes: Set<ToolCardSize>

    public init(supportsWatch: Bool, supportedCardSizes: Set<ToolCardSize>) {
        self.supportsWatch = supportsWatch
        self.supportedCardSizes = supportedCardSizes
    }
}

public extension ToolID {
    var capabilities: ToolCapabilities {
        switch self {
        case .productionCounter, .cycleTime, .defectCounter:
            ToolCapabilities(supportsWatch: true, supportedCardSizes: Set(ToolCardSize.allCases))
        case .productionProgress:
            ToolCapabilities(supportsWatch: true, supportedCardSizes: [.medium, .large])
        case .taktTime, .oee, .defectRate, .boxCalculator:
            ToolCapabilities(supportsWatch: false, supportedCardSizes: [.medium, .large])
        case .unitConverter:
            ToolCapabilities(supportsWatch: false, supportedCardSizes: [.small, .medium])
        }
    }
}
