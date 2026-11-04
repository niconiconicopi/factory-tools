import Foundation
import Combine
import StoreKit
import FactoryToolsCore

enum ProStoreProductType: Equatable, Sendable {
    case consumable
    case nonConsumable
    case autoRenewable
    case nonRenewable
}

struct ProStoreProduct: Equatable, Sendable {
    let id: String
    let type: ProStoreProductType
    let price: Decimal
    let displayPrice: String
    let isFamilyShareable: Bool
}

enum ProStorePurchaseOutcome: Equatable, Sendable {
    case purchased
    case pending
    case userCancelled
}

@MainActor
protocol ProPurchaseStore: AnyObject {
    func products(for productID: String) async throws -> [ProStoreProduct]
    func purchase(productID: String) async throws -> ProStorePurchaseOutcome
    func hasActiveProEntitlement(productID: String) async -> Bool
    func synchronize() async throws
    func transactionUpdates() -> AsyncStream<String>
}

@MainActor
private final class StoreKitProPurchaseStore: ProPurchaseStore {
    private let productID: String
    private var productsByID: [String: Product] = [:]

    init(productID: String) {
        self.productID = productID
    }

    func products(for productID: String) async throws -> [ProStoreProduct] {
        let products = try await Product.products(for: [productID])
        productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        return products.map { product in
            ProStoreProduct(
                id: product.id,
                type: Self.productType(for: product.type),
                price: product.price,
                displayPrice: product.displayPrice,
                isFamilyShareable: product.isFamilyShareable
            )
        }
    }

    func purchase(productID: String) async throws -> ProStorePurchaseOutcome {
        guard let product = productsByID[productID], product.type == .nonConsumable else {
            throw ProPurchaseError.productUnavailable
        }
        switch try await product.purchase() {
        case .success(let verification):
            let transaction = try Self.verified(verification)
            await transaction.finish()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .userCancelled
        @unknown default:
            throw ProPurchaseError.unknownPurchaseResult
        }
    }

    func hasActiveProEntitlement(productID: String) async -> Bool {
        for await result in Transaction.currentEntitlements {
            let evidence: ProEntitlementEvidence
            switch result {
            case .verified(let transaction):
                evidence = Self.entitlementEvidence(for: transaction, isVerified: true)
            case .unverified(let transaction, _):
                evidence = Self.entitlementEvidence(for: transaction, isVerified: false)
            }
            if evidence.grantsPro(for: productID) { return true }
        }
        return false
    }

    func synchronize() async throws {
        try await AppStore.sync()
    }

    func transactionUpdates() -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                for await update in Transaction.updates {
                    let transaction: Transaction
                    do {
                        transaction = try Self.verified(update)
                    } catch {
                        continue
                    }
                    guard transaction.productID == productID else { continue }
                    await transaction.finish()
                    continuation.yield(transaction.productID)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func productType(for type: Product.ProductType) -> ProStoreProductType {
        switch type {
        case .consumable: .consumable
        case .nonConsumable: .nonConsumable
        case .autoRenewable: .autoRenewable
        case .nonRenewable: .nonRenewable
        default: .nonRenewable
        }
    }

    private static func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): value
        case .unverified: throw ProPurchaseError.unverifiedTransaction
        }
    }

    private static func entitlementEvidence(
        for transaction: Transaction,
        isVerified: Bool
    ) -> ProEntitlementEvidence {
        ProEntitlementEvidence(
            productID: transaction.productID,
            isVerified: isVerified,
            isRevoked: transaction.revocationDate != nil,
            isUpgraded: transaction.isUpgraded,
            ownership: transaction.ownershipType == .familyShared ? .familyShared : .purchased
        )
    }
}

@MainActor
final class ProPurchaseManager: ObservableObject {
    private static let configuredProductID =
        Bundle.main.object(forInfoDictionaryKey: "FactoryToolsProProductID") as? String ?? ""
    static let shared = ProPurchaseManager(
        productID: configuredProductID,
        store: StoreKitProPurchaseStore(productID: configuredProductID)
    )

    @Published private(set) var product: ProStoreProduct?
    @Published private(set) var hasPro = false
    @Published private(set) var hasResolvedEntitlement = false
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessageKey: String?

    private let productID: String
    private let store: any ProPurchaseStore
    private var updatesTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    init(productID: String, store: any ProPurchaseStore, startsAutomatically: Bool = true) {
        self.productID = productID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.store = store
        guard startsAutomatically else { return }
        updatesTask = Task { [weak self] in
            await self?.observeTransactions()
        }
        refreshTask = Task { [weak self] in
            await self?.refresh()
        }
    }

    var isConfigured: Bool { !productID.isEmpty && !productID.contains("$(") }
    var canPurchase: Bool { product?.type == .nonConsumable }

    func refresh() async {
        guard isConfigured else {
            product = nil
            hasPro = false
            hasResolvedEntitlement = true
            return
        }
        isLoading = true
        defer { isLoading = false }
        await refreshEntitlement()
        do {
            let products = try await store.products(for: productID)
            product = products.first(where: { $0.type == .nonConsumable && $0.id == productID })
            await refreshEntitlement()
            statusMessageKey = product == nil ? "pro.productUnavailable" : nil
        } catch {
            product = nil
            await refreshEntitlement()
            statusMessageKey = "pro.storeUnavailable"
        }
    }

    func purchase() async {
        guard canPurchase else {
            statusMessageKey = "pro.productUnavailable"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            switch try await store.purchase(productID: productID) {
            case .purchased:
                await refreshEntitlement()
                statusMessageKey = hasPro ? "pro.purchaseComplete" : "pro.purchaseUnconfirmed"
            case .pending:
                statusMessageKey = "pro.purchasePending"
            case .userCancelled:
                statusMessageKey = nil
            }
        } catch {
            statusMessageKey = "pro.purchaseFailed"
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await store.synchronize()
            await refreshEntitlement()
            statusMessageKey = hasPro ? "pro.restoreComplete" : "pro.nothingToRestore"
        } catch {
            statusMessageKey = "pro.restoreFailed"
        }
    }

    private func observeTransactions() async {
        for await updatedProductID in store.transactionUpdates() {
            guard updatedProductID == productID else { continue }
            await refreshEntitlement()
        }
    }

    private func refreshEntitlement() async {
        guard isConfigured else {
            hasPro = false
            hasResolvedEntitlement = true
            return
        }
        hasPro = await store.hasActiveProEntitlement(productID: productID)
        hasResolvedEntitlement = true
    }
}

private enum ProPurchaseError: Error {
    case productUnavailable
    case unverifiedTransaction
    case unknownPurchaseResult
}
