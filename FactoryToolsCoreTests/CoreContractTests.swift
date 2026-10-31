import Foundation
import XCTest
import FactoryToolsCore

private enum SimulatedOutboxPersistenceError: Error {
    case unavailable
}

final class CoreContractTests: XCTestCase {
    func testToolAndCardIdentifiersRemainStableAndLanguageIndependent() {
        XCTAssertEqual(ToolID.allCases.map(\.rawValue), [
            "production.counter",
            "production.cycleTime",
            "production.takt",
            "production.oee",
            "production.progress",
            "quality.defect",
            "quality.defectRate",
            "packing.box",
            "utility.unitConverter",
        ])
        XCTAssertEqual(ToolCardSize.allCases.map(\.rawValue), ["small", "medium", "large"])
        XCTAssertEqual(ToolCategory.allCases.map(\.rawValue), ["production", "quality", "packing", "utility"])
        XCTAssertEqual(CounterEventKind.allCases.map(\.rawValue), ["increment", "decrement", "quickAdd", "reset", "undo"])
    }

    func testFeatureAccessAssignmentsMatchTheApprovedVersionOneBoundary() {
        XCTAssertEqual(FeatureAccessTier.allCases.map(\.rawValue), ["free", "pro"])
        XCTAssertTrue(FeatureAccessRegistry.hasProFeatures)
        let proFeatures: Set<FactoryFeature> = [
            .multipleHomeProfiles, .proThemes, .advancedWatchSettings,
            .detailedHistoryAnalysis, .detailedDefectAnalysis,
            .advancedDashboardCustomization, .oeeCalculator, .productionProgress,
            .downtimeTracking, .toolLife, .capabilityAnalysis, .advancedQualityControl,
            .toleranceCalculation, .machiningConditionCalculation, .advancedWarnings,
            .cycleTimeExclusions, .multipleBreaks, .complexShiftSettings,
            .detailedNotifications, .advancedCalculationSettings, .detailedLogs,
            .precisionAndRoundingSettings, .detailedCharts, .timeOfDayAnalysis,
            .defectCategoryAnalysis, .additionalWatchTools,
        ]
        for feature in FactoryFeature.allCases {
            let expectedTier: FeatureAccessTier = proFeatures.contains(feature) ? .pro : .free
            XCTAssertEqual(FeatureAccessRegistry.requiredTier(for: feature), expectedTier)
            XCTAssertEqual(FeatureAccessRegistry.allows(feature, isPro: false), expectedTier == .free)
            XCTAssertTrue(FeatureAccessRegistry.allows(feature, isPro: true))
        }
        XCTAssertTrue(FeatureAccessRegistry.allows(.pro, isPro: true))
        XCTAssertFalse(FeatureAccessRegistry.allows(.pro, isPro: false))
    }

    func testProEntitlementRequiresVerifiedActiveOwnershipOfConfiguredProduct() {
        func evidence(
            productID: String = "factorytools.pro",
            isVerified: Bool = true,
            isRevoked: Bool = false,
            isUpgraded: Bool = false,
            ownership: ProPurchaseOwnership = .purchased
        ) -> ProEntitlementEvidence {
            ProEntitlementEvidence(
                productID: productID,
                isVerified: isVerified,
                isRevoked: isRevoked,
                isUpgraded: isUpgraded,
                ownership: ownership
            )
        }

        XCTAssertTrue(evidence().grantsPro(for: "factorytools.pro"))
        XCTAssertFalse(evidence(ownership: .familyShared).grantsPro(for: "factorytools.pro"))
        XCTAssertFalse(evidence(productID: "other.product").grantsPro(for: "factorytools.pro"))
        XCTAssertFalse(evidence(isVerified: false).grantsPro(for: "factorytools.pro"))
        XCTAssertFalse(evidence(isRevoked: true).grantsPro(for: "factorytools.pro"))
        XCTAssertFalse(evidence(isUpgraded: true).grantsPro(for: "factorytools.pro"))
        XCTAssertFalse(evidence().grantsPro(for: ""))
    }

    func testPeerAuthorityDoesNotReplacePendingOrActivePairedConnection() {
        XCTAssertTrue(CounterPeerConnectionPolicy.shouldAcceptIncomingConnection(
            isAuthority: true,
            hasPendingOrActiveConnection: false
        ))
        XCTAssertFalse(CounterPeerConnectionPolicy.shouldAcceptIncomingConnection(
            isAuthority: true,
            hasPendingOrActiveConnection: true
        ))
        XCTAssertFalse(CounterPeerConnectionPolicy.shouldAcceptIncomingConnection(
            isAuthority: false,
            hasPendingOrActiveConnection: false
        ))
    }

    func testCounterSessionPoliciesAreStableAndPlatformNeutral() {
        XCTAssertEqual(ToolSessionPolicy.allCases.map(\.rawValue), ["productionCounter", "defectCounter"])
        XCTAssertEqual(ToolSessionPolicy.productionCounter.sessionToolID, .productionCounter)
        XCTAssertEqual(ToolSessionPolicy.productionCounter.defaultTargetCount, 600)
        XCTAssertEqual(ToolSessionPolicy.defectCounter.sessionToolID, .defectCounter)
        XCTAssertEqual(ToolSessionPolicy.defectCounter.defaultTargetCount, 0)
    }

    func testToolCapabilitiesAreDefinedInCoreForEveryStableID() {
        let allSizes = Set(ToolCardSize.allCases)
        let mediumAndLarge: Set<ToolCardSize> = [.medium, .large]
        let expected: [ToolID: ToolCapabilities] = [
            .productionCounter: ToolCapabilities(supportsWatch: true, supportedCardSizes: allSizes),
            .cycleTime: ToolCapabilities(supportsWatch: true, supportedCardSizes: allSizes),
            .taktTime: ToolCapabilities(supportsWatch: false, supportedCardSizes: mediumAndLarge),
            .oee: ToolCapabilities(supportsWatch: false, supportedCardSizes: mediumAndLarge),
            .productionProgress: ToolCapabilities(supportsWatch: true, supportedCardSizes: mediumAndLarge),
            .defectCounter: ToolCapabilities(supportsWatch: true, supportedCardSizes: allSizes),
            .defectRate: ToolCapabilities(supportsWatch: false, supportedCardSizes: mediumAndLarge),
            .boxCalculator: ToolCapabilities(supportsWatch: false, supportedCardSizes: mediumAndLarge),
            .unitConverter: ToolCapabilities(supportsWatch: false, supportedCardSizes: [.small, .medium]),
        ]

        XCTAssertEqual(expected.count, ToolID.allCases.count)
        for toolID in ToolID.allCases {
            XCTAssertEqual(toolID.capabilities, expected[toolID])
        }
    }

    func testCounterCommandCodableRoundTripsEveryOperation() throws {
        let eventID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let operations: [(CounterCommandOperation, String)] = [
            (.increment, "increment"),
            (.decrement, "decrement"),
            (.quickAdd(17), "quickAdd"),
            (.reset, "reset"),
            (.undo(eventID: eventID), "undo"),
            (.setTarget(42), "setTarget"),
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for (index, entry) in operations.enumerated() {
            let command = CounterCommand(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                sessionID: sessionID,
                operation: entry.0,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
            )
            let encoded = try encoder.encode(command)
            XCTAssertEqual(try decoder.decode(CounterCommand.self, from: encoded), command)
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            let wireOperation = try XCTUnwrap(root["operation"] as? [String: Any])
            XCTAssertEqual(root["schemaVersion"] as? Int, 1)
            XCTAssertEqual(wireOperation["kind"] as? String, entry.1)
            if entry.1 == "quickAdd" {
                XCTAssertEqual(wireOperation["amount"] as? Int, 17)
            }
            if entry.1 == "undo" {
                XCTAssertEqual(wireOperation["eventID"] as? String, eventID.uuidString)
            }
            if entry.1 == "setTarget" {
                XCTAssertEqual(wireOperation["amount"] as? Int, 42)
            }
        }
    }

    func testCounterCommandRejectsUnsupportedSchemaVersion() throws {
        let payload = Data(#"{"schemaVersion":2,"id":"00000000-0000-0000-0000-000000000001","sessionID":"00000000-0000-0000-0000-000000000002","operation":{"kind":"increment"},"createdAt":0}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CounterCommand.self, from: payload))
    }

    func testCounterCommandAcknowledgementUsesStableVersionedWireValues() throws {
        let commandID = UUID(uuidString: "00000000-0000-0000-0000-000000000251")!
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let expectedStatuses: [(CounterCommandAcknowledgementStatus, String)] = [
            (.applied, "applied"),
            (.alreadyApplied, "alreadyApplied"),
            (.noChange, "noChange"),
            (.staleUndo, "staleUndo"),
            (.rejected, "rejected"),
        ]

        XCTAssertEqual(CounterCommandAcknowledgementStatus.allCases.map(\.rawValue), expectedStatuses.map(\.1))
        XCTAssertTrue(CounterCommandAcknowledgementStatus.applied.requiresAuthoritativeSnapshot)
        XCTAssertTrue(CounterCommandAcknowledgementStatus.alreadyApplied.requiresAuthoritativeSnapshot)
        XCTAssertTrue(CounterCommandAcknowledgementStatus.noChange.requiresAuthoritativeSnapshot)
        XCTAssertTrue(CounterCommandAcknowledgementStatus.staleUndo.requiresAuthoritativeSnapshot)
        XCTAssertFalse(CounterCommandAcknowledgementStatus.rejected.requiresAuthoritativeSnapshot)
        for (status, wireValue) in expectedStatuses {
            let acknowledgement = CounterCommandAcknowledgement(commandID: commandID, status: status)
            let encoded = try encoder.encode(acknowledgement)
            XCTAssertEqual(try decoder.decode(CounterCommandAcknowledgement.self, from: encoded), acknowledgement)
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            XCTAssertEqual(root["schemaVersion"] as? Int, CounterCommandAcknowledgement.currentSchemaVersion)
            XCTAssertEqual(root["commandID"] as? String, commandID.uuidString)
            XCTAssertEqual(root["status"] as? String, wireValue)
        }
    }

    func testCounterCommandAcknowledgementRejectsUnsupportedSchemaAndUnknownStatus() throws {
        let id = "00000000-0000-0000-0000-000000000252"
        let unsupportedVersion = Data("{\"schemaVersion\":2,\"commandID\":\"\(id)\",\"status\":\"applied\"}".utf8)
        let unknownStatus = Data("{\"schemaVersion\":1,\"commandID\":\"\(id)\",\"status\":\"futureResult\"}".utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(CounterCommandAcknowledgement.self, from: unsupportedVersion))
        XCTAssertThrowsError(try JSONDecoder().decode(CounterCommandAcknowledgement.self, from: unknownStatus))
    }

    func testWatchCounterCatalogRoundTripsStableSessionAndHomeIDs() throws {
        let snapshot = WatchCounterSessionSnapshot(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000261")!,
            homeProfileID: UUID(uuidString: "00000000-0000-0000-0000-000000000262")!,
            homeName: "Production",
            toolID: .productionCounter,
            sessionName: "Line A",
            currentCount: 42,
            targetCount: 600,
            defaultSessionNameToolID: .productionCounter,
            homeNameIsDefault: true
        )
        let cycleHome = WatchCycleTimeHomeSnapshot(
            homeProfileID: UUID(uuidString: "00000000-0000-0000-0000-000000000263")!,
            homeName: "Production",
            homeNameIsDefault: true
        )
        let progressCard = WatchProductionProgressSnapshot(
            cardID: UUID(uuidString: "00000000-0000-0000-0000-000000000264")!,
            sessionID: snapshot.sessionID,
            homeProfileID: snapshot.homeProfileID,
            homeName: snapshot.homeName,
            currentCount: 42,
            targetCount: 600,
            homeNameIsDefault: true
        )
        let catalog = try WatchCounterCatalog(
            sessions: [snapshot],
            cycleTimeHome: cycleHome,
            progressCards: [progressCard],
            displayLanguage: .japanese
        )
        let data = try JSONEncoder().encode(catalog)
        let restored = try JSONDecoder().decode(WatchCounterCatalog.self, from: data)

        XCTAssertEqual(restored, catalog)
        XCTAssertEqual(restored.sessions.first?.toolID.rawValue, "production.counter")
        XCTAssertEqual(restored.sessions.first?.defaultSessionNameToolID, .productionCounter)
        XCTAssertEqual(restored.sessions.first?.homeNameIsDefault, true)
        XCTAssertEqual(restored.sessions.first?.currentCount, 42)
        XCTAssertEqual(restored.cycleTimeHome, cycleHome)
        XCTAssertEqual(restored.cycleTimeHome?.homeNameIsDefault, true)
        XCTAssertEqual(restored.progressCards, [progressCard])
        XCTAssertEqual(restored.progressCards.first?.homeNameIsDefault, true)
        XCTAssertEqual(restored.displayLanguage, .japanese)
        XCTAssertEqual(WatchDisplayLanguage.japanese.rawValue, "japanese")
        XCTAssertEqual(WatchDisplayLanguage.english.rawValue, "english")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["schemaVersion"] as? Int, WatchCounterCatalog.currentSchemaVersion)

        let legacyCatalog = Data("{\"schemaVersion\":1,\"sessions\":[]}".utf8)
        let restoredLegacyCatalog = try JSONDecoder().decode(WatchCounterCatalog.self, from: legacyCatalog)
        XCTAssertNil(restoredLegacyCatalog.cycleTimeHome)
        XCTAssertTrue(restoredLegacyCatalog.progressCards.isEmpty)
        XCTAssertEqual(restoredLegacyCatalog.displayLanguage, .system)

        let legacySession = Data("{\"sessionID\":\"00000000-0000-0000-0000-000000000261\",\"homeProfileID\":\"00000000-0000-0000-0000-000000000262\",\"homeName\":\"Assembly\",\"toolID\":\"production.counter\",\"sessionName\":\"Line A\",\"currentCount\":0,\"targetCount\":0}".utf8)
        let restoredLegacySession = try JSONDecoder().decode(WatchCounterSessionSnapshot.self, from: legacySession)
        XCTAssertNil(restoredLegacySession.defaultSessionNameToolID)
        XCTAssertNil(restoredLegacySession.homeNameIsDefault)
        let legacyCycleHome = Data("{\"homeProfileID\":\"00000000-0000-0000-0000-000000000263\",\"homeName\":\"Production\"}".utf8)
        XCTAssertNil(try JSONDecoder().decode(WatchCycleTimeHomeSnapshot.self, from: legacyCycleHome).homeNameIsDefault)
        let legacyProgressCard = Data("{\"cardID\":\"00000000-0000-0000-0000-000000000264\",\"sessionID\":\"00000000-0000-0000-0000-000000000261\",\"homeProfileID\":\"00000000-0000-0000-0000-000000000262\",\"homeName\":\"Production\",\"currentCount\":0,\"targetCount\":0}".utf8)
        XCTAssertNil(try JSONDecoder().decode(WatchProductionProgressSnapshot.self, from: legacyProgressCard).homeNameIsDefault)
    }

    func testWatchCycleTimeCommandValidatesAndRoundTripsMeasurement() throws {
        let command = try WatchCycleTimeCommand(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000281")!,
            homeProfileID: UUID(uuidString: "00000000-0000-0000-0000-000000000282")!,
            totalSeconds: 42,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(try JSONDecoder().decode(WatchCycleTimeCommand.self, from: JSONEncoder().encode(command)), command)
        XCTAssertThrowsError(try WatchCycleTimeCommand(homeProfileID: command.homeProfileID, totalSeconds: 0))
        XCTAssertThrowsError(try WatchCycleTimeCommand(
            homeProfileID: command.homeProfileID,
            totalSeconds: WatchCycleTimeCommand.maximumDurationSeconds + 1
        ))
        XCTAssertFalse(WatchCycleTimeCommandResponseValidator.accepts(
            WatchCycleTimeAcknowledgement(commandID: UUID(), status: .applied),
            for: command
        ))
        XCTAssertTrue(WatchCycleTimeCommandResponseValidator.accepts(
            WatchCycleTimeAcknowledgement(commandID: command.id, status: .applied),
            for: command
        ))
    }

    func testWatchCycleTimeOutboxPersistsTimerAndIdempotentFIFOCommands() throws {
        let homeID = UUID(uuidString: "00000000-0000-0000-0000-000000000283")!
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var outbox = WatchCycleTimeOutbox()
        outbox.start(homeProfileID: homeID, at: start)
        outbox.pause(at: start.addingTimeInterval(0.65))
        XCTAssertEqual(outbox.elapsedSeconds(at: start.addingTimeInterval(1)), 0.65, accuracy: 0.001)
        let pausedRestore = try JSONDecoder().decode(WatchCycleTimeOutbox.self, from: JSONEncoder().encode(outbox))
        XCTAssertEqual(pausedRestore, outbox)
        XCTAssertFalse(pausedRestore.isRunning)
        outbox = pausedRestore
        outbox.start(homeProfileID: homeID, at: start.addingTimeInterval(10))
        let command = try XCTUnwrap(outbox.finish(at: start.addingTimeInterval(10.85)))
        XCTAssertEqual(command.totalSeconds, 1)
        XCTAssertNil(try outbox.finish(at: start.addingTimeInterval(12)))
        XCTAssertTrue(try outbox.enqueue(command))
        XCTAssertFalse(try outbox.enqueue(command))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchCycleTimeOutboxFileStore(fileURL: directory.appendingPathComponent("cycle.json"))
        try store.save(outbox)
        var restored = try store.load()
        XCTAssertEqual(restored, outbox)
        XCTAssertFalse(restored.acknowledgeHead(WatchCycleTimeAcknowledgement(commandID: UUID(), status: .applied)))
        XCTAssertTrue(restored.acknowledgeHead(WatchCycleTimeAcknowledgement(commandID: command.id, status: .applied)))
        XCTAssertEqual(restored.count, 0)
    }

    func testWatchCycleTimeOutboxFileStoreRejectsOversizedFileWithoutChangingIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let fileURL = directory.appendingPathComponent("cycle-outbox.json")
        let oversizedData = Data(repeating: 0x20, count: WatchCycleTimeOutboxFileStore.maximumFileSizeBytes + 1)
        try oversizedData.write(to: fileURL)
        let store = WatchCycleTimeOutboxFileStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? WatchCycleTimeOutboxFileStoreError, .fileTooLarge)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((attributes[.size] as? NSNumber)?.intValue, oversizedData.count)
    }

    func testWatchCycleTimeOutboxFileStoreRejectsMalformedFileWithoutChangingIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let fileURL = directory.appendingPathComponent("cycle-outbox.json")
        let malformed = Data(#"{"schemaVersion":99,"pendingCommands":[],"accumulatedMilliseconds":0}"#.utf8)
        try malformed.write(to: fileURL)
        let store = WatchCycleTimeOutboxFileStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: fileURL), malformed)
    }

    func testWatchCycleTimeOutboxStoresItsMaximumValidQueueWithinFileLimit() throws {
        let homeID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var outbox = WatchCycleTimeOutbox()
        for _ in 0..<WatchCycleTimeOutbox.maximumPendingCommandCount {
            _ = try outbox.enqueue(WatchCycleTimeCommand(
                homeProfileID: homeID,
                totalSeconds: 1,
                createdAt: date
            ))
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchCycleTimeOutboxFileStore(fileURL: directory.appendingPathComponent("cycle-outbox.json"))
        try store.save(outbox)
        XCTAssertEqual(try store.load(), outbox)
        XCTAssertEqual(outbox.count, WatchCycleTimeOutbox.maximumPendingCommandCount)
    }

    func testWatchCycleTimeOutboxKeepsHomeAndRetainsSubsecondMeasurementUntilSaveable() throws {
        let firstHomeID = UUID(uuidString: "00000000-0000-0000-0000-000000000284")!
        let otherHomeID = UUID(uuidString: "00000000-0000-0000-0000-000000000285")!
        let start = Date(timeIntervalSince1970: 1_700_000_100)
        var outbox = WatchCycleTimeOutbox()
        outbox.start(homeProfileID: firstHomeID, at: start)
        outbox.start(homeProfileID: otherHomeID, at: start.addingTimeInterval(0.1))
        XCTAssertEqual(outbox.activeHomeProfileID, firstHomeID)

        outbox.pause(at: start.addingTimeInterval(0.499))
        XCTAssertNil(try outbox.finish(at: start.addingTimeInterval(0.499)))
        XCTAssertEqual(outbox.elapsedSeconds(at: start.addingTimeInterval(0.499)), 0.499, accuracy: 0.001)

        outbox.start(homeProfileID: firstHomeID, at: start.addingTimeInterval(1))
        let command = try XCTUnwrap(outbox.finish(at: start.addingTimeInterval(1.501)))
        XCTAssertEqual(command.homeProfileID, firstHomeID)
        XCTAssertEqual(command.totalSeconds, 1)
        XCTAssertNil(outbox.activeHomeProfileID)
    }

    func testWatchCycleTimeOutboxRejectsConflictingIDsAndOutOfOrderAcknowledgements() throws {
        let homeID = UUID(uuidString: "00000000-0000-0000-0000-000000000286")!
        let first = try WatchCycleTimeCommand(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000287")!,
            homeProfileID: homeID,
            totalSeconds: 10,
            createdAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let conflicting = try WatchCycleTimeCommand(
            id: first.id,
            homeProfileID: homeID,
            totalSeconds: 11,
            createdAt: first.createdAt
        )
        let second = try WatchCycleTimeCommand(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000288")!,
            homeProfileID: homeID,
            totalSeconds: 12,
            createdAt: first.createdAt
        )
        var outbox = WatchCycleTimeOutbox()
        XCTAssertTrue(try outbox.enqueue(first))
        XCTAssertFalse(try outbox.enqueue(first))
        XCTAssertThrowsError(try outbox.enqueue(conflicting))
        XCTAssertTrue(try outbox.enqueue(second))
        XCTAssertFalse(outbox.acknowledgeHead(
            WatchCycleTimeAcknowledgement(commandID: second.id, status: .applied)
        ))
        XCTAssertEqual(outbox.nextCommand?.id, first.id)
        XCTAssertTrue(outbox.acknowledgeHead(
            WatchCycleTimeAcknowledgement(commandID: first.id, status: .applied)
        ))
        XCTAssertEqual(outbox.nextCommand?.id, second.id)
    }

    func testWatchCounterCatalogRejectsDuplicateIDsInvalidValuesAndUnsupportedTools() throws {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000271")!
        let homeID = UUID(uuidString: "00000000-0000-0000-0000-000000000272")!
        let snapshot = WatchCounterSessionSnapshot(
            sessionID: sessionID,
            homeProfileID: homeID,
            homeName: "Production",
            toolID: .defectCounter,
            sessionName: "Defects",
            currentCount: 0,
            targetCount: 0
        )
        XCTAssertThrowsError(try WatchCounterCatalog(sessions: [snapshot, snapshot]))
        XCTAssertThrowsError(try WatchCounterCatalog(sessions: [WatchCounterSessionSnapshot(
            sessionID: UUID(), homeProfileID: homeID, homeName: "Production", toolID: .productionCounter,
            sessionName: "Counter", currentCount: -1, targetCount: 0
        )]))
        XCTAssertThrowsError(try WatchCounterCatalog(sessions: [WatchCounterSessionSnapshot(
            sessionID: UUID(), homeProfileID: homeID, homeName: "Production", toolID: .cycleTime,
            sessionName: "Cycle Time", currentCount: 0, targetCount: 0
        )]))
        let progressCard = WatchProductionProgressSnapshot(
            cardID: UUID(uuidString: "00000000-0000-0000-0000-000000000273")!,
            sessionID: sessionID,
            homeProfileID: homeID,
            homeName: "Production",
            currentCount: 10,
            targetCount: 20
        )
        XCTAssertThrowsError(try WatchCounterCatalog(sessions: [], progressCards: [progressCard, progressCard]))
        XCTAssertThrowsError(try WatchCounterCatalog(sessions: [], progressCards: [WatchProductionProgressSnapshot(
            cardID: UUID(), sessionID: sessionID, homeProfileID: homeID, homeName: "Production",
            currentCount: -1, targetCount: 20
        )]))
    }

    func testWatchCommandResponseMustMatchCommandAndValidSessionSnapshot() throws {
        let command = CounterCommand(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000191")!,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000192")!,
            operation: .increment
        )
        let matchingAck = CounterCommandAcknowledgement(commandID: command.id, status: .applied)
        let unrelatedAck = CounterCommandAcknowledgement(commandID: UUID(), status: .applied)
        let snapshot = WatchCounterSessionSnapshot(
            sessionID: command.sessionID,
            homeProfileID: UUID(uuidString: "00000000-0000-0000-0000-000000000193")!,
            homeName: "Assembly",
            toolID: .productionCounter,
            sessionName: "Production",
            currentCount: 1,
            targetCount: 600
        )
        let wrongSession = WatchCounterSessionSnapshot(
            sessionID: UUID(), homeProfileID: snapshot.homeProfileID, homeName: "Assembly",
            toolID: .productionCounter, sessionName: "Other", currentCount: 1, targetCount: 600
        )
        let invalidSnapshot = WatchCounterSessionSnapshot(
            sessionID: command.sessionID, homeProfileID: snapshot.homeProfileID, homeName: "Assembly",
            toolID: .productionCounter, sessionName: "Production", currentCount: -1, targetCount: 600
        )

        XCTAssertTrue(WatchCounterCommandResponseValidator.acknowledgement(matchingAck, matches: command))
        XCTAssertFalse(WatchCounterCommandResponseValidator.acknowledgement(unrelatedAck, matches: command))
        XCTAssertTrue(WatchCounterCommandResponseValidator.snapshot(snapshot, matches: command))
        XCTAssertFalse(WatchCounterCommandResponseValidator.snapshot(wrongSession, matches: command))
        XCTAssertFalse(WatchCounterCommandResponseValidator.snapshot(invalidSnapshot, matches: command))
        XCTAssertTrue(CounterCommandResponseValidator.isComplete(matchingAck, snapshot: snapshot, matches: command))
        XCTAssertFalse(CounterCommandResponseValidator.isComplete(matchingAck, snapshot: nil, matches: command))
        XCTAssertFalse(CounterCommandResponseValidator.isComplete(unrelatedAck, snapshot: snapshot, matches: command))
        XCTAssertFalse(CounterCommandResponseValidator.isComplete(matchingAck, snapshot: wrongSession, matches: command))
        XCTAssertFalse(CounterCommandResponseValidator.isComplete(matchingAck, snapshot: invalidSnapshot, matches: command))

        let unavailableAck = CounterCommandAcknowledgement(commandID: command.id, status: .rejected)
        let noChangeAck = CounterCommandAcknowledgement(commandID: command.id, status: .noChange)
        XCTAssertTrue(CounterCommandResponseValidator.indicatesUnavailableSession(
            unavailableAck, snapshot: nil, matches: command
        ))
        XCTAssertFalse(CounterCommandResponseValidator.indicatesUnavailableSession(
            unavailableAck, snapshot: snapshot, matches: command
        ))
        XCTAssertFalse(CounterCommandResponseValidator.indicatesUnavailableSession(
            CounterCommandAcknowledgement(commandID: UUID(), status: .rejected), snapshot: nil, matches: command
        ))
        XCTAssertFalse(CounterCommandResponseValidator.indicatesUnavailableSession(
            noChangeAck, snapshot: nil, matches: command
        ))

        for status in CounterCommandAcknowledgementStatus.allCases {
            let statusAck = CounterCommandAcknowledgement(commandID: command.id, status: status)
            XCTAssertTrue(CounterCommandResponseValidator.isComplete(statusAck, snapshot: snapshot, matches: command))
            XCTAssertEqual(
                CounterCommandResponseValidator.isComplete(statusAck, snapshot: nil, matches: command),
                !status.requiresAuthoritativeSnapshot
            )
        }
    }

    func testCounterPeerMessagesRoundTripAndRejectMismatchedPayloads() throws {
        let command = CounterCommand(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000171")!,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000172")!,
            operation: .quickAdd(5)
        )
        let snapshot = WatchCounterSessionSnapshot(
            sessionID: command.sessionID,
            homeProfileID: UUID(uuidString: "00000000-0000-0000-0000-000000000173")!,
            homeName: "Assembly",
            toolID: .productionCounter,
            sessionName: "Production",
            currentCount: 5,
            targetCount: 600
        )
        let catalog = try WatchCounterCatalog(sessions: [snapshot])
        let acknowledgement = CounterCommandAcknowledgement(commandID: command.id, status: .applied)
        let messages = [
            CounterPeerMessage.catalogRequest(),
            CounterPeerMessage.catalog(catalog),
            CounterPeerMessage.command(command),
            CounterPeerMessage.commandResult(acknowledgement, session: snapshot),
        ]
        for message in messages {
            let restored = try JSONDecoder().decode(CounterPeerMessage.self, from: JSONEncoder().encode(message))
            XCTAssertEqual(restored, message)
        }

        var malformed = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(messages[0])) as? [String: Any])
        malformed["command"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(command))
        let malformedData = try JSONSerialization.data(withJSONObject: malformed)
        XCTAssertThrowsError(try JSONDecoder().decode(CounterPeerMessage.self, from: malformedData))

        malformed["schemaVersion"] = CounterPeerMessage.currentSchemaVersion + 1
        let unsupportedData = try JSONSerialization.data(withJSONObject: malformed)
        XCTAssertThrowsError(try JSONDecoder().decode(CounterPeerMessage.self, from: unsupportedData))
    }

    func testCounterPeerFramesHandleFragmentationCoalescingAndBounds() throws {
        let first = CounterPeerMessage.catalogRequest(messageID: UUID(uuidString: "00000000-0000-0000-0000-000000000161")!)
        let second = CounterPeerMessage.catalogRequest(messageID: UUID(uuidString: "00000000-0000-0000-0000-000000000162")!)
        let firstFrame = try CounterPeerFrameCodec.encode(first)
        let secondFrame = try CounterPeerFrameCodec.encode(second)
        var decoder = CounterPeerFrameDecoder()

        XCTAssertTrue(try decoder.append(Data(firstFrame.prefix(2))).isEmpty)
        XCTAssertEqual(decoder.bufferedByteCount, 2)
        XCTAssertEqual(try decoder.append(Data(firstFrame.dropFirst(2))), [first])
        XCTAssertEqual(decoder.bufferedByteCount, 0)

        var joinedFrames = firstFrame
        joinedFrames.append(secondFrame)
        XCTAssertEqual(try decoder.append(joinedFrames), [first, second])

        let coalescedFrameCount = 15_000
        var largeCoalescedBatch = Data()
        largeCoalescedBatch.reserveCapacity(firstFrame.count * coalescedFrameCount)
        for _ in 0..<coalescedFrameCount {
            largeCoalescedBatch.append(firstFrame)
        }
        XCTAssertGreaterThan(largeCoalescedBatch.count, CounterPeerFrameCodec.maximumFrameLength)
        var largeBatchDecoder = CounterPeerFrameDecoder()
        XCTAssertEqual(try largeBatchDecoder.append(largeCoalescedBatch).count, coalescedFrameCount)
        XCTAssertEqual(largeBatchDecoder.bufferedByteCount, 0)

        var zeroLengthDecoder = CounterPeerFrameDecoder()
        XCTAssertThrowsError(try zeroLengthDecoder.append(Data([0, 0, 0, 0]))) { error in
            XCTAssertEqual(error as? CounterPeerFrameError, .invalidLength)
        }
        var oversizedDecoder = CounterPeerFrameDecoder()
        XCTAssertThrowsError(try oversizedDecoder.append(Data([0, 16, 0, 1]))) { error in
            XCTAssertEqual(error as? CounterPeerFrameError, .frameTooLarge)
        }
    }

    func testOutboxPreservesFIFOAcrossEncodingAndOnlyAcknowledgesHead() throws {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let first = CounterCommand(id: UUID(uuidString: "00000000-0000-0000-0000-000000000211")!, sessionID: sessionID, operation: .increment)
        let second = CounterCommand(id: UUID(uuidString: "00000000-0000-0000-0000-000000000212")!, sessionID: sessionID, operation: .quickAdd(5))
        var outbox = CounterCommandOutbox()
        XCTAssertTrue(try outbox.enqueue(first))
        XCTAssertTrue(try outbox.enqueue(second))

        let restored = try JSONDecoder().decode(CounterCommandOutbox.self, from: JSONEncoder().encode(outbox))
        XCTAssertEqual(restored, outbox)
        XCTAssertEqual(restored.nextCommand, first)
        XCTAssertFalse(outbox.acknowledgeHead(CounterCommandAcknowledgement(commandID: second.id, status: .applied)))
        XCTAssertEqual(outbox.nextCommand, first)
        XCTAssertTrue(outbox.acknowledgeHead(CounterCommandAcknowledgement(commandID: first.id, status: .applied)))
        XCTAssertEqual(outbox.nextCommand, second)
        XCTAssertTrue(outbox.acknowledgeHead(CounterCommandAcknowledgement(commandID: second.id, status: .alreadyApplied)))
        XCTAssertTrue(outbox.isEmpty)
        XCTAssertFalse(outbox.acknowledgeHead(CounterCommandAcknowledgement(commandID: second.id, status: .alreadyApplied)))
    }

    func testOutboxSuppressesExactRetriesAndRejectsChangedPayloadForSameID() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000221")!
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000222")!
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let original = CounterCommand(id: id, sessionID: sessionID, operation: .increment, createdAt: timestamp)
        var outbox = CounterCommandOutbox()

        XCTAssertTrue(try outbox.enqueue(original))
        XCTAssertFalse(try outbox.enqueue(original))
        XCTAssertEqual(outbox.count, 1)
        XCTAssertThrowsError(try outbox.enqueue(CounterCommand(
            id: id,
            sessionID: sessionID,
            operation: .decrement,
            createdAt: timestamp
        ))) { error in
            XCTAssertEqual(error as? CounterCommandOutboxError, .identifierConflict(commandID: id))
        }
        XCTAssertEqual(outbox.pendingCommands, [original])
    }

    func testOutboxCapacityPreservesSavedCommandsAndResumesAfterAcknowledgement() throws {
        var outbox = CounterCommandOutbox()
        let sessionID = UUID()
        var firstCommand: CounterCommand?
        for _ in 0..<CounterCommandOutbox.maximumPendingCommandCount {
            let command = CounterCommand(sessionID: sessionID, operation: .increment)
            if firstCommand == nil { firstCommand = command }
            _ = try outbox.enqueue(command)
        }
        let savedCommands = outbox.pendingCommands
        let rejectedCommand = CounterCommand(sessionID: sessionID, operation: .increment)

        let exactLimitPayload = try JSONEncoder().encode(outbox)
        XCTAssertEqual(
            try JSONDecoder().decode(CounterCommandOutbox.self, from: exactLimitPayload).count,
            CounterCommandOutbox.maximumPendingCommandCount
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CounterCommandOutboxFileStore(fileURL: directory.appendingPathComponent("counter-outbox.json"))
        try store.save(outbox)
        XCTAssertEqual(try store.load(), outbox)
        XCTAssertThrowsError(try outbox.enqueue(rejectedCommand)) { error in
            XCTAssertEqual(
                error as? CounterCommandOutboxError,
                .pendingLimitReached(maximumCount: CounterCommandOutbox.maximumPendingCommandCount)
            )
        }
        XCTAssertEqual(outbox.count, CounterCommandOutbox.maximumPendingCommandCount)
        XCTAssertEqual(outbox.pendingCommands, savedCommands)
        XCTAssertEqual(outbox.nextCommand, firstCommand)
        let acknowledged = try XCTUnwrap(firstCommand)
        XCTAssertFalse(try outbox.enqueue(acknowledged))
        XCTAssertTrue(outbox.acknowledgeHead(commandID: acknowledged.id))
        XCTAssertTrue(try outbox.enqueue(rejectedCommand))
        XCTAssertEqual(outbox.count, CounterCommandOutbox.maximumPendingCommandCount)
    }

    func testOutboxCanDiscardAllCommandsForAnUnavailableSessionAndPreserveOtherFIFOItems() throws {
        let unavailableSession = UUID(uuidString: "00000000-0000-0000-0000-000000000225")!
        let otherSession = UUID(uuidString: "00000000-0000-0000-0000-000000000226")!
        let commands = [
            CounterCommand(id: UUID(), sessionID: unavailableSession, operation: .increment),
            CounterCommand(id: UUID(), sessionID: otherSession, operation: .decrement),
            CounterCommand(id: UUID(), sessionID: unavailableSession, operation: .quickAdd(5)),
        ]
        var outbox = CounterCommandOutbox()
        for command in commands { _ = try outbox.enqueue(command) }

        XCTAssertEqual(outbox.discardCommands(for: unavailableSession), 2)
        XCTAssertEqual(outbox.pendingCommands, [commands[1]])
        XCTAssertEqual(outbox.nextCommand, commands[1])
        XCTAssertEqual(outbox.discardCommands(for: unavailableSession), 0)
    }

    func testOutboxEnqueueTransactionKeepsCurrentQueueWhenPersistenceFails() throws {
        let existing = CounterCommand(sessionID: UUID(), operation: .increment)
        let addition = CounterCommand(sessionID: UUID(), operation: .quickAdd(5))
        var current = CounterCommandOutbox()
        _ = try current.enqueue(existing)
        let durableQueue = current
        var attemptedSave: CounterCommandOutbox?

        XCTAssertThrowsError(try CounterCommandOutboxTransaction.enqueue(addition, into: current) { candidate in
            attemptedSave = candidate
            throw SimulatedOutboxPersistenceError.unavailable
        })

        XCTAssertEqual(current.pendingCommands, [existing])
        XCTAssertEqual(durableQueue.pendingCommands, [existing])
        XCTAssertEqual(attemptedSave?.pendingCommands, [existing, addition])
    }

    func testOutboxAcknowledgementTransactionKeepsHeadWhenPersistenceFails() throws {
        let command = CounterCommand(sessionID: UUID(), operation: .increment)
        var current = CounterCommandOutbox()
        _ = try current.enqueue(command)
        let acknowledgement = CounterCommandAcknowledgement(commandID: command.id, status: .applied)
        let snapshot = WatchCounterSessionSnapshot(
            sessionID: command.sessionID,
            homeProfileID: UUID(),
            homeName: "Assembly",
            toolID: .productionCounter,
            sessionName: "Production",
            currentCount: 1,
            targetCount: 600
        )
        let durableQueue = current
        var attemptedSave: CounterCommandOutbox?

        XCTAssertThrowsError(try CounterCommandOutboxTransaction.acknowledge(
            acknowledgement,
            snapshot: snapshot,
            command: command,
            in: current
        ) { candidate in
            attemptedSave = candidate
            throw SimulatedOutboxPersistenceError.unavailable
        })

        XCTAssertEqual(current.pendingCommands, [command])
        XCTAssertEqual(durableQueue.pendingCommands, [command])
        XCTAssertEqual(attemptedSave?.pendingCommands, [])
    }

    func testOutboxAcknowledgementTransactionRejectsAcknowledgementForPriorHead() throws {
        let completedCommand = CounterCommand(sessionID: UUID(), operation: .increment)
        let currentHead = CounterCommand(sessionID: UUID(), operation: .decrement)
        var current = CounterCommandOutbox()
        _ = try current.enqueue(currentHead)
        let acknowledgement = CounterCommandAcknowledgement(commandID: completedCommand.id, status: .rejected)

        XCTAssertThrowsError(try CounterCommandOutboxTransaction.acknowledge(
            acknowledgement,
            snapshot: nil,
            command: completedCommand,
            in: current
        ) { _ in
            XCTFail("A stale acknowledgement must not attempt to persist the current queue")
        }) { error in
            XCTAssertEqual(error as? CounterCommandOutboxTransactionError, .commandIsNotHead)
        }
        XCTAssertEqual(current.pendingCommands, [currentHead])
    }

    func testUnavailableSessionTransactionKeepsAllCommandsWhenPersistenceFails() throws {
        let unavailableSession = UUID()
        let otherSession = UUID()
        let unavailableHead = CounterCommand(sessionID: unavailableSession, operation: .increment)
        let otherCommand = CounterCommand(sessionID: otherSession, operation: .decrement)
        let unavailableLater = CounterCommand(sessionID: unavailableSession, operation: .quickAdd(5))
        var current = CounterCommandOutbox()
        _ = try current.enqueue(unavailableHead)
        _ = try current.enqueue(otherCommand)
        _ = try current.enqueue(unavailableLater)
        let durableQueue = current
        let rejection = CounterCommandAcknowledgement(commandID: unavailableHead.id, status: .rejected)
        var attemptedSave: CounterCommandOutbox?

        XCTAssertThrowsError(try CounterCommandOutboxTransaction.acknowledge(
            rejection,
            snapshot: nil,
            command: unavailableHead,
            in: current
        ) { candidate in
            attemptedSave = candidate
            throw SimulatedOutboxPersistenceError.unavailable
        })

        XCTAssertEqual(current.pendingCommands, [unavailableHead, otherCommand, unavailableLater])
        XCTAssertEqual(durableQueue.pendingCommands, [unavailableHead, otherCommand, unavailableLater])
        XCTAssertEqual(attemptedSave?.pendingCommands, [otherCommand])
    }

    func testCounterCommandRetryPolicyUsesBoundedExponentialDelays() {
        let delays = (-2...8).map { CounterCommandRetryPolicy.delaySeconds(forAttempt: $0) }
        XCTAssertEqual(delays, [1, 1, 1, 2, 4, 8, 16, 30, 30, 30, 30])
    }

    func testOutboxDecoderRejectsDuplicatePersistedCommandIDs() throws {
        let command = CounterCommand(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000231")!,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000232")!,
            operation: .increment,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let commandJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? [String: Any])
        let payload = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": CounterCommandOutbox.currentSchemaVersion,
            "pendingCommands": [commandJSON, commandJSON],
        ])

        XCTAssertThrowsError(try JSONDecoder().decode(CounterCommandOutbox.self, from: payload))
    }

    func testOutboxDecoderRejectsMoreThanMaximumPendingCommands() throws {
        let sessionID = UUID()
        let commands = (0...CounterCommandOutbox.maximumPendingCommandCount).map { _ in
            CounterCommand(sessionID: sessionID, operation: .increment)
        }
        let encodedCommands = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(commands)) as? [[String: Any]]
        )
        let payload = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": CounterCommandOutbox.currentSchemaVersion,
            "pendingCommands": encodedCommands,
        ])

        XCTAssertThrowsError(try JSONDecoder().decode(CounterCommandOutbox.self, from: payload))
    }

    func testOutboxFileStoreLoadsMissingFileAndPersistsAcrossFreshInstances() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("counter-outbox.json")
        let firstStore = CounterCommandOutboxFileStore(fileURL: fileURL)
        XCTAssertTrue(try firstStore.load().isEmpty)

        var outbox = CounterCommandOutbox()
        let command = CounterCommand(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000241")!,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000242")!,
            operation: .quickAdd(9),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        _ = try outbox.enqueue(command)
        try firstStore.save(outbox)

        let reopenedStore = CounterCommandOutboxFileStore(fileURL: fileURL)
        XCTAssertEqual(try reopenedStore.load(), outbox)
    }

    func testOutboxFileStoreDoesNotSilentlyReplaceMalformedQueue() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("counter-outbox.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let malformed = Data(#"{"schemaVersion":99,"pendingCommands":[]}"#.utf8)
        try malformed.write(to: fileURL)
        let store = CounterCommandOutboxFileStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: fileURL), malformed)
    }

    func testOutboxFileStoreRejectsOversizedFileBeforeDecodingAndLeavesItUntouched() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let fileURL = directory.appendingPathComponent("counter-outbox.json")
        let oversizedData = Data(repeating: 0x20, count: CounterCommandOutboxFileStore.maximumFileSizeBytes + 1)
        try oversizedData.write(to: fileURL)
        let store = CounterCommandOutboxFileStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? CounterCommandOutboxFileStoreError, .fileTooLarge)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((attributes[.size] as? NSNumber)?.intValue, oversizedData.count)
    }

    func testCounterCommandSignatureIsStableAndMatchesItsEvent() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let command = CounterCommand(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            operation: .quickAdd(5),
            createdAt: timestamp
        )

        XCTAssertEqual(command.payloadSignature, "schema=1|operation=quickAdd:5|date=41d954fc40000000")
        XCTAssertTrue(CounterCommand.payloadSignature(
            command.payloadSignature,
            matches: CounterEventKind.quickAdd.rawValue,
            delta: 5,
            reversesEventID: nil,
            occurredAt: timestamp
        ))
        XCTAssertFalse(CounterCommand.payloadSignature(
            command.payloadSignature,
            matches: CounterEventKind.quickAdd.rawValue,
            delta: 6,
            reversesEventID: nil,
            occurredAt: timestamp
        ))
    }

    func testCounterCommandSignatureValidationRejectsMalformedValues() {
        XCTAssertTrue(CounterCommand.isWellFormedPayloadSignature("schema=1|operation=increment|date=0"))
        XCTAssertFalse(CounterCommand.isWellFormedPayloadSignature("schema=01|operation=increment|date=0"))
        XCTAssertFalse(CounterCommand.isWellFormedPayloadSignature("schema=1|operation=quickAdd:0x10|date=0"))
        XCTAssertTrue(CounterCommand.isWellFormedPayloadSignature("schema=1|operation=setTarget:0|date=0"))
        XCTAssertFalse(CounterCommand.isWellFormedPayloadSignature("schema=1|operation=setTarget:-1|date=0"))
        XCTAssertFalse(CounterCommand.isWellFormedPayloadSignature("schema=1|operation=increment|date=zz"))
        XCTAssertFalse(CounterCommand.isWellFormedPayloadSignature("schema=1|operation=increment|date=7ff0000000000000"))
        XCTAssertFalse(CounterCommand.isWellFormedPayloadSignature("schema=1|operation=évent|date=0"))
        XCTAssertTrue(CounterCommand.isWellFormedPayloadSignature("schema=2|operation=vendor.operation|date=3ff0000000000000"))
        XCTAssertTrue(CounterCommand.isWellFormedPayloadSignature(
            "schema=1|operation=\(String(repeating: "a", count: 486))|date=0"
        ))
        XCTAssertFalse(CounterCommand.isWellFormedPayloadSignature(
            "schema=1|operation=\(String(repeating: "a", count: 487))|date=0"
        ))
    }

    func testPersistedTimestampAcceptsFourDigitYearRangeOnly() {
        XCTAssertTrue(PersistedTimestamp.isSupported(Date(timeIntervalSince1970: -62_135_596_800)))
        XCTAssertTrue(PersistedTimestamp.isSupported(Date(timeIntervalSince1970: -62_135_596_799)))
        XCTAssertTrue(PersistedTimestamp.isSupported(Date(timeIntervalSince1970: 253_402_300_799)))
        XCTAssertFalse(PersistedTimestamp.isSupported(Date(timeIntervalSince1970: 253_402_300_800)))
        XCTAssertFalse(PersistedTimestamp.isSupported(Date(timeIntervalSince1970: .infinity)))
        XCTAssertFalse(PersistedTimestamp.isSupported(Date(timeIntervalSince1970: -.infinity)))
        XCTAssertFalse(PersistedTimestamp.isSupported(Date(timeIntervalSince1970: .nan)))
    }

    func testCounterCommandSignatureMatchesEveryKnownEventShape() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let undoID = UUID(uuidString: "00000000-0000-0000-0000-000000000303")!
        let cases: [(CounterCommandOperation, String, Int, UUID?)] = [
            (.increment, CounterEventKind.increment.rawValue, 1, nil),
            (.decrement, CounterEventKind.decrement.rawValue, -1, nil),
            (.quickAdd(12), CounterEventKind.quickAdd.rawValue, 12, nil),
            (.reset, CounterEventKind.reset.rawValue, -25, nil),
            (.undo(eventID: undoID), CounterEventKind.undo.rawValue, 7, undoID),
        ]

        for (operation, kind, delta, reversesEventID) in cases {
            let command = CounterCommand(
                id: UUID(),
                sessionID: UUID(),
                operation: operation,
                createdAt: timestamp
            )
            XCTAssertTrue(CounterCommand.payloadSignature(
                command.payloadSignature,
                matches: kind,
                delta: delta,
                reversesEventID: reversesEventID,
                occurredAt: timestamp
            ))
            XCTAssertFalse(CounterCommand.payloadSignature(
                command.payloadSignature,
                matches: kind,
                delta: delta,
                reversesEventID: reversesEventID,
                occurredAt: timestamp.addingTimeInterval(1)
            ))
        }
    }

    func testTargetCommandSignatureCannotBeMistakenForCountEvent() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let command = CounterCommand(sessionID: UUID(), operation: .setTarget(900), createdAt: createdAt)

        XCTAssertFalse(CounterCommand.payloadSignature(
            command.payloadSignature,
            matches: CounterEventKind.increment.rawValue,
            delta: 1,
            reversesEventID: nil,
            occurredAt: createdAt
        ))
    }

    func testProductionProgressClampsAtBothBoundaries() {
        XCTAssertEqual(ProductionProgressMath.fraction(currentCount: -5, targetCount: 10), 0)
        XCTAssertEqual(ProductionProgressMath.fraction(currentCount: 5, targetCount: 10), 0.5)
        XCTAssertEqual(ProductionProgressMath.fraction(currentCount: 15, targetCount: 10), 1)
        XCTAssertEqual(ProductionProgressMath.fraction(currentCount: 5, targetCount: 0), 0)
    }

    func testPerUnitAndCycleTimeMathRejectNonpositiveInputs() {
        XCTAssertEqual(PerUnitTimeMath.secondsPerUnit(numeratorSeconds: 90, denominatorUnits: 3), 30)
        XCTAssertNil(CycleTimeCalculator.secondsPerUnit(totalSeconds: 0, quantity: 3))
        XCTAssertNil(TaktTimeCalculator.secondsPerUnit(netAvailableSeconds: 90, customerDemand: -1))
        XCTAssertEqual(CycleTimeMeasurement.roundedWholeSeconds(from: 2.6), 3)
        XCTAssertNil(CycleTimeMeasurement.roundedWholeSeconds(from: 0.49))
        XCTAssertNil(CycleTimeMeasurement.roundedWholeSeconds(from: -.infinity))
        XCTAssertNil(CycleTimeMeasurement.roundedWholeSeconds(from: .nan))
        XCTAssertNil(CycleTimeMeasurement.roundedWholeSeconds(from: .infinity))
        XCTAssertNil(CycleTimeMeasurement.roundedWholeSeconds(from: Double(Int.max)))
    }

    func testOEECalculationUsesDocumentedFactorsAndRejectsInvalidInputs() {
        let result = OEECalculator.calculate(
            plannedProductionMinutes: 60,
            downtimeMinutes: 10,
            idealCycleTimeSeconds: 30,
            goodUnits: 80,
            defectiveUnits: 20
        )
        XCTAssertEqual(result?.availability ?? 0, 5.0 / 6.0, accuracy: 0.000_001)
        XCTAssertEqual(result?.performance ?? 0, 1, accuracy: 0.000_001)
        XCTAssertEqual(result?.quality ?? 0, 0.8, accuracy: 0.000_001)
        XCTAssertEqual(result?.overall ?? 0, 2.0 / 3.0, accuracy: 0.000_001)
        let ideal = OEECalculator.calculate(
            plannedProductionMinutes: 60,
            downtimeMinutes: 0,
            idealCycleTimeSeconds: 30,
            goodUnits: 120,
            defectiveUnits: 0
        )
        XCTAssertEqual(ideal?.overall ?? 0, 1, accuracy: 0.000_001)
        XCTAssertEqual(ideal?.performance ?? 0, 1, accuracy: 0.000_001)
        let overTarget = OEECalculator.calculate(
            plannedProductionMinutes: 60,
            downtimeMinutes: 0,
            idealCycleTimeSeconds: 30,
            goodUnits: 240,
            defectiveUnits: 0
        )
        XCTAssertEqual(overTarget?.performance ?? 0, 2, accuracy: 0.000_001)
        XCTAssertEqual(overTarget?.overall ?? 0, 2, accuracy: 0.000_001)
        XCTAssertNil(OEECalculator.calculate(
            plannedProductionMinutes: 60,
            downtimeMinutes: 0,
            idealCycleTimeSeconds: 30,
            goodUnits: Int.max,
            defectiveUnits: 1
        ))
        XCTAssertNil(OEECalculator.calculate(
            plannedProductionMinutes: 60,
            downtimeMinutes: 0,
            idealCycleTimeSeconds: 30,
            goodUnits: 0,
            defectiveUnits: 0
        ))
        XCTAssertNil(OEECalculator.calculate(
            plannedProductionMinutes: 60,
            downtimeMinutes: 60,
            idealCycleTimeSeconds: 30,
            goodUnits: 80,
            defectiveUnits: 20
        ))
    }

    func testBoxPackingUsesBestSingleOrientationAndRejectsNoFit() {
        let result = BoxCalculator.maximumUnits(
            item: BoxDimensions(length: 2, width: 3, height: 4),
            innerBox: BoxDimensions(length: 8, width: 6, height: 4)
        )
        XCTAssertEqual(result?.unitsPerBox, 8)
        XCTAssertEqual(BoxCalculator.outcome(
            item: BoxDimensions(length: 0, width: 1, height: 1),
            innerBox: BoxDimensions(length: 10, width: 10, height: 10)
        ), .noFit)
        XCTAssertEqual(BoxCalculator.outcome(
            item: BoxDimensions(length: 1, width: 1, height: 1),
            innerBox: BoxDimensions(length: Int.max, width: Int.max, height: Int.max)
        ), .countTooLarge)
        XCTAssertNil(BoxCalculator.maximumUnits(
            item: BoxDimensions(length: 1, width: 1, height: 1),
            innerBox: BoxDimensions(length: Int.max, width: Int.max, height: Int.max)
        ))
    }

    func testEveryUnitPairRoundTripsWithinItsCategory() {
        for category in UnitCategory.allCases {
            XCTAssertEqual(Set(category.units.map(\.category)), Set([category]))
            for source in category.units {
                for target in category.units {
                    let converted = UnitConversion.convert(5, from: source, to: target)
                    XCTAssertNotNil(converted, "Missing conversion from \(source) to \(target)")
                    guard let converted else { continue }
                    let restored = UnitConversion.convert(converted, from: target, to: source)
                    XCTAssertEqual(restored ?? .nan, 5, accuracy: 1e-8, "Round trip failed from \(source) to \(target)")
                }
            }
        }
        XCTAssertEqual(Set(UnitCategory.allCases.flatMap(\.units)), Set(MeasurementUnit.allCases))
    }

    func testUnitConversionRejectsInvalidValuesAndEnforcesTemperatureFloor() {
        XCTAssertEqual(UnitConversion.convert(1, from: .meter, to: .centimeter) ?? 0, 100, accuracy: 0.000_001)
        XCTAssertEqual(UnitConversion.convert(12, from: .inch, to: .foot) ?? 0, 1, accuracy: 0.000_001)
        XCTAssertEqual(UnitConversion.convert(1, from: .kilogram, to: .gram) ?? 0, 1_000, accuracy: 0.000_001)
        XCTAssertEqual(UnitConversion.convert(1, from: .usGallon, to: .usFluidOunce) ?? 0, 128, accuracy: 0.000_001)
        XCTAssertEqual(UnitConversion.convert(32, from: .fahrenheit, to: .celsius) ?? 1, 0, accuracy: 0.000_001)
        XCTAssertEqual(UnitConversion.convert(-273.15, from: .celsius, to: .kelvin) ?? 1, 0, accuracy: 0.000_001)
        XCTAssertNil(UnitConversion.convert(1, from: .meter, to: .kilogram))
        XCTAssertNil(UnitConversion.convert(-1, from: .liter, to: .milliliter))
        XCTAssertNil(UnitConversion.convert(Double.greatestFiniteMagnitude, from: .kilometer, to: .millimeter))
        XCTAssertNil(UnitConversion.convert(.infinity, from: .meter, to: .meter))
        XCTAssertNil(UnitConversion.convert(.nan, from: .celsius, to: .fahrenheit))
        XCTAssertNil(UnitConversion.convert(-274, from: .celsius, to: .kelvin))
    }
}
