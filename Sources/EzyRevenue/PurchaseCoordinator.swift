import Foundation

@available(macOS 12.0, iOS 15.0, *)
internal enum PurchaseFlowResult: Sendable {
    case purchased(StoreKitVerifiedTransaction)
    case pending
    case cancelled
}

/// Owns the single active purchase slot for one SDK runtime.
internal final class PurchaseCoordinator: @unchecked Sendable {
    let backend: any EzyRevenueBackend
    let storeKitGateway: any StoreKitGateway

    private let stateLock = NSLock()
    private var activePurchaseGeneration: SessionGeneration?

    init(
        backend: any EzyRevenueBackend,
        storeKitGateway: any StoreKitGateway
    ) {
        self.backend = backend
        self.storeKitGateway = storeKitGateway
    }

    var isPurchaseInProgress: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return activePurchaseGeneration != nil
    }

    /// Purchases the StoreKit product represented by an offering package.
    @available(macOS 12.0, iOS 15.0, *)
    func purchasePackage(
        _ package: OfferingPackage,
        session: SessionCoordinator
    ) async -> EzyRevenueResult<PurchaseFlowResult> {
        guard case let .success(productID) = CatalogCoordinator.storeKitIdentifier(for: package) else {
            return .failure(.invalidConfiguration(
                "Offering package StoreKit identifiers must agree"
            ))
        }
        return await purchase(productID: productID, session: session)
    }

    /// Purchases a raw backend product by its canonical App Store identifier.
    @available(macOS 12.0, iOS 15.0, *)
    func purchaseProduct(
        _ product: Product,
        session: SessionCoordinator
    ) async -> EzyRevenueResult<PurchaseFlowResult> {
        let productID = product.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !productID.isEmpty else {
            return .failure(.invalidConfiguration("product identifier must not be blank"))
        }
        return await purchase(productID: productID, session: session)
    }

    /// Reserves the purchase slot for the current identity.
    @discardableResult
    func beginPurchase(for generation: SessionGeneration, session: SessionCoordinator) -> Bool {
        guard session.isCurrent(generation) else { return false }
        stateLock.lock()
        defer { stateLock.unlock() }
        guard activePurchaseGeneration == nil, session.isCurrent(generation) else {
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
        guard session.isCurrent(generation) else { return false }
        stateLock.lock()
        defer { stateLock.unlock() }
        guard activePurchaseGeneration == generation else { return false }
        activePurchaseGeneration = nil
        return true
    }

    /// Releases work during logout or an identity switch.
    func clear() {
        stateLock.lock()
        activePurchaseGeneration = nil
        stateLock.unlock()
    }

    @available(macOS 12.0, iOS 15.0, *)
    private func purchase(
        productID: String,
        session: SessionCoordinator
    ) async -> EzyRevenueResult<PurchaseFlowResult> {
        guard let generation = session.captureGeneration() else {
            return .failure(.notInitialized)
        }
        guard beginPurchase(for: generation, session: session) else {
            return .failure(.purchaseInProgress)
        }
        defer { releasePurchase(for: generation) }

        let accountToken = AppAccountToken.make(appUserID: generation.appUserID)
        let outcome: StorePurchaseOutcome
        do {
            // The gateway refreshes the exact product immediately before
            // purchase, so stale catalog prices/details are never purchased.
            outcome = try await storeKitGateway.purchase(
                productID: productID,
                appAccountToken: accountToken
            )
        } catch {
            return .failure(.purchaseFailed)
        }

        guard session.isCurrent(generation) else {
            // Do not finish or submit a transaction for a user that logged out
            // or switched identities while StoreKit was presenting UI.
            return .failure(.notInitialized)
        }

        switch outcome {
        case let .purchased(transaction):
            guard case .verified = transaction else {
                return .failure(.unverifiedTransaction)
            }
            return .success(.purchased(transaction.verifiedValue))
        case .pending:
            return .success(.pending)
        case .cancelled:
            return .success(.cancelled)
        }
    }

    private func releasePurchase(for generation: SessionGeneration) {
        stateLock.lock()
        if activePurchaseGeneration == generation {
            activePurchaseGeneration = nil
        }
        stateLock.unlock()
    }
}

@available(macOS 12.0, iOS 15.0, *)
private extension StoreKitTransactionResult {
    var verifiedValue: StoreKitVerifiedTransaction {
        switch self {
        case let .verified(transaction):
            return transaction
        case .unverified:
            preconditionFailure("Unverified transaction cannot become a purchased result")
        }
    }
}
