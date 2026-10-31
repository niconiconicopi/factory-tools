import Foundation
import Combine
import StoreKit
import FactoryToolsCore

@MainActor
final class ProPurchaseManager: ObservableObject {
    static let shared = ProPurchaseManager()

    @Published private(set) var product: Product?
    @Published private(set) var hasPro = false
    @Published private(set) var hasResolvedEntitlement = false
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessageKey: String?

    private let productID: String
    private var updatesTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    private init() {
        productID = (Bundle.main.object(forInfoDictionaryKey: "FactoryToolsProProductID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        updatesTask = Task { [weak self] in
            guard let self else { return }
            await self.observeTransactions()
        }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
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
            let products = try await Product.products(for: [productID])
            product = products.first(where: { $0.type == .nonConsumable })
            await refreshEntitlement()
            statusMessageKey = product == nil ? "pro.productUnavailable" : nil
        } catch {
            product = nil
            await refreshEntitlement()
            statusMessageKey = "pro.storeUnavailable"
        }
    }

    func purchase() async {
        guard let product, product.type == .nonConsumable else {
            statusMessageKey = "pro.productUnavailable"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                let transaction = try Self.verified(verification)
                await transaction.finish()
                await refreshEntitlement()
                statusMessageKey = hasPro ? "pro.purchaseComplete" : "pro.purchaseUnconfirmed"
            case .pending:
                statusMessageKey = "pro.purchasePending"
            case .userCancelled:
                statusMessageKey = nil
            @unknown default:
                statusMessageKey = "pro.storeUnavailable"
            }
        } catch {
            statusMessageKey = "pro.purchaseFailed"
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            statusMessageKey = hasPro ? "pro.restoreComplete" : "pro.nothingToRestore"
        } catch {
            statusMessageKey = "pro.restoreFailed"
        }
    }

    private func observeTransactions() async {
        for await update in Transaction.updates {
            let transaction: Transaction
            do {
                transaction = try Self.verified(update)
            } catch {
                continue
            }
            guard transaction.productID == productID else { continue }
            await transaction.finish()
            await refreshEntitlement()
        }
    }

    private func refreshEntitlement() async {
        guard isConfigured else {
            hasPro = false
            hasResolvedEntitlement = true
            return
        }
        var entitlementFound = false
        for await result in Transaction.currentEntitlements {
            let evidence: ProEntitlementEvidence
            switch result {
            case .verified(let transaction):
                evidence = Self.entitlementEvidence(for: transaction, isVerified: true)
            case .unverified(let transaction, _):
                evidence = Self.entitlementEvidence(for: transaction, isVerified: false)
            }
            guard evidence.grantsPro(for: productID) else { continue }
            entitlementFound = true
            break
        }
        hasPro = entitlementFound
        hasResolvedEntitlement = true
    }

    private static func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): value
        case .unverified: throw ProPurchaseError.unverifiedTransaction
        }
    }

    private static func entitlementEvidence(for transaction: Transaction, isVerified: Bool) -> ProEntitlementEvidence {
        ProEntitlementEvidence(
            productID: transaction.productID,
            isVerified: isVerified,
            isRevoked: transaction.revocationDate != nil,
            isUpgraded: transaction.isUpgraded,
            ownership: transaction.ownershipType == .familyShared ? .familyShared : .purchased
        )
    }
}

private enum ProPurchaseError: Error {
    case unverifiedTransaction
}
