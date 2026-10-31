import SwiftData

/// Frozen model inventory for the first public store format.
///
/// Keep these model definitions and their persisted property shapes stable after release.
/// Add a new VersionedSchema and an explicit MigrationStage before changing stored fields.
enum FactoryToolsSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            HomeProfile.self,
            ToolCard.self,
            ProductionSession.self,
            CountEvent.self,
            AppSettings.self,
            CycleTimeSample.self,
            OEERun.self,
            CounterCommandReceipt.self
        ]
    }

    /// Source-level persistence contract checked against the @Model declarations.
    /// SwiftData remains authoritative at runtime; this list makes accidental V1 drift visible in review.
    static let persistedPropertyInventory: [String: [String]] = [
        "HomeProfile": ["id", "name", "usesDefaultName", "sortOrder", "createdAt"],
        "ToolCard": ["id", "homeProfileID", "toolID", "sizeRawValue", "sortOrder", "showsOnWatch", "productionSessionID"],
        "ProductionSession": ["id", "homeProfileID", "toolID", "name", "currentCount", "targetCount", "nextEventSequence", "startedAt"],
        "CountEvent": ["id", "sessionID", "delta", "sequence", "occurredAt", "reversesEventID", "kindRawValue", "payloadSignature"],
        "AppSettings": ["id", "language", "themeID", "selectedHomeProfileID"],
        "CycleTimeSample": ["id", "homeProfileID", "totalSeconds", "quantity", "createdAt"],
        "OEERun": ["id", "homeProfileID", "plannedProductionMinutes", "downtimeMinutes", "idealCycleTimeSeconds", "goodUnits", "defectiveUnits", "createdAt"],
        "CounterCommandReceipt": ["id", "sessionID", "processedAt", "payloadSignature"]
    ]
}

enum FactoryToolsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FactoryToolsSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
