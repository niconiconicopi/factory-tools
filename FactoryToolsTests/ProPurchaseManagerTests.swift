import StoreKitTest
import XCTest
@testable import FactoryTools

@MainActor
final class ProPurchaseManagerTests: XCTestCase {
    func testRefreshLoadsOnlyConfiguredLifetimeNonConsumable() async {
        let store = FakeProPurchaseStore(products: [
            ProStoreProduct(
                id: "other.product",
                type: .nonConsumable,
                price: Decimal(100),
                displayPrice: "$1.00",
                isFamilyShareable: false
            ),
            Self.lifetimeProduct,
        ])
        let manager = ProPurchaseManager(productID: Self.productID, store: store, startsAutomatically: false)

        await manager.refresh()

        XCTAssertEqual(manager.product, Self.lifetimeProduct)
        XCTAssertTrue(manager.canPurchase)
        XCTAssertTrue(manager.hasResolvedEntitlement)
        XCTAssertFalse(manager.hasPro)
        XCTAssertNil(manager.statusMessageKey)
    }

    func testPurchaseSuccessUnlocksOnlyAfterEntitlementIsConfirmed() async {
        let store = FakeProPurchaseStore(purchaseOutcome: .purchased, hasPro: true)
        let manager = Self.makeManager(store: store)
        await manager.refresh()

        await manager.purchase()

        XCTAssertTrue(manager.hasPro)
        XCTAssertEqual(manager.statusMessageKey, "pro.purchaseComplete")
        XCTAssertEqual(store.purchaseProductIDs, [Self.productID])
    }

    func testPurchaseSuccessWithoutEntitlementReportsUnconfirmed() async {
        let store = FakeProPurchaseStore(purchaseOutcome: .purchased, hasPro: false)
        let manager = Self.makeManager(store: store)
        await manager.refresh()

        await manager.purchase()

        XCTAssertFalse(manager.hasPro)
        XCTAssertEqual(manager.statusMessageKey, "pro.purchaseUnconfirmed")
    }

    func testPendingPurchaseDoesNotUnlockPro() async {
        let store = FakeProPurchaseStore(purchaseOutcome: .pending)
        let manager = Self.makeManager(store: store)
        await manager.refresh()

        await manager.purchase()

        XCTAssertFalse(manager.hasPro)
        XCTAssertEqual(manager.statusMessageKey, "pro.purchasePending")
    }

    func testCancelledPurchaseDoesNotUnlockProOrLeaveStatusMessage() async {
        let store = FakeProPurchaseStore(purchaseOutcome: .userCancelled)
        let manager = Self.makeManager(store: store)
        await manager.refresh()

        await manager.purchase()

        XCTAssertFalse(manager.hasPro)
        XCTAssertNil(manager.statusMessageKey)
    }

    func testRestoreSynchronizesAndRefreshesEntitlement() async {
        let store = FakeProPurchaseStore(hasPro: true)
        let manager = Self.makeManager(store: store)
        await manager.refresh()

        await manager.restorePurchases()

        XCTAssertTrue(manager.hasPro)
        XCTAssertEqual(manager.statusMessageKey, "pro.restoreComplete")
        XCTAssertEqual(store.synchronizeCallCount, 1)
    }

    func testMissingProductCannotStartPurchase() async {
        let store = FakeProPurchaseStore(products: [])
        let manager = Self.makeManager(store: store)

        await manager.refresh()
        await manager.purchase()

        XCTAssertNil(manager.product)
        XCTAssertFalse(manager.canPurchase)
        XCTAssertEqual(manager.statusMessageKey, "pro.productUnavailable")
        XCTAssertTrue(store.purchaseProductIDs.isEmpty)
    }

    func testProductLoadFailureCanBeRetried() async {
        let store = FakeProPurchaseStore()
        store.productsShouldFail = true
        let manager = Self.makeManager(store: store)

        await manager.refresh()

        XCTAssertNil(manager.product)
        XCTAssertEqual(manager.statusMessageKey, "pro.storeUnavailable")

        store.productsShouldFail = false
        await manager.refresh()

        XCTAssertEqual(manager.product, Self.lifetimeProduct)
        XCTAssertNil(manager.statusMessageKey)
    }

    func testPurchaseFailureReportsFailureWithoutUnlocking() async {
        let store = FakeProPurchaseStore()
        store.purchaseShouldFail = true
        let manager = Self.makeManager(store: store)
        await manager.refresh()

        await manager.purchase()

        XCTAssertFalse(manager.hasPro)
        XCTAssertEqual(manager.statusMessageKey, "pro.purchaseFailed")
    }

    func testRestoreFailureReportsFailure() async {
        let store = FakeProPurchaseStore()
        store.synchronizeShouldFail = true
        let manager = Self.makeManager(store: store)
        await manager.refresh()

        await manager.restorePurchases()

        XCTAssertFalse(manager.hasPro)
        XCTAssertEqual(manager.statusMessageKey, "pro.restoreFailed")
    }

    func testTransactionUpdateRefreshesEntitlementForConfiguredProduct() async {
        let store = FakeProPurchaseStore(hasPro: false)
        let manager = Self.makeManager(store: store)
        await store.waitForTransactionSubscriber()
        store.hasPro = true

        store.publishTransactionUpdate(Self.productID)
        await store.waitUntil { manager.hasPro }

        XCTAssertTrue(manager.hasPro)
    }

    func testLocalLifetimePurchaseUnlocksAndClearingTransactionsRevokesPro() async throws {
        let configurationURL = try XCTUnwrap(
            Bundle(for: ProPurchaseManagerTests.self)
                .url(forResource: "FactoryToolsPro", withExtension: "storekit")
        )
        let session = try SKTestSession(contentsOf: configurationURL)
        session.disableDialogs = true
        session.clearTransactions()
        session.resetToDefaultState()
        session.storefront = "JPN"
        session.locale = Locale(identifier: "ja_JP")

        let manager = ProPurchaseManager.shared
        await manager.refresh()

        XCTAssertEqual(manager.product?.id, "factorytools.pro.lifetime")
        XCTAssertEqual(manager.product?.type, .nonConsumable)
        XCTAssertEqual(manager.product?.price, Decimal(980))
        XCTAssertFalse(manager.product?.isFamilyShareable ?? true)
        XCTAssertTrue(manager.canPurchase)
        XCTAssertFalse(manager.hasPro)

        await manager.purchase()

        XCTAssertTrue(manager.hasPro, "Purchase result: \(manager.statusMessageKey ?? "none")")
        XCTAssertEqual(manager.statusMessageKey, "pro.purchaseComplete")

        session.clearTransactions()
        await manager.refresh()
        XCTAssertFalse(manager.hasPro)
    }

    fileprivate static let productID = "factorytools.pro.lifetime"
    fileprivate static let lifetimeProduct = ProStoreProduct(
        id: productID,
        type: .nonConsumable,
        price: Decimal(980),
        displayPrice: "JPY 980",
        isFamilyShareable: false
    )

    private static func makeManager(store: FakeProPurchaseStore) -> ProPurchaseManager {
        ProPurchaseManager(productID: productID, store: store, startsAutomatically: false)
    }
}

@MainActor
private final class FakeProPurchaseStore: ProPurchaseStore {
    var products: [ProStoreProduct]
    var purchaseOutcome: ProStorePurchaseOutcome
    var hasPro: Bool
    var productsShouldFail = false
    var purchaseShouldFail = false
    var synchronizeShouldFail = false
    private(set) var purchaseProductIDs: [String] = []
    private(set) var synchronizeCallCount = 0
    private var transactionContinuation: AsyncStream<String>.Continuation?

    init(
        products: [ProStoreProduct] = [ProPurchaseManagerTests.lifetimeProduct],
        purchaseOutcome: ProStorePurchaseOutcome = .userCancelled,
        hasPro: Bool = false
    ) {
        self.products = products
        self.purchaseOutcome = purchaseOutcome
        self.hasPro = hasPro
    }

    func products(for productID: String) async throws -> [ProStoreProduct] {
        if productsShouldFail { throw FakeStoreError.unavailable }
        return products.filter { $0.id == productID }
    }

    func purchase(productID: String) async throws -> ProStorePurchaseOutcome {
        purchaseProductIDs.append(productID)
        if purchaseShouldFail { throw FakeStoreError.unavailable }
        return purchaseOutcome
    }

    func hasActiveProEntitlement(productID: String) async -> Bool {
        hasPro
    }

    func synchronize() async throws {
        synchronizeCallCount += 1
        if synchronizeShouldFail { throw FakeStoreError.unavailable }
    }

    func transactionUpdates() -> AsyncStream<String> {
        AsyncStream { transactionContinuation = $0 }
    }

    func publishTransactionUpdate(_ productID: String) {
        transactionContinuation?.yield(productID)
    }

    func waitForTransactionSubscriber() async {
        for _ in 0..<100 where transactionContinuation == nil {
            await Task.yield()
        }
    }

    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }
}

private enum FakeStoreError: Error {
    case unavailable
}
