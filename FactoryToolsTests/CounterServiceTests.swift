import SwiftData
import XCTest
import FactoryToolsCore
@testable import FactoryTools

@MainActor
final class CounterServiceTests: XCTestCase {
    func testVersionedSchemaV1DefinesAllPersistedModelsAndMigrationPlan() throws {
        XCTAssertEqual(FactoryToolsSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(FactoryToolsSchemaV1.models.count, 8)
        XCTAssertEqual(FactoryToolsSchemaV1.persistedPropertyInventory.count, 8)
        XCTAssertEqual(
            FactoryToolsSchemaV1.persistedPropertyInventory["ProductionSession"],
            ["id", "homeProfileID", "toolID", "name", "currentCount", "targetCount", "nextEventSequence", "startedAt"]
        )
        XCTAssertEqual(FactoryToolsMigrationPlan.schemas.count, 1)
        XCTAssertTrue(FactoryToolsMigrationPlan.stages.isEmpty)

        let schema = Schema(versionedSchema: FactoryToolsSchemaV1.self)
        let configuration = ModelConfiguration(
            "FactoryToolsSchemaV1Test",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: FactoryToolsMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let home = HomeProfile(name: "Schema test", sortOrder: 0)
        context.insert(home)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<HomeProfile>()).map(\.id), [home.id])
    }

    func testBackupRecordCountPreflightUsesOverflowSafeTotals() {
        XCTAssertNoThrow(try FactoryToolsBackupService.validateRecordCounts([2, 3], maximumRecordCount: 5))

        for (counts, maximum) in [([2, 3], 4), ([Int.max, 1], Int.max), ([-1], 5), ([1], -1)] {
            XCTAssertThrowsError(
                try FactoryToolsBackupService.validateRecordCounts(counts, maximumRecordCount: maximum)
            ) { error in
                XCTAssertEqual(error as? FactoryToolsBackupError, .backupTooLarge)
            }
        }
    }

    func testTargetCommandUpdatesSessionAndPersistsAnIdempotencyReceipt() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(
            homeProfileID: UUID(),
            toolID: ToolID.productionCounter.rawValue,
            name: "Production",
            currentCount: 12,
            targetCount: 100
        )
        context.insert(session)
        try context.save()
        let command = CounterCommand(sessionID: session.id, operation: .setTarget(250))
        let service = CounterService(modelContext: context)

        XCTAssertEqual(try service.apply(command, to: session), .applied)
        XCTAssertEqual(session.targetCount, 250)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CountEvent>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CounterCommandReceipt>()).map(\.id), [command.id])
        XCTAssertEqual(try service.apply(command, to: session), .alreadyApplied)

        let changedReplay = CounterCommand(id: command.id, sessionID: session.id, operation: .setTarget(300), createdAt: command.createdAt)
        XCTAssertThrowsError(try service.apply(changedReplay, to: session))
        XCTAssertEqual(session.targetCount, 250)
    }

    func testPeerProcessorShowsSelectedHomeButAcceptsQueuedCommandsForOtherValidHomes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let firstHome = HomeProfile(name: "First", usesDefaultName: false, sortOrder: 0)
        let selectedHome = HomeProfile(name: "Selected", usesDefaultName: false, sortOrder: 1)
        let firstSession = ProductionSession(
            homeProfileID: firstHome.id,
            toolID: ToolID.productionCounter.rawValue,
            name: "First production",
            targetCount: 20
        )
        let selectedSession = ProductionSession(
            homeProfileID: selectedHome.id,
            toolID: ToolID.defectCounter.rawValue,
            name: "Selected defects"
        )
        let unlinkedSession = ProductionSession(
            homeProfileID: firstHome.id,
            toolID: ToolID.productionCounter.rawValue,
            name: "Unlinked production"
        )
        let deletedHomeID = UUID()
        let deletedHomeSession = ProductionSession(
            homeProfileID: deletedHomeID,
            toolID: ToolID.productionCounter.rawValue,
            name: "Deleted-home production"
        )
        context.insert(firstHome)
        context.insert(selectedHome)
        context.insert(firstSession)
        context.insert(selectedSession)
        context.insert(unlinkedSession)
        context.insert(deletedHomeSession)
        context.insert(ToolCard(homeProfileID: firstHome.id, toolID: .productionCounter, sortOrder: 0, showsOnWatch: false, productionSessionID: firstSession.id))
        context.insert(ToolCard(homeProfileID: selectedHome.id, toolID: .defectCounter, sortOrder: 0, showsOnWatch: false, productionSessionID: selectedSession.id))
        context.insert(ToolCard(homeProfileID: deletedHomeID, toolID: .productionCounter, sortOrder: 0, showsOnWatch: false, productionSessionID: deletedHomeSession.id))
        context.insert(AppSettings(selectedHomeProfileID: selectedHome.id))
        try context.save()
        let processor = WatchCommandProcessor(modelContext: context)
        let command = CounterCommand(sessionID: firstSession.id, operation: .setTarget(75))
        let selectedHomeCommand = CounterCommand(sessionID: selectedSession.id, operation: .increment)

        XCTAssertTrue(try processor.catalog().sessions.isEmpty)
        XCTAssertEqual(try processor.peerCatalog().sessions.map(\.sessionID), [firstSession.id])
        XCTAssertEqual(
            try processor.process(selectedHomeCommand, allowNonWatchSessions: true, isPro: false).acknowledgement.status,
            .rejected
        )
        XCTAssertEqual(
            try processor.peerCatalog(isPro: true).sessions.map(\.sessionID),
            [selectedSession.id]
        )
        XCTAssertEqual(
            try processor.process(selectedHomeCommand, allowNonWatchSessions: true, isPro: true).acknowledgement.status,
            .applied
        )
        XCTAssertEqual(try processor.process(command, allowNonWatchSessions: true, isPro: true).acknowledgement.status, .applied)
        XCTAssertEqual(firstSession.targetCount, 75)

        let increment = CounterCommand(sessionID: firstSession.id, operation: .increment)
        let appliedIncrement = try processor.process(increment, allowNonWatchSessions: true, isPro: true)
        XCTAssertEqual(appliedIncrement.acknowledgement.status, .applied)
        XCTAssertEqual(appliedIncrement.session?.currentCount, 1)
        XCTAssertEqual(firstSession.currentCount, 1)
        XCTAssertEqual(try processor.process(increment, allowNonWatchSessions: true, isPro: true).acknowledgement.status, .alreadyApplied)
        XCTAssertEqual(firstSession.currentCount, 1)

        let unlinkedCommand = CounterCommand(sessionID: unlinkedSession.id, operation: .increment)
        let unlinkedResult = try processor.process(unlinkedCommand, allowNonWatchSessions: true, isPro: true)
        XCTAssertEqual(unlinkedResult.acknowledgement.status, .rejected)
        XCTAssertNil(unlinkedResult.session)
        XCTAssertEqual(unlinkedSession.currentCount, 0)

        let deletedHomeCommand = CounterCommand(sessionID: deletedHomeSession.id, operation: .increment)
        let deletedHomeResult = try processor.process(deletedHomeCommand, allowNonWatchSessions: true, isPro: true)
        XCTAssertEqual(deletedHomeResult.acknowledgement.status, .rejected)
        XCTAssertNil(deletedHomeResult.session)
        XCTAssertEqual(deletedHomeSession.currentCount, 0)
    }

    func testBackupIncludesEveryStoredModelAndIsDeterministicWithoutMutation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let homeID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let home = HomeProfile(
            id: homeID,
            name: "Assembly",
            usesDefaultName: false,
            sortOrder: 0,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let session = ProductionSession(
            id: sessionID,
            homeProfileID: homeID,
            toolID: ToolID.productionCounter.rawValue,
            name: "Production",
            currentCount: 4,
            targetCount: 20,
            nextEventSequence: 1,
            startedAt: Date(timeIntervalSince1970: 1_100)
        )
        let card = ToolCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            homeProfileID: homeID,
            toolID: .productionCounter,
            size: .large,
            sortOrder: 0,
            productionSessionID: sessionID
        )
        let event = CountEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000104")!,
            sessionID: sessionID,
            delta: 4,
            sequence: 0,
            occurredAt: Date(timeIntervalSince1970: 1_200),
            kind: .quickAdd
        )
        let sample = CycleTimeSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000105")!,
            homeProfileID: homeID,
            totalSeconds: 120,
            quantity: 10,
            createdAt: Date(timeIntervalSince1970: 1_300)
        )
        let oeeRun = OEERun(
            homeProfileID: homeID,
            plannedProductionMinutes: 100,
            downtimeMinutes: 20,
            idealCycleTimeSeconds: 2,
            goodUnits: 1_080,
            defectiveUnits: 120,
            createdAt: Date(timeIntervalSince1970: 1_400)
        )
        let settings = AppSettings(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000106")!,
            language: AppLanguage.english.rawValue,
            selectedHomeProfileID: homeID
        )
        let commandReceipt = CounterCommandReceipt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000107")!,
            sessionID: sessionID,
            processedAt: Date(timeIntervalSince1970: 1_250)
        )
        context.insert(home)
        context.insert(session)
        context.insert(card)
        context.insert(event)
        context.insert(sample)
        context.insert(oeeRun)
        context.insert(settings)
        context.insert(commandReceipt)
        try context.save()

        let exportTime = Date(timeIntervalSince1970: 2_000)
        let service = FactoryToolsBackupService(modelContext: context)
        let firstData = try service.makeJSON(exportedAt: exportTime)
        let secondData = try service.makeJSON(exportedAt: exportTime)
        var decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let backup = try decoder.decode(FactoryToolsBackup.self, from: firstData)
        let expectedBackup = FactoryToolsBackup(
            schemaVersion: 4,
            exportedAt: exportTime,
            homes: [FactoryToolsBackup.Home(home)],
            cards: [FactoryToolsBackup.Card(card)],
            sessions: [FactoryToolsBackup.Session(session)],
            events: [FactoryToolsBackup.Event(event)],
            commandReceipts: [FactoryToolsBackup.CommandReceipt(commandReceipt)],
            cycleTimeSamples: [FactoryToolsBackup.CycleSample(sample)],
            oeeRuns: [FactoryToolsBackup.OEERecord(oeeRun)],
            settings: [FactoryToolsBackup.Settings(settings)]
        )

        XCTAssertEqual(firstData, secondData)
        XCTAssertEqual(backup, expectedBackup)
        XCTAssertEqual(backup.homes.map(\.id), [homeID])
        XCTAssertEqual(backup.cards.map(\.id), [card.id])
        XCTAssertEqual(backup.cards.first?.productionSessionID, sessionID)
        XCTAssertEqual(backup.sessions.first?.currentCount, 4)
        XCTAssertEqual(backup.events.first?.kindRawValue, CounterEventKind.quickAdd.rawValue)
        XCTAssertEqual(backup.events.first?.delta, 4)
        XCTAssertEqual(backup.cycleTimeSamples.first?.totalSeconds, 120)
        XCTAssertEqual(backup.oeeRuns.first?.goodUnits, 1_080)
        XCTAssertEqual(backup.settings.first?.language, AppLanguage.english.rawValue)
        XCTAssertEqual(backup.settings.first?.themeID, ThemeID.industrialDark.rawValue)
        XCTAssertEqual(backup.settings.first?.selectedHomeProfileID, homeID)
        XCTAssertEqual(session.currentCount, 4)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CountEvent>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CounterCommandReceipt>()).count, 1)
    }

    func testBackupExportResolvesStaleCardSessionLinksAndImportsCopyWithoutMutation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let session = ProductionSession(
            homeProfileID: home.id,
            toolID: ToolID.productionCounter.rawValue,
            name: "Production"
        )
        let staleSessionID = UUID()
        let card = ToolCard(
            homeProfileID: home.id,
            toolID: .productionCounter,
            sortOrder: 0,
            productionSessionID: staleSessionID
        )
        context.insert(home)
        context.insert(session)
        context.insert(card)
        context.insert(AppSettings(selectedHomeProfileID: home.id))
        try context.save()

        let data = try FactoryToolsBackupService(modelContext: context).makeJSON()
        let backup = try FactoryToolsBackupService.decodeAndValidate(data)

        XCTAssertEqual(backup.cards.first?.productionSessionID, session.id)
        XCTAssertEqual(card.productionSessionID, staleSessionID)

        _ = try FactoryToolsBackupImportService(modelContext: context).addCopy(
            from: backup,
            importedHomeSuffix: " (Imported)",
            defaultHomeName: "Production",
            isPro: true
        )
        let homes = try context.fetch(FetchDescriptor<HomeProfile>())
        let importedHome = try XCTUnwrap(homes.first { $0.name == "Assembly (Imported)" })
        let importedCard = try XCTUnwrap(
            context.fetch(FetchDescriptor<ToolCard>()).first { $0.homeProfileID == importedHome.id }
        )
        let importedSession = try XCTUnwrap(
            context.fetch(FetchDescriptor<ProductionSession>()).first { $0.homeProfileID == importedHome.id }
        )
        XCTAssertEqual(importedCard.productionSessionID, importedSession.id)
        XCTAssertEqual(card.productionSessionID, staleSessionID)
    }

    func testBackupImportAddsRemappedCopyAndRollsBackOnSaveFailure() throws {
        let sourceContainer = try makeContainer()
        let sourceContext = ModelContext(sourceContainer)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let session = ProductionSession(
            homeProfileID: home.id,
            toolID: ToolID.productionCounter.rawValue,
            name: "Production",
            targetCount: 25
        )
        let card = ToolCard(
            homeProfileID: home.id,
            toolID: .productionCounter,
            size: .large,
            sortOrder: 0,
            showsOnWatch: false,
            productionSessionID: session.id
        )
        let sample = CycleTimeSample(homeProfileID: home.id, totalSeconds: 60, quantity: 5)
        let oeeRun = OEERun(
            homeProfileID: home.id,
            plannedProductionMinutes: 60,
            downtimeMinutes: 5,
            idealCycleTimeSeconds: 10,
            goodUnits: 300,
            defectiveUnits: 10
        )
        let settings = AppSettings(language: AppLanguage.english.rawValue, selectedHomeProfileID: home.id)
        sourceContext.insert(home)
        sourceContext.insert(session)
        sourceContext.insert(card)
        sourceContext.insert(sample)
        sourceContext.insert(oeeRun)
        sourceContext.insert(settings)
        try sourceContext.save()
        let counter = CounterService(modelContext: sourceContext)
        try counter.increment(session: session)
        try counter.undo(session: session)
        let noChangeCommand = CounterCommand(
            sessionID: session.id,
            operation: .decrement,
            createdAt: Date(timeIntervalSince1970: 1_500)
        )
        XCTAssertEqual(try counter.apply(noChangeCommand, to: session), .noChange)
        XCTAssertEqual(
            try sourceContext.fetch(FetchDescriptor<CounterCommandReceipt>()).map(\.sessionID),
            [session.id]
        )

        let export = try FactoryToolsBackupService(modelContext: sourceContext).makeJSON()
        let backup = try FactoryToolsBackupService.decodeAndValidate(export)
        var version3Object = try XCTUnwrap(JSONSerialization.jsonObject(with: export) as? [String: Any])
        version3Object["schemaVersion"] = 3
        for key in ["events", "commandReceipts"] {
            var records = try XCTUnwrap(version3Object[key] as? [[String: Any]])
            records = records.map { record in
                var legacyRecord = record
                legacyRecord.removeValue(forKey: "payloadSignature")
                return legacyRecord
            }
            version3Object[key] = records
        }
        let version3Data = try JSONSerialization.data(withJSONObject: version3Object)
        let version3Backup = try FactoryToolsBackupService.decodeAndValidate(version3Data)
        XCTAssertTrue(version3Backup.events.allSatisfy { $0.payloadSignature == nil })
        XCTAssertTrue(version3Backup.commandReceipts.allSatisfy { $0.payloadSignature == nil })
        let legacyContainer = try makeContainer()
        let legacyContext = ModelContext(legacyContainer)
        _ = try FactoryToolsBackupImportService(modelContext: legacyContext).addCopy(
            from: version3Backup,
            importedHomeSuffix: " (Legacy)",
            defaultHomeName: "Production",
            isPro: true
        )
        let upgradedLegacyBackup = try FactoryToolsBackupService.decodeAndValidate(
            FactoryToolsBackupService(modelContext: legacyContext).makeJSON()
        )
        XCTAssertEqual(upgradedLegacyBackup.schemaVersion, 4)
        XCTAssertTrue(upgradedLegacyBackup.events.allSatisfy { $0.payloadSignature == nil })
        XCTAssertTrue(upgradedLegacyBackup.commandReceipts.allSatisfy { $0.payloadSignature == nil })
        let sourceEvents = try sourceContext.fetch(FetchDescriptor<CountEvent>()).sorted { $0.sequence < $1.sequence }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("FactoryTools.store")
        let schema = Schema([
            HomeProfile.self, ToolCard.self, ProductionSession.self, CountEvent.self,
            AppSettings.self, CycleTimeSample.self, OEERun.self, CounterCommandReceipt.self
        ])
        let destinationHomeID = UUID()
        let destinationSessionID = UUID()
        let destinationCardID = UUID()
        let destinationEventID = UUID()
        let destinationReceiptID = UUID()
        let destinationSampleID = UUID()
        let destinationRunID = UUID()
        let destinationSettingsID = UUID()
        let writableConfiguration = ModelConfiguration(
            "BackupImportRollback",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        do {
            let destinationContainer = try ModelContainer(for: schema, configurations: [writableConfiguration])
            let destinationContext = ModelContext(destinationContainer)
            destinationContext.insert(HomeProfile(id: destinationHomeID, name: "Existing", sortOrder: 0))
            destinationContext.insert(ProductionSession(
                id: destinationSessionID,
                homeProfileID: destinationHomeID,
                toolID: ToolID.productionCounter.rawValue,
                name: "Saved count",
                currentCount: 4,
                nextEventSequence: 1
            ))
            destinationContext.insert(ToolCard(
                id: destinationCardID,
                homeProfileID: destinationHomeID,
                toolID: .productionCounter,
                sortOrder: 0,
                productionSessionID: destinationSessionID
            ))
            destinationContext.insert(CountEvent(
                id: destinationEventID,
                sessionID: destinationSessionID,
                delta: 4,
                sequence: 0,
                kind: .quickAdd
            ))
            destinationContext.insert(CounterCommandReceipt(id: destinationReceiptID, sessionID: destinationSessionID))
            destinationContext.insert(CycleTimeSample(
                id: destinationSampleID,
                homeProfileID: destinationHomeID,
                totalSeconds: 120,
                quantity: 2
            ))
            destinationContext.insert(OEERun(
                id: destinationRunID,
                homeProfileID: destinationHomeID,
                plannedProductionMinutes: 60,
                downtimeMinutes: 5,
                idealCycleTimeSeconds: 10,
                goodUnits: 300,
                defectiveUnits: 10
            ))
            destinationContext.insert(AppSettings(
                id: destinationSettingsID,
                language: AppLanguage.japanese.rawValue,
                selectedHomeProfileID: destinationHomeID
            ))
            try destinationContext.save()
        }
        let readOnlyConfiguration = ModelConfiguration(
            "BackupImportRollback",
            schema: schema,
            url: storeURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        let failContainer = try ModelContainer(for: schema, configurations: [readOnlyConfiguration])
        let failContext = ModelContext(failContainer)

        XCTAssertThrowsError(
            try FactoryToolsBackupImportService(modelContext: failContext).addCopy(
                from: backup,
                importedHomeSuffix: " (Imported)",
                defaultHomeName: "Production",
                isPro: false
            )
        )
        let reopenedFailureContainer = try ModelContainer(for: schema, configurations: [readOnlyConfiguration])
        let reopenedFailureContext = ModelContext(reopenedFailureContainer)
        XCTAssertEqual(try reopenedFailureContext.fetch(FetchDescriptor<HomeProfile>()).map(\.id), [destinationHomeID])
        XCTAssertEqual(try reopenedFailureContext.fetch(FetchDescriptor<ProductionSession>()).first?.currentCount, 4)
        XCTAssertEqual(try reopenedFailureContext.fetch(FetchDescriptor<ToolCard>()).map(\.id), [destinationCardID])
        XCTAssertEqual(try reopenedFailureContext.fetch(FetchDescriptor<CountEvent>()).map(\.id), [destinationEventID])
        XCTAssertEqual(try reopenedFailureContext.fetch(FetchDescriptor<CounterCommandReceipt>()).map(\.id), [destinationReceiptID])
        XCTAssertEqual(try reopenedFailureContext.fetch(FetchDescriptor<CycleTimeSample>()).map(\.id), [destinationSampleID])
        XCTAssertEqual(try reopenedFailureContext.fetch(FetchDescriptor<OEERun>()).map(\.id), [destinationRunID])
        let reopenedFailureSettings = try XCTUnwrap(reopenedFailureContext.fetch(FetchDescriptor<AppSettings>()).first)
        XCTAssertEqual(reopenedFailureSettings.id, destinationSettingsID)
        XCTAssertEqual(reopenedFailureSettings.selectedHomeProfileID, destinationHomeID)

        let result = try FactoryToolsBackupImportService(modelContext: sourceContext).addCopy(
            from: backup,
            importedHomeSuffix: " (Imported)",
            defaultHomeName: "Production",
            isPro: true
        )
        let allHomes = try sourceContext.fetch(FetchDescriptor<HomeProfile>())
        let allCards = try sourceContext.fetch(FetchDescriptor<ToolCard>())
        let allSessions = try sourceContext.fetch(FetchDescriptor<ProductionSession>())
        let allEvents = try sourceContext.fetch(FetchDescriptor<CountEvent>())
        let allSamples = try sourceContext.fetch(FetchDescriptor<CycleTimeSample>())
        let allOEERuns = try sourceContext.fetch(FetchDescriptor<OEERun>())
        let allCommandReceipts = try sourceContext.fetch(FetchDescriptor<CounterCommandReceipt>())
        let importedHome = try XCTUnwrap(allHomes.first { $0.name == "Assembly (Imported)" })
        let importedCard = try XCTUnwrap(allCards.first { $0.homeProfileID == importedHome.id })
        let importedSession = try XCTUnwrap(allSessions.first { $0.homeProfileID == importedHome.id })
        let importedEvents = allEvents.filter { $0.sessionID == importedSession.id }.sorted { $0.sequence < $1.sequence }
        let sourceNoChangeReceipt = try XCTUnwrap(allCommandReceipts.first { $0.sessionID == session.id })

        XCTAssertEqual(result, FactoryToolsBackupImportResult(homes: 1, cards: 1, sessions: 1, events: 2, commandReceipts: 1, cycleTimeSamples: 1, oeeRuns: 1))
        XCTAssertNotEqual(importedHome.id, home.id)
        XCTAssertNotEqual(importedCard.id, card.id)
        XCTAssertEqual(importedCard.productionSessionID, importedSession.id)
        XCTAssertEqual(importedCard.size, .large)
        XCTAssertFalse(importedCard.showsOnWatch)
        XCTAssertEqual(importedSession.targetCount, 25)
        XCTAssertEqual(importedEvents.map(\.delta), [1, -1])
        XCTAssertEqual(importedEvents.map(\.kind), [.increment, .undo])
        XCTAssertEqual(importedEvents.map(\.occurredAt), backup.events.map(\.occurredAt))
        XCTAssertEqual(importedEvents.map(\.payloadSignature), sourceEvents.map(\.payloadSignature))
        XCTAssertEqual(importedEvents.last?.reversesEventID, importedEvents.first?.id)
        let importedReceipt = try XCTUnwrap(allCommandReceipts.first { $0.sessionID == importedSession.id })
        XCTAssertEqual(importedReceipt.payloadSignature, sourceNoChangeReceipt.payloadSignature)
        XCTAssertNotEqual(importedReceipt.id, allCommandReceipts.first { $0.sessionID == session.id }?.id)
        XCTAssertEqual(
            try CounterService(modelContext: sourceContext).apply(
                CounterCommand(
                    id: importedReceipt.id,
                    sessionID: importedSession.id,
                    operation: .decrement,
                    createdAt: noChangeCommand.createdAt
                ),
                to: importedSession
            ),
            .alreadyApplied
        )
        XCTAssertEqual(importedSession.currentCount, 0)
        XCTAssertEqual(allSamples.first { $0.homeProfileID == importedHome.id }?.totalSeconds, 60)
        XCTAssertEqual(allSamples.first { $0.homeProfileID == importedHome.id }?.quantity, 5)
        let importedOEERun = try XCTUnwrap(allOEERuns.first { $0.homeProfileID == importedHome.id })
        XCTAssertEqual(importedOEERun.plannedProductionMinutes, 60)
        XCTAssertEqual(importedOEERun.goodUnits, 300)
        XCTAssertNotEqual(importedOEERun.id, oeeRun.id)
        XCTAssertEqual(allHomes.count, 2)
        XCTAssertEqual(try sourceContext.fetch(FetchDescriptor<AppSettings>()).count, 1)
        XCTAssertEqual(session.currentCount, 0)
    }

    func testRepeatedBackupImportsCreateIndependentCopiesAndKeepCurrentPreferences() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let sourceHome = HomeProfile(name: "Source", sortOrder: 0)
        let sourceSession = ProductionSession(
            homeProfileID: sourceHome.id,
            toolID: ToolID.productionCounter.rawValue,
            name: "Production",
            targetCount: 20
        )
        let sourceCard = ToolCard(
            homeProfileID: sourceHome.id,
            toolID: .productionCounter,
            sortOrder: 0,
            productionSessionID: sourceSession.id
        )
        let settings = AppSettings(
            language: AppLanguage.english.rawValue,
            selectedHomeProfileID: sourceHome.id
        )
        context.insert(sourceHome)
        context.insert(sourceSession)
        context.insert(sourceCard)
        context.insert(settings)
        try context.save()
        try CounterService(modelContext: context).quickAdd(3, to: sourceSession)

        let backupData = try FactoryToolsBackupService(modelContext: context).makeJSON()
        let backup = try FactoryToolsBackupService.decodeAndValidate(backupData)
        try AppSettingsService(modelContext: context).setLanguage(.japanese, for: settings)

        let importer = FactoryToolsBackupImportService(modelContext: context)
        XCTAssertEqual(
            try importer.addCopy(from: backup, importedHomeSuffix: " (Imported)", defaultHomeName: "Production", isPro: true),
            FactoryToolsBackupImportResult(homes: 1, cards: 1, sessions: 1, events: 1, commandReceipts: 0, cycleTimeSamples: 0, oeeRuns: 0)
        )
        XCTAssertEqual(
            try importer.addCopy(from: backup, importedHomeSuffix: " (Imported)", defaultHomeName: "Production", isPro: true),
            FactoryToolsBackupImportResult(homes: 1, cards: 1, sessions: 1, events: 1, commandReceipts: 0, cycleTimeSamples: 0, oeeRuns: 0)
        )

        let homes = HomeProfileOrdering.ordered(try context.fetch(FetchDescriptor<HomeProfile>()))
        let cards = try context.fetch(FetchDescriptor<ToolCard>())
        let sessions = try context.fetch(FetchDescriptor<ProductionSession>())
        let events = try context.fetch(FetchDescriptor<CountEvent>())
        let importedHomes = homes.filter { $0.id != sourceHome.id }
        XCTAssertEqual(homes.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(importedHomes.map(\.name), ["Source (Imported)", "Source (Imported)"])
        XCTAssertEqual(Set(homes.map(\.id)).count, 3)
        XCTAssertEqual(Set(cards.map(\.id)).count, 3)
        XCTAssertEqual(Set(sessions.map(\.id)).count, 3)
        XCTAssertEqual(Set(events.map(\.id)).count, 3)
        XCTAssertEqual(settings.language, AppLanguage.japanese.rawValue)
        XCTAssertEqual(settings.selectedHomeProfileID, sourceHome.id)

        let sessionsByHome = Dictionary(uniqueKeysWithValues: sessions.compactMap { session in
            session.homeProfileID.map { ($0, session) }
        })
        for card in cards {
            let linkedSession = try XCTUnwrap(sessionsByHome[card.homeProfileID])
            XCTAssertEqual(card.productionSessionID, linkedSession.id)
            XCTAssertEqual(linkedSession.currentCount, 3)
            XCTAssertEqual(linkedSession.targetCount, 20)
            XCTAssertEqual(events.filter { $0.sessionID == linkedSession.id }.map(\.delta), [3])
        }

        let firstCopy = try XCTUnwrap(importedHomes.first)
        let secondCopy = try XCTUnwrap(importedHomes.last)
        try HomeProfileService(modelContext: context).deleteHome(firstCopy.id)
        let remainingHomeIDs = Set(try context.fetch(FetchDescriptor<HomeProfile>()).map(\.id))
        XCTAssertEqual(remainingHomeIDs, Set([sourceHome.id, secondCopy.id]))
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettings>()).first?.selectedHomeProfileID, sourceHome.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProductionSession>()).map(\.homeProfileID).compactMap { $0 }.count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CountEvent>()).count, 2)
        XCTAssertEqual(sourceSession.currentCount, 3)
    }

    func testBackupImportCompactsCardOrderBeforeAppendingNewCards() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let productionCard = ToolCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            homeProfileID: home.id,
            toolID: .productionCounter,
            size: .medium,
            sortOrder: -4
        )
        let cycleTimeCard = ToolCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
            homeProfileID: home.id,
            toolID: .cycleTime,
            size: .medium,
            sortOrder: 8
        )
        let taktTimeCard = ToolCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
            homeProfileID: home.id,
            toolID: .taktTime,
            size: .medium,
            sortOrder: 8
        )
        context.insert(home)
        context.insert(productionCard)
        context.insert(cycleTimeCard)
        context.insert(taktTimeCard)
        context.insert(AppSettings(selectedHomeProfileID: home.id))
        try context.save()

        let backupData = try FactoryToolsBackupService(modelContext: context).makeJSON()
        let backup = try FactoryToolsBackupService.decodeAndValidate(backupData)
        try FactoryToolsBackupImportService(modelContext: context).addCopy(
            from: backup,
            importedHomeSuffix: " (Imported)",
            defaultHomeName: "Production",
            isPro: true
        )
        let importedHome = try XCTUnwrap(
            context.fetch(FetchDescriptor<HomeProfile>()).first { $0.name == "Assembly (Imported)" }
        )
        let homeToolService = HomeToolService(modelContext: context)
        let oeeTool = try XCTUnwrap(ToolRegistry.definition(for: .oee))
        try homeToolService.add(oeeTool, to: importedHome.id, locale: AppLanguage.english.locale, isPro: true)

        let importedCards = HomeCardOrdering.ordered(
            try context.fetch(FetchDescriptor<ToolCard>()).filter { $0.homeProfileID == importedHome.id }
        )
        XCTAssertEqual(importedCards.map(\.toolID), [
            ToolID.productionCounter.rawValue,
            ToolID.cycleTime.rawValue,
            ToolID.taktTime.rawValue,
            ToolID.oee.rawValue
        ])
        XCTAssertEqual(importedCards.map(\.sortOrder), [0, 1, 2, 3])
    }

    func testBackupImportPreservesHomeOrderWhenPayloadRecordsAreUnsorted() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let earlierHome = HomeProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
            name: "Earlier",
            sortOrder: -3
        )
        let laterHome = HomeProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
            name: "Later",
            sortOrder: 12
        )
        context.insert(earlierHome)
        context.insert(laterHome)
        context.insert(AppSettings(selectedHomeProfileID: earlierHome.id))
        try context.save()

        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: FactoryToolsBackupService(modelContext: context).makeJSON()
            ) as? [String: Any]
        )
        var homeRecords = try XCTUnwrap(payload["homes"] as? [[String: Any]])
        homeRecords.reverse()
        payload["homes"] = homeRecords
        let decoded = try FactoryToolsBackupService.decodeAndValidate(
            JSONSerialization.data(withJSONObject: payload)
        )

        try FactoryToolsBackupImportService(modelContext: context).addCopy(
            from: decoded,
            importedHomeSuffix: " (Imported)",
            defaultHomeName: "Production",
            isPro: true
        )
        let importedHomes = HomeProfileOrdering.ordered(
            try context.fetch(FetchDescriptor<HomeProfile>()).filter { $0.name.hasSuffix(" (Imported)") }
        )

        XCTAssertEqual(importedHomes.map(\.name), ["Earlier (Imported)", "Later (Imported)"])
        XCTAssertEqual(importedHomes.map(\.sortOrder), [2, 3])
    }

    func testFreeBackupRestoreActivatesFirstImportedHomeAndKeepsOtherDataLocked() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let existingHome = HomeProfile(name: "Current", sortOrder: 0)
        let backupHome = HomeProfile(name: "Restored", sortOrder: 1)
        let session = ProductionSession(
            homeProfileID: backupHome.id,
            toolID: ToolID.productionCounter.rawValue,
            name: "Restored production",
            currentCount: 4,
            targetCount: 50,
            nextEventSequence: 1
        )
        let card = ToolCard(
            homeProfileID: backupHome.id,
            toolID: .productionCounter,
            sortOrder: 0,
            productionSessionID: session.id
        )
        let event = CountEvent(sessionID: session.id, delta: 4, sequence: 0)
        let settings = AppSettings(selectedHomeProfileID: existingHome.id)
        [existingHome, backupHome].forEach(context.insert)
        [session].forEach(context.insert)
        context.insert(card)
        context.insert(event)
        context.insert(settings)
        try context.save()

        let data = try FactoryToolsBackupService(modelContext: context).makeJSON()
        let backup = try FactoryToolsBackupService.decodeAndValidate(data)
        try FactoryToolsBackupImportService(modelContext: context).addCopy(
            from: backup,
            importedHomeSuffix: " (Imported)",
            defaultHomeName: "Production",
            isPro: false
        )

        let homes = HomeProfileOrdering.ordered(try context.fetch(FetchDescriptor<HomeProfile>()))
        let importedHome = try XCTUnwrap(homes.first)
        XCTAssertEqual(importedHome.name, "Current (Imported)")
        XCTAssertEqual(settings.selectedHomeProfileID, importedHome.id)
        XCTAssertEqual(HomeProfileAccess.accessibleHomes(from: homes, isPro: false).map(\.id), [importedHome.id])
        XCTAssertEqual(HomeProfileAccess.accessibleHomes(from: homes, isPro: true).count, 4)

        let importedBackupHome = try XCTUnwrap(homes.first { $0.name == "Restored (Imported)" })
        let importedSession = try XCTUnwrap(
            context.fetch(FetchDescriptor<ProductionSession>()).first { $0.homeProfileID == importedBackupHome.id }
        )
        XCTAssertEqual(importedSession.currentCount, 4)
        XCTAssertEqual(importedSession.targetCount, 50)
        XCTAssertEqual(
            try CounterService(modelContext: context).events(for: importedSession).map(\.delta),
            [4]
        )
        XCTAssertFalse(HomeProfileAccess.canAccess(importedBackupHome.id, in: homes, isPro: false))
    }

    func testBackupImportLocalizesDefaultHomeNameBeforeMarkingItCustom() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Production", usesDefaultName: true, sortOrder: 0)
        context.insert(home)
        context.insert(AppSettings(selectedHomeProfileID: home.id))
        try context.save()

        let data = try FactoryToolsBackupService(modelContext: context).makeJSON()
        let backup = try FactoryToolsBackupService.decodeAndValidate(data)
        try FactoryToolsBackupImportService(modelContext: context).addCopy(
            from: backup,
            importedHomeSuffix: " (Imported)",
            defaultHomeName: "通常生産",
            isPro: true
        )

        let importedHome = try XCTUnwrap(
            context.fetch(FetchDescriptor<HomeProfile>()).first { $0.name == "通常生産 (Imported)" }
        )
        XCTAssertFalse(importedHome.usesDefaultName)
    }

    func testVersionOneBackupRestoresLegacyCounterSessionAssignment() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let session = ProductionSession(name: "Production", currentCount: 2, nextEventSequence: 1)
        let card = ToolCard(
            homeProfileID: home.id,
            toolID: .productionCounter,
            sortOrder: 0,
            productionSessionID: session.id
        )
        context.insert(home)
        context.insert(AppSettings(selectedHomeProfileID: home.id))
        context.insert(session)
        context.insert(card)
        context.insert(CountEvent(sessionID: session.id, delta: 2, sequence: 0, kind: .quickAdd))
        try context.save()

        var legacyJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: FactoryToolsBackupService(modelContext: context).makeJSON()) as? [String: Any]
        )
        legacyJSON["schemaVersion"] = 1
        legacyJSON.removeValue(forKey: "oeeRuns")
        var legacySessions = try XCTUnwrap(legacyJSON["sessions"] as? [[String: Any]])
        legacySessions[0].removeValue(forKey: "homeProfileID")
        legacySessions[0].removeValue(forKey: "toolID")
        legacyJSON["sessions"] = legacySessions
        let legacyData = try JSONSerialization.data(withJSONObject: legacyJSON)
        let backup = try FactoryToolsBackupService.decodeAndValidate(legacyData)
        XCTAssertNil(backup.sessions.first?.homeProfileID)
        XCTAssertNil(backup.sessions.first?.toolID)

        let imported = try FactoryToolsBackupImportService(modelContext: context).addCopy(
            from: backup,
            importedHomeSuffix: " (Imported)",
            defaultHomeName: "Production",
            isPro: true
        )
        let homes = try context.fetch(FetchDescriptor<HomeProfile>())
        let importedHome = try XCTUnwrap(homes.first { $0.name == "Assembly (Imported)" })
        let cards = try context.fetch(FetchDescriptor<ToolCard>())
        let importedCard = try XCTUnwrap(cards.first { $0.homeProfileID == importedHome.id })
        let importedSessionID = try XCTUnwrap(importedCard.productionSessionID)
        let sessions = try context.fetch(FetchDescriptor<ProductionSession>())
        let importedSession = try XCTUnwrap(sessions.first { $0.id == importedSessionID })
        let events = try context.fetch(FetchDescriptor<CountEvent>()).filter { $0.sessionID == importedSession.id }

        XCTAssertEqual(imported.homes, 1)
        XCTAssertEqual(imported.cards, 1)
        XCTAssertEqual(importedSession.homeProfileID, importedHome.id)
        XCTAssertEqual(importedSession.toolID, ToolID.productionCounter.rawValue)
        XCTAssertEqual(importedSession.currentCount, 2)
        XCTAssertEqual(events.map(\.delta), [2])

        let upgradedBackup = try FactoryToolsBackupService.decodeAndValidate(
            FactoryToolsBackupService(modelContext: context).makeJSON()
        )
        XCTAssertEqual(upgradedBackup.schemaVersion, 4)
        let upgradedSession = try XCTUnwrap(upgradedBackup.sessions.first { $0.id == importedSession.id })
        XCTAssertEqual(upgradedSession.homeProfileID, importedHome.id)
        XCTAssertEqual(upgradedSession.toolID, ToolID.productionCounter.rawValue)
    }

    func testBackupValidationRejectsUnsupportedVersionAndBrokenReferences() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let session = ProductionSession(
            homeProfileID: home.id,
            toolID: ToolID.productionCounter.rawValue,
            name: "Production"
        )
        context.insert(home)
        context.insert(session)
        context.insert(AppSettings(selectedHomeProfileID: home.id))
        let oeeRun = OEERun(
            homeProfileID: home.id,
            plannedProductionMinutes: 60,
            downtimeMinutes: 5,
            idealCycleTimeSeconds: 10,
            goodUnits: 300,
            defectiveUnits: 10
        )
        context.insert(oeeRun)
        try context.save()
        let data = try FactoryToolsBackupService(modelContext: context).makeJSON(exportedAt: Date(timeIntervalSince1970: 1))

        var legacyV1 = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacyV1["schemaVersion"] = 1
        legacyV1.removeValue(forKey: "oeeRuns")
        legacyV1.removeValue(forKey: "commandReceipts")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyV1)
        let decodedLegacy = try FactoryToolsBackupService.decodeAndValidate(legacyData)
        XCTAssertTrue(decodedLegacy.oeeRuns.isEmpty)
        XCTAssertTrue(decodedLegacy.commandReceipts.isEmpty)

        var legacyV2 = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacyV2["schemaVersion"] = 2
        legacyV2.removeValue(forKey: "commandReceipts")
        let legacyV2Data = try JSONSerialization.data(withJSONObject: legacyV2)
        let decodedV2 = try FactoryToolsBackupService.decodeAndValidate(legacyV2Data)
        XCTAssertTrue(decodedV2.commandReceipts.isEmpty)
        XCTAssertEqual(decodedV2.oeeRuns.map(\.id), [oeeRun.id])

        let v2Import = try FactoryToolsBackupImportService(modelContext: context).addCopy(
            from: decodedV2,
            importedHomeSuffix: " (Imported)",
            defaultHomeName: "Production",
            isPro: true
        )
        XCTAssertEqual(v2Import.oeeRuns, 1)
        let importedV2Home = try XCTUnwrap(
            context.fetch(FetchDescriptor<HomeProfile>()).first { $0.name == "Assembly (Imported)" }
        )
        let importedV2Run = try XCTUnwrap(
            context.fetch(FetchDescriptor<OEERun>()).first { $0.homeProfileID == importedV2Home.id }
        )
        XCTAssertNotEqual(importedV2Run.id, oeeRun.id)
        XCTAssertEqual(importedV2Run.goodUnits, oeeRun.goodUnits)
        let upgradedV2Backup = try FactoryToolsBackupService.decodeAndValidate(
            FactoryToolsBackupService(modelContext: context).makeJSON()
        )
        XCTAssertEqual(upgradedV2Backup.schemaVersion, 4)
        XCTAssertEqual(upgradedV2Backup.oeeRuns.count, 2)

        var incompleteV2 = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        incompleteV2["schemaVersion"] = 2
        incompleteV2.removeValue(forKey: "oeeRuns")
        let incompleteV2Data = try JSONSerialization.data(withJSONObject: incompleteV2)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(incompleteV2Data))

        var incompleteV3 = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        incompleteV3.removeValue(forKey: "commandReceipts")
        let incompleteV3Data = try JSONSerialization.data(withJSONObject: incompleteV3)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(incompleteV3Data))

        var legacyV3 = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacyV3["schemaVersion"] = 3
        legacyV3["commandReceipts"] = []
        let legacyV3Data = try JSONSerialization.data(withJSONObject: legacyV3)
        let decodedV3 = try FactoryToolsBackupService.decodeAndValidate(legacyV3Data)
        XCTAssertTrue(decodedV3.commandReceipts.isEmpty)

        var unsupported = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        unsupported["schemaVersion"] = 99
        let unsupportedData = try JSONSerialization.data(withJSONObject: unsupported)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(unsupportedData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .unsupportedVersion)
        }

        var brokenReference = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        brokenReference["cards"] = [[
            "id": UUID().uuidString,
            "homeProfileID": UUID().uuidString,
            "toolID": ToolID.productionCounter.rawValue,
            "sizeRawValue": ToolCardSize.medium.rawValue,
            "sortOrder": 0,
            "showsOnWatch": true
        ]]
        let brokenReferenceData = try JSONSerialization.data(withJSONObject: brokenReference)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(brokenReferenceData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidRelationship)
        }

        var brokenSessionReference = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        brokenSessionReference["cards"] = [[
            "id": UUID().uuidString,
            "homeProfileID": home.id.uuidString,
            "toolID": ToolID.productionCounter.rawValue,
            "sizeRawValue": ToolCardSize.medium.rawValue,
            "sortOrder": 0,
            "showsOnWatch": true,
            "productionSessionID": UUID().uuidString
        ]]
        let brokenSessionReferenceData = try JSONSerialization.data(withJSONObject: brokenSessionReference)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(brokenSessionReferenceData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidRelationship)
        }

        var invalidSessionTool = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var invalidSessionToolRecords = try XCTUnwrap(invalidSessionTool["sessions"] as? [[String: Any]])
        invalidSessionToolRecords[0]["toolID"] = ToolID.cycleTime.rawValue
        invalidSessionTool["sessions"] = invalidSessionToolRecords
        let invalidSessionToolData = try JSONSerialization.data(withJSONObject: invalidSessionTool)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(invalidSessionToolData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidStoredValue)
        }

        var unknownSessionTool = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var unknownSessionToolRecords = try XCTUnwrap(unknownSessionTool["sessions"] as? [[String: Any]])
        unknownSessionToolRecords[0]["toolID"] = "unknown.tool"
        unknownSessionTool["sessions"] = unknownSessionToolRecords
        let unknownSessionToolData = try JSONSerialization.data(withJSONObject: unknownSessionTool)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(unknownSessionToolData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidStoredValue)
        }

        var brokenSelection = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        brokenSelection["settings"] = [[
            "id": UUID().uuidString,
            "language": AppLanguage.english.rawValue,
            "themeID": ThemeID.industrialDark.rawValue,
            "selectedHomeProfileID": UUID().uuidString
        ]]
        let brokenSelectionData = try JSONSerialization.data(withJSONObject: brokenSelection)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(brokenSelectionData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidRelationship)
        }

        var invalidOEE = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        invalidOEE["oeeRuns"] = [[
            "id": UUID().uuidString,
            "homeProfileID": home.id.uuidString,
            "plannedProductionMinutes": 10,
            "downtimeMinutes": 10,
            "idealCycleTimeSeconds": 1,
            "goodUnits": 1,
            "defectiveUnits": 0,
            "createdAt": 1
        ]]
        let invalidOEEData = try JSONSerialization.data(withJSONObject: invalidOEE)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(invalidOEEData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidStoredValue)
        }

        var emptyBackup = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        emptyBackup["homes"] = []
        emptyBackup["cards"] = []
        emptyBackup["sessions"] = []
        emptyBackup["events"] = []
        emptyBackup["cycleTimeSamples"] = []
        emptyBackup["oeeRuns"] = []
        emptyBackup["settings"] = []
        let emptyBackupData = try JSONSerialization.data(withJSONObject: emptyBackup)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(emptyBackupData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidRelationship)
        }
    }

    func testBackupRejectsCounterSessionLinksAcrossHomesAndTools() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let otherHome = HomeProfile(name: "Quality", sortOrder: 1)
        let session = ProductionSession(
            homeProfileID: home.id,
            toolID: ToolID.productionCounter.rawValue,
            name: "Production"
        )
        let card = ToolCard(
            homeProfileID: home.id,
            toolID: .productionCounter,
            sortOrder: 0,
            productionSessionID: session.id
        )
        context.insert(home)
        context.insert(otherHome)
        context.insert(session)
        context.insert(card)
        context.insert(AppSettings(selectedHomeProfileID: home.id))
        try context.save()

        let validData = try FactoryToolsBackupService(modelContext: context).makeJSON()
        let validObject = try XCTUnwrap(JSONSerialization.jsonObject(with: validData) as? [String: Any])
        let originalCards = try XCTUnwrap(validObject["cards"] as? [[String: Any]])

        var crossHome = validObject
        var crossHomeCards = originalCards
        crossHomeCards[0]["homeProfileID"] = otherHome.id.uuidString
        crossHome["cards"] = crossHomeCards
        let crossHomeData = try JSONSerialization.data(withJSONObject: crossHome)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(crossHomeData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidRelationship)
        }

        var crossTool = validObject
        var crossToolCards = originalCards
        crossToolCards[0]["toolID"] = ToolID.defectCounter.rawValue
        crossTool["cards"] = crossToolCards
        let crossToolData = try JSONSerialization.data(withJSONObject: crossTool)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(crossToolData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidRelationship)
        }

        var ambiguousLegacyLink = validObject
        var legacySessions = try XCTUnwrap(validObject["sessions"] as? [[String: Any]])
        legacySessions[0]["homeProfileID"] = NSNull()
        legacySessions[0]["toolID"] = NSNull()
        ambiguousLegacyLink["sessions"] = legacySessions
        var linkedCards = originalCards
        var secondHomeCard = originalCards[0]
        secondHomeCard["id"] = UUID().uuidString
        secondHomeCard["homeProfileID"] = otherHome.id.uuidString
        linkedCards.append(secondHomeCard)
        ambiguousLegacyLink["cards"] = linkedCards
        let ambiguousLegacyData = try JSONSerialization.data(withJSONObject: ambiguousLegacyLink)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(ambiguousLegacyData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidRelationship)
        }
    }

    func testBackupValidationRejectsTimestampsOutsideISO8601ExportRange() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let session = ProductionSession(
            homeProfileID: home.id,
            toolID: ToolID.productionCounter.rawValue,
            name: "Timestamp validation"
        )
        context.insert(home)
        context.insert(session)
        context.insert(ToolCard(
            homeProfileID: home.id,
            toolID: .productionCounter,
            sortOrder: 0,
            productionSessionID: session.id
        ))
        context.insert(CycleTimeSample(homeProfileID: home.id, totalSeconds: 60, quantity: 2))
        context.insert(OEERun(
            homeProfileID: home.id,
            plannedProductionMinutes: 60,
            downtimeMinutes: 0,
            idealCycleTimeSeconds: 1,
            goodUnits: 1,
            defectiveUnits: 0
        ))
        context.insert(AppSettings(selectedHomeProfileID: home.id))
        try context.save()
        let counter = CounterService(modelContext: context)
        try counter.increment(session: session)
        try counter.quickAdd(0, to: session)
        let source = try XCTUnwrap(
            JSONSerialization.jsonObject(with: FactoryToolsBackupService(modelContext: context).makeJSON()) as? [String: Any]
        )
        XCTAssertThrowsError(try FactoryToolsBackupService(modelContext: context).makeJSON(
            exportedAt: Date(timeIntervalSince1970: 1e300)
        )) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidStoredValue)
        }

        let dateFields: [(field: String, collection: String?)] = [
            ("exportedAt", nil),
            ("createdAt", "homes"),
            ("startedAt", "sessions"),
            ("occurredAt", "events"),
            ("processedAt", "commandReceipts"),
            ("createdAt", "cycleTimeSamples"),
            ("createdAt", "oeeRuns")
        ]
        for dateField in dateFields {
            var payload = source
            if let collection = dateField.collection {
                var records = try XCTUnwrap(payload[collection] as? [[String: Any]])
                records[0][dateField.field] = 1e300
                payload[collection] = records
            } else {
                payload[dateField.field] = 1e300
            }
            let invalidData = try JSONSerialization.data(withJSONObject: payload)
            XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(invalidData), "\(dateField.collection ?? "backup").\(dateField.field)") { error in
                XCTAssertEqual(error as? FactoryToolsBackupError, .invalidStoredValue)
            }
        }
    }

    func testPersistenceServicesRejectUnsupportedTimestampsWithoutWritingRecords() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let session = ProductionSession(
            homeProfileID: home.id,
            toolID: ToolID.productionCounter.rawValue,
            name: "Timestamp validation"
        )
        context.insert(home)
        context.insert(session)
        context.insert(AppSettings(selectedHomeProfileID: home.id))
        try context.save()
        let invalidDate = Date(timeIntervalSince1970: 1e300)
        XCTAssertFalse(PersistedTimestamp.isSupported(Date(timeIntervalSince1970: .infinity)))
        XCTAssertFalse(PersistedTimestamp.isSupported(Date(timeIntervalSince1970: .nan)))

        XCTAssertThrowsError(try CycleTimeSampleService(modelContext: context).save(
            totalSeconds: 60,
            quantity: 2,
            for: home.id,
            createdAt: invalidDate
        )) { error in
            XCTAssertEqual(error as? CycleTimeSampleServiceError, .invalidTimestamp)
        }
        XCTAssertThrowsError(try OEERunService(modelContext: context).save(
            plannedProductionMinutes: 60,
            downtimeMinutes: 0,
            idealCycleTimeSeconds: 1,
            goodUnits: 1,
            defectiveUnits: 0,
            for: home.id,
            createdAt: invalidDate,
            isPro: true
        )) { error in
            XCTAssertEqual(error as? OEERunServiceError, .invalidTimestamp)
        }
        let command = CounterCommand(
            sessionID: session.id,
            operation: .increment,
            createdAt: invalidDate
        )
        XCTAssertThrowsError(try CounterService(modelContext: context).apply(command, to: session)) { error in
            XCTAssertEqual(error as? CounterServiceError, .invalidTimestamp)
        }

        XCTAssertTrue(try context.fetch(FetchDescriptor<CycleTimeSample>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<OEERun>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CountEvent>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CounterCommandReceipt>()).isEmpty)
        XCTAssertEqual(session.currentCount, 0)
        XCTAssertEqual(session.nextEventSequence, 0)
    }

    func testBackupValidationRejectsDanglingAndEventCollidingCommandReceipts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let session = ProductionSession(homeProfileID: home.id, name: "Receipt validation")
        context.insert(home)
        context.insert(session)
        context.insert(AppSettings(selectedHomeProfileID: home.id))
        try context.save()

        let counter = CounterService(modelContext: context)
        try counter.increment(session: session)
        try counter.undo(session: session)
        try counter.reset(session: session)
        let data = try FactoryToolsBackupService(modelContext: context).makeJSON()
        let validBackup = try FactoryToolsBackupService.decodeAndValidate(data)
        let eventID = try XCTUnwrap(validBackup.events.first?.id)
        XCTAssertEqual(validBackup.commandReceipts.count, 1)

        var dangling = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var danglingReceipts = try XCTUnwrap(dangling["commandReceipts"] as? [[String: Any]])
        danglingReceipts[0]["sessionID"] = UUID().uuidString
        dangling["commandReceipts"] = danglingReceipts
        let danglingData = try JSONSerialization.data(withJSONObject: dangling)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(danglingData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidRelationship)
        }

        var colliding = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var collidingReceipts = try XCTUnwrap(colliding["commandReceipts"] as? [[String: Any]])
        collidingReceipts[0]["id"] = eventID.uuidString
        colliding["commandReceipts"] = collidingReceipts
        let collidingData = try JSONSerialization.data(withJSONObject: colliding)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(collidingData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .duplicateIdentifier)
        }
    }

    func testBackupValidationEnforcesRegistrySupportedCardSizes() throws {
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let settings = AppSettings(selectedHomeProfileID: home.id)

        for definition in ToolRegistry.all {
            for size in ToolCardSize.allCases {
                let card = ToolCard(
                    homeProfileID: home.id,
                    toolID: definition.id,
                    size: size,
                    sortOrder: 0
                )
                let backup = FactoryToolsBackup(
                    schemaVersion: 3,
                    exportedAt: .now,
                    homes: [FactoryToolsBackup.Home(home)],
                    cards: [FactoryToolsBackup.Card(card)],
                    sessions: [],
                    events: [],
                    cycleTimeSamples: [],
                    settings: [FactoryToolsBackup.Settings(settings)]
                )

                if definition.supportedCardSizes.contains(size) {
                    XCTAssertNoThrow(try FactoryToolsBackupService.validate(backup), "\(definition.id) should support \(size)")
                } else {
                    XCTAssertThrowsError(try FactoryToolsBackupService.validate(backup), "\(definition.id) must reject \(size)") { error in
                        XCTAssertEqual(error as? FactoryToolsBackupError, .invalidStoredValue)
                    }
                }
            }
        }
    }

    func testBackupValidationRejectsBlankHomeNames() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        context.insert(home)
        context.insert(AppSettings(selectedHomeProfileID: home.id))
        try context.save()

        let data = try FactoryToolsBackupService(modelContext: context).makeJSON()
        var backup = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var homes = try XCTUnwrap(backup["homes"] as? [[String: Any]])
        homes[0]["name"] = " \n  \t"
        backup["homes"] = homes
        let invalidData = try JSONSerialization.data(withJSONObject: backup)

        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(invalidData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidStoredValue)
        }

    }

    func testBackupValidationRejectsBlankSessionNames() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let session = ProductionSession(homeProfileID: home.id, name: "Production")
        context.insert(home)
        context.insert(session)
        context.insert(AppSettings(selectedHomeProfileID: home.id))
        try context.save()

        let data = try FactoryToolsBackupService(modelContext: context).makeJSON()
        var backup = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var sessions = try XCTUnwrap(backup["sessions"] as? [[String: Any]])
        sessions[0]["name"] = " \n \t"
        backup["sessions"] = sessions
        let invalidData = try JSONSerialization.data(withJSONObject: backup)

        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(invalidData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidStoredValue)
        }
    }

    func testBackupFileReaderRejectsOversizedFilesBeforeJSONDecoding() throws {
        XCTAssertNoThrow(try FactoryToolsBackupService.validateBackupByteCount(16, maximumSizeInBytes: 16))
        XCTAssertThrowsError(try FactoryToolsBackupService.validateBackupByteCount(17, maximumSizeInBytes: 16)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .backupTooLarge)
        }
        XCTAssertThrowsError(try FactoryToolsBackupService.validateBackupByteCount(1, maximumSizeInBytes: -1)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .backupTooLarge)
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FactoryToolsBackup-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data(repeating: 0x7B, count: 17).write(to: fileURL)

        XCTAssertThrowsError(
            try FactoryToolsBackupService.readAndValidate(from: fileURL, maximumSizeInBytes: 16)
        ) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .backupTooLarge)
        }
        XCTAssertThrowsError(
            try FactoryToolsBackupService.decodeAndValidate(Data(repeating: 0x7B, count: 17), maximumSizeInBytes: 16)
        ) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .backupTooLarge)
        }
    }

    func testBackupValidationRejectsMismatchedEventKindAndPreservesUnknownKinds() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let session = ProductionSession(homeProfileID: home.id, name: "Kind validation", currentCount: 1, nextEventSequence: 1)
        context.insert(home)
        context.insert(session)
        context.insert(CountEvent(sessionID: session.id, delta: 1, sequence: 0, kind: .increment))
        context.insert(AppSettings(selectedHomeProfileID: home.id))
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<HomeProfile>()).map(\.id), [home.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProductionSession>()).map(\.id), [session.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<CountEvent>()).map(\.sessionID), [session.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettings>()).compactMap(\.selectedHomeProfileID), [home.id])

        let data = try FactoryToolsBackupService(modelContext: context).makeJSON()
        var backup = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var events = try XCTUnwrap(backup["events"] as? [[String: Any]])
        events[0]["kindRawValue"] = CounterEventKind.decrement.rawValue
        backup["events"] = events
        let invalidData = try JSONSerialization.data(withJSONObject: backup)

        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(invalidData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidStoredValue)
        }

        events[0]["kindRawValue"] = "futureCounterAction"
        backup["events"] = events
        let forwardCompatibleData = try JSONSerialization.data(withJSONObject: backup)
        let forwardCompatibleBackup = try FactoryToolsBackupService.decodeAndValidate(forwardCompatibleData)
        let importedContainer = try makeContainer()
        let importedContext = ModelContext(importedContainer)
        try FactoryToolsBackupImportService(modelContext: importedContext).addCopy(
            from: forwardCompatibleBackup,
            importedHomeSuffix: " (Imported)",
            defaultHomeName: "Production",
            isPro: true
        )
        let importedEvents = try importedContext.fetch(FetchDescriptor<CountEvent>())
        XCTAssertEqual(importedEvents.first?.kindRawValue, "futureCounterAction")

        let reexportedData = try FactoryToolsBackupService(modelContext: importedContext).makeJSON()
        let reexportedBackup = try FactoryToolsBackupService.decodeAndValidate(reexportedData)
        XCTAssertEqual(reexportedBackup.events.first?.kindRawValue, "futureCounterAction")
    }

    func testBackupValidationRejectsResetThatLeavesCountAboveZero() throws {
        let validContainer = try makeContainer()
        let validContext = ModelContext(validContainer)
        let validHome = HomeProfile(name: "Assembly", sortOrder: 0)
        let validSession = ProductionSession(homeProfileID: validHome.id, name: "Valid reset")
        validContext.insert(validHome)
        validContext.insert(validSession)
        validContext.insert(AppSettings(selectedHomeProfileID: validHome.id))
        try validContext.save()
        let validCounter = CounterService(modelContext: validContext)
        try validCounter.quickAdd(2, to: validSession)
        try validCounter.reset(session: validSession)
        let validData = try FactoryToolsBackupService(modelContext: validContext).makeJSON()
        XCTAssertNoThrow(try FactoryToolsBackupService.decodeAndValidate(validData))

        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let session = ProductionSession(homeProfileID: home.id, name: "Invalid reset", currentCount: 1, nextEventSequence: 1)
        context.insert(home)
        context.insert(session)
        context.insert(CountEvent(sessionID: session.id, delta: -1, sequence: 0, kind: .reset))
        context.insert(AppSettings(selectedHomeProfileID: home.id))
        try context.save()

        XCTAssertThrowsError(try FactoryToolsBackupService(modelContext: context).makeJSON()) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidStoredValue)
        }
        var invalidReset = try XCTUnwrap(JSONSerialization.jsonObject(with: validData) as? [String: Any])
        var sessions = try XCTUnwrap(invalidReset["sessions"] as? [[String: Any]])
        sessions[0]["currentCount"] = 1
        invalidReset["sessions"] = sessions
        let invalidData = try JSONSerialization.data(withJSONObject: invalidReset)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(invalidData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidStoredValue)
        }
    }

    func testBackupValidationRejectsInvalidEventBalancesAndDuplicateSequences() throws {
        let invalidContainer = try makeContainer()
        let invalidContext = ModelContext(invalidContainer)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let session = ProductionSession(homeProfileID: home.id, name: "Inconsistent", currentCount: 3, nextEventSequence: 1)
        let event = CountEvent(sessionID: session.id, delta: 4, sequence: 0)
        invalidContext.insert(home)
        invalidContext.insert(AppSettings(selectedHomeProfileID: home.id))
        invalidContext.insert(session)
        invalidContext.insert(event)
        try invalidContext.save()
        XCTAssertThrowsError(try FactoryToolsBackupService(modelContext: invalidContext).makeJSON()) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidStoredValue)
        }

        let baseContainer = try makeContainer()
        let baseContext = ModelContext(baseContainer)
        let baseHome = HomeProfile(name: "Assembly", sortOrder: 0)
        let baseSession = ProductionSession(
            homeProfileID: baseHome.id,
            name: "Inconsistent",
            currentCount: 3,
            nextEventSequence: 1
        )
        baseContext.insert(baseHome)
        baseContext.insert(AppSettings(selectedHomeProfileID: baseHome.id))
        baseContext.insert(baseSession)
        try baseContext.save()
        var inconsistent = try XCTUnwrap(
            JSONSerialization.jsonObject(with: FactoryToolsBackupService(modelContext: baseContext).makeJSON()) as? [String: Any]
        )
        inconsistent["events"] = [[
            "id": UUID().uuidString,
            "sessionID": baseSession.id.uuidString,
            "delta": 4,
            "sequence": 0,
            "occurredAt": 1_000
        ]]
        let inconsistentJSON = try JSONSerialization.data(withJSONObject: inconsistent)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(inconsistentJSON)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidStoredValue)
        }

        let duplicateContainer = try makeContainer()
        let duplicateContext = ModelContext(duplicateContainer)
        let duplicateHome = HomeProfile(name: "Assembly", sortOrder: 0)
        let duplicateSession = ProductionSession(homeProfileID: duplicateHome.id, name: "Duplicate sequence", nextEventSequence: 2)
        duplicateContext.insert(duplicateHome)
        duplicateContext.insert(AppSettings(selectedHomeProfileID: duplicateHome.id))
        duplicateContext.insert(duplicateSession)
        duplicateContext.insert(CountEvent(sessionID: duplicateSession.id, delta: 1, sequence: 0))
        duplicateContext.insert(CountEvent(sessionID: duplicateSession.id, delta: -1, sequence: 0))
        try duplicateContext.save()
        XCTAssertThrowsError(try FactoryToolsBackupService(modelContext: duplicateContext).makeJSON()) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .duplicateSequence)
        }

        let duplicateBaseContainer = try makeContainer()
        let duplicateBaseContext = ModelContext(duplicateBaseContainer)
        let duplicateBaseHome = HomeProfile(name: "Assembly", sortOrder: 0)
        let duplicateBaseSession = ProductionSession(
            homeProfileID: duplicateBaseHome.id,
            name: "Duplicate sequence",
            nextEventSequence: 2
        )
        duplicateBaseContext.insert(duplicateBaseHome)
        duplicateBaseContext.insert(AppSettings(selectedHomeProfileID: duplicateBaseHome.id))
        duplicateBaseContext.insert(duplicateBaseSession)
        try duplicateBaseContext.save()
        var duplicatePayload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: FactoryToolsBackupService(modelContext: duplicateBaseContext).makeJSON()) as? [String: Any]
        )
        duplicatePayload["events"] = [1, -1].enumerated().map { index, delta in
            [
                "id": UUID().uuidString,
                "sessionID": duplicateBaseSession.id.uuidString,
                "delta": delta,
                "sequence": 0,
                "occurredAt": 1_000 + index
            ] as [String: Any]
        }
        let duplicateJSON = try JSONSerialization.data(withJSONObject: duplicatePayload)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(duplicateJSON)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .duplicateSequence)
        }
    }

    func testBackupValidationRejectsNegativeIntermediateCountAndMalformedUndo() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let session = ProductionSession(
            homeProfileID: home.id,
            name: "Production",
            currentCount: 0,
            nextEventSequence: 4
        )
        context.insert(home)
        context.insert(AppSettings(selectedHomeProfileID: home.id))
        context.insert(session)
        try context.save()

        let base = try XCTUnwrap(
            JSONSerialization.jsonObject(with: FactoryToolsBackupService(modelContext: context).makeJSON()) as? [String: Any]
        )
        func dataWithEvents(_ events: [[String: Any]]) throws -> Data {
            var payload = base
            payload["events"] = events
            return try JSONSerialization.data(withJSONObject: payload)
        }
        func event(id: UUID, delta: Int, sequence: Int, reverses: UUID? = nil) -> [String: Any] {
            var value: [String: Any] = [
                "id": id.uuidString,
                "sessionID": session.id.uuidString,
                "delta": delta,
                "sequence": sequence,
                "occurredAt": 1_000 + sequence,
                "kindRawValue": eventKind(delta: delta, reverses: reverses).rawValue
            ]
            if let reverses { value["reversesEventID"] = reverses.uuidString }
            return value
        }
        func eventKind(delta: Int, reverses: UUID?) -> CounterEventKind {
            if reverses != nil { return .undo }
            if delta == 1 { return .increment }
            if delta == -1 { return .decrement }
            if delta > 1 { return .quickAdd }
            return .reset
        }

        let negativeFirstID = UUID()
        let negativeLastID = UUID()
        let negativeIntermediate = try dataWithEvents([
            event(id: negativeFirstID, delta: -1, sequence: 0),
            event(id: negativeLastID, delta: 1, sequence: 1)
        ])
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(negativeIntermediate)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidStoredValue)
        }

        let firstID = UUID()
        let malformedUndoID = UUID()
        let secondID = UUID()
        let validUndoID = UUID()
        let malformedUndo = try dataWithEvents([
            event(id: firstID, delta: 2, sequence: 0),
            event(id: malformedUndoID, delta: -1, sequence: 1, reverses: firstID),
            event(id: secondID, delta: 2, sequence: 2),
            event(id: validUndoID, delta: -3, sequence: 3, reverses: secondID)
        ])
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(malformedUndo)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidRelationship)
        }

        let duplicateUndo = try dataWithEvents([
            event(id: firstID, delta: 1, sequence: 0),
            event(id: malformedUndoID, delta: -1, sequence: 1, reverses: firstID),
            event(id: secondID, delta: 1, sequence: 2),
            event(id: validUndoID, delta: -1, sequence: 3, reverses: firstID)
        ])
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(duplicateUndo)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidRelationship)
        }

        let undoOfUndo = try dataWithEvents([
            event(id: firstID, delta: 1, sequence: 0),
            event(id: malformedUndoID, delta: -1, sequence: 1, reverses: firstID),
            event(id: secondID, delta: 1, sequence: 2, reverses: malformedUndoID),
            event(id: UUID(), delta: -1, sequence: 3)
        ])
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(undoOfUndo)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidRelationship)
        }

        let secondOriginalID = UUID()
        let staleUndo = try dataWithEvents([
            event(id: firstID, delta: 2, sequence: 0),
            event(id: secondOriginalID, delta: 3, sequence: 1),
            event(id: malformedUndoID, delta: -2, sequence: 2, reverses: firstID),
            event(id: validUndoID, delta: -3, sequence: 3, reverses: secondOriginalID)
        ])
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(staleUndo)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidRelationship)
        }

        let latestFirstUndo = try dataWithEvents([
            event(id: firstID, delta: 2, sequence: 0),
            event(id: secondOriginalID, delta: 3, sequence: 1),
            event(id: validUndoID, delta: -3, sequence: 2, reverses: secondOriginalID),
            event(id: malformedUndoID, delta: -2, sequence: 3, reverses: firstID)
        ])
        XCTAssertNoThrow(try FactoryToolsBackupService.decodeAndValidate(latestFirstUndo))
    }

    func testActionsUpdateAggregateAndAppendEvents() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(name: "Test")
        context.insert(session)
        let service = CounterService(modelContext: context)

        try service.increment(session: session)
        try service.quickAdd(5, to: session)
        try service.quickAdd(10, to: session)
        try service.decrement(session: session)

        XCTAssertEqual(session.currentCount, 15)
        XCTAssertEqual(session.nextEventSequence, 4)
        let events = try context.fetch(FetchDescriptor<CountEvent>())
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.reduce(0) { $0 + $1.delta }, session.currentCount)
        XCTAssertEqual(events.map(\.sequence).sorted(), [0, 1, 2, 3])
        XCTAssertEqual(events.sorted { $0.sequence < $1.sequence }.compactMap(\.kind), [.increment, .quickAdd, .quickAdd, .decrement])
    }

    func testUndoAppendsInverseEventAndPreservesHistory() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(name: "Test")
        context.insert(session)
        let service = CounterService(modelContext: context)

        try service.quickAdd(10, to: session)
        try service.undo(session: session)

        let events = try context.fetch(FetchDescriptor<CountEvent>())
        XCTAssertEqual(session.currentCount, 0)
        XCTAssertEqual(session.nextEventSequence, 2)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.reduce(0) { $0 + $1.delta }, session.currentCount)
        guard let original = events.first(where: { $0.reversesEventID == nil }),
              let inverse = events.first(where: { $0.reversesEventID != nil }) else {
            XCTFail("Undo should append a linked inverse event")
            return
        }
        XCTAssertEqual(inverse.reversesEventID, original.id)
        XCTAssertEqual(inverse.delta, -original.delta)
        XCTAssertEqual(inverse.kind, .undo)
    }

    func testCustomQuickAddAmountIsRecordedAndCanBeUndone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(name: "Test")
        context.insert(session)
        let service = CounterService(modelContext: context)

        try service.quickAdd(37, to: session)

        let addition = try XCTUnwrap(context.fetch(FetchDescriptor<CountEvent>()).first)
        XCTAssertEqual(session.currentCount, 37)
        XCTAssertEqual(addition.delta, 37)

        try service.undo(session: session)

        let events = try context.fetch(FetchDescriptor<CountEvent>()).sorted { $0.sequence < $1.sequence }
        XCTAssertEqual(session.currentCount, 0)
        XCTAssertEqual(events.map(\.delta), [37, -37])
        XCTAssertEqual(events.last?.reversesEventID, addition.id)
    }

    func testCounterCommandRoundTripsAndDuplicateDeliveryAppliesOnlyOnce() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(name: "Command test")
        context.insert(session)
        let command = CounterCommand(
            id: UUID(),
            sessionID: session.id,
            operation: .quickAdd(12),
            createdAt: Date(timeIntervalSince1970: 1_234)
        )
        let encoded = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(CounterCommand.self, from: encoded)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let operation = try XCTUnwrap(payload["operation"] as? [String: Any])
        let service = CounterService(modelContext: context)

        XCTAssertEqual(decoded, command)
        XCTAssertEqual(decoded.payloadSignature, command.payloadSignature)
        XCTAssertEqual(payload["schemaVersion"] as? Int, CounterCommand.currentSchemaVersion)
        XCTAssertEqual(operation["kind"] as? String, "quickAdd")
        XCTAssertEqual(operation["amount"] as? Int, 12)
        XCTAssertEqual(try service.apply(decoded, to: session), .applied)
        XCTAssertEqual(try service.apply(decoded, to: session), .alreadyApplied)

        let events = try context.fetch(FetchDescriptor<CountEvent>())
        XCTAssertEqual(session.currentCount, 12)
        XCTAssertEqual(session.nextEventSequence, 1)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, command.id)
        XCTAssertEqual(events.first?.occurredAt, command.createdAt)
        XCTAssertEqual(events.first?.kind, .quickAdd)
        XCTAssertEqual(events.first?.payloadSignature, command.payloadSignature)

        let undoCommand = CounterCommand(sessionID: session.id, operation: .undo(eventID: command.id))
        let encodedUndo = try JSONEncoder().encode(undoCommand)
        let decodedUndo = try JSONDecoder().decode(CounterCommand.self, from: encodedUndo)
        let undoPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedUndo) as? [String: Any])
        let undoOperation = try XCTUnwrap(undoPayload["operation"] as? [String: Any])
        XCTAssertEqual(undoOperation["kind"] as? String, "undo")
        XCTAssertEqual(undoOperation["eventID"] as? String, command.id.uuidString)
        XCTAssertEqual(try service.apply(decodedUndo, to: session), .applied)
        XCTAssertEqual(try service.apply(decodedUndo, to: session), .alreadyApplied)
        XCTAssertEqual(session.currentCount, 0)

        var unsupportedPayload = payload
        unsupportedPayload["schemaVersion"] = CounterCommand.currentSchemaVersion + 1
        let unsupportedData = try JSONSerialization.data(withJSONObject: unsupportedPayload)
        XCTAssertThrowsError(try JSONDecoder().decode(CounterCommand.self, from: unsupportedData))
    }

    func testWatchCommandProcessorCatalogAndCommandUseTheCanonicalCounterService() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let session = ProductionSession(
            homeProfileID: home.id,
            toolID: ToolID.productionCounter.rawValue,
            name: "Line A",
            currentCount: 4,
            targetCount: 20,
            nextEventSequence: 1
        )
        let card = ToolCard(
            homeProfileID: home.id,
            toolID: .productionCounter,
            size: .medium,
            sortOrder: 0,
            showsOnWatch: true,
            productionSessionID: session.id
        )
        let settings = AppSettings(language: AppLanguage.japanese.rawValue, selectedHomeProfileID: home.id)
        context.insert(home)
        context.insert(session)
        context.insert(card)
        context.insert(settings)
        try context.save()

        let processor = WatchCommandProcessor(modelContext: context)
        let catalog = try processor.catalog()
        XCTAssertEqual(catalog.displayLanguage, .japanese)
        XCTAssertEqual(catalog.sessions.map(\.sessionID), [session.id])
        XCTAssertEqual(catalog.sessions.first?.toolID, .productionCounter)
        XCTAssertEqual(catalog.sessions.first?.currentCount, 4)

        let command = CounterCommand(sessionID: session.id, operation: .increment)
        let firstResult = try processor.process(command)
        XCTAssertEqual(firstResult.acknowledgement.status, .applied)
        XCTAssertEqual(firstResult.acknowledgement.commandID, command.id)
        XCTAssertEqual(firstResult.session?.currentCount, 5)

        let retryResult = try processor.process(command)
        XCTAssertEqual(retryResult.acknowledgement.status, .alreadyApplied)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CountEvent>()).count, 1)
        XCTAssertEqual(session.currentCount, 5)
    }

    func testWatchCatalogKeepsSelectedLanguageForEmptyHomeState() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(AppSettings(language: AppLanguage.english.rawValue))
        try context.save()

        let catalog = try WatchCommandProcessor(modelContext: context).catalog()
        XCTAssertTrue(catalog.sessions.isEmpty)
        XCTAssertNil(catalog.cycleTimeHome)
        XCTAssertEqual(catalog.displayLanguage, .english)
    }

    func testWatchProductionProgressCatalogRequiresProAndWatchVisibility() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let session = ProductionSession(
            homeProfileID: home.id,
            toolID: ToolID.productionCounter.rawValue,
            name: "Line A",
            currentCount: 42,
            targetCount: 100
        )
        let card = ToolCard(
            homeProfileID: home.id,
            toolID: .productionProgress,
            sortOrder: 0,
            showsOnWatch: true,
            productionSessionID: session.id
        )
        context.insert(home)
        context.insert(session)
        context.insert(card)
        context.insert(AppSettings(selectedHomeProfileID: home.id))
        try context.save()

        let processor = WatchCommandProcessor(modelContext: context)
        XCTAssertTrue(try processor.catalog(isPro: false).progressCards.isEmpty)
        let proCatalog = try processor.catalog(isPro: true)
        XCTAssertEqual(proCatalog.progressCards, [WatchProductionProgressSnapshot(
            cardID: card.id,
            sessionID: session.id,
            homeProfileID: home.id,
            homeName: "Assembly",
            currentCount: 42,
            targetCount: 100
        )])
        XCTAssertTrue(try processor.peerCatalog(isPro: true).progressCards.isEmpty)

        card.showsOnWatch = false
        try context.save()
        XCTAssertTrue(try processor.catalog(isPro: true).progressCards.isEmpty)
    }

    func testWatchCatalogLocalizesGeneratedSessionNamesAfterLanguageChange() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let productionSession = ProductionSession(
            homeProfileID: home.id,
            toolID: ToolID.productionCounter.rawValue,
            name: String(localized: LocalizedStringResource(
                "counter.defaultSessionName",
                locale: Locale(identifier: "ja")
            ))
        )
        let defectSession = ProductionSession(
            homeProfileID: home.id,
            toolID: ToolID.defectCounter.rawValue,
            name: String(localized: LocalizedStringResource(
                "defect.defaultSessionName",
                locale: Locale(identifier: "ja")
            ))
        )
        let customSession = ProductionSession(
            homeProfileID: home.id,
            toolID: ToolID.productionCounter.rawValue,
            name: "第2ライン"
        )
        context.insert(home)
        context.insert(productionSession)
        context.insert(defectSession)
        context.insert(customSession)
        context.insert(ToolCard(
            homeProfileID: home.id,
            toolID: .productionCounter,
            sortOrder: 0,
            showsOnWatch: true,
            productionSessionID: productionSession.id
        ))
        context.insert(ToolCard(
            homeProfileID: home.id,
            toolID: .defectCounter,
            sortOrder: 1,
            showsOnWatch: true,
            productionSessionID: defectSession.id
        ))
        context.insert(ToolCard(
            homeProfileID: home.id,
            toolID: .productionCounter,
            sortOrder: 2,
            showsOnWatch: true,
            productionSessionID: customSession.id
        ))
        context.insert(AppSettings(language: AppLanguage.english.rawValue, selectedHomeProfileID: home.id))
        try context.save()

        let catalog = try WatchCommandProcessor(modelContext: context).catalog()
        XCTAssertEqual(catalog.displayLanguage, .english)
        XCTAssertEqual(catalog.sessions.first(where: { $0.toolID == .productionCounter })?.defaultSessionNameToolID, .productionCounter)
        XCTAssertEqual(catalog.sessions.first(where: { $0.toolID == .defectCounter })?.defaultSessionNameToolID, .defectCounter)
        XCTAssertNil(catalog.sessions.first(where: { $0.sessionName == "第2ライン" })?.defaultSessionNameToolID)
        XCTAssertNil(catalog.sessions.first(where: { $0.sessionName == "第2ライン" })?.homeNameIsDefault)
        XCTAssertTrue(catalog.sessions.filter { $0.defaultSessionNameToolID != nil }.allSatisfy {
            $0.sessionName.contains("セッション") || $0.sessionName.contains("不良")
        })
    }

    func testCompanionCatalogsMarkDefaultHomeNamesForLocalTranslation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Production", usesDefaultName: true, sortOrder: 0)
        let counterSession = ProductionSession(
            homeProfileID: home.id,
            toolID: ToolID.productionCounter.rawValue,
            name: "Production"
        )
        let progressSession = ProductionSession(
            homeProfileID: home.id,
            toolID: ToolID.productionCounter.rawValue,
            name: "Progress",
            currentCount: 42,
            targetCount: 100
        )
        context.insert(home)
        context.insert(counterSession)
        context.insert(progressSession)
        context.insert(ToolCard(
            homeProfileID: home.id,
            toolID: .productionCounter,
            sortOrder: 0,
            showsOnWatch: true,
            productionSessionID: counterSession.id
        ))
        context.insert(ToolCard(homeProfileID: home.id, toolID: .cycleTime, sortOrder: 1, showsOnWatch: true))
        context.insert(ToolCard(
            homeProfileID: home.id,
            toolID: .productionProgress,
            sortOrder: 2,
            showsOnWatch: true,
            productionSessionID: progressSession.id
        ))
        context.insert(AppSettings(language: AppLanguage.japanese.rawValue, selectedHomeProfileID: home.id))
        try context.save()

        let processor = WatchCommandProcessor(modelContext: context)
        let watchCatalog = try processor.catalog(isPro: true)
        XCTAssertTrue(watchCatalog.sessions.first?.homeNameIsDefault == true)
        XCTAssertTrue(watchCatalog.cycleTimeHome?.homeNameIsDefault == true)
        XCTAssertTrue(watchCatalog.progressCards.first?.homeNameIsDefault == true)
        XCTAssertEqual(
            try processor.process(CounterCommand(sessionID: counterSession.id, operation: .increment), isPro: true).session?.homeNameIsDefault,
            true
        )
        XCTAssertTrue(try processor.peerCatalog(isPro: true).sessions.first?.homeNameIsDefault == true)
    }

    func testFreeWatchCycleTimeCapturesAndIdempotentlyStoresSamplesOnIPhone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let card = ToolCard(
            homeProfileID: home.id,
            toolID: .cycleTime,
            sortOrder: 0,
            showsOnWatch: true
        )
        context.insert(home)
        context.insert(card)
        context.insert(AppSettings(selectedHomeProfileID: home.id))
        try context.save()

        let processor = WatchCommandProcessor(modelContext: context)
        let catalog = try processor.catalog(isPro: false)
        XCTAssertEqual(catalog.cycleTimeHome, WatchCycleTimeHomeSnapshot(homeProfileID: home.id, homeName: "Assembly"))

        let sampleID = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let command = try WatchCycleTimeCommand(
            id: sampleID,
            homeProfileID: home.id,
            totalSeconds: 37,
            createdAt: capturedAt
        )
        XCTAssertEqual(try processor.process(command, isPro: false).status, .applied)
        XCTAssertEqual(try processor.process(command, isPro: false).status, .alreadyApplied)

        let samples = try context.fetch(FetchDescriptor<CycleTimeSample>())
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.id, sampleID)
        XCTAssertEqual(samples.first?.totalSeconds, 37)
        XCTAssertEqual(samples.first?.quantity, 1)
        XCTAssertEqual(samples.first?.homeProfileID, home.id)

        card.showsOnWatch = false
        try context.save()
        XCTAssertEqual(try processor.process(command, isPro: false).status, .alreadyApplied)
        let hiddenCommand = try WatchCycleTimeCommand(homeProfileID: home.id, totalSeconds: 12, createdAt: capturedAt)
        XCTAssertEqual(try processor.process(hiddenCommand, isPro: false).status, .rejected)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CycleTimeSample>()).count, 1)
    }

    func testWatchCatalogTracksSelectedHomeAndVisibilityChangesAfterPersistence() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let firstHome = HomeProfile(name: "Assembly", sortOrder: 0)
        let secondHome = HomeProfile(name: "Packaging", sortOrder: 1)
        let firstSession = ProductionSession(
            homeProfileID: firstHome.id,
            toolID: ToolID.productionCounter.rawValue,
            name: "Assembly Counter"
        )
        let secondSession = ProductionSession(
            homeProfileID: secondHome.id,
            toolID: ToolID.defectCounter.rawValue,
            name: "Packaging Defects"
        )
        let firstCard = ToolCard(
            homeProfileID: firstHome.id,
            toolID: .productionCounter,
            sortOrder: 0,
            showsOnWatch: true,
            productionSessionID: firstSession.id
        )
        let secondCard = ToolCard(
            homeProfileID: secondHome.id,
            toolID: .defectCounter,
            sortOrder: 0,
            showsOnWatch: true,
            productionSessionID: secondSession.id
        )
        let settings = AppSettings(selectedHomeProfileID: firstHome.id)
        [firstHome, secondHome].forEach(context.insert)
        [firstSession, secondSession].forEach(context.insert)
        [firstCard, secondCard].forEach(context.insert)
        context.insert(settings)
        try context.save()

        let processor = WatchCommandProcessor(modelContext: context)
        XCTAssertEqual(try processor.catalog(isPro: true).sessions.map(\.sessionID), [firstSession.id])

        settings.selectedHomeProfileID = secondHome.id
        try context.save()
        XCTAssertEqual(try processor.catalog(isPro: true).sessions.map(\.sessionID), [secondSession.id])
        XCTAssertEqual(
            try processor.process(CounterCommand(sessionID: firstSession.id, operation: .increment), isPro: true).acknowledgement.status,
            .rejected,
            "Commands from a previously selected home must not remain authorized after switching homes."
        )
        XCTAssertEqual(firstSession.currentCount, 0)

        secondCard.showsOnWatch = false
        try context.save()
        XCTAssertTrue(try processor.catalog(isPro: true).sessions.isEmpty)
        XCTAssertEqual(
            try processor.process(CounterCommand(sessionID: secondSession.id, operation: .increment), isPro: true).acknowledgement.status,
            .rejected
        )
    }

    func testWatchCommandProcessorRejectsHiddenUnsupportedAndDeletedSessions() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Production", sortOrder: 0)
        let hiddenSession = ProductionSession(homeProfileID: home.id, toolID: ToolID.productionCounter.rawValue, name: "Hidden")
        let hiddenCard = ToolCard(
            homeProfileID: home.id,
            toolID: .productionCounter,
            sortOrder: 0,
            showsOnWatch: false,
            productionSessionID: hiddenSession.id
        )
        let unsupportedSession = ProductionSession(homeProfileID: home.id, toolID: ToolID.cycleTime.rawValue, name: "Cycle")
        let unsupportedCard = ToolCard(
            homeProfileID: home.id,
            toolID: .cycleTime,
            sortOrder: 1,
            showsOnWatch: true,
            productionSessionID: unsupportedSession.id
        )
        context.insert(home)
        context.insert(hiddenSession)
        context.insert(hiddenCard)
        context.insert(unsupportedSession)
        context.insert(unsupportedCard)
        try context.save()

        let processor = WatchCommandProcessor(modelContext: context)
        let hiddenResult = try processor.process(CounterCommand(sessionID: hiddenSession.id, operation: .increment))
        let unsupportedResult = try processor.process(CounterCommand(sessionID: unsupportedSession.id, operation: .increment))
        let missingResult = try processor.process(CounterCommand(sessionID: UUID(), operation: .increment))

        XCTAssertEqual(hiddenResult.acknowledgement.status, .rejected)
        XCTAssertEqual(unsupportedResult.acknowledgement.status, .rejected)
        XCTAssertEqual(missingResult.acknowledgement.status, .rejected)
        XCTAssertEqual(hiddenSession.currentCount, 0)
        XCTAssertEqual(unsupportedSession.currentCount, 0)
        XCTAssertTrue(try processor.catalog().sessions.isEmpty)
    }

    func testFreeWatchAndPeerControlsUseTheCanonicalCounterService() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Production", sortOrder: 0)
        let session = ProductionSession(
            homeProfileID: home.id,
            toolID: ToolID.productionCounter.rawValue,
            name: "Production"
        )
        context.insert(home)
        context.insert(session)
        context.insert(ToolCard(
            homeProfileID: home.id,
            toolID: .productionCounter,
            sortOrder: 0,
            productionSessionID: session.id
        ))
        try context.save()

        let processor = WatchCommandProcessor(modelContext: context)
        let command = CounterCommand(sessionID: session.id, operation: .increment)

        XCTAssertEqual(try processor.catalog(isPro: false).sessions.count, 1)
        XCTAssertEqual(try processor.peerCatalog(isPro: false).sessions.count, 1)
        XCTAssertEqual(try processor.process(command, isPro: false).acknowledgement.status, .applied)
        let peerCommand = CounterCommand(sessionID: session.id, operation: .increment)
        XCTAssertEqual(
            try processor.process(peerCommand, allowNonWatchSessions: true, isPro: false).acknowledgement.status,
            .applied
        )
        XCTAssertEqual(session.currentCount, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CountEvent>()).count, 2)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CounterCommandReceipt>()).isEmpty)
    }

    func testCounterCommandPayloadSignatureIsCanonicalAndRejectsMalformedValues() {
        let eventID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let command = CounterCommand(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
            operation: .undo(eventID: eventID),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertTrue(CounterCommand.isWellFormedPayloadSignature(command.payloadSignature))
        XCTAssertFalse(CounterCommand.isWellFormedPayloadSignature(""))
        XCTAssertFalse(CounterCommand.isWellFormedPayloadSignature("schema=1|operation=undo:not-a-uuid|date=1"))
        XCTAssertFalse(CounterCommand.isWellFormedPayloadSignature("schema=1|operation=increment|date=not-hex"))
        XCTAssertFalse(CounterCommand.isWellFormedPayloadSignature("schema=1|operation=increment|date=1|extra=value"))
        XCTAssertFalse(CounterCommand.isWellFormedPayloadSignature(
            "schema=1|operation=\(String(repeating: "a", count: 500))|date=1"
        ))
        XCTAssertTrue(CounterCommand.isWellFormedPayloadSignature("schema=2|operation=vendor.operation|date=3ff0000000000000"))
    }

    func testCounterServiceRejectsIDPresentInBothEventAndReceipt() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(name: "Conflicting records", currentCount: 1, nextEventSequence: 1)
        let commandID = UUID()
        let command = CounterCommand(
            id: commandID,
            sessionID: session.id,
            operation: .increment,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        context.insert(session)
        context.insert(CountEvent(
            id: commandID,
            sessionID: session.id,
            delta: 1,
            sequence: 0,
            occurredAt: command.createdAt,
            kind: .increment,
            payloadSignature: command.payloadSignature
        ))
        context.insert(CounterCommandReceipt(
            id: commandID,
            sessionID: session.id,
            payloadSignature: command.payloadSignature
        ))
        try context.save()

        XCTAssertThrowsError(try CounterService(modelContext: context).apply(command, to: session)) { error in
            XCTAssertEqual(error as? CounterServiceError, .commandIdentifierConflict)
        }
    }

    func testBackupRejectsMalformedCommandSignaturesAndCrossTypeIDReuse() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Signature validation", sortOrder: 0)
        let session = ProductionSession(
            homeProfileID: home.id,
            name: "Counter",
            currentCount: 1,
            nextEventSequence: 1
        )
        let eventCommand = CounterCommand(
            sessionID: session.id,
            operation: .increment,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let noChangeCommand = CounterCommand(
            sessionID: session.id,
            operation: .quickAdd(0),
            createdAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        context.insert(home)
        context.insert(session)
        context.insert(CountEvent(
            id: eventCommand.id,
            sessionID: session.id,
            delta: 1,
            sequence: 0,
            occurredAt: eventCommand.createdAt,
            kind: .increment,
            payloadSignature: eventCommand.payloadSignature
        ))
        context.insert(CounterCommandReceipt(
            id: noChangeCommand.id,
            sessionID: session.id,
            processedAt: noChangeCommand.createdAt,
            payloadSignature: noChangeCommand.payloadSignature
        ))
        context.insert(AppSettings(selectedHomeProfileID: home.id))
        try context.save()

        let validData = try FactoryToolsBackupService(modelContext: context).makeJSON()
        var malformed = try XCTUnwrap(JSONSerialization.jsonObject(with: validData) as? [String: Any])
        var malformedEvents = try XCTUnwrap(malformed["events"] as? [[String: Any]])
        malformedEvents[0]["payloadSignature"] = "schema=1|operation=increment|date=invalid"
        malformed["events"] = malformedEvents
        let malformedData = try JSONSerialization.data(withJSONObject: malformed)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(malformedData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidStoredValue)
        }

        var mismatchedPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: validData) as? [String: Any])
        var mismatchedEvents = try XCTUnwrap(mismatchedPayload["events"] as? [[String: Any]])
        mismatchedEvents[0]["delta"] = 2
        mismatchedPayload["events"] = mismatchedEvents
        var mismatchedSessions = try XCTUnwrap(mismatchedPayload["sessions"] as? [[String: Any]])
        mismatchedSessions[0]["currentCount"] = 2
        mismatchedSessions[0]["nextEventSequence"] = 1
        mismatchedPayload["sessions"] = mismatchedSessions
        let mismatchedData = try JSONSerialization.data(withJSONObject: mismatchedPayload)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(mismatchedData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .invalidStoredValue)
        }

        var reusedID = try XCTUnwrap(JSONSerialization.jsonObject(with: validData) as? [String: Any])
        var receipts = try XCTUnwrap(reusedID["commandReceipts"] as? [[String: Any]])
        receipts[0]["id"] = eventCommand.id.uuidString
        reusedID["commandReceipts"] = receipts
        let reusedIDData = try JSONSerialization.data(withJSONObject: reusedID)
        XCTAssertThrowsError(try FactoryToolsBackupService.decodeAndValidate(reusedIDData)) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .duplicateIdentifier)
        }
    }

    func testCounterCommandRejectsSessionMismatchAndIdentifierCollision() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let first = ProductionSession(name: "First")
        let second = ProductionSession(name: "Second")
        context.insert(first)
        context.insert(second)
        let service = CounterService(modelContext: context)
        let commandID = UUID()
        let firstCommand = CounterCommand(id: commandID, sessionID: first.id, operation: .increment)

        XCTAssertThrowsError(try service.apply(firstCommand, to: second)) { error in
            XCTAssertEqual(error as? CounterServiceError, .sessionMismatch)
        }
        XCTAssertEqual(try service.apply(firstCommand, to: first), .applied)
        XCTAssertEqual(try service.apply(firstCommand, to: first), .alreadyApplied)

        let reusedEventID = CounterCommand(id: commandID, sessionID: first.id, operation: .decrement)
        XCTAssertThrowsError(try service.apply(reusedEventID, to: first)) { error in
            XCTAssertEqual(error as? CounterServiceError, .commandIdentifierConflict)
        }

        let conflictingCommand = CounterCommand(id: commandID, sessionID: second.id, operation: .increment)
        XCTAssertThrowsError(try service.apply(conflictingCommand, to: second)) { error in
            XCTAssertEqual(error as? CounterServiceError, .commandIdentifierConflict)
        }

        let noOpCommand = CounterCommand(id: UUID(), sessionID: first.id, operation: .quickAdd(0))
        XCTAssertEqual(try service.apply(noOpCommand, to: first), .noChange)
        XCTAssertEqual(try service.apply(noOpCommand, to: first), .alreadyApplied)
        let reusedReceiptID = CounterCommand(id: noOpCommand.id, sessionID: first.id, operation: .quickAdd(1))
        XCTAssertThrowsError(try service.apply(reusedReceiptID, to: first)) { error in
            XCTAssertEqual(error as? CounterServiceError, .commandIdentifierConflict)
        }
        XCTAssertEqual(first.currentCount, 1)
        XCTAssertEqual(second.currentCount, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CountEvent>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CounterCommandReceipt>()).count, 1)
    }

    func testLegacyCounterRecordsWithoutSignaturesRetainReplayCompatibility() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let eventSession = ProductionSession(name: "Legacy event", currentCount: 1, nextEventSequence: 1)
        let eventID = UUID()
        let legacyEvent = CountEvent(
            id: eventID,
            sessionID: eventSession.id,
            delta: 1,
            sequence: 0,
            occurredAt: Date(timeIntervalSince1970: 10),
            kind: .increment
        )
        let receiptSession = ProductionSession(name: "Legacy receipt")
        let receiptID = UUID()
        let legacyReceipt = CounterCommandReceipt(
            id: receiptID,
            sessionID: receiptSession.id,
            processedAt: Date(timeIntervalSince1970: 11)
        )
        context.insert(eventSession)
        context.insert(legacyEvent)
        context.insert(receiptSession)
        context.insert(legacyReceipt)
        try context.save()

        let service = CounterService(modelContext: context)
        XCTAssertEqual(
            try service.apply(
                CounterCommand(id: eventID, sessionID: eventSession.id, operation: .decrement),
                to: eventSession
            ),
            .alreadyApplied
        )
        XCTAssertEqual(
            try service.apply(
                CounterCommand(id: receiptID, sessionID: receiptSession.id, operation: .increment),
                to: receiptSession
            ),
            .alreadyApplied
        )
        XCTAssertEqual(eventSession.currentCount, 1)
        XCTAssertEqual(receiptSession.currentCount, 0)
    }

    func testCounterCommandIgnoresUndoTargetThatIsNoLongerLatest() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(name: "Undo conflict", currentCount: 2, nextEventSequence: 2)
        let older = CountEvent(sessionID: session.id, delta: 1, sequence: 0, occurredAt: Date(timeIntervalSince1970: 1))
        let latest = CountEvent(sessionID: session.id, delta: 1, sequence: 1, occurredAt: Date(timeIntervalSince1970: 2))
        context.insert(session)
        context.insert(older)
        context.insert(latest)
        try context.save()

        let service = CounterService(modelContext: context)
        let staleUndo = CounterCommand(sessionID: session.id, operation: .undo(eventID: older.id))
        XCTAssertEqual(try service.apply(staleUndo, to: session), .noChange)
        XCTAssertEqual(session.currentCount, 2)
        XCTAssertEqual(session.nextEventSequence, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CountEvent>()).count, 2)

        let currentUndo = CounterCommand(sessionID: session.id, operation: .undo(eventID: latest.id))
        XCTAssertEqual(try service.apply(currentUndo, to: session), .applied)
        XCTAssertEqual(session.currentCount, 1)
        let savedUndo = try XCTUnwrap(context.fetch(FetchDescriptor<CountEvent>()).first { $0.id == currentUndo.id })
        XCTAssertEqual(savedUndo.reversesEventID, latest.id)
        XCTAssertEqual(try service.apply(staleUndo, to: session), .alreadyApplied)
        XCTAssertEqual(session.currentCount, 1)
    }

    func testNoChangeCommandReceiptPreventsReplayAfterCounterStateChanges() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(name: "No-change receipt")
        context.insert(session)
        let service = CounterService(modelContext: context)
        let decrement = CounterCommand(sessionID: session.id, operation: .decrement)

        XCTAssertEqual(try service.apply(decrement, to: session), .noChange)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CounterCommandReceipt>()).map(\.id), [decrement.id])

        let increment = CounterCommand(sessionID: session.id, operation: .increment)
        XCTAssertEqual(try service.apply(increment, to: session), .applied)
        XCTAssertEqual(session.currentCount, 1)
        XCTAssertEqual(try service.apply(decrement, to: session), .alreadyApplied)
        let changedDecrement = CounterCommand(id: decrement.id, sessionID: session.id, operation: .quickAdd(0))
        XCTAssertThrowsError(try service.apply(changedDecrement, to: session)) { error in
            XCTAssertEqual(error as? CounterServiceError, .commandIdentifierConflict)
        }

        XCTAssertEqual(session.currentCount, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CountEvent>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CounterCommandReceipt>()).count, 1)
    }

    func testNoChangeCommandReceiptPreventsReplayAfterStoreReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("CounterReceipt.store")
        let schema = Schema([ProductionSession.self, CountEvent.self, CounterCommandReceipt.self])
        let configuration = ModelConfiguration(
            "CounterReceiptPersistence",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let sessionID: UUID
        let commandID = UUID()
        let incrementCommandID = UUID()
        let commandCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let incrementCreatedAt = Date(timeIntervalSince1970: 1_700_000_001)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let session = ProductionSession(name: "Persistent receipt")
            sessionID = session.id
            context.insert(session)
            try context.save()

            let command = CounterCommand(id: commandID, sessionID: session.id, operation: .decrement, createdAt: commandCreatedAt)
            let increment = CounterCommand(id: incrementCommandID, sessionID: session.id, operation: .increment, createdAt: incrementCreatedAt)
            XCTAssertEqual(try CounterService(modelContext: context).apply(command, to: session), .noChange)
            XCTAssertEqual(try CounterService(modelContext: context).apply(increment, to: session), .applied)
            XCTAssertEqual(session.currentCount, 1)
        }

        do {
            let reopened = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(reopened)
            let session = try XCTUnwrap(context.fetch(FetchDescriptor<ProductionSession>()).first)
            let replay = CounterCommand(id: commandID, sessionID: sessionID, operation: .decrement, createdAt: commandCreatedAt)

            XCTAssertEqual(try CounterService(modelContext: context).apply(replay, to: session), .alreadyApplied)
            let alteredReplay = CounterCommand(id: commandID, sessionID: sessionID, operation: .quickAdd(0), createdAt: commandCreatedAt)
            XCTAssertThrowsError(try CounterService(modelContext: context).apply(alteredReplay, to: session)) { error in
                XCTAssertEqual(error as? CounterServiceError, .commandIdentifierConflict)
            }
            let incrementReplay = CounterCommand(id: incrementCommandID, sessionID: sessionID, operation: .increment, createdAt: incrementCreatedAt)
            XCTAssertEqual(try CounterService(modelContext: context).apply(incrementReplay, to: session), .alreadyApplied)
            let alteredIncrementReplay = CounterCommand(
                id: incrementCommandID,
                sessionID: sessionID,
                operation: .decrement,
                createdAt: incrementCreatedAt
            )
            XCTAssertThrowsError(try CounterService(modelContext: context).apply(alteredIncrementReplay, to: session)) { error in
                XCTAssertEqual(error as? CounterServiceError, .commandIdentifierConflict)
            }
            XCTAssertEqual(session.currentCount, 1)
            XCTAssertEqual(try context.fetch(FetchDescriptor<CountEvent>()).count, 1)
            XCTAssertEqual(try context.fetch(FetchDescriptor<CounterCommandReceipt>()).map(\.id), [commandID])
        }
    }

    func testPersistentStoreAddsHistoryAndReceiptModelsWithoutLosingExistingCounterData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("SchemaUpgrade.store")
        let previousSchema = Schema([
            HomeProfile.self,
            ToolCard.self,
            ProductionSession.self,
            CountEvent.self,
            AppSettings.self
        ])
        let previousConfiguration = ModelConfiguration(
            "SchemaUpgrade",
            schema: previousSchema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let currentSchema = Schema([
            HomeProfile.self,
            ToolCard.self,
            ProductionSession.self,
            CountEvent.self,
            AppSettings.self,
            CycleTimeSample.self,
            OEERun.self,
            CounterCommandReceipt.self
        ])
        let currentConfiguration = ModelConfiguration(
            "SchemaUpgrade",
            schema: currentSchema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let homeID: UUID
        let cardID: UUID
        let sessionID: UUID
        let eventID: UUID

        do {
            let previousContainer = try ModelContainer(for: previousSchema, configurations: [previousConfiguration])
            let context = ModelContext(previousContainer)
            let home = HomeProfile(name: "Existing home", sortOrder: 0)
            let session = ProductionSession(
                homeProfileID: home.id,
                name: "Existing counter",
                currentCount: 6,
                targetCount: 20,
                nextEventSequence: 1
            )
            let card = ToolCard(
                homeProfileID: home.id,
                toolID: .productionCounter,
                size: .large,
                sortOrder: 0,
                productionSessionID: session.id
            )
            let event = CountEvent(sessionID: session.id, delta: 6, sequence: 0)
            context.insert(home)
            context.insert(card)
            context.insert(session)
            context.insert(event)
            context.insert(AppSettings(selectedHomeProfileID: home.id))
            try context.save()
            homeID = home.id
            cardID = card.id
            sessionID = session.id
            eventID = event.id
        }

        do {
            let currentContainer = try ModelContainer(for: currentSchema, configurations: [currentConfiguration])
            let context = ModelContext(currentContainer)
            let home = try XCTUnwrap(context.fetch(FetchDescriptor<HomeProfile>()).first)
            let card = try XCTUnwrap(context.fetch(FetchDescriptor<ToolCard>()).first)
            let session = try XCTUnwrap(context.fetch(FetchDescriptor<ProductionSession>()).first)
            let event = try XCTUnwrap(context.fetch(FetchDescriptor<CountEvent>()).first)
            let settings = try XCTUnwrap(context.fetch(FetchDescriptor<AppSettings>()).first)

            XCTAssertEqual(home.id, homeID)
            XCTAssertEqual(home.name, "Existing home")
            XCTAssertEqual(card.id, cardID)
            XCTAssertEqual(card.homeProfileID, homeID)
            XCTAssertEqual(card.productionSessionID, sessionID)
            XCTAssertEqual(session.id, sessionID)
            XCTAssertEqual(session.currentCount, 6)
            XCTAssertEqual(session.targetCount, 20)
            XCTAssertEqual(event.id, eventID)
            XCTAssertEqual(settings.selectedHomeProfileID, homeID)
            XCTAssertEqual(try context.fetch(FetchDescriptor<CounterCommandReceipt>()).count, 0)
            XCTAssertTrue(try context.fetch(FetchDescriptor<CycleTimeSample>()).isEmpty)
            XCTAssertTrue(try context.fetch(FetchDescriptor<OEERun>()).isEmpty)

            try CounterService(modelContext: context).quickAdd(0, to: session)
            XCTAssertEqual(try context.fetch(FetchDescriptor<CounterCommandReceipt>()).count, 1)
            XCTAssertEqual(session.currentCount, 6)

            try CycleTimeSampleService(modelContext: context).save(totalSeconds: 60, quantity: 2, for: homeID)
            try OEERunService(modelContext: context).save(
                plannedProductionMinutes: 60,
                downtimeMinutes: 5,
                idealCycleTimeSeconds: 10,
                goodUnits: 300,
                defectiveUnits: 10,
                for: homeID,
                isPro: true
            )
            XCTAssertEqual(try context.fetch(FetchDescriptor<CycleTimeSample>()).count, 1)
            XCTAssertEqual(try context.fetch(FetchDescriptor<OEERun>()).count, 1)
        }

        let reopened = try ModelContainer(for: currentSchema, configurations: [currentConfiguration])
        let reopenedContext = ModelContext(reopened)
        XCTAssertEqual(try reopenedContext.fetch(FetchDescriptor<HomeProfile>()).map(\.id), [homeID])
        XCTAssertEqual(try reopenedContext.fetch(FetchDescriptor<ProductionSession>()).first?.currentCount, 6)
        XCTAssertEqual(try reopenedContext.fetch(FetchDescriptor<CountEvent>()).map(\.id), [eventID])
        XCTAssertEqual(try reopenedContext.fetch(FetchDescriptor<CycleTimeSample>()).count, 1)
        XCTAssertEqual(try reopenedContext.fetch(FetchDescriptor<OEERun>()).count, 1)
        XCTAssertEqual(try reopenedContext.fetch(FetchDescriptor<CounterCommandReceipt>()).count, 1)
    }

    func testHistoryOrderingUsesSequenceTimestampAndStableID() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let lowerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let higherID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let older = CountEvent(id: higherID, sessionID: UUID(), delta: 1, sequence: 2, occurredAt: timestamp)
        let tiedHigherID = CountEvent(id: higherID, sessionID: UUID(), delta: 1, sequence: 3, occurredAt: timestamp)
        let tiedLowerID = CountEvent(id: lowerID, sessionID: UUID(), delta: 1, sequence: 3, occurredAt: timestamp)
        let newer = CountEvent(
            id: lowerID,
            sessionID: UUID(),
            delta: 1,
            sequence: 2,
            occurredAt: timestamp.addingTimeInterval(1)
        )

        let ordered = CounterHistoryOrdering.ordered([older, tiedLowerID, newer, tiedHigherID])

        XCTAssertEqual(ordered.map(\.id), [higherID, lowerID, lowerID, higherID])
        XCTAssertEqual(ordered.map(\.sequence), [3, 3, 2, 2])
        XCTAssertEqual(ordered.map(\.occurredAt), [timestamp, timestamp, timestamp.addingTimeInterval(1), timestamp])
    }

    func testLatestUndoableEventMatchesCounterUndoOrder() throws {
        let sessionID = UUID()
        let first = CountEvent(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000031")),
            sessionID: sessionID,
            delta: 1,
            sequence: 0
        )
        let second = CountEvent(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000032")),
            sessionID: sessionID,
            delta: 1,
            sequence: 1
        )
        let undo = CountEvent(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000033")),
            sessionID: sessionID,
            delta: -1,
            sequence: 2,
            reversesEventID: second.id,
            kind: .undo
        )

        XCTAssertNil(CounterHistoryOrdering.latestUndoableEvent(in: []))
        XCTAssertEqual(CounterHistoryOrdering.latestUndoableEvent(in: [first, second])?.id, second.id)
        XCTAssertEqual(CounterHistoryOrdering.latestUndoableEvent(in: [first, second, undo])?.id, first.id)
    }

    func testHistoryCSVUsesStableColumnsAndChronologicalRows() {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let undoID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        let first = CountEvent(
            id: firstID,
            sessionID: sessionID,
            delta: 5,
            sequence: 0,
            occurredAt: Date(timeIntervalSince1970: 1_000),
            kind: .quickAdd
        )
        let undo = CountEvent(
            id: undoID,
            sessionID: sessionID,
            delta: -5,
            sequence: 1,
            occurredAt: Date(timeIntervalSince1970: 1_001),
            reversesEventID: firstID,
            kind: .undo
        )

        let csv = CounterHistoryCSV.make(sessionID: sessionID, currentCount: 0, events: [undo, first])
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines[0], "session_id,event_id,sequence,timestamp_utc,kind,delta,count_after,reverses_event_id")
        XCTAssertEqual(lines[1], "\(sessionID.uuidString),\(firstID.uuidString),0,1970-01-01T00:16:40.000Z,quickAdd,5,5,")
        XCTAssertEqual(lines[2], "\(sessionID.uuidString),\(undoID.uuidString),1,1970-01-01T00:16:41.000Z,undo,-5,0,\(firstID.uuidString)")
    }

    func testHistoryCSVValueSnapshotMatchesModelCSVOutput() {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let first = CountEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            sessionID: sessionID,
            delta: 7,
            sequence: 0,
            occurredAt: Date(timeIntervalSince1970: 1_000),
            kind: .quickAdd
        )
        let second = CountEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            sessionID: sessionID,
            delta: -2,
            sequence: 1,
            occurredAt: Date(timeIntervalSince1970: 1_001),
            reversesEventID: first.id,
            kind: .undo
        )
        let events = [second, first]

        XCTAssertEqual(
            CounterHistoryCSV.make(sessionID: sessionID, currentCount: 5, records: events.map(CounterHistoryCSVRecord.init)),
            CounterHistoryCSV.make(sessionID: sessionID, currentCount: 5, events: events)
        )
    }

    func testHistoryCSVPreservesAndEscapesUnknownEventKind() {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let event = CountEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            sessionID: sessionID,
            delta: 1,
            sequence: 0,
            occurredAt: Date(timeIntervalSince1970: 1_000),
            kind: .increment
        )
        event.kindRawValue = "future,\"action\"\ncontinued"

        let csv = CounterHistoryCSV.make(sessionID: sessionID, currentCount: 1, events: [event])
        XCTAssertTrue(csv.contains("\"future,\"\"action\"\"\ncontinued\""))
        XCTAssertTrue(csv.contains(",1,1,\r\n"))

        event.kindRawValue = "=1+1"
        let spreadsheetSafeCSV = CounterHistoryCSV.make(sessionID: sessionID, currentCount: 1, events: [event])
        XCTAssertTrue(spreadsheetSafeCSV.contains(",'=1+1,1,1,\r\n"))
    }

    func testHistoryCSVExcludesEventsFromOtherSessions() {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let unrelated = CountEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
            delta: 99,
            sequence: 0,
            kind: .quickAdd
        )
        let own = CountEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            sessionID: sessionID,
            delta: 4,
            sequence: 0,
            kind: .increment
        )

        let csv = CounterHistoryCSV.make(sessionID: sessionID, currentCount: 4, events: [unrelated, own])
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains(own.id.uuidString))
        XCTAssertFalse(csv.contains(unrelated.id.uuidString))
        XCTAssertFalse(csv.contains(",99,"))
    }

    func testHistoryBalancesReconstructEachEventAndRejectOverflow() {
        let sessionID = UUID()
        let first = CountEvent(sessionID: sessionID, delta: 5, sequence: 0)
        let reset = CountEvent(sessionID: sessionID, delta: -5, sequence: 1)
        let restored = CountEvent(sessionID: sessionID, delta: 5, sequence: 2)

        let orderedEvents = CounterHistoryOrdering.ordered([first, reset, restored])
        let balances = CounterHistoryBalances.afterEachEvent(
            orderedEvents: orderedEvents,
            currentCount: 5
        )

        XCTAssertEqual(balances?[first.id], 5)
        XCTAssertEqual(balances?[reset.id], 0)
        XCTAssertEqual(balances?[restored.id], 5)

        let minimumDelta = CountEvent(sessionID: sessionID, delta: Int.min, sequence: 0)
        XCTAssertNil(CounterHistoryBalances.afterEachEvent(events: [minimumDelta], currentCount: 0))

        let impossibleIncrement = CountEvent(sessionID: sessionID, delta: 1, sequence: 0)
        XCTAssertNil(CounterHistoryBalances.afterEachEvent(events: [impossibleIncrement], currentCount: 0))
        XCTAssertNil(CounterHistoryBalances.afterEachEvent(events: [], currentCount: -1))
    }

    func testResetAppendsZeroingEventAndUndoRestoresPreviousCount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(name: "Test")
        context.insert(session)
        let service = CounterService(modelContext: context)
        try service.quickAdd(7, to: session)

        try service.reset(session: session)

        XCTAssertEqual(session.currentCount, 0)
        XCTAssertEqual(session.nextEventSequence, 2)
        let afterReset = try context.fetch(FetchDescriptor<CountEvent>()).sorted { $0.sequence < $1.sequence }
        XCTAssertEqual(afterReset.map(\.delta), [7, -7])
        XCTAssertEqual(afterReset.map(\.kind), [.quickAdd, .reset])
        XCTAssertEqual(afterReset.reduce(0) { $0 + $1.delta }, session.currentCount)

        try service.undo(session: session)

        let afterUndo = try context.fetch(FetchDescriptor<CountEvent>()).sorted { $0.sequence < $1.sequence }
        XCTAssertEqual(session.currentCount, 7)
        XCTAssertEqual(session.nextEventSequence, 3)
        XCTAssertEqual(afterUndo.map(\.delta), [7, -7, 7])
        let resetEvent = try XCTUnwrap(afterUndo.first { $0.sequence == 1 })
        XCTAssertEqual(afterUndo.last?.reversesEventID, resetEvent.id)
        XCTAssertEqual(afterUndo.last?.kind, .undo)
        XCTAssertEqual(afterUndo.reduce(0) { $0 + $1.delta }, session.currentCount)
    }

    func testResetAtZeroDoesNotWriteAnEvent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(name: "Test")
        context.insert(session)

        try CounterService(modelContext: context).reset(session: session)

        XCTAssertEqual(session.currentCount, 0)
        XCTAssertEqual(session.nextEventSequence, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CountEvent>()).isEmpty)
    }

    func testUndoReversesDecrementByAddingOne() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(name: "Test", currentCount: 2, nextEventSequence: 2)
        let increment = CountEvent(sessionID: session.id, delta: 3, sequence: 0)
        let decrement = CountEvent(sessionID: session.id, delta: -1, sequence: 1)
        context.insert(session)
        context.insert(increment)
        context.insert(decrement)
        try context.save()

        try CounterService(modelContext: context).undo(session: session)

        let events = try context.fetch(FetchDescriptor<CountEvent>()).sorted { $0.sequence < $1.sequence }
        XCTAssertEqual(session.currentCount, 3)
        XCTAssertEqual(session.nextEventSequence, 3)
        XCTAssertEqual(events.map(\.delta), [3, -1, 1])
        XCTAssertEqual(events.last?.reversesEventID, decrement.id)
        XCTAssertEqual(events.reduce(0) { $0 + $1.delta }, session.currentCount)
    }

    func testUndoRejectsMinimumIntegerDeltaWithoutOverflowOrMutation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(name: "Test", nextEventSequence: 1)
        let invalidEvent = CountEvent(sessionID: session.id, delta: Int.min, sequence: 0)
        context.insert(session)
        context.insert(invalidEvent)
        try context.save()

        XCTAssertThrowsError(try CounterService(modelContext: context).undo(session: session)) { error in
            XCTAssertEqual(error as? CounterServiceError, .eventDeltaCannotBeReversed)
        }

        XCTAssertEqual(session.currentCount, 0)
        XCTAssertEqual(session.nextEventSequence, 1)
        let events = try context.fetch(FetchDescriptor<CountEvent>())
        XCTAssertEqual(events.map(\.id), [invalidEvent.id])
        XCTAssertEqual(events.map(\.delta), [Int.min])
    }

    func testUndoOnlyReadsEventsFromTheSelectedSession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let selectedSession = ProductionSession(name: "Selected", currentCount: 5, nextEventSequence: 1)
        let otherSession = ProductionSession(name: "Other", currentCount: 9, nextEventSequence: 1)
        let selectedEvent = CountEvent(sessionID: selectedSession.id, delta: 5, sequence: 0)
        let otherEvent = CountEvent(sessionID: otherSession.id, delta: 9, sequence: 0)
        context.insert(selectedSession)
        context.insert(otherSession)
        context.insert(selectedEvent)
        context.insert(otherEvent)
        try context.save()

        try CounterService(modelContext: context).undo(session: selectedSession)

        XCTAssertEqual(selectedSession.currentCount, 0)
        XCTAssertEqual(otherSession.currentCount, 9)
        XCTAssertEqual(otherSession.nextEventSequence, 1)
        let events = try context.fetch(FetchDescriptor<CountEvent>())
        XCTAssertEqual(events.count, 3)
        XCTAssertTrue(events.contains { $0.id == otherEvent.id && $0.reversesEventID == nil })
        XCTAssertTrue(events.contains { $0.reversesEventID == selectedEvent.id && $0.sessionID == selectedSession.id })
        XCTAssertEqual(events.filter { $0.sessionID == otherSession.id }.map(\.delta), [9])
    }

    func testRepeatedUndoMovesBackwardWithoutReversingPreviousUndo() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(name: "Test")
        context.insert(session)
        let service = CounterService(modelContext: context)

        try service.quickAdd(10, to: session)
        try service.increment(session: session)
        try service.undo(session: session)
        XCTAssertEqual(session.currentCount, 10)

        try service.undo(session: session)

        XCTAssertEqual(session.currentCount, 0)
        XCTAssertEqual(session.nextEventSequence, 4)
        let events = try context.fetch(FetchDescriptor<CountEvent>())
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.reduce(0) { $0 + $1.delta }, session.currentCount)
        XCTAssertEqual(Set(events.compactMap(\.reversesEventID)).count, 2)
    }

    func testUndoBreaksDuplicateSequenceTiesByTimestampAndStableID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(name: "Test", currentCount: 3, nextEventSequence: 3)
        let earlierID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let laterID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let earlier = CountEvent(
            id: earlierID,
            sessionID: session.id,
            delta: 1,
            sequence: 0,
            occurredAt: Date(timeIntervalSince1970: 1)
        )
        let later = CountEvent(
            id: laterID,
            sessionID: session.id,
            delta: 2,
            sequence: 0,
            occurredAt: Date(timeIntervalSince1970: 2)
        )
        context.insert(session)
        context.insert(earlier)
        context.insert(later)
        try context.save()

        try CounterService(modelContext: context).undo(session: session)

        let undoEvent = try XCTUnwrap(
            context.fetch(FetchDescriptor<CountEvent>()).first { $0.reversesEventID != nil }
        )
        XCTAssertEqual(undoEvent.reversesEventID, later.id)
        XCTAssertEqual(undoEvent.delta, -2)
        XCTAssertEqual(session.currentCount, 1)
        XCTAssertEqual(session.nextEventSequence, 4)
    }

    func testUndoBreaksEqualTimestampTiesByStableEventID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(name: "Test", currentCount: 2, nextEventSequence: 2)
        let lowerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let higherID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let sameTime = Date(timeIntervalSince1970: 1)
        let lower = CountEvent(id: lowerID, sessionID: session.id, delta: 1, sequence: 0, occurredAt: sameTime)
        let higher = CountEvent(id: higherID, sessionID: session.id, delta: 1, sequence: 0, occurredAt: sameTime)
        context.insert(session)
        context.insert(lower)
        context.insert(higher)
        try context.save()

        try CounterService(modelContext: context).undo(session: session)

        let undoEvent = try XCTUnwrap(
            context.fetch(FetchDescriptor<CountEvent>()).first { $0.reversesEventID != nil }
        )
        XCTAssertEqual(undoEvent.reversesEventID, higher.id)
        XCTAssertEqual(session.currentCount, 1)
    }

    func testDecrementCannotMakeCountNegative() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(name: "Test")
        context.insert(session)

        try CounterService(modelContext: context).decrement(session: session)

        XCTAssertEqual(session.currentCount, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CountEvent>()).isEmpty)
    }

    func testQuickAddIgnoresNonpositiveAmountsAndEmptyUndo() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(name: "Test")
        context.insert(session)
        let service = CounterService(modelContext: context)

        try service.quickAdd(0, to: session)
        try service.quickAdd(-3, to: session)
        try service.undo(session: session)

        XCTAssertEqual(session.currentCount, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CountEvent>()).isEmpty)
    }

    func testFailedCountSaveRestoresAggregateEventAndSequence() throws {
        let session = ProductionSession(name: "Test")
        let container = try makeContainer(allowsSave: false) { $0.insert(session) }
        let context = ModelContext(container)
        let storedSession = try XCTUnwrap(context.fetch(FetchDescriptor<ProductionSession>()).first)

        XCTAssertThrowsError(try CounterService(modelContext: context).increment(session: storedSession))

        XCTAssertEqual(storedSession.currentCount, 0)
        XCTAssertEqual(storedSession.nextEventSequence, 0)
        let verificationContext = ModelContext(container)
        XCTAssertTrue(try verificationContext.fetch(FetchDescriptor<CountEvent>()).isEmpty)
    }

    func testCounterSaveFailuresPreserveFileBackedCountAndCommandHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("FactoryTools.store")
        let schema = Schema([HomeProfile.self, ProductionSession.self, CountEvent.self, CounterCommandReceipt.self, AppSettings.self])
        let writableConfiguration = ModelConfiguration(
            "CounterRollback",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let homeID = UUID()
        let sessionID = UUID()
        let eventID = UUID()
        let settingsID = UUID()
        do {
            let container = try ModelContainer(for: schema, configurations: [writableConfiguration])
            let context = ModelContext(container)
            context.insert(HomeProfile(id: homeID, name: "Assembly", sortOrder: 0))
            context.insert(ProductionSession(
                id: sessionID,
                homeProfileID: homeID,
                toolID: ToolID.productionCounter.rawValue,
                name: "Existing count",
                currentCount: 2,
                targetCount: 20,
                nextEventSequence: 1
            ))
            context.insert(CountEvent(id: eventID, sessionID: sessionID, delta: 2, sequence: 0, kind: .quickAdd))
            context.insert(AppSettings(id: settingsID, language: AppLanguage.japanese.rawValue, selectedHomeProfileID: homeID))
            try context.save()
        }

        let readOnlyConfiguration = ModelConfiguration(
            "CounterRollback",
            schema: schema,
            url: storeURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        let readOnlyContainer = try ModelContainer(for: schema, configurations: [readOnlyConfiguration])
        let context = ModelContext(readOnlyContainer)
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<ProductionSession>()).first)
        let counter = CounterService(modelContext: context)
        XCTAssertThrowsError(try counter.increment(session: session))
        XCTAssertThrowsError(try counter.quickAdd(0, to: session))
        XCTAssertThrowsError(try counter.setTarget(30, for: session))
        let settings = try XCTUnwrap(context.fetch(FetchDescriptor<AppSettings>()).first)
        XCTAssertThrowsError(try AppSettingsService(modelContext: context).setLanguage(.english, for: settings))
        XCTAssertEqual(session.currentCount, 2)
        XCTAssertEqual(session.targetCount, 20)
        XCTAssertEqual(session.nextEventSequence, 1)
        XCTAssertEqual(settings.language, AppLanguage.japanese.rawValue)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CountEvent>()).map(\.id), [eventID])
        XCTAssertTrue(try context.fetch(FetchDescriptor<CounterCommandReceipt>()).isEmpty)

        let reopened = try ModelContainer(for: schema, configurations: [readOnlyConfiguration])
        let reopenedContext = ModelContext(reopened)
        let persistedSession = try XCTUnwrap(reopenedContext.fetch(FetchDescriptor<ProductionSession>()).first)
        XCTAssertEqual(persistedSession.currentCount, 2)
        XCTAssertEqual(persistedSession.targetCount, 20)
        XCTAssertEqual(persistedSession.nextEventSequence, 1)
        XCTAssertEqual(try reopenedContext.fetch(FetchDescriptor<AppSettings>()).first?.language, AppLanguage.japanese.rawValue)
        XCTAssertEqual(try reopenedContext.fetch(FetchDescriptor<CountEvent>()).map(\.id), [eventID])
        XCTAssertTrue(try reopenedContext.fetch(FetchDescriptor<CounterCommandReceipt>()).isEmpty)
    }

    func testFailedNoChangeSaveRemovesUncommittedCommandReceipt() throws {
        let container = try makeContainer(allowsSave: false)
        let context = ModelContext(container)
        let session = ProductionSession(name: "Failed no-op receipt")
        context.insert(session)

        XCTAssertThrowsError(try CounterService(modelContext: context).quickAdd(0, to: session))

        XCTAssertEqual(session.currentCount, 0)
        XCTAssertEqual(session.nextEventSequence, 0)
        let verificationContext = ModelContext(container)
        XCTAssertTrue(try verificationContext.fetch(FetchDescriptor<CountEvent>()).isEmpty)
        XCTAssertTrue(try verificationContext.fetch(FetchDescriptor<CounterCommandReceipt>()).isEmpty)
    }

    func testFailedResetSaveRestoresCountSequenceAndEventHistory() throws {
        let session = ProductionSession(name: "Test", currentCount: 5, nextEventSequence: 4)
        let container = try makeContainer(allowsSave: false) { $0.insert(session) }
        let context = ModelContext(container)
        let storedSession = try XCTUnwrap(context.fetch(FetchDescriptor<ProductionSession>()).first)

        XCTAssertThrowsError(try CounterService(modelContext: context).reset(session: storedSession))

        XCTAssertEqual(storedSession.currentCount, 5)
        XCTAssertEqual(storedSession.nextEventSequence, 4)
        let verificationContext = ModelContext(container)
        XCTAssertTrue(try verificationContext.fetch(FetchDescriptor<CountEvent>()).isEmpty)
    }

    func testFailedUndoSaveRestoresAggregateSequenceAndHistory() throws {
        let session = ProductionSession(name: "Test", currentCount: 5, nextEventSequence: 1)
        let originalEvent = CountEvent(sessionID: session.id, delta: 5, sequence: 0)
        let container = try makeContainer(allowsSave: false) { context in
            context.insert(session)
            context.insert(originalEvent)
        }
        let context = ModelContext(container)
        let storedSession = try XCTUnwrap(context.fetch(FetchDescriptor<ProductionSession>()).first)

        XCTAssertThrowsError(try CounterService(modelContext: context).undo(session: storedSession))

        XCTAssertEqual(storedSession.currentCount, 5)
        XCTAssertEqual(storedSession.nextEventSequence, 1)
        let verificationContext = ModelContext(container)
        let events = try verificationContext.fetch(FetchDescriptor<CountEvent>())
        XCTAssertEqual(events.map(\.id), [originalEvent.id])
        XCTAssertEqual(events.map(\.delta), [5])
    }

    func testFailedTargetSaveRestoresPreviousTarget() throws {
        let session = ProductionSession(name: "Test", targetCount: 600)
        let container = try makeContainer(allowsSave: false) { $0.insert(session) }
        let context = ModelContext(container)
        let storedSession = try XCTUnwrap(context.fetch(FetchDescriptor<ProductionSession>()).first)

        XCTAssertThrowsError(try CounterService(modelContext: context).setTarget(800, for: storedSession))

        XCTAssertEqual(storedSession.targetCount, 600)
    }

    func testQuickAddSaturatesAtIntegerMaximumWithoutOverflow() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(name: "Test", currentCount: Int.max - 2)
        context.insert(session)
        let service = CounterService(modelContext: context)

        try service.quickAdd(5, to: session)
        try service.increment(session: session)

        XCTAssertEqual(session.currentCount, Int.max)
        XCTAssertEqual(session.nextEventSequence, 1)
        let events = try context.fetch(FetchDescriptor<CountEvent>())
        XCTAssertEqual(events.map(\.delta), [2])
        XCTAssertEqual(events.reduce(0) { $0 + $1.delta }, session.currentCount - (Int.max - 2))
    }

    func testEventSequenceExhaustionLeavesCounterAndHistoryUnchanged() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(name: "Test", currentCount: 4, nextEventSequence: Int.max)
        let lastEvent = CountEvent(sessionID: session.id, delta: 4, sequence: Int.max - 1)
        context.insert(session)
        context.insert(lastEvent)
        try context.save()
        let service = CounterService(modelContext: context)

        XCTAssertThrowsError(try service.increment(session: session)) { error in
            XCTAssertEqual(error as? CounterServiceError, .eventSequenceExhausted)
        }

        XCTAssertEqual(session.currentCount, 4)
        XCTAssertEqual(session.nextEventSequence, Int.max)
        let events = try context.fetch(FetchDescriptor<CountEvent>())
        XCTAssertEqual(events.map(\.id), [lastEvent.id])
        XCTAssertEqual(events.reduce(0) { $0 + $1.delta }, session.currentCount)
    }

    func testUndoReversesOnlyTheAppliedPartOfSaturatedQuickAdd() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let startingCount = Int.max - 2
        let session = ProductionSession(name: "Test", currentCount: startingCount)
        context.insert(session)
        let service = CounterService(modelContext: context)

        try service.quickAdd(5, to: session)
        try service.undo(session: session)

        XCTAssertEqual(session.currentCount, startingCount)
        XCTAssertEqual(session.nextEventSequence, 2)
        let events = try context.fetch(FetchDescriptor<CountEvent>()).sorted { $0.sequence < $1.sequence }
        XCTAssertEqual(events.map(\.delta), [2, -2])
        XCTAssertNil(events.first?.reversesEventID)
        XCTAssertEqual(events.last?.reversesEventID, events.first?.id)
    }

    func testTargetCannotBeNegative() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = ProductionSession(name: "Test", targetCount: 10)
        context.insert(session)

        try CounterService(modelContext: context).setTarget(-1, for: session)

        XCTAssertEqual(session.targetCount, 0)
    }

    func testNewSessionStartsWithNonnegativeCountsAndSequence() {
        let session = ProductionSession(name: "Test", currentCount: -4, targetCount: -10, nextEventSequence: -8)

        XCTAssertEqual(session.currentCount, 0)
        XCTAssertEqual(session.targetCount, 0)
        XCTAssertEqual(session.nextEventSequence, 0)
    }

    func testHomeCardOrderingMovesAndNormalizesCardPositions() {
        let homeID = UUID()
        let first = ToolCard(homeProfileID: homeID, toolID: .productionCounter, sortOrder: 0)
        let second = ToolCard(homeProfileID: homeID, toolID: .productionCounter, sortOrder: 1)
        let third = ToolCard(homeProfileID: homeID, toolID: .productionCounter, sortOrder: 2)

        guard let moved = HomeCardOrdering.moving(first.id, before: third.id, in: [first, second, third]) else {
            XCTFail("Expected a reordered card list")
            return
        }

        XCTAssertEqual(moved.map(\.id), [second.id, first.id, third.id])
        HomeCardOrdering.assignSortOrders(moved)
        XCTAssertEqual(moved.map(\.sortOrder), [0, 1, 2])
        XCTAssertNil(HomeCardOrdering.moving(first.id, before: first.id, in: moved))
        XCTAssertNil(HomeCardOrdering.moving(first.id, before: second.id, in: [first, second, third]))
        XCTAssertNil(HomeCardOrdering.moving(UUID(), before: first.id, in: moved))

        guard let movedToFront = HomeCardOrdering.moving(third.id, before: first.id, in: [first, second, third]) else {
            XCTFail("Expected the last card to move to the front")
            return
        }
        XCTAssertEqual(movedToFront.map(\.id), [third.id, first.id, second.id])
    }

    func testHomeCardOrderingCompactsGapsBeforeAppending() {
        let first = ToolCard(homeProfileID: UUID(), toolID: .productionCounter, sortOrder: 0)
        let second = ToolCard(homeProfileID: first.homeProfileID, toolID: .productionCounter, sortOrder: 8)
        let ordered = [first, second]

        HomeCardOrdering.assignSortOrders(ordered)

        XCTAssertEqual(ordered.map(\.sortOrder), [0, 1])
    }

    func testHomeCardOrderingUsesStableIDWhenSortOrdersTie() throws {
        let homeID = UUID()
        let firstID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let first = ToolCard(id: firstID, homeProfileID: homeID, toolID: .productionCounter, sortOrder: 0)
        let second = ToolCard(id: secondID, homeProfileID: homeID, toolID: .productionCounter, sortOrder: 0)

        XCTAssertEqual(HomeCardOrdering.ordered([second, first]).map(\.id), [firstID, secondID])
    }

    func testHomeProfileOrderingUsesStableIDWhenSortOrdersTie() throws {
        let firstID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let first = HomeProfile(id: firstID, name: "First", sortOrder: 0)
        let second = HomeProfile(id: secondID, name: "Second", sortOrder: 0)

        XCTAssertEqual(HomeProfileOrdering.ordered([second, first]).map(\.id), [firstID, secondID])
    }

    func testCreateHomeCompactsExtremeSortOrdersWithoutChangingOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let earlier = HomeProfile(name: "Earlier", sortOrder: Int.min)
        let later = HomeProfile(name: "Later", sortOrder: Int.max)
        let settings = AppSettings(selectedHomeProfileID: later.id)
        context.insert(later)
        context.insert(settings)
        context.insert(earlier)
        try context.save()

        let created = try HomeProfileService(modelContext: context).createHome(
            named: "New",
            isPro: true
        )
        let homes = HomeProfileOrdering.ordered(try context.fetch(FetchDescriptor<HomeProfile>()))

        XCTAssertEqual(homes.map(\.name), ["Earlier", "Later", "New"])
        XCTAssertEqual(homes.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(settings.selectedHomeProfileID, created.id)
    }

    func testFactoryToolsJourneySurvivesReopenAndBackupCopy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("FactoryTools.store")
        let schema = Schema([
            HomeProfile.self, ToolCard.self, ProductionSession.self, CountEvent.self,
            AppSettings.self, CycleTimeSample.self, OEERun.self, CounterCommandReceipt.self
        ])
        let configuration = ModelConfiguration(
            "FactoryToolsJourney",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        let primaryHomeID: UUID
        let secondaryHomeID: UUID
        let primarySessionID: UUID
        let secondarySessionID: UUID
        let secondaryCardID: UUID
        let primaryCardIDs: [UUID]

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            try AppBootstrapService(modelContext: context).seedMissingRecords()
            let defaultHome = try XCTUnwrap(context.fetch(FetchDescriptor<HomeProfile>()).first)
            let settings = try XCTUnwrap(context.fetch(FetchDescriptor<AppSettings>()).first)
            XCTAssertTrue(defaultHome.usesDefaultName)
            XCTAssertEqual(settings.selectedHomeProfileID, defaultHome.id)
            XCTAssertEqual(settings.themeID, ThemeID.industrialDark.rawValue)
            try AppSettingsService(modelContext: context).setLanguage(.japanese, for: settings)
            XCTAssertEqual(AppLanguage.resolve(settings.language), .japanese)

            let homeService = HomeProfileService(modelContext: context)
            try homeService.setName("Assembly Line", for: defaultHome)
            let secondaryHome = try homeService.createHome(named: "Quality", isPro: true)
            let tool = try XCTUnwrap(ToolRegistry.definition(for: .productionCounter))
            let toolService = HomeToolService(modelContext: context)
            let secondaryCard = try toolService.add(tool, to: secondaryHome.id, locale: AppLanguage.japanese.locale)
            let firstCard = try toolService.add(tool, to: defaultHome.id, locale: AppLanguage.japanese.locale)
            let secondCard = try toolService.add(tool, to: defaultHome.id, locale: AppLanguage.japanese.locale)
            let thirdCard = try toolService.add(tool, to: defaultHome.id, locale: AppLanguage.japanese.locale)

            let cardService = HomeCardService(modelContext: context)
            try cardService.setSize(.small, for: firstCard)
            try cardService.setSize(.medium, for: secondCard)
            try cardService.setSize(.large, for: thirdCard)
            XCTAssertTrue(try cardService.move(thirdCard.id, before: firstCard.id, in: defaultHome.id))

            let sessions = try context.fetch(FetchDescriptor<ProductionSession>())
            let primarySession = try XCTUnwrap(ToolSessionAssignment.session(for: firstCard, in: sessions))
            let secondarySession = try XCTUnwrap(ToolSessionAssignment.session(for: secondaryCard, in: sessions))
            let counter = CounterService(modelContext: context)
            try counter.increment(session: primarySession)
            XCTAssertEqual(primarySession.currentCount, 1)
            try counter.quickAdd(5, to: primarySession)
            XCTAssertEqual(primarySession.currentCount, 6)
            try counter.decrement(session: primarySession)
            XCTAssertEqual(primarySession.currentCount, 5)
            try counter.undo(session: primarySession)
            XCTAssertEqual(primarySession.currentCount, 6)
            try counter.setTarget(20, for: primarySession)
            try AppSettingsService(modelContext: context).setLanguage(.english, for: settings)
            XCTAssertEqual(AppLanguage.resolve(settings.language), .english)
            try homeService.selectHome(defaultHome.id)

            primaryHomeID = defaultHome.id
            secondaryHomeID = secondaryHome.id
            primarySessionID = primarySession.id
            secondarySessionID = secondarySession.id
            secondaryCardID = secondaryCard.id
            primaryCardIDs = [thirdCard.id, firstCard.id, secondCard.id]
        }

        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let restoredContext = ModelContext(reopened)
        try AppBootstrapService(modelContext: restoredContext).seedMissingRecords()
        let homes = try restoredContext.fetch(FetchDescriptor<HomeProfile>())
        let settings = try XCTUnwrap(restoredContext.fetch(FetchDescriptor<AppSettings>()).first)
        let cards = try restoredContext.fetch(FetchDescriptor<ToolCard>())
        let sessions = try restoredContext.fetch(FetchDescriptor<ProductionSession>())
        let events = try restoredContext.fetch(FetchDescriptor<CountEvent>())

        XCTAssertEqual(homes.count, 2, "Relaunch must not seed a duplicate default home")
        XCTAssertEqual(settings.language, AppLanguage.english.rawValue)
        XCTAssertEqual(settings.selectedHomeProfileID, primaryHomeID)
        XCTAssertEqual(homes.first(where: { $0.id == primaryHomeID })?.name, "Assembly Line")
        XCTAssertEqual(homes.first(where: { $0.id == secondaryHomeID })?.name, "Quality")

        let primaryCards = HomeCardOrdering.ordered(cards.filter { $0.homeProfileID == primaryHomeID })
        XCTAssertEqual(primaryCards.map(\.id), primaryCardIDs)
        XCTAssertEqual(primaryCards.map(\.size), [.large, .small, .medium])
        XCTAssertEqual(primaryCards.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(cards.filter { $0.homeProfileID == secondaryHomeID }.map(\.id), [secondaryCardID])

        let primarySession = try XCTUnwrap(sessions.first(where: { $0.id == primarySessionID }))
        let secondarySession = try XCTUnwrap(sessions.first(where: { $0.id == secondarySessionID }))
        XCTAssertEqual(primarySession.currentCount, 6)
        XCTAssertEqual(primarySession.targetCount, 20)
        XCTAssertEqual(secondarySession.currentCount, 0)
        XCTAssertEqual(try XCTUnwrap(ToolSessionAssignment.session(for: primaryCards[0], in: sessions)).id, primarySessionID)
        XCTAssertEqual(
            events.filter { $0.sessionID == primarySessionID }.sorted { $0.sequence < $1.sequence }.map(\.kind),
            [.increment, .quickAdd, .decrement, .undo]
        )
        XCTAssertEqual(events.filter { $0.sessionID == primarySessionID }.reduce(0) { $0 + $1.delta }, primarySession.currentCount)

        let backupData = try FactoryToolsBackupService(modelContext: restoredContext).makeJSON()
        let backup = try FactoryToolsBackupService.decodeAndValidate(backupData)
        let recordCount = backup.homes.count + backup.cards.count + backup.sessions.count + backup.events.count
            + backup.commandReceipts.count + backup.cycleTimeSamples.count + backup.oeeRuns.count + backup.settings.count
        XCTAssertNoThrow(try FactoryToolsBackupService.validateBackupRecordLimitAndCounterHistory(
            backup,
            maximumRecordCount: recordCount
        ))
        XCTAssertThrowsError(try FactoryToolsBackupService.validateBackupRecordLimitAndCounterHistory(
            backup,
            maximumRecordCount: recordCount - 1
        )) { error in
            XCTAssertEqual(error as? FactoryToolsBackupError, .backupTooLarge)
        }
        let importContainer = try makeContainer()
        let importContext = ModelContext(importContainer)
        let importResult = try FactoryToolsBackupImportService(modelContext: importContext).addCopy(
            from: backup,
            importedHomeSuffix: " (Imported)",
            defaultHomeName: "Production",
            isPro: true
        )
        XCTAssertEqual(importResult.homes, 2)
        XCTAssertEqual(importResult.cards, 4)
        XCTAssertEqual(importResult.sessions, 2)
        XCTAssertEqual(importResult.events, 4)

        let importedHomes = try importContext.fetch(FetchDescriptor<HomeProfile>())
        let importedCards = try importContext.fetch(FetchDescriptor<ToolCard>())
        let importedSessions = try importContext.fetch(FetchDescriptor<ProductionSession>())
        let importedEvents = try importContext.fetch(FetchDescriptor<CountEvent>())
        let importedPrimaryHome = try XCTUnwrap(importedHomes.first { $0.name == "Assembly Line (Imported)" })
        let importedPrimarySession = try XCTUnwrap(importedSessions.first {
            $0.homeProfileID == importedPrimaryHome.id && $0.toolID == ToolID.productionCounter.rawValue
        })
        let importedPrimaryCards = HomeCardOrdering.ordered(importedCards.filter {
            $0.homeProfileID == importedPrimaryHome.id
        })
        XCTAssertEqual(importedPrimaryCards.count, 3)
        XCTAssertTrue(importedPrimaryCards.allSatisfy { $0.productionSessionID == importedPrimarySession.id })
        XCTAssertEqual(importedPrimarySession.currentCount, 6)
        XCTAssertEqual(importedPrimarySession.targetCount, 20)
        XCTAssertEqual(importedEvents.filter { $0.sessionID == importedPrimarySession.id }.count, 4)
        XCTAssertNotEqual(importedPrimaryHome.id, primaryHomeID)
        XCTAssertNotEqual(importedPrimarySession.id, primarySessionID)
    }

    func testImportedHomeLifecycleReopensReexportsAndDeletesOnlyItsOwnData() throws {
        let sourceContainer = try makeContainer()
        let sourceContext = ModelContext(sourceContainer)
        let sourceHome = HomeProfile(name: "Imported Factory", sortOrder: 0)
        let sourceSettings = AppSettings(selectedHomeProfileID: sourceHome.id)
        sourceContext.insert(sourceHome)
        sourceContext.insert(sourceSettings)
        let counter = try XCTUnwrap(ToolRegistry.definition(for: .productionCounter))
        let sourceCard = try HomeToolService(modelContext: sourceContext).add(
            counter,
            to: sourceHome.id,
            locale: AppLanguage.english.locale
        )
        let sourceSession = try XCTUnwrap(
            sourceContext.fetch(FetchDescriptor<ProductionSession>()).first
        )
        XCTAssertEqual(sourceCard.productionSessionID, sourceSession.id)
        try CounterService(modelContext: sourceContext).quickAdd(3, to: sourceSession)
        try CounterService(modelContext: sourceContext).setTarget(12, for: sourceSession)
        try CycleTimeSampleService(modelContext: sourceContext).save(
            totalSeconds: 90,
            quantity: 6,
            for: sourceHome.id
        )
        try OEERunService(modelContext: sourceContext).save(
            plannedProductionMinutes: 60,
            downtimeMinutes: 5,
            idealCycleTimeSeconds: 10,
            goodUnits: 300,
            defectiveUnits: 10,
            for: sourceHome.id,
            isPro: true
        )
        let sourceBackup = try FactoryToolsBackupService.decodeAndValidate(
            FactoryToolsBackupService(modelContext: sourceContext).makeJSON()
        )

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("ImportedFactory.store")
        let schema = Schema([
            HomeProfile.self, ToolCard.self, ProductionSession.self, CountEvent.self,
            AppSettings.self, CycleTimeSample.self, OEERun.self, CounterCommandReceipt.self
        ])
        let writableConfiguration = ModelConfiguration(
            "ImportedFactoryLifecycle",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let retainedHomeID = UUID()
        let retainedSessionID: UUID
        let importedHomeID: UUID

        do {
            let container = try ModelContainer(for: schema, configurations: [writableConfiguration])
            let context = ModelContext(container)
            let retainedHome = HomeProfile(id: retainedHomeID, name: "Keep", sortOrder: 0)
            context.insert(retainedHome)
            context.insert(AppSettings(language: AppLanguage.japanese.rawValue, selectedHomeProfileID: retainedHome.id))
            try context.save()
            let retainedCard = try HomeToolService(modelContext: context).add(
                counter,
                to: retainedHome.id,
                locale: AppLanguage.japanese.locale
            )
            let retainedSession = try XCTUnwrap(
                context.fetch(FetchDescriptor<ProductionSession>()).first
            )
            try CounterService(modelContext: context).quickAdd(7, to: retainedSession)
            try CounterService(modelContext: context).setTarget(40, for: retainedSession)
            XCTAssertEqual(retainedCard.homeProfileID, retainedHomeID)
            retainedSessionID = retainedSession.id
        }

        do {
            let reopened = try ModelContainer(for: schema, configurations: [writableConfiguration])
            let context = ModelContext(reopened)
            let retainedSettings = try XCTUnwrap(context.fetch(FetchDescriptor<AppSettings>()).first)
            XCTAssertEqual(retainedSettings.language, AppLanguage.japanese.rawValue)
            XCTAssertEqual(retainedSettings.selectedHomeProfileID, retainedHomeID)

            let result = try FactoryToolsBackupImportService(modelContext: context).addCopy(
                from: sourceBackup,
                importedHomeSuffix: " (Imported)",
                defaultHomeName: "Production",
                isPro: true
            )
            XCTAssertEqual(result, FactoryToolsBackupImportResult(
                homes: 1,
                cards: 1,
                sessions: 1,
                events: 1,
                commandReceipts: 0,
                cycleTimeSamples: 1,
                oeeRuns: 1
            ))

            let importedHome = try XCTUnwrap(
                context.fetch(FetchDescriptor<HomeProfile>()).first { $0.name == "Imported Factory (Imported)" }
            )
            importedHomeID = importedHome.id
            let importedSession = try XCTUnwrap(
                context.fetch(FetchDescriptor<ProductionSession>()).first { $0.homeProfileID == importedHome.id }
            )
            XCTAssertNotEqual(importedSession.id, sourceSession.id)
            XCTAssertEqual(importedSession.currentCount, 3)
            XCTAssertEqual(importedSession.targetCount, 12)
            XCTAssertEqual(importedSession.toolID, ToolID.productionCounter.rawValue)
            XCTAssertEqual(
                try context.fetch(FetchDescriptor<ToolCard>()).first { $0.homeProfileID == importedHome.id }?.productionSessionID,
                importedSession.id
            )
            XCTAssertEqual(try context.fetch(FetchDescriptor<CountEvent>()).filter { $0.sessionID == importedSession.id }.map(\.delta), [3])
            XCTAssertEqual(try context.fetch(FetchDescriptor<CycleTimeSample>()).filter { $0.homeProfileID == importedHome.id }.first?.secondsPerUnit, 15)
            XCTAssertNotNil(try context.fetch(FetchDescriptor<OEERun>()).first { $0.homeProfileID == importedHome.id }?.calculation)

            let reexported = try FactoryToolsBackupService(modelContext: context).makeJSON()
            let reopenedBackup = try FactoryToolsBackupService.decodeAndValidate(reexported)
            XCTAssertEqual(reopenedBackup.homes.count, 2)
            XCTAssertEqual(reopenedBackup.sessions.first { $0.id == importedSession.id }?.currentCount, 3)
            XCTAssertEqual(reopenedBackup.cycleTimeSamples.filter { $0.homeProfileID == importedHome.id }.count, 1)
            XCTAssertEqual(reopenedBackup.oeeRuns.filter { $0.homeProfileID == importedHome.id }.count, 1)

            try HomeProfileService(modelContext: context).deleteHome(importedHome.id)
            let afterDelete = try context.fetch(FetchDescriptor<HomeProfile>())
            XCTAssertEqual(afterDelete.map(\.id), [retainedHomeID])
            XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettings>()).first?.selectedHomeProfileID, retainedHomeID)
            XCTAssertEqual(try context.fetch(FetchDescriptor<ToolCard>()).map(\.homeProfileID), [retainedHomeID])
            XCTAssertEqual(try context.fetch(FetchDescriptor<ProductionSession>()).map(\.id), [retainedSessionID])
            XCTAssertEqual(try context.fetch(FetchDescriptor<CountEvent>()).map(\.sessionID), [retainedSessionID])
            XCTAssertTrue(try context.fetch(FetchDescriptor<CycleTimeSample>()).isEmpty)
            XCTAssertTrue(try context.fetch(FetchDescriptor<OEERun>()).isEmpty)

            let finalBackup = try FactoryToolsBackupService(modelContext: context).makeJSON()
            let finalSnapshot = try FactoryToolsBackupService.decodeAndValidate(finalBackup)
            XCTAssertEqual(finalSnapshot.homes.map(\.id), [retainedHomeID])
            XCTAssertEqual(finalSnapshot.sessions.map(\.id), [retainedSessionID])
            XCTAssertEqual(finalSnapshot.events.map(\.delta), [7])
        }

        let finalContainer = try ModelContainer(for: schema, configurations: [writableConfiguration])
        let finalContext = ModelContext(finalContainer)
        XCTAssertEqual(try finalContext.fetch(FetchDescriptor<HomeProfile>()).map(\.id), [retainedHomeID])
        XCTAssertEqual(try finalContext.fetch(FetchDescriptor<ToolCard>()).map(\.homeProfileID), [retainedHomeID])
        let finalSession = try XCTUnwrap(finalContext.fetch(FetchDescriptor<ProductionSession>()).first)
        XCTAssertEqual(finalSession.id, retainedSessionID)
        XCTAssertEqual(finalSession.currentCount, 7)
        XCTAssertEqual(finalSession.targetCount, 40)
        XCTAssertEqual(try finalContext.fetch(FetchDescriptor<CountEvent>()).map(\.delta), [7])
        XCTAssertTrue(try finalContext.fetch(FetchDescriptor<CounterCommandReceipt>()).isEmpty)
        XCTAssertTrue(try finalContext.fetch(FetchDescriptor<CycleTimeSample>()).isEmpty)
        XCTAssertTrue(try finalContext.fetch(FetchDescriptor<OEERun>()).isEmpty)
        XCTAssertEqual(try finalContext.fetch(FetchDescriptor<AppSettings>()).first?.language, AppLanguage.japanese.rawValue)
        XCTAssertNil(try finalContext.fetch(FetchDescriptor<HomeProfile>()).first { $0.id == importedHomeID })
    }

    func testPersistentStoreRestoresCustomHomeCardsCounterAndLanguage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("FactoryTools.store")
        let schema = Schema([HomeProfile.self, ToolCard.self, ProductionSession.self, CountEvent.self, AppSettings.self, CycleTimeSample.self, OEERun.self, CounterCommandReceipt.self])
        let configuration = ModelConfiguration("PersistenceTest", schema: schema, url: storeURL, allowsSave: true, cloudKitDatabase: .none)
        let homeID: UUID
        let selectedHomeID: UUID
        let sessionID: UUID
        let sampleID: UUID
        let commandReceiptID: UUID
        let sampleCreatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let expectedCardIDs: Set<UUID>

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let home = HomeProfile(name: "Production", usesDefaultName: true, sortOrder: 0)
            let settings = AppSettings(selectedHomeProfileID: home.id)
            context.insert(home)
            context.insert(settings)
            try context.save()
            try AppSettingsService(modelContext: context).setLanguage(.english, for: settings)
            try HomeProfileService(modelContext: context).setName("Assembly Line", for: home)
            let selectedHome = try HomeProfileService(modelContext: context).createHome(
                named: "Quality",
                isPro: true
            )

            let productionCounter = try XCTUnwrap(ToolRegistry.definition(for: .productionCounter))
            let homeToolService = HomeToolService(modelContext: context)
            let counterCard = try homeToolService.add(productionCounter, to: home.id, locale: AppLanguage.english.locale)
            let firstCard = try homeToolService.add(productionCounter, to: home.id, locale: AppLanguage.english.locale)
            let mediumCard = try homeToolService.add(productionCounter, to: home.id, locale: AppLanguage.english.locale)
            let cardService = HomeCardService(modelContext: context)
            try cardService.setSize(.large, for: counterCard)
            try cardService.setSize(.small, for: firstCard)
            try cardService.setSize(.large, for: mediumCard)
            try cardService.setSize(.medium, for: mediumCard)
            try cardService.move(firstCard.id, before: counterCard.id, in: home.id)
            let removedCard = try homeToolService.add(productionCounter, to: home.id, locale: AppLanguage.english.locale)
            try cardService.remove(removedCard)
            let session = try XCTUnwrap(context.fetch(FetchDescriptor<ProductionSession>()).first)
            try CounterService(modelContext: context).quickAdd(12, to: session)
            try CounterService(modelContext: context).quickAdd(0, to: session)
            try CounterService(modelContext: context).setTarget(24, for: session)
            let sample = try CycleTimeSampleService(modelContext: context).save(
                totalSeconds: 180,
                quantity: 12,
                for: home.id,
                createdAt: sampleCreatedAt
            )
            homeID = home.id
            selectedHomeID = selectedHome.id
            sessionID = session.id
            sampleID = sample.id
            commandReceiptID = try XCTUnwrap(context.fetch(FetchDescriptor<CounterCommandReceipt>()).first?.id)
            expectedCardIDs = [counterCard.id, firstCard.id, mediumCard.id]
        }

        do {
            let reopened = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(reopened)
            let homes = try context.fetch(FetchDescriptor<HomeProfile>())
            let cards = try context.fetch(FetchDescriptor<ToolCard>())
            let sessions = try context.fetch(FetchDescriptor<ProductionSession>())
            let settings = try context.fetch(FetchDescriptor<AppSettings>())
            let events = try context.fetch(FetchDescriptor<CountEvent>())
            let commandReceipts = try context.fetch(FetchDescriptor<CounterCommandReceipt>())
            let samples = try context.fetch(FetchDescriptor<CycleTimeSample>())
            let restoredSession = try XCTUnwrap(sessions.first)
            let restoredSample = try XCTUnwrap(samples.first)

            XCTAssertEqual(homes.first?.id, homeID)
            XCTAssertEqual(homes.count, 2)
            XCTAssertEqual(homes.first?.name, "Assembly Line")
            XCTAssertEqual(homes.first?.usesDefaultName, false)
            let orderedCards = cards.sorted { $0.sortOrder < $1.sortOrder }
            XCTAssertEqual(Set(orderedCards.map(\.id)), expectedCardIDs)
            XCTAssertEqual(orderedCards.map(\.toolID), Array(repeating: ToolID.productionCounter.rawValue, count: 3))
            XCTAssertEqual(orderedCards.map(\.size), [.small, .large, .medium])
            XCTAssertEqual(orderedCards.map(\.sortOrder), [0, 1, 2])
            XCTAssertEqual(orderedCards.map(\.homeProfileID), Array(repeating: homeID, count: 3))
            XCTAssertEqual(orderedCards.compactMap(\.productionSessionID), Array(repeating: sessionID, count: 3))
            XCTAssertEqual(restoredSession.id, sessionID)
            XCTAssertEqual(restoredSession.homeProfileID, homeID)
            XCTAssertEqual(restoredSession.toolID, ToolID.productionCounter.rawValue)
            XCTAssertEqual(restoredSession.currentCount, 12)
            XCTAssertEqual(restoredSession.targetCount, 24)
            XCTAssertEqual(restoredSession.nextEventSequence, 1)
            XCTAssertEqual(events.map(\.delta), [12])
            XCTAssertEqual(events.map(\.sessionID), [sessionID])
            XCTAssertEqual(events.map(\.sequence), [0])
            XCTAssertEqual(events.map(\.kind), [.quickAdd])
            XCTAssertEqual(commandReceipts.map(\.id), [commandReceiptID])
            XCTAssertEqual(commandReceipts.first?.sessionID, sessionID)
            XCTAssertEqual(events.reduce(0) { $0 + $1.delta }, restoredSession.currentCount)
            XCTAssertEqual(settings.first?.language, AppLanguage.english.rawValue)
            XCTAssertEqual(settings.first?.themeID, ThemeID.industrialDark.rawValue)
            XCTAssertEqual(settings.first?.selectedHomeProfileID, selectedHomeID)
            XCTAssertEqual(samples.count, 1)
            XCTAssertEqual(restoredSample.id, sampleID)
            XCTAssertEqual(restoredSample.homeProfileID, homeID)
            XCTAssertEqual(restoredSample.totalSeconds, 180)
            XCTAssertEqual(restoredSample.quantity, 12)
            XCTAssertEqual(restoredSample.createdAt, sampleCreatedAt)
            XCTAssertEqual(restoredSample.secondsPerUnit, 15)

            try CounterService(modelContext: context).undo(session: restoredSession)

            let eventsAfterUndo = try context.fetch(FetchDescriptor<CountEvent>())
                .sorted { $0.sequence < $1.sequence }
            XCTAssertEqual(restoredSession.currentCount, 0)
            XCTAssertEqual(restoredSession.nextEventSequence, 2)
            XCTAssertEqual(eventsAfterUndo.map(\.delta), [12, -12])
            XCTAssertEqual(eventsAfterUndo.map(\.sequence), [0, 1])
            XCTAssertEqual(eventsAfterUndo.map(\.kind), [.quickAdd, .undo])
            XCTAssertEqual(eventsAfterUndo.last?.reversesEventID, eventsAfterUndo.first?.id)
            XCTAssertEqual(eventsAfterUndo.reduce(0) { $0 + $1.delta }, restoredSession.currentCount)
        }
    }

    func testBootstrapServiceCreatesHomeAndSettingsOnlyOnce() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = AppBootstrapService(modelContext: context)

        try service.seedMissingRecords()
        try service.seedMissingRecords()

        let homes = try context.fetch(FetchDescriptor<HomeProfile>())
        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        let cards = try context.fetch(FetchDescriptor<ToolCard>())
        let sessions = try context.fetch(FetchDescriptor<ProductionSession>())
        XCTAssertEqual(homes.count, 1)
        XCTAssertEqual(homes.first?.usesDefaultName, true)
        XCTAssertEqual(homes.first?.sortOrder, 0)
        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(settings.first?.language, AppLanguage.system.rawValue)
        XCTAssertEqual(settings.first?.selectedHomeProfileID, homes.first?.id)
        XCTAssertTrue(cards.isEmpty)
        XCTAssertTrue(sessions.isEmpty)
    }

    func testBootstrapServiceRepairsMissingSettingsWithoutDuplicatingHome() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let existingHome = HomeProfile(name: "Custom", sortOrder: 0)
        context.insert(existingHome)
        try context.save()

        try AppBootstrapService(modelContext: context).seedMissingRecords()

        let homes = try context.fetch(FetchDescriptor<HomeProfile>())
        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        XCTAssertEqual(homes.map(\.id), [existingHome.id])
        XCTAssertEqual(homes.first?.name, "Custom")
        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(settings.first?.selectedHomeProfileID, existingHome.id)
    }

    func testBootstrapServiceRepairsMissingHomeWithoutDuplicatingSettings() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let existingSettings = AppSettings(language: AppLanguage.english.rawValue)
        context.insert(existingSettings)
        try context.save()

        try AppBootstrapService(modelContext: context).seedMissingRecords()

        let homes = try context.fetch(FetchDescriptor<HomeProfile>())
        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        XCTAssertEqual(homes.count, 1)
        XCTAssertEqual(homes.first?.usesDefaultName, true)
        XCTAssertEqual(homes.first?.sortOrder, 0)
        XCTAssertEqual(settings.map(\.id), [existingSettings.id])
        XCTAssertEqual(settings.first?.language, AppLanguage.english.rawValue)
        XCTAssertEqual(settings.first?.selectedHomeProfileID, homes.first?.id)
    }

    func testBootstrapServiceRepairsUnknownSelectedHomeID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let first = HomeProfile(name: "Production", usesDefaultName: true, sortOrder: 0)
        let second = HomeProfile(name: "Assembly", sortOrder: 1)
        let settings = AppSettings(selectedHomeProfileID: UUID())
        context.insert(first)
        context.insert(second)
        context.insert(settings)
        try context.save()

        try AppBootstrapService(modelContext: context).seedMissingRecords()

        XCTAssertEqual(settings.selectedHomeProfileID, first.id)
    }

    func testBootstrapServicePreservesValidNonfirstHomeSelection() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let first = HomeProfile(name: "Production", usesDefaultName: true, sortOrder: 0)
        let second = HomeProfile(name: "Assembly", sortOrder: 1)
        let settings = AppSettings(selectedHomeProfileID: second.id)
        context.insert(first)
        context.insert(second)
        context.insert(settings)
        try context.save()

        try AppBootstrapService(modelContext: context).seedMissingRecords()

        XCTAssertEqual(settings.selectedHomeProfileID, second.id)
    }

    func testBootstrapServiceMigratesLegacySessionFromItsCounterCard() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Production", sortOrder: 0)
        let settings = AppSettings(selectedHomeProfileID: home.id)
        let session = ProductionSession(name: "Production run", currentCount: 9, targetCount: 600, nextEventSequence: 1)
        let card = ToolCard(homeProfileID: home.id, toolID: .productionCounter, sortOrder: 0, productionSessionID: session.id)
        let event = CountEvent(sessionID: session.id, delta: 9, sequence: 0)
        context.insert(home)
        context.insert(settings)
        context.insert(session)
        context.insert(card)
        context.insert(event)
        try context.save()

        let service = AppBootstrapService(modelContext: context)
        try service.seedMissingRecords()
        try service.seedMissingRecords()

        XCTAssertEqual(session.homeProfileID, home.id)
        XCTAssertEqual(session.toolID, ToolID.productionCounter.rawValue)
        XCTAssertEqual(session.currentCount, 9)
        XCTAssertEqual(card.productionSessionID, session.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CountEvent>()).map(\.id), [event.id])
    }

    func testBootstrapServiceSkipsAmbiguousOrMismatchedLegacySessionAssignments() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let firstHome = HomeProfile(name: "Production", sortOrder: 0)
        let secondHome = HomeProfile(name: "Assembly", sortOrder: 1)
        let settings = AppSettings(selectedHomeProfileID: firstHome.id)
        let ambiguousSession = ProductionSession(name: "Shared legacy session")
        let wrongToolSession = ProductionSession(toolID: ToolID.productionCounter.rawValue, name: "Legacy session")
        let ambiguousFirstCard = ToolCard(homeProfileID: firstHome.id, toolID: .productionCounter, sortOrder: 0, productionSessionID: ambiguousSession.id)
        let ambiguousSecondCard = ToolCard(homeProfileID: secondHome.id, toolID: .productionCounter, sortOrder: 0, productionSessionID: ambiguousSession.id)
        let mismatchedCard = ToolCard(homeProfileID: firstHome.id, toolID: .defectCounter, sortOrder: 1, productionSessionID: wrongToolSession.id)
        context.insert(firstHome)
        context.insert(secondHome)
        context.insert(settings)
        [ambiguousSession, wrongToolSession].forEach(context.insert)
        [ambiguousFirstCard, ambiguousSecondCard, mismatchedCard].forEach(context.insert)
        try context.save()

        try AppBootstrapService(modelContext: context).seedMissingRecords()

        XCTAssertNil(ambiguousSession.homeProfileID)
        XCTAssertNil(ambiguousSession.toolID)
        XCTAssertNil(wrongToolSession.homeProfileID)
        XCTAssertEqual(wrongToolSession.toolID, ToolID.productionCounter.rawValue)
    }

    func testBootstrapServiceRollsBackDefaultsWhenInitialSaveFails() throws {
        let container = try makeContainer(allowsSave: false)
        let context = ModelContext(container)

        XCTAssertThrowsError(try AppBootstrapService(modelContext: context).seedMissingRecords())

        let verificationContext = ModelContext(container)
        XCTAssertTrue(try verificationContext.fetch(FetchDescriptor<HomeProfile>()).isEmpty)
        XCTAssertTrue(try verificationContext.fetch(FetchDescriptor<AppSettings>()).isEmpty)
    }

    func testBootstrapRepairSaveFailurePreservesPersistedLegacyState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("FactoryTools.store")
        let schema = Schema([HomeProfile.self, ToolCard.self, ProductionSession.self, AppSettings.self])
        let writableConfiguration = ModelConfiguration(
            "BootstrapRepairRollback",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let homeID = UUID()
        let sessionID = UUID()
        let cardID = UUID()
        let settingsID = UUID()
        do {
            let container = try ModelContainer(for: schema, configurations: [writableConfiguration])
            let context = ModelContext(container)
            let home = HomeProfile(id: homeID, name: "Assembly", sortOrder: 0)
            let session = ProductionSession(id: sessionID, name: "Legacy count")
            let card = ToolCard(
                id: cardID,
                homeProfileID: homeID,
                toolID: .productionCounter,
                sortOrder: 0,
                productionSessionID: sessionID
            )
            let settings = AppSettings(id: settingsID, selectedHomeProfileID: UUID())
            context.insert(home)
            context.insert(session)
            context.insert(card)
            context.insert(settings)
            try context.save()
        }

        let readOnlyConfiguration = ModelConfiguration(
            "BootstrapRepairRollback",
            schema: schema,
            url: storeURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        let readOnlyContainer = try ModelContainer(for: schema, configurations: [readOnlyConfiguration])
        let context = ModelContext(readOnlyContainer)
        XCTAssertThrowsError(try AppBootstrapService(modelContext: context).seedMissingRecords())

        let settingsAfterRollback = try XCTUnwrap(
            context.fetch(FetchDescriptor<AppSettings>()).first { $0.id == settingsID }
        )
        let sessionAfterRollback = try XCTUnwrap(
            context.fetch(FetchDescriptor<ProductionSession>()).first { $0.id == sessionID }
        )
        XCTAssertNotNil(settingsAfterRollback.selectedHomeProfileID)
        XCTAssertNotEqual(settingsAfterRollback.selectedHomeProfileID, homeID)
        XCTAssertNil(sessionAfterRollback.homeProfileID)
        XCTAssertNil(sessionAfterRollback.toolID)

        let reopened = try ModelContainer(for: schema, configurations: [readOnlyConfiguration])
        let reopenedContext = ModelContext(reopened)
        let persistedSettings = try XCTUnwrap(reopenedContext.fetch(FetchDescriptor<AppSettings>()).first)
        let persistedSession = try XCTUnwrap(reopenedContext.fetch(FetchDescriptor<ProductionSession>()).first)
        XCTAssertNotEqual(persistedSettings.selectedHomeProfileID, homeID)
        XCTAssertNil(persistedSession.homeProfileID)
        XCTAssertNil(persistedSession.toolID)
        XCTAssertEqual(try reopenedContext.fetch(FetchDescriptor<HomeProfile>()).map(\.id), [homeID])
        XCTAssertEqual(try reopenedContext.fetch(FetchDescriptor<ToolCard>()).map(\.id), [cardID])
    }

    func testHomeCardServicePersistsSizeReorderAndRemoval() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let first = ToolCard(homeProfileID: home.id, toolID: .productionCounter, size: .small, sortOrder: 0)
        let second = ToolCard(homeProfileID: home.id, toolID: .productionCounter, size: .medium, sortOrder: 1)
        let third = ToolCard(homeProfileID: home.id, toolID: .productionCounter, size: .large, sortOrder: 2)
        context.insert(home)
        context.insert(first)
        context.insert(second)
        context.insert(third)
        try context.save()

        let service = HomeCardService(modelContext: context)
        try service.setSize(.large, for: first)
        try service.move(third.id, before: first.id, in: home.id)
        let movedCards = HomeCardOrdering.ordered(try context.fetch(FetchDescriptor<ToolCard>()))

        XCTAssertEqual(movedCards.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(movedCards.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(first.size, .large)
        XCTAssertFalse(try service.move(third.id, before: third.id, in: home.id))

        try service.remove(first)
        let remainingCards = HomeCardOrdering.ordered(try context.fetch(FetchDescriptor<ToolCard>()))
        XCTAssertEqual(remainingCards.map(\.id), [third.id, second.id])
        XCTAssertEqual(remainingCards.map(\.sortOrder), [0, 1])
    }

    func testHomeCardServiceReordersOnlyTheSelectedHome() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let firstHome = HomeProfile(name: "Assembly", sortOrder: 0)
        let secondHome = HomeProfile(name: "Quality", sortOrder: 1)
        let firstCard = ToolCard(homeProfileID: firstHome.id, toolID: .productionCounter, sortOrder: 0)
        let secondCard = ToolCard(homeProfileID: firstHome.id, toolID: .productionCounter, sortOrder: 1)
        let otherFirstCard = ToolCard(homeProfileID: secondHome.id, toolID: .productionCounter, sortOrder: 0)
        let otherSecondCard = ToolCard(homeProfileID: secondHome.id, toolID: .productionCounter, sortOrder: 1)
        context.insert(firstHome)
        context.insert(secondHome)
        context.insert(firstCard)
        context.insert(secondCard)
        context.insert(otherFirstCard)
        context.insert(otherSecondCard)
        try context.save()

        try HomeCardService(modelContext: context).move(secondCard.id, before: firstCard.id, in: firstHome.id)

        let cards = try context.fetch(FetchDescriptor<ToolCard>())
        let firstHomeCards = HomeCardOrdering.ordered(cards.filter { $0.homeProfileID == firstHome.id })
        let secondHomeCards = HomeCardOrdering.ordered(cards.filter { $0.homeProfileID == secondHome.id })
        XCTAssertEqual(firstHomeCards.map(\.id), [secondCard.id, firstCard.id])
        XCTAssertEqual(firstHomeCards.map(\.sortOrder), [0, 1])
        XCTAssertEqual(secondHomeCards.map(\.id), [otherFirstCard.id, otherSecondCard.id])
        XCTAssertEqual(secondHomeCards.map(\.sortOrder), [0, 1])
    }

    func testHomeProfileServicePersistsCustomAndDefaultNames() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Production", usesDefaultName: true, sortOrder: 0)
        context.insert(home)
        try context.save()

        let service = HomeProfileService(modelContext: context)
        try service.setName("  Assembly Line  ", for: home)
        var savedHome = try XCTUnwrap(context.fetch(FetchDescriptor<HomeProfile>()).first)
        XCTAssertEqual(savedHome.name, "Assembly Line")
        XCTAssertFalse(savedHome.usesDefaultName)

        try service.setName("  \n", for: savedHome)
        savedHome = try XCTUnwrap(context.fetch(FetchDescriptor<HomeProfile>()).first)
        XCTAssertEqual(savedHome.name, "Production")
        XCTAssertTrue(savedHome.usesDefaultName)
    }

    func testHomeProfileServiceUsesTheCentralFeatureAccessPolicy() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let settings = AppSettings(selectedHomeProfileID: nil)
        context.insert(settings)
        try context.save()
        let service = HomeProfileService(modelContext: context)

        XCTAssertFalse(FeatureAccessRegistry.allows(.multipleHomeProfiles, isPro: false))
        XCTAssertTrue(FeatureAccessRegistry.allows(.multipleHomeProfiles, isPro: true))
        let firstHome = try service.createHome(named: "Production")
        XCTAssertEqual(settings.selectedHomeProfileID, firstHome.id)
        XCTAssertThrowsError(try service.createHome(named: "Assembly")) {
            XCTAssertEqual($0 as? HomeProfileServiceError, .proRequired)
        }
        let secondHome = try service.createHome(named: "Assembly", isPro: true)
        XCTAssertEqual(settings.selectedHomeProfileID, secondHome.id)
        XCTAssertEqual(HomeProfileOrdering.ordered(try context.fetch(FetchDescriptor<HomeProfile>())).map(\.name), ["Production", "Assembly"])
    }

    func testHomeProfileAccessPreservesAdditionalHomesButLocksThemForFree() throws {
        let first = HomeProfile(name: "Production", sortOrder: 0)
        let second = HomeProfile(name: "Assembly", sortOrder: 1)
        let homes = [second, first]

        XCTAssertEqual(HomeProfileAccess.accessibleHomes(from: homes, isPro: false).map(\.id), [first.id])
        XCTAssertFalse(HomeProfileAccess.canAccess(second.id, in: homes, isPro: false))
        XCTAssertEqual(HomeProfileAccess.selectedHome(from: homes, selectedID: second.id, isPro: false)?.id, first.id)
        XCTAssertEqual(HomeProfileAccess.accessibleHomes(from: homes, isPro: true).map(\.id), [first.id, second.id])
        XCTAssertTrue(HomeProfileAccess.canAccess(second.id, in: homes, isPro: true))
        XCTAssertEqual(HomeProfileAccess.selectedHome(from: homes, selectedID: second.id, isPro: true)?.id, second.id)
    }

    func testHomeProfileServiceCreatesAndSelectsNamedHome() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let firstHome = HomeProfile(name: "Production", usesDefaultName: true, sortOrder: 0)
        let settings = AppSettings(selectedHomeProfileID: firstHome.id)
        context.insert(firstHome)
        context.insert(settings)
        try context.save()

        let created = try HomeProfileService(modelContext: context).createHome(
            named: "  Assembly  ",
            isPro: true
        )

        XCTAssertEqual(created.name, "Assembly")
        XCTAssertFalse(created.usesDefaultName)
        XCTAssertEqual(created.sortOrder, 1)
        XCTAssertEqual(settings.selectedHomeProfileID, created.id)
        XCTAssertEqual(HomeProfileOrdering.ordered(try context.fetch(FetchDescriptor<HomeProfile>())).map(\.id), [firstHome.id, created.id])
    }

    func testHomeProfileServiceRenamesNonselectedHomeWithoutChangingSelectionOrOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let selectedHome = HomeProfile(name: "Production", usesDefaultName: true, sortOrder: 0)
        let otherHome = HomeProfile(name: "Assembly", sortOrder: 1)
        let settings = AppSettings(selectedHomeProfileID: selectedHome.id)
        context.insert(selectedHome)
        context.insert(otherHome)
        context.insert(settings)
        try context.save()

        XCTAssertThrowsError(try HomeProfileService(modelContext: context).setName("Locked", for: otherHome)) {
            XCTAssertEqual($0 as? HomeProfileServiceError, .proRequired)
        }
        try HomeProfileService(modelContext: context).setName("Quality", for: otherHome, isPro: true)

        XCTAssertEqual(otherHome.name, "Quality")
        XCTAssertEqual(otherHome.sortOrder, 1)
        XCTAssertEqual(settings.selectedHomeProfileID, selectedHome.id)
    }

    func testHomeProfileServiceRejectsBlankNewHomeName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Production", usesDefaultName: true, sortOrder: 0)
        context.insert(home)
        context.insert(AppSettings(selectedHomeProfileID: home.id))
        try context.save()

        XCTAssertThrowsError(try HomeProfileService(modelContext: context).createHome(named: " \n "))
        XCTAssertEqual(try context.fetch(FetchDescriptor<HomeProfile>()).count, 1)
    }

    func testHomeProfileServiceSelectsExistingHomeAndRejectsUnknownID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let first = HomeProfile(name: "Production", usesDefaultName: true, sortOrder: 0)
        let second = HomeProfile(name: "Assembly", sortOrder: 1)
        let settings = AppSettings(selectedHomeProfileID: first.id)
        context.insert(first)
        context.insert(second)
        context.insert(settings)
        try context.save()

        XCTAssertThrowsError(try HomeProfileService(modelContext: context).selectHome(second.id)) {
            XCTAssertEqual($0 as? HomeProfileServiceError, .proRequired)
        }
        try HomeProfileService(modelContext: context).selectHome(second.id, isPro: true)
        XCTAssertEqual(settings.selectedHomeProfileID, second.id)
        XCTAssertThrowsError(try HomeProfileService(modelContext: context).selectHome(UUID()))
        XCTAssertEqual(settings.selectedHomeProfileID, second.id)
    }

    func testHomeProfileServiceRestoresSelectionWhenSaveFails() throws {
        let container = try makeContainer(allowsSave: false)
        let context = ModelContext(container)
        let first = HomeProfile(name: "Production", usesDefaultName: true, sortOrder: 0)
        let second = HomeProfile(name: "Assembly", sortOrder: 1)
        let settings = AppSettings(selectedHomeProfileID: first.id)
        context.insert(first)
        context.insert(second)
        context.insert(settings)

        XCTAssertThrowsError(try HomeProfileService(modelContext: context).selectHome(second.id, isPro: true))
        XCTAssertEqual(settings.selectedHomeProfileID, first.id)
    }

    func testHomeProfileServiceReordersAndCompactsHomePositions() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let first = HomeProfile(name: "Production", usesDefaultName: true, sortOrder: 0)
        let second = HomeProfile(name: "Assembly", sortOrder: 1)
        let third = HomeProfile(name: "Quality", sortOrder: 2)
        let settings = AppSettings(selectedHomeProfileID: second.id)
        context.insert(first)
        context.insert(second)
        context.insert(third)
        context.insert(settings)
        try context.save()

        let service = HomeProfileService(modelContext: context)
        XCTAssertThrowsError(try service.move(third.id, before: first.id)) {
            XCTAssertEqual($0 as? HomeProfileServiceError, .proRequired)
        }
        XCTAssertTrue(try service.move(third.id, before: first.id, isPro: true))

        let orderedHomes = HomeProfileOrdering.ordered(try context.fetch(FetchDescriptor<HomeProfile>()))
        XCTAssertEqual(orderedHomes.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(orderedHomes.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(settings.selectedHomeProfileID, second.id)
        XCTAssertFalse(try service.move(first.id, before: first.id, isPro: true))
    }

    func testHomeProfileServiceRestoresOrderWhenMoveSaveFails() throws {
        let container = try makeContainer(allowsSave: false)
        let context = ModelContext(container)
        let first = HomeProfile(name: "Production", usesDefaultName: true, sortOrder: 0)
        let second = HomeProfile(name: "Assembly", sortOrder: 1)
        let third = HomeProfile(name: "Quality", sortOrder: 2)
        context.insert(first)
        context.insert(second)
        context.insert(third)

        XCTAssertThrowsError(try HomeProfileService(modelContext: context).move(third.id, before: first.id, isPro: true))
        XCTAssertEqual([first.sortOrder, second.sortOrder, third.sortOrder], [0, 1, 2])
    }

    func testHomeProfileServiceDeletesSelectedHomeDataAndSelectsRemainingHome() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let remainingHome = HomeProfile(name: "Production", sortOrder: 0)
        let deletedHome = HomeProfile(name: "Packaging", sortOrder: 1)
        let settings = AppSettings(selectedHomeProfileID: deletedHome.id)
        let duplicateSettings = AppSettings(selectedHomeProfileID: deletedHome.id)
        let session = ProductionSession(homeProfileID: deletedHome.id, name: "Packaging count")
        let sessionReceipt = CounterCommandReceipt(id: UUID(), sessionID: session.id)
        let card = ToolCard(homeProfileID: deletedHome.id, toolID: .productionCounter, sortOrder: 0, productionSessionID: session.id)
        let event = CountEvent(sessionID: session.id, delta: 1, sequence: 0)
        let legacySession = ProductionSession(name: "Legacy packaging count", currentCount: 3, nextEventSequence: 1)
        let legacyReceipt = CounterCommandReceipt(id: UUID(), sessionID: legacySession.id)
        let legacyCard = ToolCard(homeProfileID: deletedHome.id, toolID: .productionCounter, sortOrder: 1, productionSessionID: legacySession.id)
        let legacyEvent = CountEvent(sessionID: legacySession.id, delta: 3, sequence: 0)
        let sharedLegacySession = ProductionSession(name: "Shared legacy count", currentCount: 4, nextEventSequence: 1)
        let sharedLegacyReceipt = CounterCommandReceipt(id: UUID(), sessionID: sharedLegacySession.id)
        let deletedSharedLegacyCard = ToolCard(homeProfileID: deletedHome.id, toolID: .productionCounter, sortOrder: 2, productionSessionID: sharedLegacySession.id)
        let remainingSharedLegacyCard = ToolCard(homeProfileID: remainingHome.id, toolID: .productionCounter, sortOrder: 1, productionSessionID: sharedLegacySession.id)
        let sharedLegacyEvent = CountEvent(sessionID: sharedLegacySession.id, delta: 4, sequence: 0)
        let sample = CycleTimeSample(homeProfileID: deletedHome.id, totalSeconds: 60, quantity: 10)
        let preservedSession = ProductionSession(homeProfileID: remainingHome.id, name: "Production count")
        let preservedReceipt = CounterCommandReceipt(id: UUID(), sessionID: preservedSession.id)
        let preservedCard = ToolCard(homeProfileID: remainingHome.id, toolID: .productionCounter, sortOrder: 0, productionSessionID: preservedSession.id)
        let preservedEvent = CountEvent(sessionID: preservedSession.id, delta: 7, sequence: 0)
        let preservedSample = CycleTimeSample(homeProfileID: remainingHome.id, totalSeconds: 90, quantity: 10)
        let oeeRun = OEERun(
            homeProfileID: deletedHome.id,
            plannedProductionMinutes: 60,
            downtimeMinutes: 5,
            idealCycleTimeSeconds: 10,
            goodUnits: 300,
            defectiveUnits: 10
        )
        let preservedOEERun = OEERun(
            homeProfileID: remainingHome.id,
            plannedProductionMinutes: 60,
            downtimeMinutes: 0,
            idealCycleTimeSeconds: 10,
            goodUnits: 300,
            defectiveUnits: 0
        )
        [remainingHome, deletedHome].forEach(context.insert)
        [settings, duplicateSettings].forEach(context.insert)
        context.insert(session)
        context.insert(sessionReceipt)
        context.insert(card)
        context.insert(event)
        context.insert(legacySession)
        context.insert(legacyReceipt)
        context.insert(legacyCard)
        context.insert(legacyEvent)
        context.insert(sharedLegacySession)
        context.insert(sharedLegacyReceipt)
        context.insert(deletedSharedLegacyCard)
        context.insert(remainingSharedLegacyCard)
        context.insert(sharedLegacyEvent)
        context.insert(sample)
        context.insert(preservedSession)
        context.insert(preservedReceipt)
        context.insert(preservedCard)
        context.insert(preservedEvent)
        context.insert(preservedSample)
        context.insert(oeeRun)
        context.insert(preservedOEERun)
        try context.save()

        try HomeProfileService(modelContext: context).deleteHome(deletedHome.id)

        XCTAssertEqual(HomeProfileOrdering.ordered(try context.fetch(FetchDescriptor<HomeProfile>())).map(\.id), [remainingHome.id])
        XCTAssertEqual(remainingHome.sortOrder, 0)
        XCTAssertEqual(settings.selectedHomeProfileID, remainingHome.id)
        XCTAssertEqual(duplicateSettings.selectedHomeProfileID, remainingHome.id)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<ToolCard>()).map(\.id)), Set([preservedCard.id, remainingSharedLegacyCard.id]))
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<ProductionSession>()).map(\.id)), Set([preservedSession.id, sharedLegacySession.id]))
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<CountEvent>()).map(\.id)), Set([preservedEvent.id, sharedLegacyEvent.id]))
        XCTAssertEqual(
            Set(try context.fetch(FetchDescriptor<CounterCommandReceipt>()).map(\.id)),
            Set([sharedLegacyReceipt.id, preservedReceipt.id])
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<CycleTimeSample>()).map(\.id), [preservedSample.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<OEERun>()).map(\.id), [preservedOEERun.id])
    }

    func testHomeProfileServicePreservesSelectionWhenDeletingAnotherHome() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let selected = HomeProfile(name: "Production", sortOrder: 0)
        let deleted = HomeProfile(name: "Assembly", sortOrder: 1)
        let last = HomeProfile(name: "Quality", sortOrder: 2)
        let settings = AppSettings(selectedHomeProfileID: selected.id)
        [selected, deleted, last].forEach(context.insert)
        context.insert(settings)
        try context.save()

        try HomeProfileService(modelContext: context).deleteHome(deleted.id)

        XCTAssertEqual(HomeProfileOrdering.ordered(try context.fetch(FetchDescriptor<HomeProfile>())).map(\.id), [selected.id, last.id])
        XCTAssertEqual([selected.sortOrder, last.sortOrder], [0, 1])
        XCTAssertEqual(settings.selectedHomeProfileID, selected.id)
    }

    func testHomeProfileServiceRejectsDeletingLastOrUnknownHome() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let onlyHome = HomeProfile(name: "Production", sortOrder: 0)
        context.insert(onlyHome)
        try context.save()
        let service = HomeProfileService(modelContext: context)

        XCTAssertThrowsError(try service.deleteHome(onlyHome.id)) {
            XCTAssertEqual($0 as? HomeProfileServiceError, .lastHome)
        }
        XCTAssertThrowsError(try service.deleteHome(UUID())) {
            XCTAssertEqual($0 as? HomeProfileServiceError, .homeNotFound)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<HomeProfile>()).map(\.id), [onlyHome.id])
    }

    func testHomeProfileSaveFailuresPreservePersistedSelectionNamesAndOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("FactoryTools.store")
        let schema = Schema([
            HomeProfile.self, ToolCard.self, ProductionSession.self, CountEvent.self,
            AppSettings.self, CycleTimeSample.self, OEERun.self, CounterCommandReceipt.self
        ])
        let firstHomeID = UUID()
        let secondHomeID = UUID()
        let settingsID = UUID()
        let writableConfiguration = ModelConfiguration(
            "HomeProfileRollback",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [writableConfiguration])
            let context = ModelContext(container)
            context.insert(HomeProfile(id: firstHomeID, name: "Production", usesDefaultName: true, sortOrder: 0))
            context.insert(HomeProfile(id: secondHomeID, name: "Assembly", sortOrder: 1))
            context.insert(AppSettings(id: settingsID, selectedHomeProfileID: firstHomeID))
            try context.save()
        }

        let readOnlyConfiguration = ModelConfiguration(
            "HomeProfileRollback",
            schema: schema,
            url: storeURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [readOnlyConfiguration])
        let context = ModelContext(container)
        let service = HomeProfileService(modelContext: context)
        let homes = try context.fetch(FetchDescriptor<HomeProfile>())
        let secondHome = try XCTUnwrap(homes.first { $0.id == secondHomeID })
        let settings = try XCTUnwrap(context.fetch(FetchDescriptor<AppSettings>()).first)

        XCTAssertThrowsError(try service.createHome(named: "New home", isPro: true))
        XCTAssertThrowsError(try service.selectHome(secondHomeID, isPro: true))
        XCTAssertThrowsError(try service.setName("Renamed", for: secondHome, isPro: true))
        XCTAssertThrowsError(try service.move(secondHomeID, before: firstHomeID, isPro: true))

        let restoredHomes = HomeProfileOrdering.ordered(try context.fetch(FetchDescriptor<HomeProfile>()))
        XCTAssertEqual(restoredHomes.map(\.id), [firstHomeID, secondHomeID])
        XCTAssertEqual(restoredHomes.map(\.name), ["Production", "Assembly"])
        XCTAssertEqual(restoredHomes.map(\.usesDefaultName), [true, false])
        XCTAssertEqual(restoredHomes.map(\.sortOrder), [0, 1])
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettings>()).map(\.id), [settingsID])
        XCTAssertEqual(settings.selectedHomeProfileID, firstHomeID)
    }

    func testHomeDeleteSaveFailurePreservesPersistedHomesAndRelatedData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("FactoryTools.store")
        let schema = Schema([
            HomeProfile.self, ToolCard.self, ProductionSession.self, CountEvent.self,
            AppSettings.self, CycleTimeSample.self, OEERun.self, CounterCommandReceipt.self
        ])
        let writableConfiguration = ModelConfiguration(
            "HomeDeleteRollback",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let deletedHomeID = UUID()
        let retainedHomeID = UUID()
        let sessionID = UUID()
        let cardID = UUID()
        let eventID = UUID()
        let receiptID = UUID()
        let sampleID = UUID()
        let runID = UUID()
        do {
            let container = try ModelContainer(for: schema, configurations: [writableConfiguration])
            let context = ModelContext(container)
            let deletedHome = HomeProfile(id: deletedHomeID, name: "Assembly", sortOrder: 1)
            let retainedHome = HomeProfile(id: retainedHomeID, name: "Production", sortOrder: 0)
            let settings = AppSettings(selectedHomeProfileID: deletedHomeID)
            let session = ProductionSession(
                id: sessionID,
                homeProfileID: deletedHomeID,
                toolID: ToolID.productionCounter.rawValue,
                name: "Assembly count",
                currentCount: 2,
                nextEventSequence: 1
            )
            let card = ToolCard(
                id: cardID,
                homeProfileID: deletedHomeID,
                toolID: .productionCounter,
                sortOrder: 0,
                productionSessionID: sessionID
            )
            let event = CountEvent(id: eventID, sessionID: sessionID, delta: 2, sequence: 0, kind: .quickAdd)
            let receipt = CounterCommandReceipt(id: receiptID, sessionID: sessionID)
            let sample = CycleTimeSample(id: sampleID, homeProfileID: deletedHomeID, totalSeconds: 60, quantity: 2)
            let run = OEERun(
                id: runID,
                homeProfileID: deletedHomeID,
                plannedProductionMinutes: 60,
                downtimeMinutes: 0,
                idealCycleTimeSeconds: 30,
                goodUnits: 2,
                defectiveUnits: 0
            )
            [deletedHome, retainedHome].forEach(context.insert)
            context.insert(settings)
            context.insert(session)
            context.insert(card)
            context.insert(event)
            context.insert(receipt)
            context.insert(sample)
            context.insert(run)
            try context.save()
        }

        let readOnlyConfiguration = ModelConfiguration(
            "HomeDeleteRollback",
            schema: schema,
            url: storeURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        let readOnlyContainer = try ModelContainer(for: schema, configurations: [readOnlyConfiguration])
        let context = ModelContext(readOnlyContainer)
        XCTAssertThrowsError(try HomeProfileService(modelContext: context).deleteHome(deletedHomeID))

        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<HomeProfile>()).map(\.id)), [deletedHomeID, retainedHomeID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ToolCard>()).map(\.id), [cardID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProductionSession>()).map(\.id), [sessionID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<CountEvent>()).map(\.id), [eventID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<CounterCommandReceipt>()).map(\.id), [receiptID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<CycleTimeSample>()).map(\.id), [sampleID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<OEERun>()).map(\.id), [runID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettings>()).first?.selectedHomeProfileID, deletedHomeID)
        XCTAssertEqual(HomeProfileOrdering.ordered(try context.fetch(FetchDescriptor<HomeProfile>())).map(\.sortOrder), [0, 1])
    }

    func testCardAndPresetSaveFailuresPreservePersistedDataAndRollbackNewRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("FactoryTools.store")
        let schema = Schema([
            HomeProfile.self, ToolCard.self, ProductionSession.self, CountEvent.self,
            AppSettings.self, CycleTimeSample.self, OEERun.self, CounterCommandReceipt.self
        ])
        let homeID = UUID()
        let settingsID = UUID()
        let sessionID = UUID()
        let firstCardID = UUID()
        let secondCardID = UUID()
        let eventID = UUID()
        let writableConfiguration = ModelConfiguration(
            "CardPresetRollback",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [writableConfiguration])
            let context = ModelContext(container)
            let home = HomeProfile(id: homeID, name: "Production", sortOrder: 0)
            let settings = AppSettings(id: settingsID, selectedHomeProfileID: homeID)
            let session = ProductionSession(
                id: sessionID,
                homeProfileID: homeID,
                toolID: ToolID.productionCounter.rawValue,
                name: "Production count",
                currentCount: 5,
                targetCount: 20,
                nextEventSequence: 1
            )
            let firstCard = ToolCard(
                id: firstCardID,
                homeProfileID: homeID,
                toolID: .productionCounter,
                size: .small,
                sortOrder: 0,
                productionSessionID: sessionID
            )
            let secondCard = ToolCard(
                id: secondCardID,
                homeProfileID: homeID,
                toolID: .productionCounter,
                size: .medium,
                sortOrder: 1,
                productionSessionID: sessionID
            )
            let event = CountEvent(id: eventID, sessionID: sessionID, delta: 5, sequence: 0, kind: .quickAdd)
            context.insert(home)
            [firstCard, secondCard].forEach(context.insert)
            context.insert(session)
            context.insert(settings)
            context.insert(event)
            try context.save()
        }

        let readOnlyConfiguration = ModelConfiguration(
            "CardPresetRollback",
            schema: schema,
            url: storeURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [readOnlyConfiguration])
        let context = ModelContext(container)
        let cardService = HomeCardService(modelContext: context)
        let cards = try context.fetch(FetchDescriptor<ToolCard>())
        let firstCard = try XCTUnwrap(cards.first { $0.id == firstCardID })
        let secondCard = try XCTUnwrap(cards.first { $0.id == secondCardID })

        XCTAssertThrowsError(try cardService.setSize(.large, for: firstCard))
        XCTAssertThrowsError(try cardService.move(secondCardID, before: firstCardID, in: homeID))
        XCTAssertThrowsError(try cardService.remove(secondCard))
        XCTAssertThrowsError(
            try HomeToolService(modelContext: context).applyPackagingPreset(
                to: homeID,
                locale: AppLanguage.english.locale
            )
        )

        let verificationContext = ModelContext(container)
        let restoredCards = HomeCardOrdering.ordered(try verificationContext.fetch(FetchDescriptor<ToolCard>()))
        XCTAssertEqual(restoredCards.map(\.id), [firstCardID, secondCardID])
        XCTAssertEqual(restoredCards.map(\.size), [.small, .medium])
        XCTAssertEqual(restoredCards.map(\.sortOrder), [0, 1])
        XCTAssertEqual(restoredCards.compactMap(\.productionSessionID), [sessionID, sessionID])
        XCTAssertEqual(try verificationContext.fetch(FetchDescriptor<HomeProfile>()).map(\.id), [homeID])
        XCTAssertEqual(try verificationContext.fetch(FetchDescriptor<AppSettings>()).map(\.id), [settingsID])
        let restoredSession = try XCTUnwrap(verificationContext.fetch(FetchDescriptor<ProductionSession>()).first)
        XCTAssertEqual(restoredSession.id, sessionID)
        XCTAssertEqual(restoredSession.currentCount, 5)
        XCTAssertEqual(restoredSession.targetCount, 20)
        XCTAssertEqual(try verificationContext.fetch(FetchDescriptor<CountEvent>()).map(\.id), [eventID])
        XCTAssertTrue(try verificationContext.fetch(FetchDescriptor<CounterCommandReceipt>()).isEmpty)
        XCTAssertTrue(try verificationContext.fetch(FetchDescriptor<CycleTimeSample>()).isEmpty)
        XCTAssertTrue(try verificationContext.fetch(FetchDescriptor<OEERun>()).isEmpty)
    }

    func testHomeProfileServiceRollsBackDeleteWhenSaveFails() throws {
        let first = HomeProfile(name: "Production", sortOrder: 0)
        let second = HomeProfile(name: "Assembly", sortOrder: 1)
        let settings = AppSettings(selectedHomeProfileID: second.id)
        let container = try makeContainer(allowsSave: false) { context in
            context.insert(first)
            context.insert(second)
            context.insert(settings)
        }
        let context = ModelContext(container)

        XCTAssertThrowsError(try HomeProfileService(modelContext: context).deleteHome(second.id))
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<HomeProfile>()).map(\.id)), [first.id, second.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettings>()).first?.selectedHomeProfileID, second.id)
    }

    func testHomeCardServiceRollsBackWhenSaveFails() throws {
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let card = ToolCard(homeProfileID: home.id, toolID: .productionCounter, size: .small, sortOrder: 0)
        let container = try makeContainer(allowsSave: false) { context in
            context.insert(home)
            context.insert(card)
        }
        let context = ModelContext(container)
        let storedCard = try XCTUnwrap(context.fetch(FetchDescriptor<ToolCard>()).first)

        XCTAssertThrowsError(try HomeCardService(modelContext: context).setSize(.large, for: storedCard))

        XCTAssertEqual(try context.fetch(FetchDescriptor<HomeProfile>()).map(\.id), [home.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ToolCard>()).first?.size, .small)
    }

    func testHomeCardServiceRejectsSizesNotAllowedByToolRegistry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let card = ToolCard(homeProfileID: home.id, toolID: .taktTime, size: .medium, sortOrder: 0)
        context.insert(home)
        context.insert(card)
        try context.save()

        XCTAssertThrowsError(try HomeCardService(modelContext: context).setSize(.small, for: card))
        XCTAssertEqual(card.size, .medium)
    }

    func testHomeProfileServiceRestoresNameWhenSaveFails() throws {
        let container = try makeContainer(allowsSave: false)
        let context = ModelContext(container)
        let home = HomeProfile(name: "Production", usesDefaultName: true, sortOrder: 0)
        context.insert(home)

        XCTAssertThrowsError(try HomeProfileService(modelContext: context).setName("Assembly", for: home))

        XCTAssertEqual(home.name, "Production")
        XCTAssertTrue(home.usesDefaultName)
    }

    func testHomeToolServiceAddsCardsAndReusesOnlyTheMatchingHomeSession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let otherHomeID = UUID()
        let otherHomeSession = ProductionSession(
            homeProfileID: otherHomeID,
            toolID: ToolID.productionCounter.rawValue,
            name: "Other home"
        )
        context.insert(home)
        context.insert(otherHomeSession)
        try context.save()

        let tool = try XCTUnwrap(ToolRegistry.definition(for: .productionCounter))
        let service = HomeToolService(modelContext: context)
        let firstCard = try service.add(tool, to: home.id, locale: AppLanguage.english.locale)
        let secondCard = try service.add(tool, to: home.id, locale: AppLanguage.english.locale)

        let cards = try context.fetch(FetchDescriptor<ToolCard>())
        let sessions = try context.fetch(FetchDescriptor<ProductionSession>())
        let homeSession = try XCTUnwrap(sessions.first { $0.homeProfileID == home.id })
        XCTAssertEqual(cards.filter { $0.homeProfileID == home.id }.count, 2)
        XCTAssertEqual(firstCard.productionSessionID, homeSession.id)
        XCTAssertEqual(secondCard.productionSessionID, homeSession.id)
        XCTAssertEqual(homeSession.toolID, ToolID.productionCounter.rawValue)
        XCTAssertEqual(homeSession.name, "Production run")
        XCTAssertEqual(homeSession.currentCount, 0)
        XCTAssertEqual(homeSession.targetCount, 600)
        XCTAssertEqual(homeSession.nextEventSequence, 0)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first { $0.homeProfileID == otherHomeID }?.id, otherHomeSession.id)
    }

    func testHomeToolServiceUsesJapaneseNameWithoutChangingStableToolID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        context.insert(home)
        try context.save()
        let tool = try XCTUnwrap(ToolRegistry.definition(for: .productionCounter))

        let card = try HomeToolService(modelContext: context).add(
            tool,
            to: home.id,
            locale: AppLanguage.japanese.locale
        )
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<ProductionSession>()).first)

        XCTAssertEqual(card.toolID, "production.counter")
        XCTAssertEqual(session.toolID, "production.counter")
        XCTAssertEqual(session.name, "生産セッション")
    }

    func testAssemblyPresetAddsLocalizedToolsInOrderWithIndependentSessions() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        context.insert(home)
        try context.save()

        let cards = try HomeToolService(modelContext: context).applyAssemblyPreset(
            to: home.id,
            locale: AppLanguage.japanese.locale
        )
        let orderedCards = HomeCardOrdering.ordered(cards)
        let sessions = try context.fetch(FetchDescriptor<ProductionSession>())

        XCTAssertEqual(orderedCards.map(\.toolID), AssemblyPreset.toolIDs.map(\.rawValue))
        XCTAssertEqual(orderedCards.map(\.sortOrder), Array(0..<AssemblyPreset.toolIDs.count))
        XCTAssertEqual(sessions.compactMap(\.toolID).sorted(), [ToolID.productionCounter.rawValue, ToolID.defectCounter.rawValue].sorted())
        XCTAssertNotNil(orderedCards[0].productionSessionID)
        XCTAssertNotNil(orderedCards[3].productionSessionID)
        XCTAssertNotEqual(orderedCards[0].productionSessionID, orderedCards[3].productionSessionID)
        XCTAssertNil(orderedCards[1].productionSessionID)
        XCTAssertNil(orderedCards[2].productionSessionID)
        XCTAssertEqual(sessions.first { $0.toolID == ToolID.productionCounter.rawValue }?.name, "生産セッション")
        XCTAssertEqual(sessions.first { $0.toolID == ToolID.defectCounter.rawValue }?.name, "不良カウント")
        XCTAssertEqual(
            orderedCards.map(\.showsOnWatch),
            AssemblyPreset.toolIDs.map { ToolRegistry.definition(for: $0)?.supportsWatch ?? false }
        )
    }

    func testAssemblyPresetSkipsExistingCardsAndCanBeAppliedRepeatedly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        context.insert(home)
        try context.save()
        let service = HomeToolService(modelContext: context)
        let counter = try XCTUnwrap(ToolRegistry.definition(for: .productionCounter))
        try service.add(counter, to: home.id, locale: AppLanguage.english.locale)

        let firstBatch = try service.applyAssemblyPreset(to: home.id, locale: AppLanguage.english.locale)
        let secondBatch = try service.applyAssemblyPreset(to: home.id, locale: AppLanguage.english.locale)
        let cards = try context.fetch(FetchDescriptor<ToolCard>()).filter { $0.homeProfileID == home.id }

        XCTAssertEqual(firstBatch.map(\.toolID), AssemblyPreset.toolIDs.dropFirst().map(\.rawValue))
        XCTAssertTrue(secondBatch.isEmpty)
        XCTAssertEqual(cards.count, AssemblyPreset.toolIDs.count)
        XCTAssertEqual(cards.filter { $0.toolID == ToolID.productionCounter.rawValue }.count, 1)
    }

    func testAssemblyPresetRollsBackAllNewRecordsWhenBatchSaveFails() throws {
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let container = try makeContainer(allowsSave: false) { $0.insert(home) }
        let context = ModelContext(container)

        XCTAssertThrowsError(
            try HomeToolService(modelContext: context).applyAssemblyPreset(
                to: home.id,
                locale: AppLanguage.english.locale
            )
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<HomeProfile>()).map(\.id), [home.id])
        XCTAssertTrue(try context.fetch(FetchDescriptor<ToolCard>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProductionSession>()).isEmpty)
    }

    func testPackagingPresetAddsToolsInOrderWithSharedProductionSession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Packaging", sortOrder: 0)
        context.insert(home)
        try context.save()

        let cards = try HomeToolService(modelContext: context).applyPackagingPreset(
            to: home.id,
            locale: AppLanguage.japanese.locale,
            isPro: true
        )
        let orderedCards = HomeCardOrdering.ordered(cards)
        let sessions = try context.fetch(FetchDescriptor<ProductionSession>())

        XCTAssertEqual(PackagingPreset.toolIDs, [
            .productionCounter, .productionProgress, .defectCounter, .defectRate, .boxCalculator, .unitConverter, .oee
        ])
        XCTAssertEqual(orderedCards.map(\.toolID), PackagingPreset.toolIDs.map(\.rawValue))
        XCTAssertEqual(orderedCards.map(\.sortOrder), Array(0..<PackagingPreset.toolIDs.count))
        XCTAssertEqual(orderedCards[0].productionSessionID, orderedCards[1].productionSessionID)
        XCTAssertNotEqual(orderedCards[0].productionSessionID, orderedCards[2].productionSessionID)
        XCTAssertNil(orderedCards[3].productionSessionID)
        XCTAssertNil(orderedCards[4].productionSessionID)
        XCTAssertNil(orderedCards[5].productionSessionID)
        XCTAssertNil(orderedCards[6].productionSessionID)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(
            orderedCards.map(\.showsOnWatch),
            PackagingPreset.toolIDs.map { ToolRegistry.definition(for: $0)?.supportsWatch ?? false }
        )
    }

    func testFreePackagingPresetSkipsProToolsButKeepsFreeToolsUsable() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Packaging", sortOrder: 0)
        context.insert(home)
        try context.save()

        let cards = try HomeToolService(modelContext: context).applyPackagingPreset(
            to: home.id,
            locale: AppLanguage.english.locale
        )

        XCTAssertEqual(Set(cards.compactMap { ToolID(rawValue: $0.toolID) }), [
            .productionCounter, .defectCounter, .defectRate, .boxCalculator, .unitConverter,
        ])
        XCTAssertFalse(cards.contains { $0.toolID == ToolID.productionProgress.rawValue || $0.toolID == ToolID.oee.rawValue })
    }

    func testPackagingPresetSkipsExistingCardsAndCanBeAppliedRepeatedly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Packaging", sortOrder: 0)
        context.insert(home)
        try context.save()
        let service = HomeToolService(modelContext: context)
        let unitConverter = try XCTUnwrap(ToolRegistry.definition(for: .unitConverter))
        try service.add(unitConverter, to: home.id, locale: AppLanguage.english.locale)

        let firstBatch = try service.applyPackagingPreset(to: home.id, locale: AppLanguage.english.locale, isPro: true)
        let secondBatch = try service.applyPackagingPreset(to: home.id, locale: AppLanguage.english.locale, isPro: true)
        let cards = try context.fetch(FetchDescriptor<ToolCard>()).filter { $0.homeProfileID == home.id }

        XCTAssertEqual(firstBatch.map(\.toolID), PackagingPreset.toolIDs.filter { $0 != .unitConverter }.map(\.rawValue))
        XCTAssertTrue(secondBatch.isEmpty)
        XCTAssertEqual(cards.count, PackagingPreset.toolIDs.count)
        XCTAssertEqual(cards.filter { $0.toolID == ToolID.unitConverter.rawValue }.count, 1)
    }

    func testPackagingPresetRollsBackAllNewRecordsWhenBatchSaveFails() throws {
        let home = HomeProfile(name: "Packaging", sortOrder: 0)
        let container = try makeContainer(allowsSave: false) { $0.insert(home) }
        let context = ModelContext(container)

        XCTAssertThrowsError(
            try HomeToolService(modelContext: context).applyPackagingPreset(
                to: home.id,
                locale: AppLanguage.english.locale,
                isPro: true
            )
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<HomeProfile>()).map(\.id), [home.id])
        XCTAssertTrue(try context.fetch(FetchDescriptor<ToolCard>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProductionSession>()).isEmpty)
    }

    func testHomeToolServiceUsesRegistryAvailabilityAsAuthority() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        context.insert(home)
        try context.save()

        let callerMarkedUnavailableTool = ToolDefinition(
            id: .unitConverter,
            titleKey: "tool.unitConverter.title",
            category: .utility,
            accessTier: .free,
            isAvailable: false,
            homeCardRoute: .unitConverter
        )

        let card = try HomeToolService(modelContext: context).add(
            callerMarkedUnavailableTool,
            to: home.id,
            locale: AppLanguage.english.locale
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<HomeProfile>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ToolCard>()).map(\.id), [card.id])
        XCTAssertEqual(card.toolID, ToolID.unitConverter.rawValue)
        XCTAssertFalse(card.showsOnWatch, "new-card defaults must use canonical Registry metadata")
        XCTAssertNil(card.productionSessionID)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProductionSession>()).isEmpty)

        let oee = try XCTUnwrap(ToolRegistry.definition(for: .oee))
        XCTAssertThrowsError(try HomeToolService(modelContext: context).add(
            oee,
            to: home.id,
            locale: AppLanguage.english.locale
        )) { XCTAssertEqual($0 as? HomeToolServiceError, .proRequired) }
        let proCard = try HomeToolService(modelContext: context).add(
            oee,
            to: home.id,
            locale: AppLanguage.english.locale,
            isPro: true
        )
        XCTAssertEqual(proCard.toolID, ToolID.oee.rawValue)
    }

    func testEveryRegisteredToolHasAnExplicitFreeOrProAccessTier() {
        XCTAssertEqual(ToolRegistry.all.count, ToolID.allCases.count)
        XCTAssertEqual(Set(ToolRegistry.all.map(\.id)).count, ToolID.allCases.count)
        XCTAssertEqual(Set(ToolRegistry.all.filter { $0.accessTier == .pro }.map(\.id)), [.productionProgress, .oee])
        XCTAssertTrue(ToolRegistry.hasProAssignments)
    }

    func testHomeToolServiceInitializesWatchVisibilityFromEveryRegistryDefinition() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        context.insert(home)
        context.insert(AppSettings(selectedHomeProfileID: home.id))
        try context.save()

        let service = HomeToolService(modelContext: context)
        for definition in ToolRegistry.all where definition.isAvailable {
            let card = try service.add(definition, to: home.id, locale: AppLanguage.english.locale, isPro: true)
            XCTAssertEqual(card.showsOnWatch, definition.supportsWatch, "Watch visibility mismatch for \(definition.id)")
        }

        let storedCards = try context.fetch(FetchDescriptor<ToolCard>())
        XCTAssertEqual(storedCards.count, ToolRegistry.all.filter(\.isAvailable).count)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: storedCards.map { ($0.toolID, $0.showsOnWatch) }),
            Dictionary(uniqueKeysWithValues: ToolRegistry.all.filter(\.isAvailable).map {
                ($0.id.rawValue, $0.supportsWatch)
            })
        )

        let backup = try FactoryToolsBackupService.decodeAndValidate(
            FactoryToolsBackupService(modelContext: context).makeJSON()
        )
        let importContainer = try makeContainer()
        let importContext = ModelContext(importContainer)
        _ = try FactoryToolsBackupImportService(modelContext: importContext).addCopy(
            from: backup,
            importedHomeSuffix: " (Imported)",
            defaultHomeName: "Production",
            isPro: true
        )
        let importedCards = try importContext.fetch(FetchDescriptor<ToolCard>())
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: importedCards.map { ($0.toolID, $0.showsOnWatch) }),
            Dictionary(uniqueKeysWithValues: ToolRegistry.all.filter(\.isAvailable).map {
                ($0.id.rawValue, $0.supportsWatch)
            })
        )
    }

    func testHomeToolServiceRejectsMissingHomeWithoutWritingData() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let tool = try XCTUnwrap(ToolRegistry.definition(for: .productionCounter))

        XCTAssertThrowsError(
            try HomeToolService(modelContext: context).add(
                tool,
                to: UUID(),
                locale: AppLanguage.english.locale
            )
        )

        XCTAssertTrue(try context.fetch(FetchDescriptor<ToolCard>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProductionSession>()).isEmpty)
    }

    func testHomeToolServiceCompactsExistingOrderAndAppendsNewCard() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let session = ProductionSession(
            homeProfileID: home.id,
            toolID: ToolID.productionCounter.rawValue,
            name: "Production run"
        )
        let firstCard = ToolCard(
            homeProfileID: home.id,
            toolID: .productionCounter,
            sortOrder: 2,
            productionSessionID: session.id
        )
        let secondCard = ToolCard(
            homeProfileID: home.id,
            toolID: .productionCounter,
            sortOrder: 8,
            productionSessionID: session.id
        )
        context.insert(home)
        context.insert(session)
        context.insert(firstCard)
        context.insert(secondCard)
        try context.save()

        let tool = try XCTUnwrap(ToolRegistry.definition(for: .productionCounter))
        let addedCard = try HomeToolService(modelContext: context).add(
            tool,
            to: home.id,
            locale: AppLanguage.english.locale
        )
        let fetchedCards = try context.fetch(FetchDescriptor<ToolCard>())
        let orderedCards = fetchedCards
            .filter { $0.homeProfileID == home.id }
            .sorted { $0.sortOrder < $1.sortOrder }

        XCTAssertEqual(orderedCards.map(\.id), [firstCard.id, secondCard.id, addedCard.id])
        XCTAssertEqual(orderedCards.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(orderedCards.map(\.productionSessionID), [session.id, session.id, session.id])
    }

    func testHomeToolServiceRollsBackCardAndSessionWhenSaveFails() throws {
        let tool = try XCTUnwrap(ToolRegistry.definition(for: .productionCounter))
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let container = try makeContainer(allowsSave: false) { $0.insert(home) }
        let context = ModelContext(container)

        XCTAssertThrowsError(
            try HomeToolService(modelContext: context).add(
                tool,
                to: home.id,
                locale: AppLanguage.english.locale
            )
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<HomeProfile>()).map(\.id), [home.id])
        XCTAssertTrue(try context.fetch(FetchDescriptor<ToolCard>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProductionSession>()).isEmpty)
    }

    private func makeContainer(
        allowsSave: Bool = true,
        seed: ((ModelContext) throws -> Void)? = nil
    ) throws -> ModelContainer {
        let schema = Schema([
            HomeProfile.self,
            ToolCard.self,
            ProductionSession.self,
            CountEvent.self,
            AppSettings.self,
            CycleTimeSample.self,
            OEERun.self,
            CounterCommandReceipt.self
        ])
        guard !allowsSave else {
            let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            if let seed {
                let context = ModelContext(container)
                try seed(context)
                try context.save()
            }
            return container
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FactoryToolsReadOnly-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("FactoryTools.store")
        let configurationName = UUID().uuidString
        let writable = ModelConfiguration(configurationName, schema: schema, url: storeURL, cloudKitDatabase: .none)
        let writableContainer = try ModelContainer(for: schema, configurations: [writable])
        if let seed {
            let context = ModelContext(writableContainer)
            try seed(context)
            try context.save()
        }
        let readOnly = ModelConfiguration(configurationName, schema: schema, url: storeURL, allowsSave: false, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [readOnly])
    }
}

@MainActor
final class ToolRegistryTests: XCTestCase {
    func testToolAccessAssignmentsMatchTheApprovedVersionOneBoundary() throws {
        let expected: [ToolID: FeatureAccessTier] = [
            .productionCounter: .free,
            .cycleTime: .free,
            .taktTime: .free,
            .oee: .pro,
            .productionProgress: .pro,
            .defectCounter: .free,
            .defectRate: .free,
            .boxCalculator: .free,
            .unitConverter: .free,
        ]

        XCTAssertEqual(Set(ToolRegistry.all.map(\.id)), Set(expected.keys))
        for (toolID, accessTier) in expected {
            let definition = try XCTUnwrap(ToolRegistry.definition(for: toolID))
            XCTAssertTrue(definition.isAvailable, "\(toolID.rawValue) should be available in Version 1")
            XCTAssertEqual(definition.accessTier, accessTier, "Unexpected access tier for \(toolID.rawValue)")
            XCTAssertEqual(
                FeatureAccessRegistry.allows(definition.accessTier, isPro: false),
                accessTier == .free,
                "Free access mismatch for \(toolID.rawValue)"
            )
            XCTAssertTrue(FeatureAccessRegistry.allows(definition.accessTier, isPro: true))
        }
    }

    func testDefectRateMathHandlesValidZeroAndOutOfRangeRatios() {
        XCTAssertNil(DefectRateMath.fraction(defectCount: 0, productionCount: 0))
        XCTAssertNil(DefectRateMath.fraction(defectCount: -1, productionCount: 10))
        XCTAssertEqual(DefectRateMath.fraction(defectCount: 8, productionCount: 100), 0.08)
        XCTAssertEqual(DefectRateMath.fraction(defectCount: 12, productionCount: 10), 1.2)
    }

    func testDefectRateIsAvailableForMediumAndLargeCards() throws {
        let definition = try XCTUnwrap(ToolRegistry.definition(for: .defectRate))

        XCTAssertEqual(definition.category, .quality)
        XCTAssertTrue(definition.isAvailable)
        XCTAssertEqual(definition.supportedCardSizes, [.medium, .large])
        XCTAssertEqual(definition.titleKey, "tool.defectRate.title")
    }

    func testThemeManagerResolvesIndustrialDarkTypographyAndBorderTokens() {
        let theme = ThemeManager().theme(for: .industrialDark)

        XCTAssertEqual(theme.id, .industrialDark)
        XCTAssertEqual(theme.id.rawValue, "industrial.dark")
        XCTAssertEqual(theme.cornerRadius, 18)
        XCTAssertEqual(theme.borderWidth, 1)
        XCTAssertEqual(theme.smallCounterPointSize, 30)
        XCTAssertEqual(theme.regularCounterPointSize, 48)
    }

    func testAppLanguageMapsToJapaneseAndEnglishLocales() {
        XCTAssertEqual(AppLanguage.japanese.locale.identifier, "ja")
        XCTAssertEqual(AppLanguage.english.locale.identifier, "en")
    }

    func testAppSettingsSelectionUsesStableIDWhenRecordsAreDuplicated() throws {
        let lowerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let higherID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let lower = AppSettings(id: lowerID, language: AppLanguage.japanese.rawValue)
        let higher = AppSettings(id: higherID, language: AppLanguage.english.rawValue)

        XCTAssertEqual(AppSettingsOrdering.primary(in: [higher, lower])?.id, lowerID)
        XCTAssertEqual(AppSettingsOrdering.primary(in: [higher, lower])?.language, AppLanguage.japanese.rawValue)
        XCTAssertNil(AppSettingsOrdering.primary(in: []))
    }

    func testAppLanguageFallsBackToSystemForMissingOrUnknownPreference() {
        XCTAssertEqual(AppLanguage.resolve(nil), .system)
        XCTAssertEqual(AppLanguage.resolve("unsupported"), .system)
        XCTAssertEqual(AppLanguage.resolve(AppLanguage.japanese.rawValue), .japanese)
    }

    func testAppSettingsServicePersistsLanguageChanges() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let settings = AppSettings(language: AppLanguage.japanese.rawValue)
        context.insert(settings)
        try context.save()

        try AppSettingsService(modelContext: context).setLanguage(.english, for: settings)

        XCTAssertEqual(settings.language, AppLanguage.english.rawValue)
        XCTAssertEqual(AppLanguage.resolve(settings.language), .english)
        XCTAssertEqual(AppLanguage.resolve(settings.language).locale.identifier, "en")
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettings>()).first?.language, AppLanguage.english.rawValue)
    }

    func testAppSettingsServiceRestoresLanguageWhenSaveFails() throws {
        let container = try makeContainer(allowsSave: false)
        let context = ModelContext(container)
        let settings = AppSettings(language: AppLanguage.japanese.rawValue)
        context.insert(settings)

        XCTAssertThrowsError(try AppSettingsService(modelContext: context).setLanguage(.english, for: settings))

        XCTAssertEqual(settings.language, AppLanguage.japanese.rawValue)
    }

    func testNoOpSettingsChangesDoNotRequireStoreWrites() throws {
        let container = try makeContainer(allowsSave: false)
        let context = ModelContext(container)
        let session = ProductionSession(name: "Test", targetCount: 600)
        let settings = AppSettings(language: AppLanguage.system.rawValue)
        context.insert(session)
        context.insert(settings)

        try CounterService(modelContext: context).setTarget(600, for: session)
        try AppSettingsService(modelContext: context).setLanguage(.system, for: settings)

        XCTAssertEqual(session.targetCount, 600)
        XCTAssertEqual(settings.language, AppLanguage.system.rawValue)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProductionSession>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettings>()).count, 1)
    }

    func testBlankHomeNameReturnsToLocalizedDefaultState() {
        let defaultName = HomeNameResolution.resolve("  \n ")
        XCTAssertEqual(defaultName.name, "Production")
        XCTAssertTrue(defaultName.usesDefaultName)

        let customName = HomeNameResolution.resolve(" Assembly Line \n")
        XCTAssertEqual(customName.name, "Assembly Line")
        XCTAssertFalse(customName.usesDefaultName)
    }

    func testDefaultProductionSessionNameUsesSelectedLocale() {
        XCTAssertEqual(
            String(localized: LocalizedStringResource("counter.defaultSessionName", locale: AppLanguage.japanese.locale)),
            "生産セッション"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("counter.defaultSessionName", locale: AppLanguage.english.locale)),
            "Production run"
        )
    }

    func testCardSizeLabelsResolveInJapaneseAndEnglish() {
        XCTAssertEqual(
            String(localized: LocalizedStringResource("card.size.small", locale: AppLanguage.english.locale)),
            "Small"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("card.size.small", locale: AppLanguage.japanese.locale)),
            "小"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("card.size.medium", locale: AppLanguage.english.locale)),
            "Medium"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("card.size.medium", locale: AppLanguage.japanese.locale)),
            "中"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("card.size.large", locale: AppLanguage.english.locale)),
            "Large"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("card.size.large", locale: AppLanguage.japanese.locale)),
            "大"
        )
    }

    func testCounterAccessibilityLabelResolvesInJapaneseAndEnglish() {
        XCTAssertEqual(
            String(localized: LocalizedStringResource("counter.currentCount", locale: AppLanguage.english.locale)),
            "Current count"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("counter.currentCount", locale: AppLanguage.japanese.locale)),
            "現在のカウント"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("counter.goal", locale: AppLanguage.english.locale)),
            "Target count"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("counter.goal", locale: AppLanguage.japanese.locale)),
            "目標数"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("counter.progress", locale: AppLanguage.english.locale)),
            "Progress toward target"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("counter.progress", locale: AppLanguage.japanese.locale)),
            "目標への進捗"
        )
    }

    func testHomeManagementAccessibilityLabelsNameTheTargetInBothLanguages() {
        let homeName = "Assembly"
        XCTAssertEqual(
            String(localized: LocalizedStringResource(
                String.LocalizationValue("home.renameNamed \(homeName)"),
                locale: AppLanguage.english.locale
            )),
            "Rename Assembly"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource(
                String.LocalizationValue("home.renameNamed \(homeName)"),
                locale: AppLanguage.japanese.locale
            )),
            "Assemblyの名前を変更"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource(
                String.LocalizationValue("home.moveEarlierNamed \(homeName)"),
                locale: AppLanguage.english.locale
            )),
            "Move Assembly earlier"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource(
                String.LocalizationValue("home.moveEarlierNamed \(homeName)"),
                locale: AppLanguage.japanese.locale
            )),
            "Assemblyを上へ移動"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource(
                String.LocalizationValue("home.moveLaterNamed \(homeName)"),
                locale: AppLanguage.english.locale
            )),
            "Move Assembly later"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource(
                String.LocalizationValue("home.moveLaterNamed \(homeName)"),
                locale: AppLanguage.japanese.locale
            )),
            "Assemblyを下へ移動"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource(
                String.LocalizationValue("home.deleteNamed \(homeName)"),
                locale: AppLanguage.english.locale
            )),
            "Delete Assembly"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource(
                String.LocalizationValue("home.deleteNamed \(homeName)"),
                locale: AppLanguage.japanese.locale
            )),
            "Assemblyを削除"
        )
        let localizedDefaultName = String(localized: LocalizedStringResource(
            "home.defaultName",
            locale: AppLanguage.japanese.locale
        ))
        XCTAssertEqual(
            String(localized: LocalizedStringResource(
                String.LocalizationValue("home.deleteNamed \(localizedDefaultName)"),
                locale: AppLanguage.japanese.locale
            )),
            "通常生産を削除"
        )
    }

    func testToolFormGuidanceIsLocalizedInJapaneseAndEnglish() {
        let guidance: [(String, String, String)] = [
            (
                "cycleTime.invalidInput",
                "Enter positive whole numbers for both inputs.",
                "両方の項目に1以上の整数を入力してください。"
            ),
            (
                "taktTime.invalidInput",
                "Enter positive whole numbers for both inputs.",
                "両方の項目に1以上の整数を入力してください。"
            ),
            (
                "oee.invalidInput",
                "Enter a positive planned time and ideal cycle time, downtime below planned time, nonnegative counts, and at least one unit.",
                "計画時間と理想サイクルタイムは1以上、停止時間は計画時間未満、数量は0以上で合計1個以上を入力してください。"
            ),
            (
                "boxCalculator.enterDimensions",
                "Enter all six dimensions to see the result.",
                "計算結果を見るには6つの寸法を入力してください。"
            ),
            (
                "boxCalculator.noFit",
                "Enter positive whole-number dimensions and make sure the item fits in at least one orientation.",
                "寸法に1以上の整数を入力し、品物がいずれかの向きで箱に入ることを確認してください。"
            ),
            (
                "unitConverter.invalidInput",
                "Use a valid number. Length, mass, and volume must be nonnegative; temperature must be at or above absolute zero.",
                "有効な数値を入力してください。長さ・質量・体積は0以上、温度は絶対零度以上で入力します。"
            )
        ]

        for (key, english, japanese) in guidance {
            XCTAssertEqual(
                String(localized: LocalizedStringResource(
                    String.LocalizationValue(stringLiteral: key),
                    locale: AppLanguage.english.locale
                )),
                english,
                "Unexpected English guidance for \(key)"
            )
            XCTAssertEqual(
                String(localized: LocalizedStringResource(
                    String.LocalizationValue(stringLiteral: key),
                    locale: AppLanguage.japanese.locale
                )),
                japanese,
                "Unexpected Japanese guidance for \(key)"
            )
        }
    }

    func testHistoryDeletionAccessibilityLabelsIdentifyTheRecordInBothLanguages() {
        let timestamp = "Nov 2, 2026"
        XCTAssertEqual(
            String(localized: LocalizedStringResource(
                String.LocalizationValue("cycleTime.removeSampleNamed \(timestamp)"),
                locale: AppLanguage.english.locale
            )),
            "Delete Cycle Time sample from Nov 2, 2026"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource(
                String.LocalizationValue("cycleTime.removeSampleNamed \(timestamp)"),
                locale: AppLanguage.japanese.locale
            )),
            "Nov 2, 2026のサイクルタイム記録を削除"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource(
                String.LocalizationValue("oee.removeRunNamed \(timestamp)"),
                locale: AppLanguage.english.locale
            )),
            "Delete OEE result from Nov 2, 2026"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource(
                String.LocalizationValue("oee.removeRunNamed \(timestamp)"),
                locale: AppLanguage.japanese.locale
            )),
            "Nov 2, 2026のOEE結果を削除"
        )
    }

    func testEmptyHomeGuidanceIsLocalizedInJapaneseAndEnglish() {
        XCTAssertEqual(
            String(localized: LocalizedStringResource("home.empty.title", locale: AppLanguage.english.locale)),
            "Build your home"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("home.empty.title", locale: AppLanguage.japanese.locale)),
            "ホームを作成しましょう"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("home.empty.message", locale: AppLanguage.english.locale)),
            "Add a tool to make this space yours."
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("home.empty.message", locale: AppLanguage.japanese.locale)),
            "ツールを追加して、使いやすいホームを作成できます。"
        )
    }

    func testSaveFailureMessageIsLocalizedInJapaneseAndEnglish() {
        XCTAssertEqual(
            String(localized: LocalizedStringResource("error.saveMessage", locale: AppLanguage.english.locale)),
            "Please try again."
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("error.saveMessage", locale: AppLanguage.japanese.locale)),
            "もう一度お試しください。"
        )
    }

    func testOversizedBackupMessageIsLocalizedInJapaneseAndEnglish() {
        XCTAssertTrue(
            String(localized: LocalizedStringResource("settings.backup.description", locale: AppLanguage.english.locale))
                .contains("64 MiB and 500,000 records")
        )
        XCTAssertTrue(
            String(localized: LocalizedStringResource("settings.backup.description", locale: AppLanguage.japanese.locale))
                .contains("64 MiBまたは50万件")
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("settings.backup.tooLarge", locale: AppLanguage.english.locale)),
            "This backup exceeds the 64 MiB or 500,000-record limit. Choose a smaller backup."
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("settings.backup.tooLarge", locale: AppLanguage.japanese.locale)),
            "バックアップが64 MiBまたは50万件の上限を超えています。より小さいファイルを選んでください。"
        )
    }

    func testHistoryDeleteConfirmationsAreLocalizedInJapaneseAndEnglish() {
        XCTAssertEqual(
            String(localized: LocalizedStringResource("cycleTime.deleteConfirmation.title", locale: AppLanguage.english.locale)),
            "Delete this Cycle Time sample?"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("cycleTime.deleteConfirmation.title", locale: AppLanguage.japanese.locale)),
            "このサイクルタイムの計算例を削除しますか？"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("cycleTime.deleteConfirmation.message", locale: AppLanguage.english.locale)),
            "This saved sample will be removed from this home."
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("cycleTime.deleteConfirmation.message", locale: AppLanguage.japanese.locale)),
            "保存した計算例をこのホームから削除します。"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("oee.deleteConfirmation.title", locale: AppLanguage.english.locale)),
            "Delete this OEE run?"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("oee.deleteConfirmation.title", locale: AppLanguage.japanese.locale)),
            "このOEE記録を削除しますか？"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("oee.deleteConfirmation.message", locale: AppLanguage.english.locale)),
            "This saved run will be removed from this home."
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("oee.deleteConfirmation.message", locale: AppLanguage.japanese.locale)),
            "保存した記録をこのホームから削除します。"
        )
    }

    func testInvalidCounterEventMessageIsLocalizedInJapaneseAndEnglish() {
        XCTAssertEqual(
            String(localized: LocalizedStringResource("error.counterEventInvalid", locale: AppLanguage.english.locale)),
            "The previous count change can’t be undone."
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("error.counterEventInvalid", locale: AppLanguage.japanese.locale)),
            "直前のカウント記録を取り消せません。"
        )
    }

    func testCounterHistoryCorruptionGuidanceIsLocalizedInJapaneseAndEnglish() {
        XCTAssertEqual(
            String(localized: LocalizedStringResource("counter.history.balanceUnavailable", locale: AppLanguage.english.locale)),
            "Balances are hidden because this history is inconsistent."
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("counter.history.balanceUnavailable", locale: AppLanguage.japanese.locale)),
            "履歴に不整合があるため、操作後の残高を表示できません。"
        )
    }

    func testHomeGridAdaptsColumnCountAndKeepsLargeCardsFullWidth() {
        XCTAssertEqual(HomeGridLayout.maximumContentWidth, 1020)
        XCTAssertEqual(HomeGridLayout.minimumColumnWidth(isAccessibilitySize: false), 160)
        XCTAssertEqual(HomeGridLayout.minimumColumnWidth(isAccessibilitySize: true), 280)
        XCTAssertTrue(HomeGridLayout.rows(for: [], columnCount: 2).isEmpty)
        XCTAssertEqual(HomeGridLayout.columnCount(availableWidth: 284, minimumColumnWidth: 160, spacing: 14), 1)
        XCTAssertEqual(HomeGridLayout.columnCount(availableWidth: 354, minimumColumnWidth: 160, spacing: 14), 2)
        XCTAssertEqual(HomeGridLayout.columnCount(availableWidth: 724, minimumColumnWidth: 160, spacing: 14), 4)
        XCTAssertEqual(HomeGridLayout.columnCount(availableWidth: 984, minimumColumnWidth: 160, spacing: 14), 5)
        XCTAssertEqual(HomeGridLayout.columnCount(availableWidth: 724, minimumColumnWidth: 280, spacing: 14), 2)
        XCTAssertEqual(HomeGridLayout.columnCount(availableWidth: .greatestFiniteMagnitude, minimumColumnWidth: 160, spacing: 14), 5)
        XCTAssertEqual(HomeGridLayout.columnCount(availableWidth: .infinity, minimumColumnWidth: 160, spacing: 14), 1)
        XCTAssertEqual(HomeGridLayout.columnCount(availableWidth: .nan, minimumColumnWidth: 160, spacing: 14), 1)
        XCTAssertEqual(HomeGridLayout.columnCount(availableWidth: 1_020, minimumColumnWidth: .leastNonzeroMagnitude, spacing: 0), 5)

        let homeID = UUID()
        let firstSmall = ToolCard(homeProfileID: homeID, toolID: .productionCounter, size: .small, sortOrder: 0)
        let large = ToolCard(homeProfileID: homeID, toolID: .productionCounter, size: .large, sortOrder: 1)
        let medium = ToolCard(homeProfileID: homeID, toolID: .productionCounter, size: .medium, sortOrder: 2)
        let lastSmall = ToolCard(homeProfileID: homeID, toolID: .productionCounter, size: .small, sortOrder: 3)

        let rows = HomeGridLayout.rows(for: [firstSmall, large, medium, lastSmall], columnCount: 2)

        XCTAssertEqual(rows.map { $0.cards.map(\.id) }, [[firstSmall.id], [large.id], [medium.id, lastSmall.id]])
        XCTAssertEqual(rows.map(\.id), [firstSmall.id, large.id, medium.id])
        XCTAssertEqual(rows.map(\.isFullWidth), [false, true, false])
        let narrowRows = HomeGridLayout.rows(for: [firstSmall, medium, large], columnCount: 1)
        XCTAssertEqual(narrowRows.map { $0.cards.map(\.id) }, [[firstSmall.id], [medium.id], [large.id]])
        XCTAssertEqual(narrowRows.map(\.isFullWidth), [false, false, true])
        let noColumnRows = HomeGridLayout.rows(for: [firstSmall, medium], columnCount: 0)
        XCTAssertEqual(noColumnRows.map { $0.cards.map(\.id) }, [[firstSmall.id], [medium.id]])
    }

    func testCardSizePresentationAddsSpaceAndInformationForLargerCards() {
        XCTAssertEqual(HomeCardPresentation.minimumHeight(for: .small), 146)
        XCTAssertEqual(HomeCardPresentation.minimumHeight(for: .medium), 184)
        XCTAssertEqual(HomeCardPresentation.minimumHeight(for: .large), 232)
        XCTAssertEqual(HomeCardPresentation.showsSessionLabel(for: .small), false)
        XCTAssertEqual(HomeCardPresentation.showsSessionLabel(for: .medium), true)
        XCTAssertEqual(HomeCardPresentation.showsTarget(for: .small), false)
        XCTAssertEqual(HomeCardPresentation.showsTarget(for: .medium), true)
        XCTAssertEqual(HomeCardPresentation.showsProgress(for: .medium), false)
        XCTAssertEqual(HomeCardPresentation.showsProgress(for: .large), true)
        XCTAssertEqual(HomeCardPresentation.minimumActionWidth, 44)
        XCTAssertEqual(HomeCardPresentation.actionSpacing, 2)
        XCTAssertEqual(HomeCardPresentation.padding(for: .medium), HomeCardPresentation.padding(for: .small))
        XCTAssertGreaterThan(HomeCardPresentation.padding(for: .large), HomeCardPresentation.padding(for: .medium))
        let mediumCardContentWidth = HomeGridLayout.minimumColumnWidth(isAccessibilitySize: false)
            - HomeCardPresentation.padding(for: .medium) * 2
        let minimumCounterActionsWidth = HomeCardPresentation.minimumActionWidth * 3
            + HomeCardPresentation.actionSpacing * 2
        XCTAssertGreaterThanOrEqual(mediumCardContentWidth, minimumCounterActionsWidth)
    }

    func testProgressFractionIsSafeForZeroAndSaturatedTargets() {
        XCTAssertEqual(ProductionProgressMath.fraction(currentCount: 25, targetCount: 100), 0.25)
        XCTAssertEqual(ProductionProgressMath.fraction(currentCount: 150, targetCount: 100), 1)
        XCTAssertEqual(ProductionProgressMath.fraction(currentCount: -5, targetCount: 100), 0)
        XCTAssertEqual(ProductionProgressMath.fraction(currentCount: 25, targetCount: 0), 0)
        XCTAssertEqual(ProductionProgressMath.fraction(currentCount: 25, targetCount: -10), 0)
        XCTAssertEqual(
            HomeCardPresentation.formattedProgress(currentCount: 1, targetCount: 600, locale: Locale(identifier: "en_US")),
            "0.2%"
        )
    }

    func testToolIdentifiersAreStableAndCounterSupportsEveryCardSize() {
        XCTAssertEqual(ToolID.productionCounter.rawValue, "production.counter")
        let counter = ToolRegistry.definition(for: .productionCounter)
        XCTAssertTrue(counter?.isAvailable == true)
        XCTAssertEqual(counter?.supportedCardSizes, Set(ToolCardSize.allCases))
    }

    func testToolRegistrySearchUsesLocalizedNamesStableIDsAndCategories() {
        let japanese = Locale(identifier: "ja")
        let english = Locale(identifier: "en")
        XCTAssertEqual(ToolRegistry.matching("生産カウンター", locale: japanese).map(\.id), [.productionCounter])
        XCTAssertEqual(ToolRegistry.matching("production counter", locale: english).map(\.id), [.productionCounter])
        XCTAssertEqual(ToolRegistry.matching("production counter", locale: japanese).map(\.id), [.productionCounter])
        XCTAssertEqual(ToolRegistry.matching("生産カウンター", locale: english).map(\.id), [.productionCounter])
        XCTAssertEqual(ToolRegistry.matching("production.cycleTime", locale: english).map(\.id), [.cycleTime])
        XCTAssertEqual(ToolRegistry.matching("quality", locale: english).map(\.id), [.defectCounter, .defectRate])
        XCTAssertEqual(ToolRegistry.matching("Quality", locale: japanese).map(\.id), [.defectCounter, .defectRate])
        XCTAssertEqual(ToolRegistry.matching("品質", locale: english).map(\.id), [.defectCounter, .defectRate])
        XCTAssertEqual(
            ToolRegistry.matching("", category: .quality, locale: japanese).map(\.id),
            [.defectCounter, .defectRate]
        )
        XCTAssertTrue(ToolRegistry.matching("no such tool", locale: english).isEmpty)
    }

    func testCycleTimeUsesTotalSecondsPerProducedUnit() {
        XCTAssertEqual(CycleTimeCalculator.secondsPerUnit(totalSeconds: 180, quantity: 12), 15)
        XCTAssertEqual(CycleTimeCalculator.secondsPerUnit(totalSeconds: 90, quantity: 4), 22.5)
        XCTAssertNil(CycleTimeCalculator.secondsPerUnit(totalSeconds: 0, quantity: 1))
        XCTAssertNil(CycleTimeCalculator.secondsPerUnit(totalSeconds: 10, quantity: 0))
        XCTAssertNil(CycleTimeCalculator.secondsPerUnit(totalSeconds: -1, quantity: 2))
        XCTAssertNil(CycleTimeCalculator.secondsPerUnit(totalSeconds: 10, quantity: -2))
    }

    func testCycleTimeHistorySummaryCalculatesLatestAverageBestAndChange() throws {
        let earlierDate = Date(timeIntervalSince1970: 1_700_000_000)
        let latestDate = Date(timeIntervalSince1970: 1_700_000_100)
        let points = [
            CycleTimeHistoryPoint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, createdAt: earlierDate, secondsPerUnit: 8),
            CycleTimeHistoryPoint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, createdAt: latestDate, secondsPerUnit: 18),
            CycleTimeHistoryPoint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, createdAt: latestDate, secondsPerUnit: 12)
        ]

        let summary = try XCTUnwrap(CycleTimeHistoryMath.summary(from: points))
        XCTAssertEqual(summary.sampleCount, 3)
        XCTAssertEqual(summary.latestSecondsPerUnit, 12)
        XCTAssertEqual(summary.averageSecondsPerUnit, 38.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(summary.bestSecondsPerUnit, 8)
        XCTAssertEqual(summary.changeFromPrevious, -6)
    }

    func testCycleTimeHistorySummaryIgnoresInvalidAndNonpositiveSamples() {
        XCTAssertNil(CycleTimeHistoryMath.summary(from: [
            CycleTimeHistoryPoint(id: UUID(), createdAt: .now, secondsPerUnit: .nan),
            CycleTimeHistoryPoint(id: UUID(), createdAt: .now, secondsPerUnit: .infinity),
            CycleTimeHistoryPoint(id: UUID(), createdAt: .now, secondsPerUnit: 0)
        ]))
    }

    func testCycleTimeHistoryPeriodIncludesCalendarBoundaryAndExcludesFutureSamples() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 2, day: 1, hour: 12)))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 1, day: 26)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 2, day: 2)))
        let laterToday = now.addingTimeInterval(60 * 60)
        let points = [
            CycleTimeHistoryPoint(id: UUID(), createdAt: start.addingTimeInterval(-1), secondsPerUnit: 11),
            CycleTimeHistoryPoint(id: UUID(), createdAt: start, secondsPerUnit: 12),
            CycleTimeHistoryPoint(id: UUID(), createdAt: now, secondsPerUnit: 13),
            CycleTimeHistoryPoint(id: UUID(), createdAt: laterToday, secondsPerUnit: 14),
            CycleTimeHistoryPoint(id: UUID(), createdAt: end, secondsPerUnit: 14)
        ]

        let filtered = CycleTimeHistoryMath.points(points, within: .days7, asOf: now, calendar: calendar)
        XCTAssertEqual(filtered.map(\.secondsPerUnit), [12, 13])
    }

    func testCycleTimeHistoryPeriodUsesCalendarArithmeticAcrossDaylightSavingChange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 12)))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 3, day: 4)))
        let nextDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 3, day: 11)))
        let points = [
            CycleTimeHistoryPoint(id: UUID(), createdAt: start.addingTimeInterval(-1), secondsPerUnit: 10),
            CycleTimeHistoryPoint(id: UUID(), createdAt: start, secondsPerUnit: 12),
            CycleTimeHistoryPoint(id: UUID(), createdAt: now, secondsPerUnit: 14),
            CycleTimeHistoryPoint(id: UUID(), createdAt: nextDay, secondsPerUnit: 16)
        ]

        let filtered = CycleTimeHistoryMath.points(points, within: .days7, asOf: now, calendar: calendar)
        XCTAssertEqual(filtered.map(\.secondsPerUnit), [12, 14])
    }

    func testOEECalculatorReturnsAvailabilityPerformanceQualityAndOverall() throws {
        let result = try XCTUnwrap(OEECalculator.calculate(
            plannedProductionMinutes: 100,
            downtimeMinutes: 20,
            idealCycleTimeSeconds: 2,
            goodUnits: 1_080,
            defectiveUnits: 120
        ))

        XCTAssertEqual(result.availability, 0.8, accuracy: 0.000_001)
        XCTAssertEqual(result.performance, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(result.quality, 0.9, accuracy: 0.000_001)
        XCTAssertEqual(result.overall, 0.36, accuracy: 0.000_001)
    }

    func testOEECalculatorRejectsInvalidInputsAndReportsUncappedPerformance() throws {
        XCTAssertNil(OEECalculator.calculate(plannedProductionMinutes: 0, downtimeMinutes: 0, idealCycleTimeSeconds: 1, goodUnits: 1, defectiveUnits: 0))
        XCTAssertNil(OEECalculator.calculate(plannedProductionMinutes: 10, downtimeMinutes: 10, idealCycleTimeSeconds: 1, goodUnits: 1, defectiveUnits: 0))
        XCTAssertNil(OEECalculator.calculate(plannedProductionMinutes: 10, downtimeMinutes: -1, idealCycleTimeSeconds: 1, goodUnits: 1, defectiveUnits: 0))
        XCTAssertNil(OEECalculator.calculate(plannedProductionMinutes: 10, downtimeMinutes: 0, idealCycleTimeSeconds: 0, goodUnits: 1, defectiveUnits: 0))
        XCTAssertNil(OEECalculator.calculate(plannedProductionMinutes: 10, downtimeMinutes: 0, idealCycleTimeSeconds: 1, goodUnits: -1, defectiveUnits: 0))
        XCTAssertNil(OEECalculator.calculate(plannedProductionMinutes: 10, downtimeMinutes: 0, idealCycleTimeSeconds: 1, goodUnits: 0, defectiveUnits: 0))
        XCTAssertNil(OEECalculator.calculate(plannedProductionMinutes: 10, downtimeMinutes: 0, idealCycleTimeSeconds: 1, goodUnits: Int.max, defectiveUnits: 1))

        let largeFiniteResult = OEECalculator.calculate(
            plannedProductionMinutes: Int.max,
            downtimeMinutes: Int.max - 1,
            idealCycleTimeSeconds: Int.max,
            goodUnits: Int.max,
            defectiveUnits: 0
        )
        XCTAssertTrue(largeFiniteResult?.overall.isFinite == true)

        let fastOutput = try XCTUnwrap(OEECalculator.calculate(
            plannedProductionMinutes: 60,
            downtimeMinutes: 0,
            idealCycleTimeSeconds: 100,
            goodUnits: 60,
            defectiveUnits: 0
        ))
        XCTAssertEqual(fastOutput.performance, 100.0 / 60.0, accuracy: 0.000_001)
        XCTAssertGreaterThan(fastOutput.overall, 1)
    }

    func testOEEToolIsAvailableAsAMediumOrLargeProductionCard() throws {
        let definition = try XCTUnwrap(ToolRegistry.definition(for: .oee))

        XCTAssertEqual(ToolID.oee.rawValue, "production.oee")
        XCTAssertEqual(definition.category, .production)
        XCTAssertEqual(definition.titleKey, "tool.oee.title")
        XCTAssertTrue(definition.isAvailable)
        XCTAssertEqual(definition.supportedCardSizes, [.medium, .large])
    }

    func testOEERunServiceRejectsFreeSaveThroughFeatureAccessRegistry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Packaging", sortOrder: 0)
        context.insert(home)
        try context.save()

        XCTAssertThrowsError(try OEERunService(modelContext: context).save(
            plannedProductionMinutes: 60,
            downtimeMinutes: 0,
            idealCycleTimeSeconds: 10,
            goodUnits: 300,
            defectiveUnits: 0,
            for: home.id
        )) { error in
            XCTAssertEqual(error as? OEERunServiceError, .proRequired)
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<OEERun>()).isEmpty)
    }

    func testOEERunServiceSavesHomeScopedResults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Packaging", sortOrder: 0)
        let otherHome = HomeProfile(name: "Assembly", sortOrder: 1)
        context.insert(home)
        context.insert(otherHome)
        try context.save()
        let createdAt = Date(timeIntervalSince1970: 1_900_000_000)

        let run = try OEERunService(modelContext: context).save(
            plannedProductionMinutes: 100,
            downtimeMinutes: 20,
            idealCycleTimeSeconds: 2,
            goodUnits: 1_080,
            defectiveUnits: 120,
            for: home.id,
            createdAt: createdAt,
            isPro: true
        )

        XCTAssertEqual(run.homeProfileID, home.id)
        XCTAssertEqual(run.createdAt, createdAt)
        XCTAssertEqual(run.calculation?.overall ?? -1, 0.36, accuracy: 0.000_001)
        XCTAssertTrue(try context.fetch(FetchDescriptor<OEERun>()).allSatisfy { $0.homeProfileID == home.id })
        XCTAssertNotEqual(run.homeProfileID, otherHome.id)
        try OEERunService(modelContext: context).delete(run, from: home.id)
        XCTAssertTrue(try context.fetch(FetchDescriptor<OEERun>()).isEmpty)
    }

    func testOEERunServiceRejectsInvalidInputMissingHomeAndCrossHomeDelete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Packaging", sortOrder: 0)
        let otherHome = HomeProfile(name: "Assembly", sortOrder: 1)
        context.insert(home)
        context.insert(otherHome)
        try context.save()
        let service = OEERunService(modelContext: context)

        XCTAssertThrowsError(try service.save(
            plannedProductionMinutes: 10,
            downtimeMinutes: 10,
            idealCycleTimeSeconds: 1,
            goodUnits: 1,
            defectiveUnits: 0,
            for: home.id,
            isPro: true
        )) { XCTAssertEqual($0 as? OEERunServiceError, .invalidInput) }
        XCTAssertThrowsError(try service.save(
            plannedProductionMinutes: 10,
            downtimeMinutes: 0,
            idealCycleTimeSeconds: 1,
            goodUnits: 1,
            defectiveUnits: 0,
            for: UUID(),
            isPro: true
        )) { XCTAssertEqual($0 as? OEERunServiceError, .homeNotFound) }

        let run = try service.save(
            plannedProductionMinutes: 10,
            downtimeMinutes: 0,
            idealCycleTimeSeconds: 1,
            goodUnits: 1,
            defectiveUnits: 0,
            for: home.id,
            isPro: true
        )
        XCTAssertThrowsError(try service.delete(run, from: otherHome.id)) {
            XCTAssertEqual($0 as? OEERunServiceError, .wrongHome)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<OEERun>()).count, 1)
    }

    func testOEERunServiceRollsBackWhenSaveFails() throws {
        let home = HomeProfile(name: "Packaging", sortOrder: 0)
        let container = try makeContainer(allowsSave: false) { $0.insert(home) }
        let context = ModelContext(container)

        XCTAssertThrowsError(try OEERunService(modelContext: context).save(
            plannedProductionMinutes: 10,
            downtimeMinutes: 0,
            idealCycleTimeSeconds: 1,
            goodUnits: 1,
            defectiveUnits: 0,
            for: home.id,
            isPro: true
        ))
        let verificationContext = ModelContext(container)
        XCTAssertTrue(try verificationContext.fetch(FetchDescriptor<OEERun>()).isEmpty)
        XCTAssertEqual(try verificationContext.fetch(FetchDescriptor<HomeProfile>()).map(\.id), [home.id])
    }

    func testPersistentStoreRestoresOEERunHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("FactoryTools.store")
        let schema = Schema([HomeProfile.self, OEERun.self])
        let configuration = ModelConfiguration("OEERunPersistence", schema: schema, url: storeURL, allowsSave: true, cloudKitDatabase: .none)
        let homeID: UUID
        let runID: UUID

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let home = HomeProfile(name: "Packaging", sortOrder: 0)
            context.insert(home)
            try context.save()
            let run = try OEERunService(modelContext: context).save(
                plannedProductionMinutes: 480,
                downtimeMinutes: 30,
                idealCycleTimeSeconds: 8,
                goodUnits: 2_400,
                defectiveUnits: 50,
                for: home.id,
                createdAt: Date(timeIntervalSince1970: 1_900_000_000),
                isPro: true
            )
            homeID = home.id
            runID = run.id
        }

        do {
            let reopened = try ModelContainer(for: schema, configurations: [configuration])
            let runs = try ModelContext(reopened).fetch(FetchDescriptor<OEERun>())
            let restored = try XCTUnwrap(runs.first)
            XCTAssertEqual(restored.id, runID)
            XCTAssertEqual(restored.homeProfileID, homeID)
            XCTAssertEqual(restored.plannedProductionMinutes, 480)
            XCTAssertEqual(restored.downtimeMinutes, 30)
            XCTAssertEqual(restored.goodUnits, 2_400)
            XCTAssertEqual(restored.defectiveUnits, 50)
            XCTAssertNotNil(restored.calculation)
        }
    }

    func testOEEHistorySummaryCalculatesLatestAverageBestAndChange() throws {
        let firstID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let thirdID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let now = Date(timeIntervalSince1970: 2_000)

        let summary = try XCTUnwrap(OEEHistoryMath.summary(from: [
            OEEHistoryPoint(id: firstID, createdAt: now.addingTimeInterval(-60), overall: 0.2),
            OEEHistoryPoint(id: secondID, createdAt: now, overall: 0.6),
            OEEHistoryPoint(id: thirdID, createdAt: now.addingTimeInterval(-30), overall: 0.4)
        ]))

        XCTAssertEqual(summary.runCount, 3)
        XCTAssertEqual(summary.latestOverall, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(summary.averageOverall, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(summary.bestOverall, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(summary.changeFromPrevious ?? -1, 0.2, accuracy: 0.000_001)
    }

    func testOEEHistorySummaryUsesStableIDForTiedTimesAndPreservesOver100Percent() throws {
        let lowerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let higherID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let date = Date(timeIntervalSince1970: 2_000)

        let summary = try XCTUnwrap(OEEHistoryMath.summary(from: [
            OEEHistoryPoint(id: higherID, createdAt: date, overall: 0.8),
            OEEHistoryPoint(id: lowerID, createdAt: date, overall: 1.2),
            OEEHistoryPoint(id: UUID(), createdAt: date, overall: .nan)
        ]))

        XCTAssertEqual(summary.runCount, 2)
        XCTAssertEqual(summary.latestOverall, 1.2, accuracy: 0.000_001)
        XCTAssertEqual(summary.averageOverall, 1.0, accuracy: 0.000_001)
        XCTAssertEqual(summary.bestOverall, 1.2, accuracy: 0.000_001)
        XCTAssertEqual(summary.changeFromPrevious ?? -1, 0.4, accuracy: 0.000_001)
    }

    func testOEEHistorySummaryReturnsNilWithoutFiniteResults() {
        XCTAssertNil(OEEHistoryMath.summary(from: [
            OEEHistoryPoint(id: UUID(), createdAt: .now, overall: .infinity),
            OEEHistoryPoint(id: UUID(), createdAt: .now, overall: .nan)
        ]))
    }

    func testOEEHistoryCSVIsDeterministicUTCAndHomeScoped() {
        let homeID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let otherHomeID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let first = OEERun(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            homeProfileID: homeID,
            plannedProductionMinutes: 100,
            downtimeMinutes: 20,
            idealCycleTimeSeconds: 2,
            goodUnits: 1_080,
            defectiveUnits: 120,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let second = OEERun(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
            homeProfileID: homeID,
            plannedProductionMinutes: 60,
            downtimeMinutes: 0,
            idealCycleTimeSeconds: 1,
            goodUnits: 3_000,
            defectiveUnits: 0,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let otherHomeRun = OEERun(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
            homeProfileID: otherHomeID,
            plannedProductionMinutes: 60,
            downtimeMinutes: 0,
            idealCycleTimeSeconds: 1,
            goodUnits: 3_000,
            defectiveUnits: 0
        )

        let csv = OEEHistoryCSV.make(homeID: homeID, runs: [second, otherHomeRun, first])
        let firstRow = csv.range(of: first.id.uuidString)!.lowerBound
        let secondRow = csv.range(of: second.id.uuidString)!.lowerBound

        XCTAssertTrue(csv.hasPrefix("home_id,run_id,recorded_at_utc,planned_production_minutes"))
        XCTAssertTrue(csv.contains("1970-01-01T00:00:01.000Z"))
        XCTAssertTrue(csv.contains(",0.8,0.5,0.9,0.36\r\n"))
        XCTAssertFalse(csv.contains(otherHomeRun.id.uuidString))
        XCTAssertLessThan(firstRow, secondRow)
        XCTAssertEqual(csv, OEEHistoryCSV.make(homeID: homeID, runs: [first, second]))
        XCTAssertEqual(csv, OEEHistoryCSV.make(homeID: homeID, records: [second, otherHomeRun, first].map(OEECSVRecord.init)))

        let overflowingRecord = OEECSVRecord(OEERun(
            homeProfileID: homeID,
            plannedProductionMinutes: 1,
            downtimeMinutes: 0,
            idealCycleTimeSeconds: 1,
            goodUnits: Int.max,
            defectiveUnits: 1,
            createdAt: Date(timeIntervalSince1970: 2_000)
        ))
        XCTAssertEqual(
            OEEHistoryCSV.make(homeID: homeID, records: [overflowingRecord]).components(separatedBy: "\r\n").filter { !$0.isEmpty }.count,
            1,
            "CSV must omit an invalid total-unit row instead of overflowing"
        )
    }

    func testCycleTimeHistoryCSVIsDeterministicUTCAndHomeScoped() {
        let homeID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let otherHomeID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let first = CycleTimeSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            homeProfileID: homeID,
            totalSeconds: 75,
            quantity: 5,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let tied = CycleTimeSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            homeProfileID: homeID,
            totalSeconds: 120,
            quantity: 4,
            createdAt: first.createdAt
        )
        let otherHome = CycleTimeSample(
            homeProfileID: otherHomeID,
            totalSeconds: 300,
            quantity: 10,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let csv = CycleTimeHistoryCSV.make(homeID: homeID, samples: [first, otherHome, tied])
        let rows = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], "home_id,sample_id,recorded_at_utc,total_seconds,quantity,seconds_per_unit")
        XCTAssertTrue(rows[1].contains(",00000000-0000-0000-0000-000000000010,"))
        XCTAssertTrue(rows[1].contains("2023-11-14T22:13:20.000Z"))
        XCTAssertTrue(rows[1].hasSuffix(",120,4,30.0"))
        XCTAssertTrue(rows[2].contains(",00000000-0000-0000-0000-000000000011,"))
        XCTAssertFalse(csv.contains(otherHomeID.uuidString))
        XCTAssertEqual(csv, CycleTimeHistoryCSV.make(homeID: homeID, samples: [tied, first]))
        XCTAssertEqual(csv, CycleTimeHistoryCSV.make(homeID: homeID, records: [first, otherHome, tied].map(CycleTimeCSVRecord.init)))
    }

    func testOEEHistoryPeriodIncludesCalendarBoundariesAndExcludesFutureEntries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let asOf = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 12)))
        let firstIncluded = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 0)))
        let justOutside = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 23, minute: 59)))
        let future = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 0)))
        let boundary = OEEHistoryPoint(id: UUID(), createdAt: firstIncluded, overall: 0.5)
        let old = OEEHistoryPoint(id: UUID(), createdAt: justOutside, overall: 0.7)
        let nextDay = OEEHistoryPoint(id: UUID(), createdAt: future, overall: 0.9)
        let laterToday = OEEHistoryPoint(id: UUID(), createdAt: asOf.addingTimeInterval(60 * 60), overall: 0.8)

        let lastSevenDays = OEEHistoryMath.points(
            [old, nextDay, boundary, laterToday],
            within: .days7,
            asOf: asOf,
            calendar: calendar
        )

        XCTAssertEqual(lastSevenDays, [boundary])
        XCTAssertEqual(
            OEEHistoryMath.points([old, nextDay, boundary, laterToday], within: .all, asOf: asOf, calendar: calendar),
            [old, nextDay, boundary, laterToday]
        )
    }

    func testOEEHistoryPeriodsUseCalendarArithmeticAcrossDaylightSavingChanges() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let asOf = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12)))
        let includedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 0)))
        let excludedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 3, hour: 23, minute: 59)))
        let included = OEEHistoryPoint(id: UUID(), createdAt: includedDate, overall: 0.4)
        let excluded = OEEHistoryPoint(id: UUID(), createdAt: excludedDate, overall: 0.3)

        XCTAssertEqual(
            OEEHistoryMath.points([excluded, included], within: .days7, asOf: asOf, calendar: calendar),
            [included]
        )
    }

    func testCycleTimeMeasurementRoundsToWholeSecondsAndRejectsInvalidTimes() {
        XCTAssertEqual(CycleTimeMeasurement.roundedWholeSeconds(from: 1.49), 1)
        XCTAssertEqual(CycleTimeMeasurement.roundedWholeSeconds(from: 1.5), 2)
        XCTAssertNil(CycleTimeMeasurement.roundedWholeSeconds(from: 0.49))
        XCTAssertNil(CycleTimeMeasurement.roundedWholeSeconds(from: 0))
        XCTAssertNil(CycleTimeMeasurement.roundedWholeSeconds(from: -1))
        XCTAssertNil(CycleTimeMeasurement.roundedWholeSeconds(from: .infinity))
        XCTAssertNil(CycleTimeMeasurement.roundedWholeSeconds(from: .nan))
        XCTAssertNil(CycleTimeMeasurement.roundedWholeSeconds(from: Double(Int.max)))
    }

    func testCycleTimeSampleServiceSavesAndDeletesHomeScopedSamples() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let otherHome = HomeProfile(name: "Quality", sortOrder: 1)
        context.insert(home)
        context.insert(otherHome)
        try context.save()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

        let sample = try CycleTimeSampleService(modelContext: context).save(
            totalSeconds: 180,
            quantity: 12,
            for: home.id,
            createdAt: createdAt
        )

        XCTAssertEqual(sample.homeProfileID, home.id)
        XCTAssertEqual(sample.totalSeconds, 180)
        XCTAssertEqual(sample.quantity, 12)
        XCTAssertEqual(sample.secondsPerUnit, 15)
        XCTAssertEqual(sample.createdAt, createdAt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CycleTimeSample>()).count, 1)

        XCTAssertThrowsError(try CycleTimeSampleService(modelContext: context).delete(sample, from: otherHome.id)) { error in
            XCTAssertEqual(error as? CycleTimeSampleServiceError, .wrongHome)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<CycleTimeSample>()).count, 1)

        try CycleTimeSampleService(modelContext: context).delete(sample, from: home.id)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CycleTimeSample>()).isEmpty)
    }

    func testCycleTimeSampleServiceRejectsInvalidValuesAndMissingHomes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        context.insert(home)
        try context.save()
        let service = CycleTimeSampleService(modelContext: context)

        for (totalSeconds, quantity) in [(0, 1), (10, 0), (-1, 2), (10, -2)] {
            XCTAssertThrowsError(try service.save(totalSeconds: totalSeconds, quantity: quantity, for: home.id)) { error in
                XCTAssertEqual(error as? CycleTimeSampleServiceError, .invalidInput)
            }
        }
        XCTAssertThrowsError(try service.save(totalSeconds: 10, quantity: 1, for: UUID())) { error in
            XCTAssertEqual(error as? CycleTimeSampleServiceError, .homeNotFound)
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<CycleTimeSample>()).isEmpty)
    }

    func testCycleTimeSampleSaveFailureRollsBackInsertedSample() throws {
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        let container = try makeContainer(allowsSave: false) { $0.insert(home) }
        let context = ModelContext(container)

        XCTAssertThrowsError(
            try CycleTimeSampleService(modelContext: context).save(
                totalSeconds: 180,
                quantity: 12,
                for: home.id
            )
        )

        let verificationContext = ModelContext(container)
        XCTAssertTrue(try verificationContext.fetch(FetchDescriptor<CycleTimeSample>()).isEmpty)
    }

    func testHistorySaveAndDeleteFailuresPreserveFileBackedRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("FactoryTools.store")
        let schema = Schema([HomeProfile.self, CycleTimeSample.self, OEERun.self])
        let writableConfiguration = ModelConfiguration(
            "HistoryRollback",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let homeID = UUID()
        let sampleID = UUID()
        let runID = UUID()
        do {
            let container = try ModelContainer(for: schema, configurations: [writableConfiguration])
            let context = ModelContext(container)
            context.insert(HomeProfile(id: homeID, name: "Assembly", sortOrder: 0))
            context.insert(CycleTimeSample(id: sampleID, homeProfileID: homeID, totalSeconds: 120, quantity: 2))
            context.insert(OEERun(
                id: runID,
                homeProfileID: homeID,
                plannedProductionMinutes: 60,
                downtimeMinutes: 5,
                idealCycleTimeSeconds: 10,
                goodUnits: 300,
                defectiveUnits: 10
            ))
            try context.save()
        }

        let readOnlyConfiguration = ModelConfiguration(
            "HistoryRollback",
            schema: schema,
            url: storeURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        let readOnlyContainer = try ModelContainer(for: schema, configurations: [readOnlyConfiguration])
        let context = ModelContext(readOnlyContainer)
        let sampleService = CycleTimeSampleService(modelContext: context)
        let runService = OEERunService(modelContext: context)
        XCTAssertThrowsError(try sampleService.save(totalSeconds: 60, quantity: 1, for: homeID))
        XCTAssertThrowsError(try runService.save(
            plannedProductionMinutes: 60,
            downtimeMinutes: 0,
            idealCycleTimeSeconds: 10,
            goodUnits: 300,
            defectiveUnits: 0,
            for: homeID,
            isPro: true
        ))

        let sample = try XCTUnwrap(context.fetch(FetchDescriptor<CycleTimeSample>()).first { $0.id == sampleID })
        let run = try XCTUnwrap(context.fetch(FetchDescriptor<OEERun>()).first { $0.id == runID })
        XCTAssertThrowsError(try sampleService.delete(sample, from: homeID))
        XCTAssertThrowsError(try runService.delete(run, from: homeID))
        let reopened = try ModelContainer(for: schema, configurations: [readOnlyConfiguration])
        let reopenedContext = ModelContext(reopened)
        XCTAssertEqual(try reopenedContext.fetch(FetchDescriptor<CycleTimeSample>()).map(\.id), [sampleID])
        XCTAssertEqual(try reopenedContext.fetch(FetchDescriptor<OEERun>()).map(\.id), [runID])
        XCTAssertEqual(try reopenedContext.fetch(FetchDescriptor<HomeProfile>()).map(\.id), [homeID])
    }

    func testCycleTimeToolIsAvailableWithoutCreatingCounterSession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        context.insert(home)
        try context.save()

        let cycleTime = try XCTUnwrap(ToolRegistry.definition(for: .cycleTime))
        XCTAssertTrue(cycleTime.isAvailable)
        let card = try HomeToolService(modelContext: context).add(
            cycleTime,
            to: home.id,
            locale: AppLanguage.english.locale
        )

        XCTAssertEqual(card.toolID, "production.cycleTime")
        XCTAssertNil(card.productionSessionID)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProductionSession>()).isEmpty)
    }

    func testTaktTimeUsesNetAvailableSecondsPerCustomerUnit() {
        XCTAssertEqual(TaktTimeCalculator.secondsPerUnit(netAvailableSeconds: 28_800, customerDemand: 480), 60.0)
        XCTAssertEqual(TaktTimeCalculator.secondsPerUnit(netAvailableSeconds: 90, customerDemand: 4), 22.5)
        XCTAssertNil(TaktTimeCalculator.secondsPerUnit(netAvailableSeconds: 0, customerDemand: 1))
        XCTAssertNil(TaktTimeCalculator.secondsPerUnit(netAvailableSeconds: 90, customerDemand: 0))
        XCTAssertNil(TaktTimeCalculator.secondsPerUnit(netAvailableSeconds: -1, customerDemand: 2))
        XCTAssertNil(TaktTimeCalculator.secondsPerUnit(netAvailableSeconds: 90, customerDemand: -2))
    }

    func testTaktTimeToolIsAvailableWithoutCreatingCounterSession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        context.insert(home)
        try context.save()

        let taktTime = try XCTUnwrap(ToolRegistry.definition(for: .taktTime))
        XCTAssertTrue(taktTime.isAvailable)
        XCTAssertEqual(taktTime.supportedCardSizes, [.medium, .large])
        let card = try HomeToolService(modelContext: context).add(
            taktTime,
            to: home.id,
            locale: AppLanguage.english.locale
        )

        XCTAssertEqual(card.toolID, "production.takt")
        XCTAssertNil(card.productionSessionID)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProductionSession>()).isEmpty)
    }

    func testBoxCalculatorChecksRotationsAndReturnsBestPackingLayout() {
        let result = BoxCalculator.maximumUnits(
            item: BoxDimensions(length: 30, width: 20, height: 10),
            innerBox: BoxDimensions(length: 20, width: 30, height: 50)
        )

        XCTAssertEqual(result?.unitsPerBox, 5)
        XCTAssertEqual(result?.unitsAlongLength, 1)
        XCTAssertEqual(result?.unitsAlongWidth, 1)
        XCTAssertEqual(result?.unitsAlongHeight, 5)
        XCTAssertEqual(result?.itemOrientation, BoxDimensions(length: 20, width: 30, height: 10))
    }

    func testBoxCalculatorRejectsInvalidUnfittingAndOverflowingDimensions() {
        XCTAssertNil(
            BoxCalculator.maximumUnits(
                item: BoxDimensions(length: 0, width: 2, height: 3),
                innerBox: BoxDimensions(length: 10, width: 10, height: 10)
            )
        )
        XCTAssertNil(
            BoxCalculator.maximumUnits(
                item: BoxDimensions(length: 11, width: 2, height: 3),
                innerBox: BoxDimensions(length: 10, width: 10, height: 10)
            )
        )
        XCTAssertNil(
            BoxCalculator.maximumUnits(
                item: BoxDimensions(length: 1, width: 1, height: 1),
                innerBox: BoxDimensions(length: Int.max, width: Int.max, height: Int.max)
            )
        )
        XCTAssertEqual(
            BoxCalculator.outcome(
                item: BoxDimensions(length: 1, width: 1, height: 1),
                innerBox: BoxDimensions(length: Int.max, width: Int.max, height: Int.max)
            ),
            .countTooLarge
        )
        XCTAssertEqual(
            BoxCalculator.outcome(
                item: BoxDimensions(length: 11, width: 2, height: 3),
                innerBox: BoxDimensions(length: 10, width: 10, height: 10)
            ),
            .noFit
        )
    }

    func testBoxCalculatorToolIsAvailableForMediumAndLargeCardsWithoutCreatingSession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        context.insert(home)
        try context.save()

        let boxTool = try XCTUnwrap(ToolRegistry.definition(for: .boxCalculator))
        XCTAssertTrue(boxTool.isAvailable)
        XCTAssertEqual(boxTool.supportedCardSizes, [.medium, .large])
        let card = try HomeToolService(modelContext: context).add(
            boxTool,
            to: home.id,
            locale: AppLanguage.english.locale
        )

        XCTAssertEqual(card.toolID, "packing.box")
        XCTAssertNil(card.productionSessionID)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProductionSession>()).isEmpty)
    }

    func testBoxCalculatorPackingAssumptionIsLocalizedInJapaneseAndEnglish() {
        XCTAssertEqual(
            String(localized: LocalizedStringResource("boxCalculator.enterDimensions", locale: AppLanguage.english.locale)),
            "Enter all six dimensions to see the result."
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("boxCalculator.enterDimensions", locale: AppLanguage.japanese.locale)),
            "計算結果を見るには6つの寸法を入力してください。"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("boxCalculator.sameOrientationNote", locale: AppLanguage.english.locale)),
            "Assumes every item uses the same orientation; mixed orientations are not included."
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("boxCalculator.sameOrientationNote", locale: AppLanguage.japanese.locale)),
            "すべての品物を同じ向きに配置します。異なる向きを混ぜた配置は計算しません。"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("boxCalculator.countTooLarge", locale: AppLanguage.english.locale)),
            "The item count exceeds the supported numeric range. Enter smaller dimensions."
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("boxCalculator.countTooLarge", locale: AppLanguage.japanese.locale)),
            "計算個数が扱える数値の範囲を超えています。より小さい寸法を入力してください。"
        )
    }

    func testUnitConversionConvertsLengthMassVolumeAndTemperature() throws {
        XCTAssertEqual(
            try XCTUnwrap(UnitConversion.convert(1_000, from: .millimeter, to: .meter)),
            1,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            try XCTUnwrap(UnitConversion.convert(12, from: .inch, to: .foot)),
            1,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            try XCTUnwrap(UnitConversion.convert(1, from: .pound, to: .kilogram)),
            0.45359237,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            try XCTUnwrap(UnitConversion.convert(1, from: .usGallon, to: .liter)),
            3.785411784,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            try XCTUnwrap(UnitConversion.convert(32, from: .fahrenheit, to: .celsius)),
            0,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            try XCTUnwrap(UnitConversion.convert(0, from: .celsius, to: .kelvin)),
            273.15,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            try XCTUnwrap(UnitConversion.convert(-459.67, from: .fahrenheit, to: .kelvin)),
            0,
            accuracy: 1e-9
        )
    }

    func testUnitConversionRejectsInvalidValuesAndIncompatibleUnits() {
        XCTAssertNil(UnitConversion.convert(-1, from: .meter, to: .foot))
        XCTAssertNil(UnitConversion.convert(1, from: .meter, to: .kilogram))
        XCTAssertNil(UnitConversion.convert(-273.16, from: .celsius, to: .kelvin))
        XCTAssertNil(UnitConversion.convert(-1, from: .kelvin, to: .celsius))
        XCTAssertNil(UnitConversion.convert(.nan, from: .meter, to: .foot))
        XCTAssertNil(UnitConversion.convert(.infinity, from: .liter, to: .milliliter))
        XCTAssertNil(UnitConversion.convert(Double.greatestFiniteMagnitude, from: .kilometer, to: .millimeter))
        XCTAssertNil(UnitConversion.convert(Double.greatestFiniteMagnitude, from: .celsius, to: .fahrenheit))
    }

    func testEveryUnitPairRoundTripsWithinItsCategory() throws {
        let categorizedUnits = UnitCategory.allCases.flatMap(\.units)
        XCTAssertEqual(Set(categorizedUnits), Set(MeasurementUnit.allCases))
        XCTAssertEqual(categorizedUnits.count, Set(categorizedUnits).count)

        for category in UnitCategory.allCases {
            XCTAssertTrue(category.units.allSatisfy { $0.category == category })
            for source in category.units {
                for target in category.units {
                    let converted = try XCTUnwrap(
                        UnitConversion.convert(123.456, from: source, to: target),
                        "Expected \(source) to convert to \(target) in \(category)"
                    )
                    let restored = try XCTUnwrap(
                        UnitConversion.convert(converted, from: target, to: source),
                        "Expected \(target) to convert back to \(source) in \(category)"
                    )
                    XCTAssertEqual(restored, 123.456, accuracy: 1e-9, "\(source) ↔ \(target)")
                }
            }
        }
    }

    func testLocalizedNumberParserRespectsLocaleAndRequiresTheWholeInput() {
        XCTAssertEqual(LocalizedNumberParser.parse("1,234.5", locale: Locale(identifier: "en_US")), 1_234.5)
        XCTAssertEqual(LocalizedNumberParser.parse("1,234.5", locale: Locale(identifier: "ja_JP")), 1_234.5)
        XCTAssertEqual(LocalizedNumberParser.parse("-12.5", locale: Locale(identifier: "en_US")), -12.5)
        XCTAssertEqual(LocalizedNumberParser.parse("-12.5", locale: Locale(identifier: "ja_JP")), -12.5)
        XCTAssertEqual(LocalizedNumberParser.parse("  12.75  ", locale: Locale(identifier: "en_US")), 12.75)
        XCTAssertNil(LocalizedNumberParser.parse("12.5seconds", locale: Locale(identifier: "en_US")))
        XCTAssertNil(LocalizedNumberParser.parse("NaN", locale: Locale(identifier: "en_US")))
        XCTAssertNil(LocalizedNumberParser.parse("Infinity", locale: Locale(identifier: "en_US")))
        XCTAssertNil(LocalizedNumberParser.parse("1e999", locale: Locale(identifier: "en_US")))
        XCTAssertNil(LocalizedNumberParser.parse("", locale: Locale(identifier: "ja_JP")))
        XCTAssertEqual(LocalizedNumberParser.parseInteger("1,234", locale: Locale(identifier: "en_US")), 1_234)
        XCTAssertEqual(LocalizedNumberParser.parseInteger("1,234", locale: Locale(identifier: "ja_JP")), 1_234)
        XCTAssertEqual(LocalizedNumberParser.parseInteger("1.234", locale: Locale(identifier: "de_DE")), 1_234)
        XCTAssertEqual(
            LocalizedNumberParser.parseInteger("9,223,372,036,854,775,807", locale: Locale(identifier: "en_US")),
            Int.max
        )
        XCTAssertEqual(
            LocalizedNumberParser.parseInteger("-9,223,372,036,854,775,808", locale: Locale(identifier: "en_US")),
            Int.min
        )
        XCTAssertNil(LocalizedNumberParser.parseInteger("1.5", locale: Locale(identifier: "en_US")))
        XCTAssertNil(LocalizedNumberParser.parseInteger("9,223,372,036,854,775,808", locale: Locale(identifier: "en_US")))
        XCTAssertNil(LocalizedNumberParser.parseInteger("123items", locale: Locale(identifier: "en_US")))
    }

    func testUnitConverterToolIsAvailableForSmallAndMediumCardsWithoutCreatingSession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        context.insert(home)
        try context.save()

        let unitTool = try XCTUnwrap(ToolRegistry.definition(for: .unitConverter))
        XCTAssertTrue(unitTool.isAvailable)
        XCTAssertEqual(unitTool.supportedCardSizes, [.small, .medium])
        let card = try HomeToolService(modelContext: context).add(
            unitTool,
            to: home.id,
            locale: AppLanguage.english.locale
        )

        XCTAssertEqual(card.toolID, "utility.unitConverter")
        XCTAssertNil(card.productionSessionID)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProductionSession>()).isEmpty)
    }

    func testUnitConverterCategoryAndUnitNamesAreLocalized() {
        XCTAssertEqual(
            String(localized: LocalizedStringResource("unitConverter.category.length", locale: AppLanguage.english.locale)),
            "Length"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("unitConverter.category.length", locale: AppLanguage.japanese.locale)),
            "長さ"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("unitConverter.unit.usFluidOunce", locale: AppLanguage.english.locale)),
            "US fluid ounce"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("unitConverter.unit.usFluidOunce", locale: AppLanguage.japanese.locale)),
            "米液量オンス"
        )
    }

    func testDefectCounterTracksIndependentLocalizedCountWithSharedCounterService() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        context.insert(home)
        try context.save()

        let defectTool = try XCTUnwrap(ToolRegistry.definition(for: .defectCounter))
        XCTAssertTrue(defectTool.isAvailable)
        XCTAssertEqual(defectTool.supportedCardSizes, Set(ToolCardSize.allCases))
        let service = HomeToolService(modelContext: context)
        let defectCard = try service.add(defectTool, to: home.id, locale: AppLanguage.english.locale)
        let secondDefectCard = try service.add(defectTool, to: home.id, locale: AppLanguage.english.locale)
        let productionTool = try XCTUnwrap(ToolRegistry.definition(for: .productionCounter))
        let productionCard = try service.add(productionTool, to: home.id, locale: AppLanguage.english.locale)

        let sessions = try context.fetch(FetchDescriptor<ProductionSession>())
        XCTAssertEqual(sessions.count, 2)
        let defectSession = try XCTUnwrap(sessions.first { $0.toolID == ToolID.defectCounter.rawValue })
        let productionSession = try XCTUnwrap(sessions.first { $0.toolID == ToolID.productionCounter.rawValue })
        XCTAssertEqual(defectSession.name, "Defect count")
        XCTAssertEqual(defectSession.targetCount, 0)
        XCTAssertEqual(defectCard.productionSessionID, defectSession.id)
        XCTAssertEqual(secondDefectCard.productionSessionID, defectSession.id)
        XCTAssertEqual(productionCard.productionSessionID, productionSession.id)
        XCTAssertNotEqual(defectSession.id, productionSession.id)

        let counterService = CounterService(modelContext: context)
        try counterService.increment(session: defectSession)
        try counterService.quickAdd(5, to: defectSession)
        try counterService.undo(session: defectSession)

        XCTAssertEqual(defectSession.currentCount, 1)
        XCTAssertEqual(productionSession.currentCount, 0)
        let defectEvents = try context.fetch(FetchDescriptor<CountEvent>()).filter { $0.sessionID == defectSession.id }
        XCTAssertEqual(defectEvents.map(\.delta), [1, 5, -5])
        XCTAssertEqual(ToolSessionAssignment.session(for: defectCard, in: sessions)?.id, defectSession.id)
    }

    func testDefectCounterSessionNameUsesJapaneseWithoutChangingStableToolID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        context.insert(home)
        try context.save()
        let defectTool = try XCTUnwrap(ToolRegistry.definition(for: .defectCounter))

        let card = try HomeToolService(modelContext: context).add(
            defectTool,
            to: home.id,
            locale: AppLanguage.japanese.locale
        )
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<ProductionSession>()).first)

        XCTAssertEqual(card.toolID, "quality.defect")
        XCTAssertEqual(session.toolID, "quality.defect")
        XCTAssertEqual(session.name, "不良カウント")
        XCTAssertEqual(session.targetCount, 0)
    }

    func testProductionProgressReusesTheProductionCounterSessionWhenAddedFirst() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let home = HomeProfile(name: "Assembly", sortOrder: 0)
        context.insert(home)
        try context.save()

        let progress = try XCTUnwrap(ToolRegistry.definition(for: .productionProgress))
        XCTAssertTrue(progress.isAvailable)
        XCTAssertEqual(progress.supportedCardSizes, [.medium, .large])
        let service = HomeToolService(modelContext: context)
        let progressCard = try service.add(progress, to: home.id, locale: AppLanguage.english.locale, isPro: true)
        let counter = try XCTUnwrap(ToolRegistry.definition(for: .productionCounter))
        let counterCard = try service.add(counter, to: home.id, locale: AppLanguage.english.locale)

        let sessions = try context.fetch(FetchDescriptor<ProductionSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.toolID, ToolID.productionCounter.rawValue)
        XCTAssertEqual(progressCard.productionSessionID, sessions.first?.id)
        XCTAssertEqual(counterCard.productionSessionID, sessions.first?.id)
        XCTAssertEqual(ToolSessionAssignment.session(for: progressCard, in: sessions)?.id, sessions.first?.id)
    }

    func testProductionProgressFindsCounterSessionWhenItsLinkIsMissingOrStale() {
        let homeID = UUID()
        let session = ProductionSession(
            homeProfileID: homeID,
            toolID: ToolID.productionCounter.rawValue,
            name: "Production"
        )
        let missingLink = ToolCard(homeProfileID: homeID, toolID: .productionProgress, sortOrder: 0)
        let staleLink = ToolCard(
            homeProfileID: homeID,
            toolID: .productionProgress,
            sortOrder: 1,
            productionSessionID: UUID()
        )

        XCTAssertEqual(ToolSessionAssignment.session(for: missingLink, in: [session])?.id, session.id)
        XCTAssertEqual(ToolSessionAssignment.session(for: staleLink, in: [session])?.id, session.id)
    }

    func testProductionProgressGuidanceIsLocalizedInJapaneseAndEnglish() {
        XCTAssertEqual(
            String(localized: LocalizedStringResource("progress.targetNotSet", locale: AppLanguage.english.locale)),
            "No production target is set."
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("progress.targetNotSet", locale: AppLanguage.japanese.locale)),
            "生産目標が設定されていません。"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("progress.setTarget", locale: AppLanguage.english.locale)),
            "Set production target"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("progress.setTarget", locale: AppLanguage.japanese.locale)),
            "生産目標を設定"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("progress.targetReached", locale: AppLanguage.english.locale)),
            "Target reached"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource("progress.targetReached", locale: AppLanguage.japanese.locale)),
            "目標達成"
        )
    }

    func testEveryToolIdentifierIsStableAndIndependentOfDisplayLanguage() {
        XCTAssertEqual(
            ToolID.allCases.map(\.rawValue),
            [
                "production.counter",
                "production.cycleTime",
                "production.takt",
                "production.oee",
                "production.progress",
                "quality.defect",
                "quality.defectRate",
                "packing.box",
                "utility.unitConverter"
            ]
        )
    }

    func testToolSessionAssignmentIsScopedToHomeAndToolAndReaddUsesSameSession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let homeID = UUID()
        let otherHomeID = UUID()
        let home = HomeProfile(id: homeID, name: "Home", sortOrder: 0)
        let matchingSession = ProductionSession(
            homeProfileID: homeID,
            toolID: ToolID.productionCounter.rawValue,
            name: "Home counter"
        )
        let otherHomeSession = ProductionSession(
            homeProfileID: otherHomeID,
            toolID: ToolID.productionCounter.rawValue,
            name: "Other home counter"
        )
        let otherToolSession = ProductionSession(
            homeProfileID: homeID,
            toolID: "inventory.stock",
            name: "Other tool"
        )
        let counterCard = ToolCard(
            homeProfileID: homeID,
            toolID: .productionCounter,
            sortOrder: 0,
            productionSessionID: matchingSession.id
        )
        context.insert(home)
        context.insert(matchingSession)
        context.insert(otherHomeSession)
        context.insert(otherToolSession)
        context.insert(counterCard)
        try context.save()
        try CounterService(modelContext: context).quickAdd(14, to: matchingSession)
        try CounterService(modelContext: context).setTarget(50, for: matchingSession)
        try HomeCardService(modelContext: context).remove(counterCard)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ToolCard>()).isEmpty)
        XCTAssertEqual(matchingSession.currentCount, 14)
        XCTAssertEqual(matchingSession.targetCount, 50)
        let productionCounter = try XCTUnwrap(ToolRegistry.definition(for: .productionCounter))
        let readdedCard = try HomeToolService(modelContext: context).add(
            productionCounter,
            to: homeID,
            locale: AppLanguage.english.locale
        )
        let remainingSessions = try context.fetch(FetchDescriptor<ProductionSession>())
        let remainingEvents = try context.fetch(FetchDescriptor<CountEvent>())
        let restoredSession = try XCTUnwrap(remainingSessions.first { $0.id == matchingSession.id })

        XCTAssertEqual(readdedCard.productionSessionID, matchingSession.id)
        XCTAssertEqual(readdedCard.sortOrder, 0)
        XCTAssertEqual(restoredSession.currentCount, 14)
        XCTAssertEqual(restoredSession.targetCount, 50)
        XCTAssertEqual(remainingEvents.map(\.delta), [14])
        XCTAssertEqual(
            ToolSessionAssignment.session(
                for: homeID,
                toolID: .productionCounter,
                in: remainingSessions
            )?.id,
            matchingSession.id
        )
        XCTAssertNil(
            ToolSessionAssignment.session(
                for: UUID(),
                toolID: .productionCounter,
                in: remainingSessions
            )
        )
    }

    func testToolSessionAssignmentSelectsEarliestMatchingDuplicateDeterministically() throws {
        let homeID = UUID()
        let sharedStart = Date(timeIntervalSince1970: 100)
        let lowerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let higherID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let laterID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let later = ProductionSession(
            id: laterID,
            homeProfileID: homeID,
            toolID: ToolID.productionCounter.rawValue,
            name: "Later",
            startedAt: Date(timeIntervalSince1970: 200)
        )
        let earlierWithHigherID = ProductionSession(
            id: higherID,
            homeProfileID: homeID,
            toolID: ToolID.productionCounter.rawValue,
            name: "Earlier, higher ID",
            startedAt: sharedStart
        )
        let earlierWithLowerID = ProductionSession(
            id: lowerID,
            homeProfileID: homeID,
            toolID: ToolID.productionCounter.rawValue,
            name: "Earlier, lower ID",
            startedAt: sharedStart
        )

        let selected = ToolSessionAssignment.session(
            for: homeID,
            toolID: .productionCounter,
            in: [later, earlierWithHigherID, earlierWithLowerID]
        )

        XCTAssertEqual(selected?.id, lowerID)
    }

    func testCardSessionLookupRejectsCrossHomeLinksAndRecoversStaleSessionIDs() {
        let homeID = UUID()
        let otherHomeID = UUID()
        let homeSession = ProductionSession(
            homeProfileID: homeID,
            toolID: ToolID.productionCounter.rawValue,
            name: "Home counter"
        )
        let otherHomeSession = ProductionSession(
            homeProfileID: otherHomeID,
            toolID: ToolID.productionCounter.rawValue,
            name: "Other home counter"
        )
        let staleLinkedCard = ToolCard(
            homeProfileID: homeID,
            toolID: .productionCounter,
            sortOrder: 0,
            productionSessionID: otherHomeSession.id
        )
        let missingLinkedCard = ToolCard(
            homeProfileID: homeID,
            toolID: .productionCounter,
            sortOrder: 1,
            productionSessionID: UUID()
        )

        XCTAssertEqual(ToolSessionAssignment.session(for: staleLinkedCard, in: [otherHomeSession, homeSession])?.id, homeSession.id)
        XCTAssertEqual(ToolSessionAssignment.session(for: missingLinkedCard, in: [homeSession])?.id, homeSession.id)
        XCTAssertNil(ToolSessionAssignment.session(for: missingLinkedCard, in: [otherHomeSession]))
    }

    func testRegistryContainsEveryToolOnceWithUniqueIdentifiers() {
        let registryIDs = ToolRegistry.all.map(\.id.rawValue)
        let registryRoutes = ToolRegistry.all.map(\.homeCardRoute)
        let expectedSessionPolicies: [ToolID: ToolSessionPolicy] = [
            .productionCounter: .productionCounter,
            .productionProgress: .productionCounter,
            .defectCounter: .defectCounter,
        ]
        let expectedRoutes: [ToolID: ToolCardRoute] = [
            .productionCounter: .productionCounter,
            .cycleTime: .cycleTime,
            .taktTime: .taktTime,
            .oee: .oee,
            .productionProgress: .productionProgress,
            .defectCounter: .defectCounter,
            .defectRate: .defectRate,
            .boxCalculator: .boxCalculator,
            .unitConverter: .unitConverter,
        ]

        XCTAssertEqual(registryIDs.count, Set(registryIDs).count)
        XCTAssertEqual(Set(registryIDs), Set(ToolID.allCases.map(\.rawValue)))
        XCTAssertEqual(registryRoutes.count, Set(registryRoutes).count)
        XCTAssertFalse(registryRoutes.contains(.comingSoon))
        for (toolID, route) in expectedRoutes {
            XCTAssertEqual(ToolRegistry.definition(for: toolID)?.homeCardRoute, route)
        }
        for definition in ToolRegistry.all {
            XCTAssertEqual(definition.sessionPolicy, expectedSessionPolicies[definition.id])
            XCTAssertEqual(definition.supportsWatch, definition.id.capabilities.supportsWatch)
            XCTAssertEqual(definition.supportedCardSizes, definition.id.capabilities.supportedCardSizes)
        }
        XCTAssertEqual(ToolSessionPolicy.productionCounter.defaultSessionNameKey, "counter.defaultSessionName")
        XCTAssertEqual(ToolSessionPolicy.productionCounter.defaultTargetCount, 600)
        XCTAssertEqual(ToolSessionPolicy.defectCounter.defaultSessionNameKey, "defect.defaultSessionName")
        XCTAssertEqual(ToolSessionPolicy.defectCounter.defaultTargetCount, 0)
    }

    private func makeContainer(
        allowsSave: Bool = true,
        seed: ((ModelContext) throws -> Void)? = nil
    ) throws -> ModelContainer {
        let schema = Schema([
            HomeProfile.self,
            ToolCard.self,
            ProductionSession.self,
            CountEvent.self,
            CounterCommandReceipt.self,
            AppSettings.self,
            CycleTimeSample.self,
            OEERun.self
        ])
        guard !allowsSave else {
            let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            if let seed {
                let context = ModelContext(container)
                try seed(context)
                try context.save()
            }
            return container
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FactoryToolsReadOnly-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("FactoryTools.store")
        let configurationName = UUID().uuidString
        let writable = ModelConfiguration(configurationName, schema: schema, url: storeURL, cloudKitDatabase: .none)
        let writableContainer = try ModelContainer(for: schema, configurations: [writable])
        if let seed {
            let context = ModelContext(writableContainer)
            try seed(context)
            try context.save()
        }
        let readOnly = ModelConfiguration(configurationName, schema: schema, url: storeURL, allowsSave: false, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [readOnly])
    }
}

