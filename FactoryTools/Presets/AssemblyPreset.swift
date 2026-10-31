import FactoryToolsCore
import Foundation

struct AssemblyPreset {
    static let titleKey = "home.preset.assembly"
    static let descriptionKey = "home.preset.assemblyDescription"
    static let toolIDs: [ToolID] = [
        .productionCounter,
        .cycleTime,
        .taktTime,
        .defectCounter
    ]
}

struct PackagingPreset {
    static let titleKey = "home.preset.packaging"
    static let descriptionKey = "home.preset.packagingDescription"
    static let toolIDs: [ToolID] = [
        .productionCounter,
        .productionProgress,
        .defectCounter,
        .defectRate,
        .boxCalculator,
        .unitConverter,
        .oee
    ]
}
