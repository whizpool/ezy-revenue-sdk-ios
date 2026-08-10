import XCTest
@testable import EzyRevenue

@available(macOS 12.0, iOS 15.0, *)
final class PurchaseRecoveryTests: XCTestCase {
    func testVerifiedPurchaseSubmitsReceiptBeforeFinishing() async {
        let backend = TestBackend()
        let store = TestSessionStore()
        let storeKit = TestStoreKitGateway()
        let transaction = makeVerifiedTransaction(id: 101)
        storeKit.purchaseOutcome = .purchased(transaction)
        let (purchase, session) = await makeRuntime(
            backend: backend,
            store: store,
            storeKit: storeKit
        )

        let result = await purchase.purchaseProduct(
            Product(
                identifier: "com.example.premium.monthly",
                displayName: "Premium",
                type: .subscription,
                storeStatus: .approved,
                isActive: true
            ),
            session: session
        )

        guard case let .success(.purchased(verified)) = result else {
            return XCTFail("Expected a purchased result: \(result)")
        }
        XCTAssertEqual(verified.id, 101)
        XCTAssertEqual(storeKit.finishedIDs, [101])
        XCTAssertEqual(backend.receipts.count, 1)
        XCTAssertEqual(backend.receipts.first?.appUserID, "user-1")
        XCTAssertEqual(backend.receipts.first?.transactionID, "101")
        XCTAssertEqual(backend.receipts.first?.fetchToken, "verified-jws")
        XCTAssertNil(backend.receipts.first?.purchaseToken)
        XCTAssertEqual(
            storeKit.accountTokens.first!,
            AppAccountToken.make(appUserID: "user-1")
        )
    }

    func testReceiptFailureLeavesTransactionUnfinishedAndRecoveryRetriesIt() async {
        let backend = TestBackend()
        backend.receiptResults = [.failure(.network), .success(statusCode: 200, body: Data("{}".utf8))]
        let store = TestSessionStore()
        let storeKit = TestStoreKitGateway()
        let transaction = makeVerifiedTransaction(id: 202)
        storeKit.purchaseOutcome = .purchased(transaction)
        let (purchase, session) = await makeRuntime(
            backend: backend,
            store: store,
            storeKit: storeKit
        )

        let purchaseResult = await purchase.purchaseProduct(
            Product(
                identifier: "com.example.premium.monthly",
                displayName: "Premium",
                type: .subscription,
                storeStatus: .approved,
                isActive: true
            ),
            session: session
        )
        guard case .failure(.network) = purchaseResult else {
            return XCTFail("Expected receipt failure: \(purchaseResult)")
        }
        XCTAssertTrue(storeKit.finishedIDs.isEmpty)

        storeKit.unfinished = [transaction]
        await purchase.recoverUnfinishedTransactions(session: session)

        XCTAssertEqual(storeKit.finishedIDs, [202])
        XCTAssertEqual(backend.receipts.count, 2)
    }

    func testUnverifiedTransactionIsNeverSubmittedOrFinished() async {
        let backend = TestBackend()
        let storeKit = TestStoreKitGateway()
        storeKit.purchaseOutcome = .purchased(
            .unverified(
                StoreKitUnverifiedTransaction(
                    id: 303,
                    productID: "com.example.premium.monthly",
                    reason: "invalid signature"
                )
            )
        )
        let (purchase, session) = await makeRuntime(
            backend: backend,
            store: TestSessionStore(),
            storeKit: storeKit
        )

        let result = await purchase.purchaseProduct(
            Product(
                identifier: "com.example.premium.monthly",
                displayName: "Premium",
                type: .subscription,
                storeStatus: .approved,
                isActive: true
            ),
            session: session
        )

        guard case .failure(.unverifiedTransaction) = result else {
            return XCTFail("Expected unverified transaction failure: \(result)")
        }
        XCTAssertTrue(backend.receipts.isEmpty)
        XCTAssertTrue(storeKit.finishedIDs.isEmpty)
    }

    func testRestoreSyncsAndProcessesCurrentEntitlements() async {
        let backend = TestBackend()
        let storeKit = TestStoreKitGateway()
        storeKit.currentEntitlements = [makeVerifiedTransaction(id: 404)]
        let (purchase, session) = await makeRuntime(
            backend: backend,
            store: TestSessionStore(),
            storeKit: storeKit
        )

        let result = await purchase.restorePurchases(session: session)

        guard case .success = result else {
            return XCTFail("Expected restore success: \(result)")
        }
        XCTAssertEqual(storeKit.syncCount, 1)
        XCTAssertEqual(storeKit.finishedIDs, [404])
        XCTAssertEqual(backend.receipts.first?.transactionID, "404")
    }

    func testPendingAndCancelledOutcomesAreDistinguished() async {
        let backend = TestBackend()
        let storeKit = TestStoreKitGateway()
        let (purchase, session) = await makeRuntime(
            backend: backend,
            store: TestSessionStore(),
            storeKit: storeKit
        )
        let product = Product(
            identifier: "com.example.premium.monthly",
            displayName: "Premium",
            type: .subscription,
            storeStatus: .approved,
            isActive: true
        )

        storeKit.purchaseOutcome = .pending
        let pending = await purchase.purchaseProduct(product, session: session)
        storeKit.purchaseOutcome = .cancelled
        let cancelled = await purchase.purchaseProduct(product, session: session)

        guard case .success(.pending) = pending else {
            return XCTFail("Expected pending result")
        }
        guard case .success(.cancelled) = cancelled else {
            return XCTFail("Expected cancelled result")
        }
    }

    private func makeRuntime(
        backend: TestBackend,
        store: TestSessionStore,
        storeKit: TestStoreKitGateway
    ) async -> (PurchaseCoordinator, SessionCoordinator) {
        let session = SessionCoordinator(backend: backend, sessionStore: store)
        _ = await session.initialize(
            apiKeyFingerprint: "project",
            requestedAppUserID: "user-1"
        )
        return (
            PurchaseCoordinator(
                backend: backend,
                storeKitGateway: storeKit
            ),
            session
        )
    }
}
