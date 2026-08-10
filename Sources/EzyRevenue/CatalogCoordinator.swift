/// Owns in-memory catalog and customer snapshots for one SDK runtime.
internal final class CatalogCoordinator {
    let backend: any EzyRevenueBackend
    let storeKitGateway: any StoreKitGateway

    private(set) var offerings: [Offering] = []
    private(set) var currentOffering: Offering?
    private(set) var products: [Product] = []
    private(set) var customerInfo: CustomerInfo?

    init(
        backend: any EzyRevenueBackend,
        storeKitGateway: any StoreKitGateway
    ) {
        self.backend = backend
        self.storeKitGateway = storeKitGateway
    }

    /// Commits offerings only if the originating identity is still active.
    @discardableResult
    func commitOfferings(
        _ offerings: [Offering],
        currentOffering: Offering?,
        for generation: SessionGeneration,
        session: SessionCoordinator
    ) -> Bool {
        guard session.isCurrent(generation) else { return false }
        self.offerings = offerings
        self.currentOffering = currentOffering
        return true
    }

    /// Commits products only if the originating identity is still active.
    @discardableResult
    func commitProducts(
        _ products: [Product],
        for generation: SessionGeneration,
        session: SessionCoordinator
    ) -> Bool {
        guard session.isCurrent(generation) else { return false }
        self.products = products
        return true
    }

    /// Commits customer information only if the originating identity is current.
    @discardableResult
    func commitCustomerInfo(
        _ customerInfo: CustomerInfo,
        for generation: SessionGeneration,
        session: SessionCoordinator
    ) -> Bool {
        guard session.isCurrent(generation) else { return false }
        self.customerInfo = customerInfo
        return true
    }

    /// Clears all snapshots during identity changes and logout.
    func clear() {
        offerings = []
        currentOffering = nil
        products = []
        customerInfo = nil
    }
}
