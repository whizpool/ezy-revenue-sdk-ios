import XCTest
@testable import EzyRevenue

@available(macOS 12.0, iOS 15.0, *)
final class PublicAPISignatureTests: XCTestCase {
    func testPublicFacadeExposesTheV1OperationSurface() async {
        let sdk = EzyRevenue(
            component: EzyRevenueComponent(
                backend: TestBackend(),
                sessionStore: TestSessionStore(),
                storeKitGateway: TestStoreKitGateway()
            )
        )
        let configuration = EzyRevenueConfiguration(
            apiKey: "test-api-key",
            logLevel: .none
        )

        _ = await sdk.initialize(configuration: configuration)
        _ = await sdk.logIn(appUserID: "user-123")
        _ = await sdk.getOfferings()
        _ = await sdk.getProducts()
        _ = await sdk.getCustomerInfo()
        _ = await sdk.purchasePackage(OfferingPackage(identifier: "monthly"))
        _ = await sdk.purchaseProduct(
            Product(
                identifier: "com.example.premium.monthly",
                displayName: "Premium Monthly",
                type: .subscription,
                storeStatus: .approved,
                isActive: true
            )
        )
        _ = await sdk.restorePurchases()
        _ = await sdk.logOut()
    }
}
