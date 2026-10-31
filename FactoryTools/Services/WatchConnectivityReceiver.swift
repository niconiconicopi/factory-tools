import FactoryToolsCore
import Foundation
import SwiftData
@preconcurrency import WatchConnectivity

@MainActor
final class WatchConnectivityReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityReceiver()

    private var modelContainer: ModelContainer?

    private override init() {
        super.init()
    }

    func start(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func publishCatalog() {
        guard ProPurchaseManager.shared.hasResolvedEntitlement,
              let modelContainer,
              WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else { return }
        do {
            let catalog = try WatchCommandProcessor(modelContext: modelContainer.mainContext).catalog(
                isPro: ProPurchaseManager.shared.hasPro
            )
            let data = try JSONEncoder().encode(catalog)
            try session.updateApplicationContext([WatchCommandWireKey.catalog: data])
        } catch {
            // The next Watch catalog request retries without replacing the last valid application context.
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor [weak self] in self?.publishCatalog() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // Commands use the reply-handler variant so the Watch only removes its head after an acknowledgement.
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let commandData = message[WatchCommandWireKey.command] as? Data
        let cycleTimeCommandData = message[WatchCommandWireKey.cycleTimeCommand] as? Data
        let requestsCatalog = message[WatchCommandWireKey.requestCatalog] as? Bool == true
        Task { @MainActor [weak self] in
            guard let self else {
                replyHandler([WatchCommandWireKey.retry: true])
                return
            }
            guard ProPurchaseManager.shared.hasResolvedEntitlement else {
                replyHandler([WatchCommandWireKey.retry: true])
                return
            }
            do {
                if requestsCatalog {
                    let catalog = try self.makeCatalogData()
                    replyHandler([WatchCommandWireKey.catalog: catalog])
                    return
                }
                if let cycleTimeCommandData {
                    let command = try JSONDecoder().decode(WatchCycleTimeCommand.self, from: cycleTimeCommandData)
                    let acknowledgement = try self.process(command)
                    replyHandler([
                        WatchCommandWireKey.cycleTimeAcknowledgement: try JSONEncoder().encode(acknowledgement)
                    ])
                    return
                }
                guard let commandData else {
                    replyHandler([WatchCommandWireKey.retry: false])
                    return
                }
                let command = try JSONDecoder().decode(CounterCommand.self, from: commandData)
                let result = try self.process(command)
                var response: [String: Any] = [
                    WatchCommandWireKey.acknowledgement: try JSONEncoder().encode(result.acknowledgement)
                ]
                if let snapshot = result.session {
                    response[WatchCommandWireKey.session] = try JSONEncoder().encode(snapshot)
                }
                replyHandler(response)
            } catch {
                replyHandler([WatchCommandWireKey.retry: true])
            }
        }
    }

    private func makeCatalogData() throws -> Data {
        guard ProPurchaseManager.shared.hasResolvedEntitlement else {
            throw WatchConnectivityReceiverError.entitlementUnavailable
        }
        guard let modelContainer else { throw WatchConnectivityReceiverError.storeUnavailable }
        let catalog = try WatchCommandProcessor(modelContext: modelContainer.mainContext).catalog(
            isPro: ProPurchaseManager.shared.hasPro
        )
        return try JSONEncoder().encode(catalog)
    }

    private func process(_ command: CounterCommand) throws -> WatchCommandProcessingResult {
        guard ProPurchaseManager.shared.hasResolvedEntitlement else {
            throw WatchConnectivityReceiverError.entitlementUnavailable
        }
        guard let modelContainer else { throw WatchConnectivityReceiverError.storeUnavailable }
        return try WatchCommandProcessor(modelContext: modelContainer.mainContext).process(
            command,
            isPro: ProPurchaseManager.shared.hasPro
        )
    }

    private func process(_ command: WatchCycleTimeCommand) throws -> WatchCycleTimeAcknowledgement {
        guard ProPurchaseManager.shared.hasResolvedEntitlement else {
            throw WatchConnectivityReceiverError.entitlementUnavailable
        }
        guard let modelContainer else { throw WatchConnectivityReceiverError.storeUnavailable }
        return try WatchCommandProcessor(modelContext: modelContainer.mainContext).process(
            command,
            isPro: ProPurchaseManager.shared.hasPro
        )
    }
}

private enum WatchConnectivityReceiverError: Error {
    case storeUnavailable
    case entitlementUnavailable
}
