/// Manually constructed dependency graph for one SDK runtime.
///
/// There is intentionally no dependency-injection framework. The three
/// external boundaries are explicit so tests can replace them with small fakes.
internal final class EzyRevenueComponent {
    let backend: any EzyRevenueBackend
    let sessionStore: any SessionStore
    let storeKitGateway: any StoreKitGateway

    let sessionCoordinator: SessionCoordinator
    let catalogCoordinator: CatalogCoordinator
    let purchaseCoordinator: PurchaseCoordinator

    init(
        backend: any EzyRevenueBackend,
        sessionStore: any SessionStore,
        storeKitGateway: any StoreKitGateway
    ) {
        self.backend = backend
        self.sessionStore = sessionStore
        self.storeKitGateway = storeKitGateway
        self.sessionCoordinator = SessionCoordinator(
            backend: backend,
            sessionStore: sessionStore
        )
        self.catalogCoordinator = CatalogCoordinator(
            backend: backend,
            storeKitGateway: storeKitGateway
        )
        self.purchaseCoordinator = PurchaseCoordinator(
            backend: backend,
            storeKitGateway: storeKitGateway
        )
    }

    static func unavailable() -> EzyRevenueComponent {
        EzyRevenueComponent(
            backend: UnavailableBackend(),
            sessionStore: UnavailableSessionStore(),
            storeKitGateway: UnavailableStoreKitGateway()
        )
    }
}

private struct UnavailableBackend: EzyRevenueBackend {}
private struct UnavailableSessionStore: SessionStore {}
private struct UnavailableStoreKitGateway: StoreKitGateway {}
