import Dispatch
import Combine
import FactoryToolsCore
import Foundation
import Network
import Security
import SwiftData

@MainActor
final class LocalPeerCounterTransport: ObservableObject {
    static let shared = LocalPeerCounterTransport()

    @Published private(set) var statusKey = "peer.status.disconnected"
    @Published private(set) var catalog: [WatchCounterSessionSnapshot] = []
    @Published private(set) var pendingCommandCount = 0
    @Published private(set) var unassignedLegacyCommandCount = 0
    @Published private(set) var hasUnassignedLegacyOutboxError = false

    private let queue = DispatchQueue(label: "FactoryTools.LocalPeer.Transport")
    private let serviceType = "_factorytools._tcp"
    private let outboxRepository = LocalPeerCounterOutboxRepository()
    private var loadedOutboxIdentity: String?
    private var loadedPairingKey: Data?
    private var modelContainer: ModelContainer?
    private var listener: NWListener?
    private var listenerGeneration: UUID?
    private var browser: NWBrowser?
    private var browserGeneration: UUID?
    private var wire: LocalPeerWireConnection?
    private var outbox = CounterCommandOutbox()
    private var legacyOutbox = CounterCommandOutbox()
    private var isAuthority = false
    private var commandInFlight = false
    private var inFlightCommandID: UUID?
    private var responseTimeoutTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0
    private var authorityRetryTask: Task<Void, Never>?
    private var authorityRetryAttempt = 0

    private init() {
        refreshLegacyOutboxCount()
    }

    func startAuthority(modelContainer: ModelContainer) {
        guard ProPurchaseManager.shared.hasResolvedEntitlement else { return }
        authorityRetryTask?.cancel()
        authorityRetryTask = nil
        self.modelContainer = modelContainer
        isAuthority = true
        guard let key = Self.loadPairingKey() else {
            statusKey = "peer.status.pairingRequired"
            return
        }
        guard listener == nil else { return }

        do {
            guard let parameters = Self.parameters(pairingKey: key) else {
                statusKey = "peer.status.unavailable"
                return
            }
            let listener = try NWListener(using: parameters)
            let listenerID = UUID()
            listener.service = NWListener.Service(name: "Factory Tools", type: serviceType)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self, self.listenerGeneration == listenerID else {
                        connection.cancel()
                        return
                    }
                    self.accept(connection, pairingKey: key)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.listenerGeneration == listenerID else { return }
                    if case .ready = state {
                        self.statusKey = "peer.status.waiting"
                        self.authorityRetryAttempt = 0
                    } else if case .failed = state {
                        self.statusKey = "peer.status.unavailable"
                        self.listener?.cancel()
                        self.listener = nil
                        self.listenerGeneration = nil
                        self.scheduleAuthorityRetry()
                    }
                }
            }
            self.listener = listener
            listenerGeneration = listenerID
            listener.start(queue: queue)
            statusKey = "peer.status.starting"
        } catch {
            statusKey = "peer.status.unavailable"
            scheduleAuthorityRetry()
        }
    }

    func stopAuthority() {
        authorityRetryTask?.cancel()
        authorityRetryTask = nil
        authorityRetryAttempt = 0
        listenerGeneration = nil
        listener?.cancel()
        listener = nil
        clearCommandFlight(cancelRetry: true)
        wire?.cancel()
        wire = nil
        isAuthority = false
        statusKey = "peer.status.disconnected"
    }

    func connectAsClient() {
        isAuthority = false
        retryTask?.cancel()
        retryTask = nil
        guard let key = Self.loadPairingKey() else {
            statusKey = "peer.status.pairingRequired"
            return
        }
        guard loadOutboxIfNeeded() else { return }
        guard browser == nil else { return }
        do {
            guard let parameters = Self.parameters(pairingKey: key) else {
                statusKey = "peer.status.unavailable"
                return
            }
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
            let browserID = UUID()
            browser.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.browserGeneration == browserID else { return }
                    if case .failed = state {
                        self.statusKey = "peer.status.unavailable"
                        self.browser = nil
                        self.browserGeneration = nil
                        self.scheduleRetry()
                    }
                }
            }
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                guard let endpoint = results.first?.endpoint else { return }
                Task { @MainActor in
                    guard let self, self.browserGeneration == browserID else { return }
                    self.connect(to: endpoint, pairingKey: key)
                }
            }
            self.browser = browser
            browserGeneration = browserID
            browser.start(queue: queue)
            statusKey = "peer.status.searching"
        }
    }

    func disconnectClient() {
        retryTask?.cancel()
        retryTask = nil
        browserGeneration = nil
        browser?.cancel()
        browser = nil
        clearCommandFlight()
        wire?.cancel()
        wire = nil
        statusKey = "peer.status.disconnected"
    }

    func resumeClient() {
        guard !isAuthority else { return }
        guard wire != nil else {
            browserGeneration = nil
            browser?.cancel()
            browser = nil
            connectAsClient()
            return
        }
        requestCatalog()
    }

    func requestCatalog() {
        guard let wire else { return }
        do {
            try wire.send(.catalogRequest())
        } catch {
            statusKey = "peer.status.sendFailed"
        }
    }

    func publishCatalog() {
        guard isAuthority, let modelContainer, let wire else { return }
        do {
            let snapshot = try WatchCommandProcessor(modelContext: modelContainer.mainContext).peerCatalog(
                isPro: ProPurchaseManager.shared.hasPro
            )
            try wire.send(.catalog(snapshot))
        } catch {
            statusKey = "peer.status.sendFailed"
        }
    }

    func enqueue(_ command: CounterCommand) {
        guard loadOutboxIfNeeded() else { return }
        do {
            let updated = try CounterCommandOutboxTransaction.enqueue(command, into: outbox) { candidate in
                try persistOutbox(candidate)
            }
            outbox = updated
            pendingCommandCount = outbox.count
            if outbox.count >= CounterCommandOutbox.maximumPendingCommandCount {
                statusKey = "peer.status.queueFull"
            }
            sendNextCommandIfPossible()
        } catch CounterCommandOutboxError.pendingLimitReached(maximumCount: _) {
            statusKey = "peer.status.queueFull"
        } catch {
            statusKey = "peer.status.storageError"
        }
    }

    private func accept(_ connection: NWConnection, pairingKey: Data) {
        guard CounterPeerConnectionPolicy.shouldAcceptIncomingConnection(
            isAuthority: isAuthority,
            hasPendingOrActiveConnection: wire != nil
        ) else {
            connection.cancel()
            return
        }
        let peer = makeWire(connection, pairingKey: pairingKey)
        wire = peer
        statusKey = "peer.status.connecting"
        peer.start()
    }

    private func connect(to endpoint: NWEndpoint, pairingKey: Data) {
        guard !isAuthority, wire == nil else { return }
        guard let parameters = Self.parameters(pairingKey: pairingKey) else {
            statusKey = "peer.status.unavailable"
            browser?.cancel()
            browser = nil
            browserGeneration = nil
            return
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        let peer = makeWire(connection, pairingKey: pairingKey)
        wire = peer
        statusKey = "peer.status.connecting"
        peer.start()
    }

    private func makeWire(_ connection: NWConnection, pairingKey: Data) -> LocalPeerWireConnection {
        LocalPeerWireConnection(connection: connection, queue: queue) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    private func handle(_ event: LocalPeerWireEvent) {
        switch event {
        case .ready(let connectionID):
            guard wire?.id == connectionID else { return }
            statusKey = "peer.status.connected"
            if !isAuthority {
                requestCatalog()
                sendNextCommandIfPossible()
            }
        case .message(let connectionID, let message):
            guard wire?.id == connectionID else { return }
            handle(message)
        case .failed(let connectionID):
            guard wire?.id == connectionID else { return }
            wire = nil
            clearCommandFlight()
            if isAuthority {
                statusKey = listener == nil ? "peer.status.disconnected" : "peer.status.waiting"
            } else if browser != nil {
                statusKey = "peer.status.reconnecting"
                scheduleRetry()
            } else {
                statusKey = "peer.status.disconnected"
            }
        }
    }

    private func handle(_ message: CounterPeerMessage) {
        if isAuthority {
            handleAuthorityMessage(message)
        } else {
            handleClientMessage(message)
        }
    }

    private func handleAuthorityMessage(_ message: CounterPeerMessage) {
        guard let modelContainer, let wire else { return }
        do {
            switch message.kind {
            case .catalogRequest:
                let snapshot = try WatchCommandProcessor(modelContext: modelContainer.mainContext).peerCatalog(
                    isPro: ProPurchaseManager.shared.hasPro
                )
                try wire.send(.catalog(snapshot))
            case .command:
                guard let command = message.command else { return }
                let result = try WatchCommandProcessor(modelContext: modelContainer.mainContext).process(
                    command,
                    allowNonWatchSessions: true,
                    isPro: ProPurchaseManager.shared.hasPro
                )
                try wire.send(.commandResult(result.acknowledgement, session: result.session))
            case .catalog, .commandResult:
                break
            }
        } catch {
            statusKey = "peer.status.processingError"
            wire.cancel()
            self.wire = nil
        }
    }

    private func handleClientMessage(_ message: CounterPeerMessage) {
        switch message.kind {
        case .catalog:
            guard let remoteCatalog = message.catalog else { return }
            catalog = remoteCatalog.sessions
            do {
                try persistOutbox(outbox)
                pendingCommandCount = outbox.count
                sendNextCommandIfPossible()
            } catch {
                statusKey = "peer.status.storageError"
                scheduleRetry()
            }
        case .commandResult:
            guard let command = outbox.nextCommand else { return }
            guard let acknowledgement = message.acknowledgement else {
                retryAfterInvalidResponse()
                return
            }
            // A duplicate response from a timed-out attempt may arrive after the next head was sent.
            // Ignore acknowledgements for a different command; the current head remains durable.
            guard acknowledgement.commandID == command.id else { return }
            guard CounterCommandResponseValidator.isComplete(acknowledgement, snapshot: message.session, matches: command) else {
                retryAfterInvalidResponse()
                return
            }
            clearCommandFlight(cancelRetry: true)
            statusKey = "peer.status.connected"
            let sessionUnavailable = CounterCommandResponseValidator.indicatesUnavailableSession(
                acknowledgement,
                snapshot: message.session,
                matches: command
            )
            do {
                let updated = try CounterCommandOutboxTransaction.acknowledge(
                    acknowledgement,
                    snapshot: message.session,
                    command: command,
                    in: outbox
                ) { candidate in
                    try persistOutbox(candidate)
                }
                outbox = updated
                retryAttempt = 0
                if let snapshot = message.session {
                    catalog.removeAll { $0.sessionID == snapshot.sessionID }
                    catalog.append(snapshot)
                } else if sessionUnavailable {
                    catalog.removeAll { $0.sessionID == command.sessionID }
                }
                pendingCommandCount = outbox.count
                sendNextCommandIfPossible()
            } catch {
                statusKey = "peer.status.storageError"
                scheduleRetry()
            }
        case .catalogRequest, .command:
            break
        }
    }

    private func retryAfterInvalidResponse() {
        clearCommandFlight()
        statusKey = "peer.status.invalidResponse"
        scheduleRetry()
    }

    private func clearCommandFlight(cancelRetry: Bool = false) {
        responseTimeoutTask?.cancel()
        responseTimeoutTask = nil
        inFlightCommandID = nil
        commandInFlight = false
        if cancelRetry {
            retryTask?.cancel()
            retryTask = nil
        }
    }

    private func scheduleResponseTimeout(for commandID: UUID) {
        responseTimeoutTask?.cancel()
        responseTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(15))
            } catch {
                return
            }
            guard let self, !Task.isCancelled, self.inFlightCommandID == commandID else { return }
            self.responseTimeoutTask = nil
            self.inFlightCommandID = nil
            self.commandInFlight = false
            self.statusKey = "peer.status.responseTimedOut"
            self.scheduleRetry()
        }
    }

    private func sendNextCommandIfPossible() {
        guard !isAuthority, retryTask == nil, let wire, !commandInFlight, let command = outbox.nextCommand else { return }
        do {
            try wire.send(.command(command))
            commandInFlight = true
            inFlightCommandID = command.id
            scheduleResponseTimeout(for: command.id)
        } catch {
            statusKey = "peer.status.sendFailed"
        }
    }

    @discardableResult
    private func loadOutboxIfNeeded() -> Bool {
        guard let pairingKey = Self.loadPairingKey() else {
            statusKey = "peer.status.pairingRequired"
            return false
        }
        let identity = LocalPeerPairingKeyStore.identity(for: pairingKey)
        guard loadedOutboxIdentity != identity else { return true }
        do {
            outbox = try outboxRepository.load(for: pairingKey)
            loadedOutboxIdentity = identity
            loadedPairingKey = pairingKey
            pendingCommandCount = outbox.count
            return true
        } catch {
            statusKey = "peer.status.storageError"
            return false
        }
    }

    private func persistOutbox(_ candidate: CounterCommandOutbox) throws {
        guard let loadedPairingKey else { throw LocalPeerCounterTransportError.outboxNotConfigured }
        try outboxRepository.save(candidate, for: loadedPairingKey)
    }

    func reassignLegacyCommandsToCurrentPeer() {
        guard loadOutboxIfNeeded(), let loadedPairingKey else { return }
        do {
            let updated = try outboxRepository.reassignUnassignedLegacyOutbox(to: loadedPairingKey)
            outbox = updated
            pendingCommandCount = updated.count
            refreshLegacyOutboxCount()
            statusKey = wire == nil ? "peer.status.disconnected" : "peer.status.connected"
            sendNextCommandIfPossible()
        } catch {
            statusKey = "peer.status.storageError"
            refreshLegacyOutboxCount()
        }
    }

    func loadCurrentPairingOutboxForCodeChange() -> Bool {
        loadOutboxIfNeeded()
    }

    private func refreshLegacyOutboxCount() {
        do {
            legacyOutbox = try outboxRepository.loadUnassignedLegacyOutbox()
            unassignedLegacyCommandCount = legacyOutbox.count
            hasUnassignedLegacyOutboxError = false
        } catch {
            hasUnassignedLegacyOutboxError = true
            statusKey = "peer.status.storageError"
        }
    }

    private func scheduleRetry() {
        guard retryTask == nil else { return }
        let delay = CounterCommandRetryPolicy.delaySeconds(forAttempt: retryAttempt)
        retryAttempt += 1
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(Int64(delay)))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.retryTask = nil
            self?.wire?.cancel()
            self?.wire = nil
            self?.clearCommandFlight()
            self?.browserGeneration = nil
            self?.browser?.cancel()
            self?.browser = nil
            self?.connectAsClient()
        }
    }

    private func scheduleAuthorityRetry() {
        guard isAuthority, authorityRetryTask == nil, modelContainer != nil else { return }
        let delay = CounterCommandRetryPolicy.delaySeconds(forAttempt: authorityRetryAttempt)
        authorityRetryAttempt += 1
        authorityRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(Int64(delay)))
            } catch {
                return
            }
            guard let self else { return }
            self.authorityRetryTask = nil
            guard !Task.isCancelled,
                  self.isAuthority,
                  self.listener == nil,
                  let modelContainer = self.modelContainer,
                  ProPurchaseManager.shared.hasResolvedEntitlement,
                  FeatureAccessRegistry.allows(.ipadCounterControl, isPro: ProPurchaseManager.shared.hasPro) else {
                return
            }
            self.startAuthority(modelContainer: modelContainer)
        }
    }

    private static func loadPairingKey() -> Data? {
        guard let code = LocalPeerPairingKeyStore.loadCode() else { return nil }
        do {
            return try LocalPeerPairingKeyStore.keyData(from: code)
        } catch {
            return nil
        }
    }

    private static func parameters(pairingKey: Data) -> NWParameters? {
        let tls = NWProtocolTLS.Options()
        let identity = Data("factory-tools-local-peer-v1".utf8)
        let keyDispatchData = pairingKey.withUnsafeBytes { DispatchData(bytes: $0) }
        let identityDispatchData = identity.withUnsafeBytes { DispatchData(bytes: $0) }
        guard let cipherSuite = tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_256_GCM_SHA384)) else {
            return nil
        }
        // Network.framework TLS-PSK uses the classic NWConnection/NWListener APIs and TLS 1.2.
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        // Explicitly offer a PSK cipher suite instead of relying on default TLS suites.
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions, cipherSuite)
        sec_protocol_options_add_pre_shared_key(
            tls.securityProtocolOptions,
            keyDispatchData as __DispatchData,
            identityDispatchData as __DispatchData
        )
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.includePeerToPeer = true
        return parameters
    }
}

private enum LocalPeerCounterTransportError: Error {
    case outboxNotConfigured
}

@MainActor
private final class LocalPeerWireConnection {
    let id = UUID()
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let onEvent: (LocalPeerWireEvent) -> Void
    private var decoder = CounterPeerFrameDecoder()
    private var isCancelled = false

    init(connection: NWConnection, queue: DispatchQueue, onEvent: @escaping (LocalPeerWireEvent) -> Void) {
        self.connection = connection
        self.queue = queue
        self.onEvent = onEvent
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.onEvent(.ready(self.id))
                    self.receiveNext()
                case .failed, .cancelled:
                    self.onEvent(.failed(self.id))
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)
    }

    func send(_ message: CounterPeerMessage) throws {
        let frame = try CounterPeerFrameCodec.encode(message)
        connection.send(content: frame, completion: .contentProcessed { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in
                guard let self else { return }
                self.onEvent(.failed(self.id))
            }
        })
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        connection.cancel()
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, !self.isCancelled else { return }
                do {
                    if let data {
                        for message in try self.decoder.append(data) {
                            self.onEvent(.message(self.id, message))
                        }
                    }
                } catch {
                    self.onEvent(.failed(self.id))
                    self.cancel()
                    return
                }
                if isComplete || error != nil {
                    self.onEvent(.failed(self.id))
                    self.cancel()
                } else {
                    self.receiveNext()
                }
            }
        }
    }
}

@MainActor
private enum LocalPeerWireEvent {
    case ready(UUID)
    case message(UUID, CounterPeerMessage)
    case failed(UUID)
}
