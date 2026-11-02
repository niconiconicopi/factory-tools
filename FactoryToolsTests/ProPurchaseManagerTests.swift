import StoreKitTest
import XCTest
@testable import FactoryTools

@MainActor
final class ProPurchaseManagerTests: XCTestCase {
    func testLocalLifetimePurchaseUnlocksAndClearingTransactionsRevokesPro() async throws {
        if ProcessInfo.processInfo.environment["FACTORYTOOLS_SKIP_STOREKIT_TESTS"] == "1" {
            throw XCTSkip("Headless GitHub Simulator StoreKitTest cannot save SKTestSession configuration (SKInternalErrorDomain Code=3); run this integration test from Xcode.")
        }
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
}
