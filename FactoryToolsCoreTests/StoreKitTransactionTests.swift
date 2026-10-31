import Foundation
import StoreKit
import StoreKitTest
import XCTest
import FactoryToolsCore

@MainActor
final class StoreKitTransactionTests: XCTestCase {
    @available(macOS 14.0, *)
    func testLocalNonConsumablePurchaseCreatesVerifiedEntitlement() async throws {
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

        let transaction = try await session.buyProduct(identifier: "factorytools.pro.lifetime")
        XCTAssertEqual(transaction.productID, "factorytools.pro.lifetime")

        var hasVerifiedEntitlement = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let entitlement) = result else { continue }
            if entitlement.productID == "factorytools.pro.lifetime" {
                hasVerifiedEntitlement = true
                break
            }
        }
        XCTAssertTrue(hasVerifiedEntitlement, "A local non-consumable purchase must appear in current entitlements.")
        await transaction.finish()
    }
}
