import XCTest
@testable import EzyRevenue

@available(macOS 12.0, iOS 15.0, *)
final class CatalogEnrichmentTests: XCTestCase {
    func testMissingStoreKitProductsRemainVisibleAndUnavailable() async {
        let storeKit = TestStoreKitGateway()
        storeKit.products = [
            StoreKitProduct(
                id: "available",
                displayName: "Available",
                description: "",
                displayPrice: "$1.99",
                priceMicros: 1_990_000,
                currencyCode: "USD",
                subscriptionPeriod: nil,
                introductoryOffer: nil
            ),
        ]
        let catalog = CatalogCoordinator(
            backend: TestBackend(),
            storeKitGateway: storeKit
        )
        let products = [
            Product(
                identifier: "available",
                displayName: "Available",
                type: .nonConsumable,
                storeStatus: .approved,
                isActive: true,
                price: Price(amountMicros: 1_000_000, currencyCode: "USD")
            ),
            Product(
                identifier: "missing",
                displayName: "Missing",
                type: .subscription,
                storeStatus: .approved,
                isActive: true,
                price: Price(amountMicros: 2_000_000, currencyCode: "USD")
            ),
        ]

        let enriched = await catalog.enrichProducts(products)

        XCTAssertEqual(enriched.count, 2)
        XCTAssertEqual(enriched[0].price?.displayPrice, "$1.99")
        XCTAssertEqual(enriched[0].price?.amountMicros, 1_990_000)
        XCTAssertTrue(enriched[0].isAvailableInAppStore)
        XCTAssertEqual(enriched[1].price?.amountMicros, 2_000_000)
        XCTAssertFalse(enriched[1].isAvailableInAppStore)
    }

    func testPackageIdentifierValidationDoesNotSilentlyChooseAProduct() {
        let mismatched = OfferingPackage(
            identifier: "monthly",
            platformProductIdentifier: "platform-id",
            products: [
                Product(
                    identifier: "nested-id",
                    displayName: "Product",
                    type: .subscription,
                    storeStatus: .approved,
                    isActive: true
                ),
            ]
        )
        let multipleWithoutPlatform = OfferingPackage(
            identifier: "multiple",
            products: [
                Product(
                    identifier: "one",
                    displayName: "One",
                    type: .subscription,
                    storeStatus: .approved,
                    isActive: true
                ),
                Product(
                    identifier: "two",
                    displayName: "Two",
                    type: .subscription,
                    storeStatus: .approved,
                    isActive: true
                ),
            ]
        )

        XCTAssertEqual(
            CatalogCoordinator.storeKitIdentifier(for: mismatched),
            .failure(.invalidConfiguration("Offering package StoreKit identifiers must agree"))
        )
        XCTAssertEqual(
            CatalogCoordinator.storeKitIdentifier(for: multipleWithoutPlatform),
            .failure(.invalidConfiguration(
                "Offering package must contain one StoreKit product identifier"
            ))
        )
    }

    func testLiveVerifiedUpdateUsesTheSameReceiptAndFinishPath() async {
        let backend = TestBackend()
        let storeKit = TestStoreKitGateway()
        let session = SessionCoordinator(
            backend: backend,
            sessionStore: TestSessionStore()
        )
        _ = await session.initialize(
            apiKeyFingerprint: "project",
            requestedAppUserID: "user"
        )
        let purchase = PurchaseCoordinator(
            backend: backend,
            storeKitGateway: storeKit
        )
        purchase.startTransactionListener(session: session)
        storeKit.emit(makeVerifiedTransaction(id: 909))

        for _ in 0..<100 where storeKit.finishedIDs.isEmpty {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTAssertEqual(storeKit.finishedIDs, [909])
        XCTAssertEqual(backend.receipts.first?.transactionID, "909")
    }
}
