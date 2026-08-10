import Foundation

@available(macOS 12.0, iOS 15.0, *)
internal enum PurchaseFlowResult: Sendable {
    case purchased(StoreKitVerifiedTransaction)
    case pending
    case cancelled
}

/// Owns the single active purchase slot, transaction recovery, and the live
/// StoreKit update listener for one SDK runtime.
internal final class PurchaseCoordinator: @unchecked Sendable {
    let backend: any EzyRevenueBackend
    let storeKitGateway: any StoreKitGateway

    private let operationGate = AsyncOperationGate()
    private let stateLock = NSLock()
    private var activePurchaseGeneration: SessionGeneration?
    private var processedTransactionIDs: Set<UInt64> = []
    private var transactionListenerTask: Task<Void, Never>?
    private var transactionListenerEpoch: UInt64 = 0

    init(
        backend: any EzyRevenueBackend,
        storeKitGateway: any StoreKitGateway
    ) {
        self.backend = backend
        self.storeKitGateway = storeKitGateway
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    var isPurchaseInProgress: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return activePurchaseGeneration != nil
    }

    /// Starts the one live StoreKit update consumer for this runtime.
    @available(macOS 12.0, iOS 15.0, *)
    func startTransactionListener(session: SessionCoordinator) {
        stateLock.lock()
        guard transactionListenerTask == nil else {
            stateLock.unlock()
            return
        }
        transactionListenerEpoch &+= 1
        let listenerEpoch = transactionListenerEpoch
        let task = Task { [weak self, storeKitGateway] in
            let updates = await storeKitGateway.transactionUpdates()
            for await update in updates {
                guard !Task.isCancelled else { break }
                _ = await self?.processTransaction(
                    update,
                    session: session,
                    listenerEpoch: listenerEpoch
                )
            }
        }
        transactionListenerTask = task
        stateLock.unlock()
    }

    /// Processes StoreKit unfinished work during initialization. Failed
    /// submissions are deliberately left unfinished for a later retry.
    @available(macOS 12.0, iOS 15.0, *)
    func recoverUnfinishedTransactions(session: SessionCoordinator) async {
        let unfinished = await storeKitGateway.unfinishedTransactions()
        for transaction in unfinished {
            _ = await processTransaction(transaction, session: session, listenerEpoch: nil)
        }
    }

    /// Synchronizes the App Store and processes both unfinished work and
    /// current entitlements through the same receipt submission path.
    @available(macOS 12.0, iOS 15.0, *)
    func restorePurchases(session: SessionCoordinator) async -> EzyRevenueResult<Void> {
        guard let generation = session.captureGeneration() else {
            return .failure(.notInitialized)
        }
        do {
            try await storeKitGateway.syncStore()
        } catch {
            return .failure(.network)
        }
        guard session.isCurrent(generation) else {
            return .failure(.notInitialized)
        }

        var firstFailure: EzyRevenueError?
        let unfinished = await storeKitGateway.unfinishedTransactions()
        for transaction in unfinished {
            let result = await processTransaction(
                transaction,
                session: session,
                listenerEpoch: nil,
                force: false
            )
            if case let .failure(error) = result, firstFailure == nil {
                firstFailure = error
            }
        }

        let currentEntitlements = await storeKitGateway.currentEntitlements()
        for transaction in currentEntitlements {
            let result = await processTransaction(
                transaction,
                session: session,
                listenerEpoch: nil,
                force: true
            )
            if case let .failure(error) = result, firstFailure == nil {
                firstFailure = error
            }
        }

        guard session.isCurrent(generation) else {
            return .failure(.notInitialized)
        }
        if let firstFailure {
            return .failure(firstFailure)
        }
        return .success(())
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
        processedTransactionIDs.removeAll()
        transactionListenerEpoch &+= 1
        transactionListenerTask?.cancel()
        transactionListenerTask = nil
        stateLock.unlock()
    }

    @available(macOS 12.0, iOS 15.0, *)
    private func purchase(
        productID: String,
        session: SessionCoordinator
    ) async -> EzyRevenueResult<PurchaseFlowResult> {
        do {
            return try await operationGate.withLock { [self] in
                await purchaseLocked(productID: productID, session: session)
            }
        } catch {
            return .failure(.purchaseFailed)
        }
    }

    @available(macOS 12.0, iOS 15.0, *)
    private func purchaseLocked(
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
            guard case let .verified(verifiedTransaction) = transaction else {
                return .failure(.unverifiedTransaction)
            }
            guard markTransactionForProcessing(verifiedTransaction.id) else {
                return .success(.purchased(verifiedTransaction))
            }
            let result = await submitReceiptAndFinish(
                verifiedTransaction,
                for: generation,
                session: session
            )
            if case .failure = result {
                removeTransactionFromProcessing(verifiedTransaction.id)
            }
            return result
        case .pending:
            return .success(.pending)
        case .cancelled:
            return .success(.cancelled)
        }
    }

    @available(macOS 12.0, iOS 15.0, *)
    private func processTransaction(
        _ result: StoreKitTransactionResult,
        session: SessionCoordinator,
        listenerEpoch: UInt64?,
        force: Bool = false
    ) async -> EzyRevenueResult<Void> {
        guard listenerEpoch.map(isCurrentListenerEpoch) ?? true else {
            return .failure(.notInitialized)
        }
        guard case let .verified(transaction) = result else {
            // Unverified transactions are intentionally ignored and never
            // finished or treated as a purchase.
            return .success(())
        }
        guard let generation = session.captureGeneration(),
              session.isCurrent(generation) else {
            return .failure(.notInitialized)
        }
        if force, isTransactionAlreadyProcessed(transaction.id) {
            return .success(())
        }
        guard markTransactionForProcessing(transaction.id) else {
            return .success(())
        }

        do {
            let submission = try await operationGate.withLock { [self] in
                await submitReceiptAndFinish(
                    transaction,
                    for: generation,
                    session: session,
                    listenerEpoch: listenerEpoch
                )
            }
            if case let .failure(error) = submission {
                // A failed backend result leaves the transaction unfinished
                // and must be retried by a future recovery pass.
                removeTransactionFromProcessing(transaction.id)
                return .failure(error)
            }
        } catch {
            removeTransactionFromProcessing(transaction.id)
            return .failure(.network)
        }
        guard session.isCurrent(generation) else {
            removeTransactionFromProcessing(transaction.id)
            return .failure(.notInitialized)
        }
        return .success(())
    }

    @available(macOS 12.0, iOS 15.0, *)
    private func submitReceiptAndFinish(
        _ transaction: StoreKitVerifiedTransaction,
        for generation: SessionGeneration,
        session: SessionCoordinator,
        listenerEpoch: UInt64? = nil
    ) async -> EzyRevenueResult<PurchaseFlowResult> {
        guard listenerEpoch.map(isCurrentListenerEpoch) ?? true,
              session.isCurrent(generation) else {
            return .failure(.notInitialized)
        }

        let receipt = ReceiptRequest(
            appUserID: generation.appUserID,
            productIdentifier: transaction.productID,
            transactionID: String(transaction.id),
            receiptData: AppReceiptProvider.base64Receipt(),
            fetchToken: transaction.jwsRepresentation.nonBlank
        )
        let backendResult = await session.executeAuthenticated { [backend] _ in
            do {
                return try await backend.postReceipt(receipt)
            } catch {
                return .failure(.network)
            }
        }
        guard case .success = backendResult else {
            if case let .failure(error) = backendResult {
                return .failure(error)
            }
            return .failure(.network)
        }

        guard listenerEpoch.map(isCurrentListenerEpoch) ?? true,
              session.isCurrent(generation) else {
            return .failure(.notInitialized)
        }
        await storeKitGateway.finish(transaction)
        return .success(.purchased(transaction))
    }

    private func isCurrentListenerEpoch(_ epoch: UInt64) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return transactionListenerEpoch == epoch
    }

    private func isTransactionAlreadyProcessed(_ transactionID: UInt64) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return processedTransactionIDs.contains(transactionID)
    }

    private func markTransactionForProcessing(_ transactionID: UInt64) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return processedTransactionIDs.insert(transactionID).inserted
    }

    private func removeTransactionFromProcessing(_ transactionID: UInt64) {
        stateLock.lock()
        processedTransactionIDs.remove(transactionID)
        stateLock.unlock()
    }

    private func releasePurchase(for generation: SessionGeneration) {
        stateLock.lock()
        if activePurchaseGeneration == generation {
            activePurchaseGeneration = nil
        }
        stateLock.unlock()
    }
}

private extension String {
    var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
