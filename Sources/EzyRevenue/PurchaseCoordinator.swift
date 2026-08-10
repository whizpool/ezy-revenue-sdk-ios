/// Owns the single active purchase slot for one SDK runtime.
internal final class PurchaseCoordinator {
    let backend: any EzyRevenueBackend
    let storeKitGateway: any StoreKitGateway

    private(set) var activePurchaseGeneration: SessionGeneration?

    init(
        backend: any EzyRevenueBackend,
        storeKitGateway: any StoreKitGateway
    ) {
        self.backend = backend
        self.storeKitGateway = storeKitGateway
    }

    var isPurchaseInProgress: Bool {
        activePurchaseGeneration != nil
    }

    /// Reserves the purchase slot for the current identity.
    @discardableResult
    func beginPurchase(for generation: SessionGeneration, session: SessionCoordinator) -> Bool {
        guard session.isCurrent(generation), activePurchaseGeneration == nil else {
            return false
        }
        activePurchaseGeneration = generation
        return true
    }

    /// Releases the purchase slot only while its owning identity is current.
    @discardableResult
    func endPurchase(
        for generation: SessionGeneration,
        session: SessionCoordinator
    ) -> Bool {
        guard session.isCurrent(generation), activePurchaseGeneration == generation else {
            return false
        }
        activePurchaseGeneration = nil
        return true
    }

    /// Releases work during logout or an identity switch.
    func clear() {
        activePurchaseGeneration = nil
    }
}
