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

    deinit {
        storeKitGateway.shutdown()
    }

    init(
        backend: any EzyRevenueBackend,
        sessionStore: any SessionStore,
        storeKitGateway: any StoreKitGateway,
        logger: EzyRevenueLogger = EzyRevenueLogger(level: .none)
    ) {
        self.backend = backend
        self.sessionStore = sessionStore
        self.storeKitGateway = storeKitGateway
        self.sessionCoordinator = SessionCoordinator(
            backend: backend,
            sessionStore: sessionStore,
            logger: logger
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

    static func unavailable(
        logger: EzyRevenueLogger = EzyRevenueLogger(level: .none)
    ) -> EzyRevenueComponent {
        EzyRevenueComponent(
            backend: UnavailableBackend(),
            sessionStore: KeychainSessionStore(logger: logger),
            storeKitGateway: UnavailableStoreKitGateway(),
            logger: logger
        )
    }

    @available(macOS 12.0, iOS 15.0, *)
    static func runtime(
        apiKey: String,
        userCountryCode: String?,
        logger: EzyRevenueLogger
    ) -> EzyRevenueComponent {
        let backend = URLSessionEzyRevenueBackend(
            apiKey: apiKey,
            metadataProvider: {
                await MetadataProvider.current(userCountryCode: userCountryCode)
            },
            logger: logger
        )
        return EzyRevenueComponent(
            backend: backend,
            sessionStore: KeychainSessionStore(logger: logger),
            storeKitGateway: StoreKit2Gateway(),
            logger: logger
        )
    }
}

private struct UnavailableBackend: EzyRevenueBackend {}
private struct UnavailableStoreKitGateway: StoreKitGateway {}
