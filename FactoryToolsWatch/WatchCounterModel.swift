import Combine
import FactoryToolsCore
import Foundation
@preconcurrency import WatchConnectivity

@MainActor
final class WatchCounterModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var sessions: [WatchCounterSessionSnapshot] = []
    @Published private(set) var cycleTimeHome: WatchCycleTimeHomeSnapshot?
    @Published private(set) var progressCards: [WatchProductionProgressSnapshot] = []
    @Published private(set) var displayLanguage: WatchDisplayLanguage = .system
    @Published private(set) var pendingCount = 0
    @Published private(set) var cycleTimePendingCount = 0
    @Published private(set) var isReachable = false
    @Published private(set) var latestStatus: CounterCommandAcknowledgementStatus?
    @Published private(set) var latestCycleTimeStatus: WatchCycleTimeAcknowledgementStatus?
    @Published private(set) var storageUnavailable = false
    @Published private(set) var queueLimitReached = false
    @Published private(set) var cycleTimeQueueLimitReached = false
    @Published private(set) var cycleTimerRunning = false

    private var outbox = CounterCommandOutbox()
    private var cycleTimeOutbox = WatchCycleTimeOutbox()
    private let cycleClock = ContinuousClock()
    private var cycleTimerRuntimeStartedAt: ContinuousClock.Instant?
    private var cycleTimerRuntimeBaseMilliseconds: Int64?
    private var fileStore: CounterCommandOutboxFileStore?
    private var cycleTimeFileStore: WatchCycleTimeOutboxFileStore?
    private var sendingCommandID: UUID?
    private var sendingAttemptID: UUID?
    private var responseTimeoutTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0
    private var sendingCycleTimeCommandID: UUID?
    private var sendingCycleTimeAttemptID: UUID?
    private var cycleTimeResponseTimeoutTask: Task<Void, Never>?
    private var cycleTimeRetryTask: Task<Void, Never>?
    private var cycleTimeRetryAttempt = 0

    override init() {
        super.init()
        do {
            try reloadOutboxFromDisk()
        } catch {
            storageUnavailable = true
        }

        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(id: UUID) -> WatchCounterSessionSnapshot? {
        sessions.first { $0.sessionID == id }
    }

    func retryStorage() {
        do {
            try reloadOutboxFromDisk()
            storageUnavailable = false
            latestStatus = nil
            if WCSession.isSupported() {
                isReachable = WCSession.default.activationState == .activated && WCSession.default.isReachable
            }
            sendHeadIfReachable()
            sendCycleTimeHeadIfReachable()
        } catch {
            storageUnavailable = true
        }
    }

    func addOne(to session: WatchCounterSessionSnapshot) {
        enqueue(.increment, for: session)
    }

    func subtractOne(from session: WatchCounterSessionSnapshot) {
        enqueue(.decrement, for: session)
    }

    func addFive(to session: WatchCounterSessionSnapshot) {
        enqueue(.quickAdd(5), for: session)
    }

    func startCycleTimer(for home: WatchCycleTimeHomeSnapshot) {
        guard !storageUnavailable, cycleTimeFileStore != nil else { return }
        let wasRunning = cycleTimeOutbox.isRunning
        var updated = cycleTimeOutbox
        updated.start(homeProfileID: home.homeProfileID)
        guard persistCycleTimeOutbox(updated) else { return }
        if !wasRunning, updated.isRunning {
            cycleTimerRuntimeBaseMilliseconds = updated.elapsedMilliseconds(at: .now)
            cycleTimerRuntimeStartedAt = cycleClock.now
        }
    }

    func pauseCycleTimer() {
        guard cycleTimeOutbox.isRunning else { return }
        var updated = cycleTimeOutbox
        updated.pause(totalElapsedMilliseconds: cycleTimerElapsedMilliseconds())
        guard persistCycleTimeOutbox(updated) else { return }
        cycleTimerRuntimeBaseMilliseconds = nil
        cycleTimerRuntimeStartedAt = nil
    }

    func resetCycleTimer() {
        var updated = cycleTimeOutbox
        updated.resetTimer()
        guard persistCycleTimeOutbox(updated) else { return }
        cycleTimerRuntimeBaseMilliseconds = nil
        cycleTimerRuntimeStartedAt = nil
    }

    func finishCycleTimer() {
        guard !storageUnavailable, let cycleTimeFileStore else { return }
        var updated = cycleTimeOutbox
        do {
            guard let command = try updated.finish(totalElapsedMilliseconds: cycleTimerElapsedMilliseconds()) else { return }
            _ = try updated.enqueue(command)
            try cycleTimeFileStore.save(updated)
            commitCycleTimeOutbox(updated)
            cycleTimerRuntimeBaseMilliseconds = nil
            cycleTimerRuntimeStartedAt = nil
            latestCycleTimeStatus = nil
            sendCycleTimeHeadIfReachable()
        } catch WatchCycleTimeOutboxError.pendingLimitReached(maximumCount: _) {
            cycleTimeQueueLimitReached = true
        } catch {
            storageUnavailable = true
        }
    }

    func cycleElapsed(at date: Date = .now) -> Double {
        Double(cycleTimerElapsedMilliseconds(at: date)) / 1_000
    }

    func cycleTimerCanUse(homeProfileID: UUID) -> Bool {
        cycleTimeOutbox.activeHomeProfileID.map { $0 == homeProfileID } ?? true
    }

    func refreshCatalog() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            [WatchCommandWireKey.requestCatalog: true],
            replyHandler: { [weak self] response in
                guard let data = response[WatchCommandWireKey.catalog] as? Data else { return }
                Task { @MainActor in
                    self?.isReachable = true
                    self?.applyCatalog(data)
                    self?.sendHeadIfReachable()
                    self?.sendCycleTimeHeadIfReachable()
                }
            },
            errorHandler: { _ in }
        )
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = activationState == .activated && session.isReachable
        let catalogData = session.receivedApplicationContext[WatchCommandWireKey.catalog] as? Data
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isReachable = reachable
            self.applyCatalog(catalogData)
            self.refreshCatalog()
            self.sendHeadIfReachable()
            self.sendCycleTimeHeadIfReachable()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isReachable = reachable
            if reachable {
                self.refreshCatalog()
                self.sendHeadIfReachable()
                self.sendCycleTimeHeadIfReachable()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext[WatchCommandWireKey.catalog] as? Data
        Task { @MainActor [weak self] in self?.applyCatalog(data) }
    }

    private func enqueue(_ operation: CounterCommandOperation, for session: WatchCounterSessionSnapshot) {
        guard !storageUnavailable, let fileStore else { return }
        var updated = outbox
        do {
            _ = try updated.enqueue(CounterCommand(sessionID: session.sessionID, operation: operation))
            try fileStore.save(updated)
            outbox = updated
            pendingCount = outbox.count
            latestStatus = nil
            queueLimitReached = outbox.count >= CounterCommandOutbox.maximumPendingCommandCount
            sendHeadIfReachable()
        } catch CounterCommandOutboxError.pendingLimitReached(maximumCount: _) {
            queueLimitReached = true
        } catch {
            storageUnavailable = true
        }
    }

    private func reloadOutboxFromDisk() throws {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let store = CounterCommandOutboxFileStore(
            fileURL: directory.appendingPathComponent("FactoryTools/counter-outbox.json")
        )
        let cycleTimeStore = WatchCycleTimeOutboxFileStore(
            fileURL: directory.appendingPathComponent("FactoryTools/cycle-time-outbox.json")
        )
        fileStore = store
        cycleTimeFileStore = cycleTimeStore
        outbox = try store.load()
        cycleTimeOutbox = try cycleTimeStore.load()
        pendingCount = outbox.count
        cycleTimePendingCount = cycleTimeOutbox.count
        queueLimitReached = outbox.count >= CounterCommandOutbox.maximumPendingCommandCount
        cycleTimeQueueLimitReached = cycleTimeOutbox.count >= WatchCycleTimeOutbox.maximumPendingCommandCount
        cycleTimerRunning = cycleTimeOutbox.isRunning
        if cycleTimeOutbox.isRunning {
            cycleTimerRuntimeBaseMilliseconds = cycleTimeOutbox.elapsedMilliseconds(at: .now)
            cycleTimerRuntimeStartedAt = cycleClock.now
        } else {
            cycleTimerRuntimeBaseMilliseconds = nil
            cycleTimerRuntimeStartedAt = nil
        }
    }

    private func sendHeadIfReachable() {
        guard !storageUnavailable, isReachable, retryTask == nil, let command = outbox.nextCommand,
              sendingCommandID != command.id else { return }
        guard let data = try? JSONEncoder().encode(command) else { return }
        let attemptID = UUID()
        sendingCommandID = command.id
        sendingAttemptID = attemptID
        scheduleResponseTimeout(for: command, attemptID: attemptID)
        WCSession.default.sendMessage(
            [WatchCommandWireKey.command: data],
            replyHandler: { [weak self] response in
                let acknowledgementData = response[WatchCommandWireKey.acknowledgement] as? Data
                let snapshotData = response[WatchCommandWireKey.session] as? Data
                Task { @MainActor in
                    guard let self, self.sendingAttemptID == attemptID else { return }
                    self.clearSendingAttempt()
                    let acknowledged = self.applyCommandResponse(
                        acknowledgementData,
                        snapshotData: snapshotData,
                        expectedCommand: command
                    )
                    if acknowledged {
                        self.resetRetryBackoff()
                        self.sendHeadIfReachable()
                    } else {
                        self.scheduleRetry()
                    }
                }
            },
            errorHandler: { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.sendingAttemptID == attemptID else { return }
                    self.clearSendingAttempt()
                    self.isReachable = WCSession.default.isReachable
                    self.scheduleRetry()
                }
            }
        )
    }

    @discardableResult
    private func persistCycleTimeOutbox(_ updated: WatchCycleTimeOutbox) -> Bool {
        guard !storageUnavailable, let cycleTimeFileStore else { return false }
        do {
            try cycleTimeFileStore.save(updated)
            commitCycleTimeOutbox(updated)
            return true
        } catch {
            storageUnavailable = true
            return false
        }
    }

    private func cycleTimerElapsedMilliseconds(at date: Date = .now) -> Int64 {
        guard let cycleTimerRuntimeStartedAt,
              let cycleTimerRuntimeBaseMilliseconds else {
            return cycleTimeOutbox.elapsedMilliseconds(at: date)
        }
        let elapsed = cycleTimerRuntimeStartedAt.duration(to: cycleClock.now).components
        let maximum = Int64(WatchCycleTimeCommand.maximumDurationSeconds) * 1_000
        let seconds = max(0, elapsed.seconds)
        guard seconds < maximum / 1_000 else { return maximum }
        let runtimeMilliseconds = seconds * 1_000
            + Int64(elapsed.attoseconds / 1_000_000_000_000_000)
        return min(maximum, cycleTimerRuntimeBaseMilliseconds + max(0, runtimeMilliseconds))
    }

    private func commitCycleTimeOutbox(_ updated: WatchCycleTimeOutbox) {
        cycleTimeOutbox = updated
        cycleTimePendingCount = updated.count
        cycleTimeQueueLimitReached = updated.count >= WatchCycleTimeOutbox.maximumPendingCommandCount
        cycleTimerRunning = updated.isRunning
    }

    private func sendCycleTimeHeadIfReachable() {
        guard !storageUnavailable, isReachable, cycleTimeRetryTask == nil,
              let command = cycleTimeOutbox.nextCommand,
              sendingCycleTimeCommandID != command.id,
              let data = try? JSONEncoder().encode(command) else { return }
        let attemptID = UUID()
        sendingCycleTimeCommandID = command.id
        sendingCycleTimeAttemptID = attemptID
        scheduleCycleTimeResponseTimeout(for: command, attemptID: attemptID)
        WCSession.default.sendMessage(
            [WatchCommandWireKey.cycleTimeCommand: data],
            replyHandler: { [weak self] response in
                let acknowledgementData = response[WatchCommandWireKey.cycleTimeAcknowledgement] as? Data
                Task { @MainActor in
                    guard let self, self.sendingCycleTimeAttemptID == attemptID else { return }
                    self.clearCycleTimeAttempt()
                    if self.applyCycleTimeResponse(acknowledgementData, expectedCommand: command) {
                        self.resetCycleTimeRetryBackoff()
                        self.sendCycleTimeHeadIfReachable()
                    } else {
                        self.scheduleCycleTimeRetry()
                    }
                }
            },
            errorHandler: { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.sendingCycleTimeAttemptID == attemptID else { return }
                    self.clearCycleTimeAttempt()
                    self.isReachable = WCSession.default.isReachable
                    self.scheduleCycleTimeRetry()
                }
            }
        )
    }

    private func scheduleCycleTimeResponseTimeout(for command: WatchCycleTimeCommand, attemptID: UUID) {
        cycleTimeResponseTimeoutTask?.cancel()
        cycleTimeResponseTimeoutTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self,
                  self.sendingCycleTimeCommandID == command.id,
                  self.sendingCycleTimeAttemptID == attemptID else { return }
            self.cycleTimeResponseTimeoutTask = nil
            self.sendingCycleTimeCommandID = nil
            self.sendingCycleTimeAttemptID = nil
            self.isReachable = WCSession.default.isReachable
            self.scheduleCycleTimeRetry()
        }
    }

    private func clearCycleTimeAttempt() {
        cycleTimeResponseTimeoutTask?.cancel()
        cycleTimeResponseTimeoutTask = nil
        sendingCycleTimeCommandID = nil
        sendingCycleTimeAttemptID = nil
    }

    private func applyCycleTimeResponse(_ data: Data?, expectedCommand: WatchCycleTimeCommand) -> Bool {
        guard cycleTimeOutbox.nextCommand?.id == expectedCommand.id,
              let data,
              let acknowledgement = try? JSONDecoder().decode(WatchCycleTimeAcknowledgement.self, from: data),
              WatchCycleTimeCommandResponseValidator.accepts(acknowledgement, for: expectedCommand),
              let cycleTimeFileStore else { return false }
        var updated = cycleTimeOutbox
        guard updated.acknowledgeHead(acknowledgement) else { return false }
        do {
            try cycleTimeFileStore.save(updated)
            commitCycleTimeOutbox(updated)
            latestCycleTimeStatus = acknowledgement.status
            return true
        } catch {
            storageUnavailable = true
            return false
        }
    }

    private func scheduleCycleTimeRetry() {
        guard cycleTimeRetryTask == nil, !storageUnavailable, cycleTimeOutbox.nextCommand != nil else { return }
        let delaySeconds = CounterCommandRetryPolicy.delaySeconds(forAttempt: cycleTimeRetryAttempt)
        cycleTimeRetryAttempt = min(cycleTimeRetryAttempt + 1, 6)
        cycleTimeRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.cycleTimeRetryTask = nil
            guard !self.storageUnavailable else { return }
            self.isReachable = WCSession.default.isReachable
            if self.isReachable { self.sendCycleTimeHeadIfReachable() }
        }
    }

    private func resetCycleTimeRetryBackoff() {
        cycleTimeRetryTask?.cancel()
        cycleTimeRetryTask = nil
        cycleTimeRetryAttempt = 0
    }

    private func scheduleResponseTimeout(for command: CounterCommand, attemptID: UUID) {
        responseTimeoutTask?.cancel()
        responseTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(15))
            } catch {
                return
            }
            guard let self,
                  self.sendingCommandID == command.id,
                  self.sendingAttemptID == attemptID else { return }
            self.responseTimeoutTask = nil
            self.sendingCommandID = nil
            self.sendingAttemptID = nil
            self.isReachable = WCSession.default.isReachable
            self.scheduleRetry()
        }
    }

    private func clearSendingAttempt() {
        responseTimeoutTask?.cancel()
        responseTimeoutTask = nil
        sendingCommandID = nil
        sendingAttemptID = nil
    }

    private func applyCommandResponse(
        _ acknowledgementData: Data?,
        snapshotData: Data?,
        expectedCommand: CounterCommand
    ) -> Bool {
        guard outbox.nextCommand?.id == expectedCommand.id,
              let acknowledgementData,
              let acknowledgement = try? JSONDecoder().decode(CounterCommandAcknowledgement.self, from: acknowledgementData),
              let fileStore else { return false }

        let responseSnapshot: WatchCounterSessionSnapshot?
        if let snapshotData {
            guard let snapshot = try? JSONDecoder().decode(WatchCounterSessionSnapshot.self, from: snapshotData),
                  WatchCounterCommandResponseValidator.snapshot(snapshot, matches: expectedCommand) else { return false }
            responseSnapshot = snapshot
        } else {
            responseSnapshot = nil
        }
        guard CounterCommandResponseValidator.isComplete(
            acknowledgement,
            snapshot: responseSnapshot,
            matches: expectedCommand
        ) else { return false }

        var updated = outbox
        let sessionUnavailable = CounterCommandResponseValidator.indicatesUnavailableSession(
            acknowledgement,
            snapshot: responseSnapshot,
            matches: expectedCommand
        )
        if sessionUnavailable {
            _ = updated.discardCommands(for: expectedCommand.sessionID)
        } else {
            guard updated.acknowledgeHead(acknowledgement) else { return false }
        }

        var updatedSessions = sessions
        if let snapshot = responseSnapshot {
            if let index = updatedSessions.firstIndex(where: { $0.sessionID == snapshot.sessionID }) {
                updatedSessions[index] = snapshot
            } else {
                updatedSessions.append(snapshot)
            }
        } else if sessionUnavailable {
            updatedSessions.removeAll { $0.sessionID == expectedCommand.sessionID }
        }

        do {
            try fileStore.save(updated)
            outbox = updated
            sessions = updatedSessions
            pendingCount = outbox.count
            queueLimitReached = outbox.count >= CounterCommandOutbox.maximumPendingCommandCount
            latestStatus = acknowledgement.status
            return true
        } catch {
            storageUnavailable = true
            return false
        }
    }

    private func scheduleRetry() {
        guard retryTask == nil, !storageUnavailable, outbox.nextCommand != nil else { return }
        let delaySeconds = CounterCommandRetryPolicy.delaySeconds(forAttempt: retryAttempt)
        retryAttempt = min(retryAttempt + 1, 6)
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.retryTask = nil
            guard !self.storageUnavailable else { return }
            self.isReachable = WCSession.default.isReachable
            if self.isReachable {
                self.sendHeadIfReachable()
            }
        }
    }

    private func resetRetryBackoff() {
        retryTask?.cancel()
        retryTask = nil
        retryAttempt = 0
    }

    private func applyCatalog(_ data: Data?) {
        guard let data, let catalog = try? JSONDecoder().decode(WatchCounterCatalog.self, from: data) else { return }
        sessions = catalog.sessions
        cycleTimeHome = catalog.cycleTimeHome
        progressCards = catalog.progressCards
        displayLanguage = catalog.displayLanguage
    }

}
