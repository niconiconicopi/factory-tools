import Foundation
import StoreKit
import StoreKitTest
import XCTest
@testable import FactoryTools

@MainActor
final class StoreKitPurchaseIntegrationTests: XCTestCase {
    func testStoreKitPurchaseGrantsProEntitlement() async throws {
        let configurationURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "FactoryToolsPro", withExtension: "storekit")
        )
        let session = try SKTestSession(contentsOf: configurationURL)
        session.disableDialogs = true
        session.clearTransactions()
        defer {
            session.clearTransactions()
            session.resetToDefaultState()
        }

        let purchaseManager = ProPurchaseManager.shared
        await purchaseManager.refresh()
        XCTAssertTrue(purchaseManager.canPurchase, "The local StoreKit product must be available as a non-consumable.")

        let transaction = try await session.buyProduct(identifier: "factorytools.pro.lifetime")
        await transaction.finish()
        await purchaseManager.refresh()

        XCTAssertTrue(purchaseManager.hasResolvedEntitlement)
        XCTAssertTrue(purchaseManager.hasPro, "A verified local StoreKit purchase must unlock Pro.")
    }
}
