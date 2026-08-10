import Foundation
import XCTest
@testable import EzyRevenue

final class PublicAPIModelsTests: XCTestCase {
    func testConfigurationRequiresAndRetainsExplicitLogLevel() {
        let configuration = EzyRevenueConfiguration(
            apiKey: "test-api-key",
            appUserID: nil,
            logLevel: .none
        )

        XCTAssertEqual(configuration.logLevel, .none)
        XCTAssertNil(configuration.appUserID)
    }

    func testPublicModelsAreImmutableValueTypes() {
        let price = Price(
            amountMicros: 9_990_000,
            currencyCode: "USD",
            displayPrice: "$9.99"
        )
        let product = Product(
            identifier: "com.example.premium.monthly",
            displayName: "Premium Monthly",
            type: .subscription,
            storeStatus: .approved,
            isActive: true,
            price: price,
            isAvailableInAppStore: true
        )
        let package = OfferingPackage(
            identifier: "$rc_monthly",
            platformProductIdentifier: product.identifier,
            products: [product]
        )
        let offering = Offering(
            identifier: "offering-premium",
            packages: [package]
        )

        XCTAssertEqual(offering.packages.first?.products.first?.price?.amountMicros, 9_990_000)
        XCTAssertEqual(PurchaseResult.pending, .pending)
    }

    func testCustomerInfoProvidesBackendActivityHelpers() {
        let customerInfo = CustomerInfo(
            entitlements: [
                "premium": EntitlementInfo(
                    identifier: "premium",
                    isActive: true,
                    productIdentifier: "com.example.premium.monthly"
                )
            ],
            subscriptions: [
                "com.example.premium.monthly": SubscriptionInfo(
                    productIdentifier: "com.example.premium.monthly",
                    isActive: true
                )
            ]
        )

        XCTAssertTrue(customerInfo.entitlementIsActive("premium"))
        XCTAssertEqual(customerInfo.activeSubscriptions, ["com.example.premium.monthly"])
    }
}
