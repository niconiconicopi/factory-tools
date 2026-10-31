import Foundation
import XCTest
import Dispatch
import Network
import Security
import FactoryToolsCore
@testable import FactoryTools

final class LocalPeerPairingKeyStoreTests: XCTestCase {
    func testLocalPeerTLSParametersCompleteLoopbackPSKHandshake() throws {
        let pairingKey = Data(repeating: 0x5a, count: 32)
        let listenerParameters = try XCTUnwrap(LocalPeerTLSParameters.make(pairingKey: pairingKey))
        let clientParameters = try XCTUnwrap(LocalPeerTLSParameters.make(pairingKey: pairingKey))
        let listener = try NWListener(using: listenerParameters)
        let callbackQueue = DispatchQueue(label: "FactoryToolsTests.LocalPeerTLS")
        let listenerReady = expectation(description: "TLS-PSK listener becomes ready")
        let clientReady = expectation(description: "matching pairing key completes TLS-PSK handshake")

        listener.stateUpdateHandler = { state in
            if case .ready = state { listenerReady.fulfill() }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: callbackQueue)
        }
        listener.start(queue: callbackQueue)
        defer { listener.cancel() }

        wait(for: [listenerReady], timeout: 10)
        let port = try XCTUnwrap(listener.port)
        let client = NWConnection(
            to: .hostPort(host: "127.0.0.1", port: port),
            using: clientParameters
        )
        client.stateUpdateHandler = { state in
            if case .ready = state { clientReady.fulfill() }
        }
        client.start(queue: callbackQueue)
        defer { client.cancel() }

        wait(for: [clientReady], timeout: 10)
    }

    func testLocalPeerTLSParametersRejectMismatchedPairingKey() throws {
        let listenerKey = Data(repeating: 0x5a, count: 32)
        let wrongClientKey = Data(repeating: 0xa5, count: 32)
        let listenerParameters = try XCTUnwrap(LocalPeerTLSParameters.make(pairingKey: listenerKey))
        let clientParameters = try XCTUnwrap(LocalPeerTLSParameters.make(pairingKey: wrongClientKey))
        let listener = try NWListener(using: listenerParameters)
        let callbackQueue = DispatchQueue(label: "FactoryToolsTests.LocalPeerTLS.Rejection")
        let listenerReady = DispatchSemaphore(value: 0)
        let clientFinished = DispatchSemaphore(value: 0)
        var clientDidBecomeReady = false

        listener.stateUpdateHandler = { state in
            if case .ready = state { listenerReady.signal() }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: callbackQueue)
        }
        listener.start(queue: callbackQueue)
        defer { listener.cancel() }

        XCTAssertEqual(listenerReady.wait(timeout: .now() + 10), .success)
        let port = try XCTUnwrap(listener.port)
        let client = NWConnection(
            to: .hostPort(host: "127.0.0.1", port: port),
            using: clientParameters
        )
        client.stateUpdateHandler = { state in
            switch state {
            case .ready:
                clientDidBecomeReady = true
                clientFinished.signal()
            case .failed:
                clientFinished.signal()
            default:
                break
            }
        }
        client.start(queue: callbackQueue)
        defer { client.cancel() }

        XCTAssertEqual(clientFinished.wait(timeout: .now() + 10), .success)
        let connected = callbackQueue.sync { clientDidBecomeReady }
        XCTAssertFalse(connected, "a TLS-PSK peer with a different pairing key must not become ready")
    }

    func testPairingCodeDecodesThirtyTwoBytes() throws {
        let key = try LocalPeerPairingKeyStore.keyData(from: String(repeating: "a5", count: 32))

        XCTAssertEqual(key, Data(repeating: 0xa5, count: 32))
        XCTAssertEqual(
            LocalPeerPairingKeyStore.identity(for: key),
            "fc8b64001c5fdd0f2f40fb67dae4a865a2c5bd17836676d6d5b58b7917e33717"
        )
        XCTAssertNotEqual(
            LocalPeerPairingKeyStore.identity(for: key),
            LocalPeerPairingKeyStore.identity(for: Data(repeating: 0xa4, count: 32))
        )
    }

    func testPairingCodeRejectsWrongLengthAndNonHexCharacters() {
        XCTAssertThrowsError(try LocalPeerPairingKeyStore.keyData(from: String(repeating: "a", count: 63)))
        XCTAssertThrowsError(try LocalPeerPairingKeyStore.keyData(from: String(repeating: "g0", count: 32)))
    }

    func testPairingCodeChangeNeedsConfirmationOnlyForDifferentCodeWithPendingCommands() {
        XCTAssertTrue(LocalPeerPairingCodeChangePolicy.requiresConfirmation(
            currentCode: "a", proposedCode: "b", pendingCommandCount: 1
        ))
        XCTAssertFalse(LocalPeerPairingCodeChangePolicy.requiresConfirmation(
            currentCode: "a", proposedCode: "a", pendingCommandCount: 1
        ))
        XCTAssertFalse(LocalPeerPairingCodeChangePolicy.requiresConfirmation(
            currentCode: "a", proposedCode: "b", pendingCommandCount: 0
        ))
        XCTAssertTrue(LocalPeerPairingCodeChangePolicy.requiresConfirmation(
            currentCode: nil, proposedCode: "b", pendingCommandCount: 1
        ))
        XCTAssertFalse(LocalPeerPairingCodeChangePolicy.requiresConfirmation(
            currentCode: nil, proposedCode: "b", pendingCommandCount: -1
        ))
    }

    func testPairingCodeReplacementOrRemovalNeedsConfirmationWhenCodeExists() {
        XCTAssertTrue(LocalPeerPairingCodeChangePolicy.requiresConfirmationBeforeReset(currentCode: "active-code"))
        XCTAssertFalse(LocalPeerPairingCodeChangePolicy.requiresConfirmationBeforeReset(currentCode: nil))
    }

    func testRestoringSameAuthorityCodeSkipsConfirmationButChangingItRequiresConfirmation() {
        XCTAssertTrue(LocalPeerPairingCodeChangePolicy.requiresConfirmationBeforeAuthorityCodeChange(
            currentCode: "current-code", proposedCode: "saved-code"
        ))
        XCTAssertFalse(LocalPeerPairingCodeChangePolicy.requiresConfirmationBeforeAuthorityCodeChange(
            currentCode: "same-code", proposedCode: "same-code"
        ))
        XCTAssertFalse(LocalPeerPairingCodeChangePolicy.requiresConfirmationBeforeAuthorityCodeChange(
            currentCode: nil, proposedCode: "saved-code"
        ))
    }

    func testPairingSecretIsRedactedWhenSceneIsInactiveOrScreenIsCaptured() {
        XCTAssertFalse(PairingSecretVisibilityPolicy.shouldRedact(sceneIsActive: true, isScreenCaptured: false))
        XCTAssertTrue(PairingSecretVisibilityPolicy.shouldRedact(sceneIsActive: false, isScreenCaptured: false))
        XCTAssertTrue(PairingSecretVisibilityPolicy.shouldRedact(sceneIsActive: true, isScreenCaptured: true))
        XCTAssertTrue(PairingSecretVisibilityPolicy.shouldRedact(sceneIsActive: false, isScreenCaptured: true))
    }

    func testKeychainUpdateFailurePreservesExistingPairingItem() {
        var attemptedInsert = false

        let status = LocalPeerPairingKeyStore.upsertStatus(
            updateStatus: errSecInteractionNotAllowed,
            itemNotFoundStatus: errSecItemNotFound
        ) {
            attemptedInsert = true
            return errSecSuccess
        }

        XCTAssertEqual(status, errSecInteractionNotAllowed)
        XCTAssertFalse(attemptedInsert)
    }

    func testKeychainUpsertAddsOnlyWhenNoPairingItemExists() {
        var attemptedInsert = false

        let status = LocalPeerPairingKeyStore.upsertStatus(
            updateStatus: errSecItemNotFound,
            itemNotFoundStatus: errSecItemNotFound
        ) {
            attemptedInsert = true
            return errSecSuccess
        }

        XCTAssertEqual(status, errSecSuccess)
        XCTAssertTrue(attemptedInsert)
    }

    func testKeychainUpsertDoesNotReplaceSuccessfulUpdate() {
        var attemptedInsert = false

        let status = LocalPeerPairingKeyStore.upsertStatus(
            updateStatus: errSecSuccess,
            itemNotFoundStatus: errSecItemNotFound
        ) {
            attemptedInsert = true
            return errSecIO
        }

        XCTAssertEqual(status, errSecSuccess)
        XCTAssertFalse(attemptedInsert)
    }

    func testKeychainUpsertReturnsInitialRegistrationFailure() {
        let status = LocalPeerPairingKeyStore.upsertStatus(
            updateStatus: errSecItemNotFound,
            itemNotFoundStatus: errSecItemNotFound
        ) {
            errSecIO
        }

        XCTAssertEqual(status, errSecIO)
    }

    func testCounterOutboxesAreIsolatedByPairingSecret() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = LocalPeerCounterOutboxRepository(applicationSupportDirectory: directory)
        let firstKey = Data(repeating: 0x11, count: 32)
        let secondKey = Data(repeating: 0x22, count: 32)
        let sessionID = UUID()
        let firstCommand = CounterCommand(sessionID: sessionID, operation: .increment)
        let secondCommand = CounterCommand(sessionID: sessionID, operation: .decrement)
        var firstOutbox = CounterCommandOutbox()
        var secondOutbox = CounterCommandOutbox()
        _ = try firstOutbox.enqueue(firstCommand)
        _ = try secondOutbox.enqueue(secondCommand)

        try repository.save(firstOutbox, for: firstKey)
        try repository.save(secondOutbox, for: secondKey)
        let reopenedRepository = LocalPeerCounterOutboxRepository(applicationSupportDirectory: directory)

        XCTAssertEqual(try reopenedRepository.load(for: firstKey).pendingCommands, [firstCommand])
        XCTAssertEqual(try reopenedRepository.load(for: secondKey).pendingCommands, [secondCommand])
        XCTAssertNotEqual(
            LocalPeerPairingKeyStore.identity(for: firstKey),
            LocalPeerPairingKeyStore.identity(for: secondKey)
        )
    }

    func testLegacyOutboxStaysUnassignedUntilExplicitReassignment() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = LocalPeerCounterOutboxRepository(applicationSupportDirectory: directory)
        let pairingKey = Data(repeating: 0x33, count: 32)
        let command = CounterCommand(sessionID: UUID(), operation: .quickAdd(5))
        var legacy = CounterCommandOutbox()
        _ = try legacy.enqueue(command)
        let legacyURL = directory.appendingPathComponent("iPad-Counter-Outbox.json")
        try CounterCommandOutboxFileStore(fileURL: legacyURL).save(legacy)

        XCTAssertTrue(try repository.load(for: pairingKey).isEmpty)
        XCTAssertEqual(try repository.loadUnassignedLegacyOutbox().pendingCommands, [command])

        let assigned = try repository.reassignUnassignedLegacyOutbox(to: pairingKey)
        XCTAssertEqual(assigned.pendingCommands, [command])
        XCTAssertEqual(try repository.load(for: pairingKey).pendingCommands, [command])
        XCTAssertTrue(try repository.loadUnassignedLegacyOutbox().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertEqual(try repository.reassignUnassignedLegacyOutbox(to: pairingKey).pendingCommands, [command])
    }

    func testLegacyReassignmentConflictPreservesBothOutboxes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = LocalPeerCounterOutboxRepository(applicationSupportDirectory: directory)
        let pairingKey = Data(repeating: 0x44, count: 32)
        let commandID = UUID()
        let sessionID = UUID()
        let scopedCommand = CounterCommand(id: commandID, sessionID: sessionID, operation: .increment)
        let legacyCommand = CounterCommand(id: commandID, sessionID: sessionID, operation: .decrement)
        var scoped = CounterCommandOutbox()
        var legacy = CounterCommandOutbox()
        _ = try scoped.enqueue(scopedCommand)
        _ = try legacy.enqueue(legacyCommand)
        try repository.save(scoped, for: pairingKey)
        let legacyURL = directory.appendingPathComponent("iPad-Counter-Outbox.json")
        try CounterCommandOutboxFileStore(fileURL: legacyURL).save(legacy)

        XCTAssertThrowsError(try repository.reassignUnassignedLegacyOutbox(to: pairingKey))
        XCTAssertEqual(try repository.load(for: pairingKey).pendingCommands, [scopedCommand])
        XCTAssertEqual(try repository.loadUnassignedLegacyOutbox().pendingCommands, [legacyCommand])
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
    }

    func testMalformedLegacyOutboxRemainsUntouched() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = LocalPeerCounterOutboxRepository(applicationSupportDirectory: directory)
        let pairingKey = Data(repeating: 0x55, count: 32)
        let legacyURL = directory.appendingPathComponent("iPad-Counter-Outbox.json")
        let malformed = Data(#"{"schemaVersion":99,"pendingCommands":[]}"#.utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        try malformed.write(to: legacyURL)

        XCTAssertThrowsError(try repository.loadUnassignedLegacyOutbox())
        XCTAssertThrowsError(try repository.reassignUnassignedLegacyOutbox(to: pairingKey))
        XCTAssertEqual(try Data(contentsOf: legacyURL), malformed)
        XCTAssertTrue(try repository.load(for: pairingKey).isEmpty)
    }

    func testLegacyOutboxRemainsAvailableWhenScopedSaveFails() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = LocalPeerCounterOutboxRepository(applicationSupportDirectory: directory)
        let pairingKey = Data(repeating: 0x66, count: 32)
        let command = CounterCommand(sessionID: UUID(), operation: .increment)
        var legacy = CounterCommandOutbox()
        _ = try legacy.enqueue(command)
        let legacyURL = directory.appendingPathComponent("iPad-Counter-Outbox.json")
        try CounterCommandOutboxFileStore(fileURL: legacyURL).save(legacy)

        let scopedDirectory = directory.appendingPathComponent("iPad-Counter-Outboxes", isDirectory: true)
        try Data("not a directory".utf8).write(to: scopedDirectory)

        XCTAssertThrowsError(try repository.reassignUnassignedLegacyOutbox(to: pairingKey))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertEqual(try repository.loadUnassignedLegacyOutbox(), legacy)
    }
}
