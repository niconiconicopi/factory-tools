import FactoryToolsCore
import Foundation

struct LocalPeerCounterOutboxRepository {
    let applicationSupportDirectory: URL

    init(applicationSupportDirectory: URL? = nil) {
        self.applicationSupportDirectory = applicationSupportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("FactoryTools", isDirectory: true)
    }

    func load(for pairingKey: Data) throws -> CounterCommandOutbox {
        try scopedStore(for: pairingKey).load()
    }

    func save(_ outbox: CounterCommandOutbox, for pairingKey: Data) throws {
        try scopedStore(for: pairingKey).save(outbox)
    }

    func loadUnassignedLegacyOutbox() throws -> CounterCommandOutbox {
        try legacyStore.load()
    }

    /// Assigns the legacy queue only after the user chooses a pairing, and removes it only after the scoped save succeeds.
    func reassignUnassignedLegacyOutbox(to pairingKey: Data) throws -> CounterCommandOutbox {
        let legacy = try legacyStore.load()
        var scoped = try scopedStore(for: pairingKey).load()
        guard !legacy.isEmpty else { return scoped }

        for command in legacy.pendingCommands {
            _ = try scoped.enqueue(command)
        }
        try scopedStore(for: pairingKey).save(scoped)
        try FileManager.default.removeItem(at: legacyStore.fileURL)
        return scoped
    }

    private var legacyStore: CounterCommandOutboxFileStore {
        CounterCommandOutboxFileStore(
            fileURL: applicationSupportDirectory.appendingPathComponent("iPad-Counter-Outbox.json")
        )
    }

    private func scopedStore(for pairingKey: Data) throws -> CounterCommandOutboxFileStore {
        guard pairingKey.count == 32 else { throw LocalPeerCounterOutboxRepositoryError.invalidPairingKey }
        let identity = LocalPeerPairingKeyStore.identity(for: pairingKey)
        return CounterCommandOutboxFileStore(
            fileURL: applicationSupportDirectory
                .appendingPathComponent("iPad-Counter-Outboxes", isDirectory: true)
                .appendingPathComponent("\(identity).json")
        )
    }
}

enum LocalPeerCounterOutboxRepositoryError: Error, Equatable {
    case invalidPairingKey
}
