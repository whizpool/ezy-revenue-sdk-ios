import Foundation
import XCTest
@testable import EzyRevenue

final class BackendMappingTests: XCTestCase {
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
