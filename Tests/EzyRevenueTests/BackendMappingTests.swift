import Foundation
import XCTest
@testable import EzyRevenue

final class BackendMappingTests: XCTestCase {
    func testLoginMappingAcceptsTokenlessAndOptionalAccessTokenResponses() {
        XCTAssertEqual(
            BackendMapper.mapLoginAccessToken(from: Data("{}".utf8)),
            .success(nil)
        )
        XCTAssertEqual(
            BackendMapper.mapLoginAccessToken(
                from: Data("{\"appAccessToken\":\"token\"}".utf8)
            ),
            .success("token")
        )
        XCTAssertEqual(
            BackendMapper.mapLoginAccessToken(from: Data("not-json".utf8)),
            .failure(.invalidResponse)
        )
    }

    func testOfferingsRejectMismatchedPackageStoreKitIdentifiers() {
        let data = Data(
            """
            {
              "offerings": [{
                "identifier": "premium",
                "packages": [{
                  "identifier": "monthly",
                  "platform_product_identifier": "platform-id",
                  "products": [{
                    "identifier": "different-id",
                    "displayName": "Premium",
                    "type": "SUBSCRIPTION",
                    "storeStatus": "APPROVED",
                    "isActive": true
                  }]
                }]
              }]
            }
            """.utf8
        )

        XCTAssertEqual(
            BackendMapper.mapOfferings(from: data),
            .failure(.invalidResponse)
        )
    }

    func testOfferingsFixtureMapsTheCurrentOfferingAndMicros() throws {
        let result = BackendMapper.mapOfferings(from: fixture("offerings-success"))
        guard case let .success(snapshot) = result else {
            return XCTFail("Expected offerings fixture to map successfully: \(result)")
        }

        XCTAssertEqual(snapshot.offerings.count, 2)
        XCTAssertEqual(snapshot.currentOffering?.identifier, "offering-premium")
        let package = try XCTUnwrap(snapshot.currentOffering?.packages.first)
        let product = try XCTUnwrap(package.products.first)
        XCTAssertEqual(package.platformProductIdentifier, product.identifier)
        XCTAssertEqual(product.type, .subscription)
        XCTAssertEqual(product.storeStatus, .approved)
        XCTAssertTrue(product.isActive)
        XCTAssertEqual(product.price?.amountMicros, 9_990_000)
        XCTAssertEqual(product.price?.currencyCode, "USD")
    }

    func testProductsFixtureMapsTheDocumentedWrapperAndLocalizedPriceStartsEmpty() throws {
        let result = BackendMapper.mapProducts(from: fixture("products-success"))
        guard case let .success(products) = result else {
            return XCTFail("Expected products fixture to map successfully: \(result)")
        }

        let product = try XCTUnwrap(products.first)
        XCTAssertEqual(product.productID, "product-premium-monthly")
        XCTAssertEqual(product.identifier, "com.example.ezyrevenue.premium.monthly")
        XCTAssertEqual(product.price?.amountMicros, 9_990_000)
        XCTAssertNil(product.price?.displayPrice)
        XCTAssertFalse(product.isAvailableInAppStore)
    }

    func testSubscriberFixtureComputesBackendActivityAgainstRequestDate() throws {
        let result = BackendMapper.mapCustomerInfo(from: fixture("subscriber-success"))
        guard case let .success(customerInfo) = result else {
            return XCTFail("Expected subscriber fixture to map successfully: \(result)")
        }

        XCTAssertEqual(
            customerInfo.originalAppUserID,
            "$RCAnonymousID:12345678-1234-1234-1234-1234567890ab"
        )
        XCTAssertTrue(customerInfo.entitlementIsActive("premium"))
        XCTAssertEqual(
            customerInfo.activeSubscriptions,
            ["com.example.ezyrevenue.premium.monthly"]
        )
        XCTAssertTrue(customerInfo.subscriptions["com.example.ezyrevenue.premium.monthly"]?.willRenew == true)
        XCTAssertEqual(
            customerInfo.subscriptions["com.example.ezyrevenue.premium.monthly"]?.status,
            "ACTIVE"
        )
    }

    func testSubscriptionStatusOverridesDatesAndNilFallsBackToExpiry() {
        let data = Data(
            """
            {
              "request_date": "2026-08-03T17:25:00.000Z",
              "subscriber": {
                "original_app_user_id": "user-123",
                "subscriptions": {
                  "active": {
                    "expires_date": "2026-01-01T00:00:00Z",
                    "status": "active"
                  },
                  "expired": {
                    "expires_date": "2099-01-01T00:00:00Z",
                    "status": "EXPIRED"
                  },
                  "legacy-expired": {
                    "expires_date": "2026-01-01T00:00:00Z",
                    "status": null
                  },
                  "legacy-active": {
                    "expires_date": "2099-01-01T00:00:00Z"
                  }
                }
              }
            }
            """.utf8
        )

        guard case let .success(customerInfo) = BackendMapper.mapCustomerInfo(from: data) else {
            return XCTFail("Expected subscription status response to map successfully")
        }

        XCTAssertTrue(customerInfo.subscriptions["active"]?.isActive == true)
        XCTAssertEqual(customerInfo.subscriptions["active"]?.status, "ACTIVE")
        XCTAssertFalse(customerInfo.subscriptions["expired"]?.isActive == true)
        XCTAssertEqual(customerInfo.subscriptions["expired"]?.status, "EXPIRED")
        XCTAssertFalse(customerInfo.subscriptions["legacy-expired"]?.isActive == true)
        XCTAssertNil(customerInfo.subscriptions["legacy-expired"]?.status)
        XCTAssertTrue(customerInfo.subscriptions["legacy-active"]?.isActive == true)
        XCTAssertNil(customerInfo.subscriptions["legacy-active"]?.status)
    }

    func testValidEmptyCollectionsRemainSuccessful() {
        let offerings = BackendMapper.mapOfferings(from: fixture("empty-offerings-success"))
        let products = BackendMapper.mapProducts(from: fixture("empty-products-success"))

        guard case let .success(offeringsSnapshot) = offerings else {
            return XCTFail("Empty offerings should be successful")
        }
        guard case let .success(productsValue) = products else {
            return XCTFail("Empty products should be successful")
        }

        XCTAssertTrue(offeringsSnapshot.offerings.isEmpty)
        XCTAssertNil(offeringsSnapshot.currentOffering)
        XCTAssertTrue(productsValue.isEmpty)
    }

    func testProductsAcceptBackendNameStatusAndGroupAliases() throws {
        let data = Data(
            """
            {
              "success": true,
              "data": [{
                "productId": "product-monthly",
                "identifier": "com.whizpool.ezyrevenue.sample.premium.monthly",
                "name": "Monthly",
                "type": "SUBSCRIPTION",
                "group": null,
                "status": "MISSING_METADATA",
                "appleFamilySharable": false,
                "appleSubscriptionPeriod": "ONE_MONTH",
                "googleBasePlanId": null,
                "googleSubscriptionId": null
              }]
            }
            """.utf8
        )

        guard case let .success(products) = BackendMapper.mapProducts(from: data) else {
            return XCTFail("Expected backend product aliases to map successfully")
        }

        let product = try XCTUnwrap(products.first)
        XCTAssertEqual(product.productID, "product-monthly")
        XCTAssertEqual(product.identifier, "com.whizpool.ezyrevenue.sample.premium.monthly")
        XCTAssertEqual(product.displayName, "Monthly")
        XCTAssertEqual(product.storeStatus, .unknown("MISSING_METADATA"))
        XCTAssertFalse(product.isActive)
        XCTAssertNil(product.productGroup)
    }

    func testProductNormalizationIsCaseInsensitiveButExplicitActivityWins() {
        let data = Data(
            """
            {
              "success": true,
              "data": [{
                "identifier": "com.example.case-test",
                "displayName": "Case Test",
                "type": "sUbScRiPtIoN",
                "storeStatus": "aPpRoVeD",
                "isActive": false,
                "price": {"amount": 1000000, "currency": "USD"}
              }]
            }
            """.utf8
        )

        guard case let .success(products) = BackendMapper.mapProducts(from: data) else {
            return XCTFail("Expected case-insensitive product mapping")
        }

        XCTAssertEqual(products.first?.type, .subscription)
        XCTAssertEqual(products.first?.storeStatus, .approved)
        XCTAssertFalse(products.first?.isActive == true)
    }

    func testUnknownBackendFieldsAreIgnored() {
        let data = Data(
            """
            {
              "current_offering_id": "offering-basic",
              "future_configuration": {"subscription_group_id": "ignored"},
              "offerings": [{
                "identifier": "offering-basic",
                "description": "Basic",
                "isDefault": false,
                "future_field": true,
                "packages": []
              }]
            }
            """.utf8
        )

        guard case let .success(snapshot) = BackendMapper.mapOfferings(from: data) else {
            return XCTFail("Unknown fields should not invalidate a valid response")
        }

        XCTAssertEqual(snapshot.offerings.map(\.identifier), ["offering-basic"])
        XCTAssertEqual(snapshot.currentOffering?.identifier, "offering-basic")
    }

    func testMissingRequiredProductFieldsReturnInvalidResponse() {
        let data = Data(
            """
            {
              "success": true,
              "data": [{
                "displayName": "Missing identifier",
                "type": "SUBSCRIPTION",
                "storeStatus": "APPROVED"
              }]
            }
            """.utf8
        )

        XCTAssertEqual(BackendMapper.mapProducts(from: data), .failure(.invalidResponse))
    }

    func testMalformedDateReturnsInvalidResponse() {
        let data = Data(
            """
            {
              "request_date": "not-a-date",
              "subscriber": {
                "original_app_user_id": "user-123",
                "entitlements": {},
                "subscriptions": {}
              }
            }
            """.utf8
        )

        XCTAssertEqual(
            BackendMapper.mapCustomerInfo(from: data),
            .failure(.invalidResponse)
        )
    }

    private func fixture(_ name: String) -> Data {
        let url = Bundle.module.url(
            forResource: name,
            withExtension: "json"
        )!
        return try! Data(contentsOf: url)
    }
}
