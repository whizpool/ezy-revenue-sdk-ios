import XCTest
@testable import EzyRevenue

final class ArchitectureBoundaryTests: XCTestCase {
    func testManualComponentConstructionKeepsTheThreeExternalBoundaries() {
        let component = EzyRevenueComponent(
            backend: FakeBackend(),
            sessionStore: FakeSessionStore(),
            storeKitGateway: FakeStoreKitGateway()
        )

        XCTAssertTrue(component.backend is FakeBackend)
        XCTAssertTrue(component.sessionStore is FakeSessionStore)
        XCTAssertTrue(component.storeKitGateway is FakeStoreKitGateway)
    }

    func testSessionGenerationRejectsLateWorkAfterIdentitySwitchAndLogout() {
        let session = SessionCoordinator(
            backend: FakeBackend(),
            sessionStore: FakeSessionStore()
        )

        let firstUser = session.activate(appUserID: "user-a")
        XCTAssertTrue(session.isCurrent(firstUser))

        _ = session.activate(appUserID: "user-b")
        XCTAssertFalse(session.isCurrent(firstUser))

        let secondUser = try! XCTUnwrap(session.captureGeneration())
        session.invalidate()
        XCTAssertFalse(session.isCurrent(secondUser))
    }

    func testCatalogDoesNotCommitAStaleResponse() {
        let session = SessionCoordinator(
            backend: FakeBackend(),
            sessionStore: FakeSessionStore()
        )
        let catalog = CatalogCoordinator(
            backend: FakeBackend(),
            storeKitGateway: FakeStoreKitGateway()
        )
        let oldGeneration = session.activate(appUserID: "user-a")
        _ = session.activate(appUserID: "user-b")

        let committed = catalog.commitOfferings(
            [Offering(identifier: "old")],
            currentOffering: nil,
            for: oldGeneration,
            session: session
        )

        XCTAssertFalse(committed)
        XCTAssertTrue(catalog.offerings.isEmpty)
    }

    func testPurchaseCoordinatorAllowsOnlyOneCurrentGeneration() throws {
        let session = SessionCoordinator(
            backend: FakeBackend(),
            sessionStore: FakeSessionStore()
        )
        let generation = session.activate(appUserID: "user-a")
        let purchase = PurchaseCoordinator(
            backend: FakeBackend(),
            storeKitGateway: FakeStoreKitGateway()
        )

        XCTAssertTrue(purchase.beginPurchase(for: generation, session: session))
        XCTAssertFalse(purchase.beginPurchase(for: generation, session: session))

        _ = session.activate(appUserID: "user-b")
        XCTAssertFalse(purchase.endPurchase(for: generation, session: session))

        purchase.clear()
        XCTAssertFalse(purchase.isPurchaseInProgress)
    }

    private struct FakeBackend: EzyRevenueBackend {}
    private struct FakeSessionStore: SessionStore {}
    private struct FakeStoreKitGateway: StoreKitGateway {}
}
