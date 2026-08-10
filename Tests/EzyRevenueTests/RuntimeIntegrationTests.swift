import XCTest
@testable import EzyRevenue

@available(macOS 12.0, iOS 15.0, *)
final class RuntimeIntegrationTests: XCTestCase {
    func testFacadeInitializesLoadsEnrichedCatalogAndCustomerInfo() async {
        let backend = TestBackend()
        backend.offeringsResult = .success(
            statusCode: 200,
            body: Data(
                """
                {
                  "current_offering_id": "premium",
                  "offerings": [{
                    "identifier": "premium",
                    "isDefault": true,
                    "packages": [{
                      "identifier": "monthly",
                      "platform_product_identifier": "com.example.premium.monthly",
                      "products": [{
                        "identifier": "com.example.premium.monthly",
                        "displayName": "Premium Monthly",
                        "type": "SUBSCRIPTION",
                        "storeStatus": "APPROVED",
                        "isActive": true,
                        "price": {"amount": 9990000, "currency": "USD"}
                      }]
                    }]
                  }]
                }
                """.utf8
            )
        )
        backend.productsResult = .success(
            statusCode: 200,
            body: Data(
                """
                {"success":true,"data":[{
                  "identifier":"com.example.premium.monthly",
                  "displayName":"Premium Monthly",
                  "type":"SUBSCRIPTION",
                  "storeStatus":"APPROVED",
                  "isActive":true,
                  "price":{"amount":9990000,"currency":"USD"}
                }]}
                """.utf8
            )
        )
        backend.customerResult = .success(
            statusCode: 200,
            body: Data(
                """
                {"request_date":"2026-01-01T00:00:00Z","subscriber":{
                  "original_app_user_id":"user-1",
                  "entitlements":{"premium":{"expires_date":"2099-01-01T00:00:00Z"}},
                  "subscriptions":{}
                }}
                """.utf8
            )
        )
        let storeKit = TestStoreKitGateway()
        storeKit.products = [
            StoreKitProduct(
                id: "com.example.premium.monthly",
                displayName: "Premium Monthly",
                description: "Premium",
                displayPrice: "$9.99",
                priceMicros: 9_990_000,
                currencyCode: "USD",
                subscriptionPeriod: StoreKitSubscriptionPeriod(value: 1, unit: .month),
                introductoryOffer: nil
            ),
        ]
        let store = TestSessionStore()
        let sdk = EzyRevenue(
            component: EzyRevenueComponent(
                backend: backend,
                sessionStore: store,
                storeKitGateway: storeKit
            )
        )

        assertSuccess(
            await sdk.initialize(
                configuration: EzyRevenueConfiguration(
                    apiKey: "test-key",
                    appUserID: "user-1",
                    logLevel: .none
                )
            )
        )

        let offeringsResult = await sdk.getOfferings()
        let productsResult = await sdk.getProducts()
        let customerResult = await sdk.getCustomerInfo()

        guard case let .success(offerings) = offeringsResult,
              case let .success(products) = productsResult,
              case let .success(customerInfo) = customerResult else {
            return XCTFail("Expected catalog and customer requests to succeed")
        }
        XCTAssertEqual(offerings.first?.identifier, "premium")
        XCTAssertEqual(offerings.first?.packages.first?.products.first?.price?.displayPrice, "$9.99")
        XCTAssertTrue(offerings.first?.packages.first?.products.first?.isAvailableInAppStore == true)
        XCTAssertEqual(products.first?.price?.amountMicros, 9_990_000)
        XCTAssertEqual(customerInfo.originalAppUserID, "user-1")
        XCTAssertTrue(customerInfo.entitlementIsActive("premium"))
        XCTAssertEqual(backend.offeringsCalls.first?.0, "user-1")
    }

    func testPublicRestoreSyncsTransactionsThenRefreshesCustomerInfo() async {
        let backend = TestBackend()
        let storeKit = TestStoreKitGateway()
        storeKit.currentEntitlements = [makeVerifiedTransaction(id: 808)]
        let sdk = EzyRevenue(
            component: EzyRevenueComponent(
                backend: backend,
                sessionStore: TestSessionStore(),
                storeKitGateway: storeKit
            )
        )
        assertSuccess(
            await sdk.initialize(
                configuration: EzyRevenueConfiguration(
                    apiKey: "test-key",
                    appUserID: "user",
                    logLevel: .none
                )
            )
        )

        let result = await sdk.restorePurchases()

        guard case let .success(customerInfo) = result else {
            return XCTFail("Expected restore to return customer info: \(result)")
        }
        XCTAssertEqual(customerInfo.originalAppUserID, "user")
        XCTAssertEqual(storeKit.syncCount, 1)
        XCTAssertEqual(storeKit.finishedIDs, [808])
        XCTAssertEqual(backend.receipts.first?.transactionID, "808")
        XCTAssertEqual(backend.customerCalls.last?.0, "user")
    }

    func testIdentitySwitchAndLogoutClearSnapshotsAndSession() async {
        let backend = TestBackend()
        let store = TestSessionStore()
        let storeKit = TestStoreKitGateway()
        let sdk = EzyRevenue(
            component: EzyRevenueComponent(
                backend: backend,
                sessionStore: store,
                storeKitGateway: storeKit
            )
        )

        assertSuccess(
            await sdk.initialize(
                configuration: EzyRevenueConfiguration(
                    apiKey: "test-key",
                    appUserID: "user-a",
                    logLevel: .none
                )
            )
        )
        _ = await sdk.getOfferings()
        let initializedBeforeSwitch = await sdk.isInitialized
        XCTAssertTrue(initializedBeforeSwitch)

        assertSuccess(await sdk.logIn(appUserID: "user-b"))
        let switchedUser = await sdk.appUserID
        let offeringsAfterSwitch = await sdk.offerings
        XCTAssertEqual(switchedUser, "user-b")
        XCTAssertTrue(offeringsAfterSwitch.isEmpty)

        assertSuccess(await sdk.logOut())
        let initializedAfterLogout = await sdk.isInitialized
        let userAfterLogout = await sdk.appUserID
        XCTAssertFalse(initializedAfterLogout)
        XCTAssertNil(userAfterLogout)
        XCTAssertTrue(store.session?.appUserID.hasPrefix(AnonymousAppUserID.prefix) == true)
        XCTAssertFalse(store.session?.isAuthenticated == true)
        XCTAssertEqual(backend.logoutIDs, ["user-b"])
    }

    private func assertSuccess(
        _ result: EzyRevenueResult<Void>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success = result else {
            XCTFail("Expected success, got \(result)", file: file, line: line)
            return
        }
    }
}
