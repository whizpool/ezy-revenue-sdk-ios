import Foundation
import StoreKit

/// StoreKit product data kept internal to the SDK.
@available(macOS 12.0, iOS 15.0, *)
internal struct StoreKitProduct: Equatable, Sendable {
    let id: String
    let displayName: String
    let description: String
    let displayPrice: String
}

/// A verified transaction handle retained until backend processing can finish it.
@available(macOS 12.0, iOS 15.0, *)
internal struct StoreKitVerifiedTransaction: @unchecked Sendable {
    let id: UInt64
    let productID: String
    let jwsRepresentation: String
    fileprivate let rawTransaction: StoreKit.Transaction

    init(transaction: StoreKit.Transaction, jwsRepresentation: String) {
        id = transaction.id
        productID = transaction.productID
        self.jwsRepresentation = jwsRepresentation
        rawTransaction = transaction
    }
}

/// A transaction that failed StoreKit verification and must never grant access.
@available(macOS 12.0, iOS 15.0, *)
internal struct StoreKitUnverifiedTransaction: Equatable, Sendable {
    let id: UInt64
    let productID: String
    let reason: String
}

@available(macOS 12.0, iOS 15.0, *)
internal enum StoreKitTransactionResult: Equatable, Sendable {
    case verified(StoreKitVerifiedTransaction)
    case unverified(StoreKitUnverifiedTransaction)

    static func == (
        lhs: StoreKitTransactionResult,
        rhs: StoreKitTransactionResult
    ) -> Bool {
        switch (lhs, rhs) {
        case let (.verified(left), .verified(right)):
            return left.id == right.id && left.productID == right.productID
        case let (.unverified(left), .unverified(right)):
            return left == right
        default:
            return false
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
internal enum StorePurchaseOutcome: Equatable, Sendable {
    case purchased(StoreKitTransactionResult)
    case pending
    case cancelled
}

internal enum StoreKitGatewayError: Error, Equatable, Sendable {
    case unavailable
    case productNotFound(String)
    case operationFailed(String)
}

/// StoreKit boundary used by catalog, purchase, and recovery flows.
internal protocol StoreKitGateway: Sendable {
    @available(macOS 12.0, iOS 15.0, *)
    func fetchProducts(for identifiers: Set<String>) async throws -> [StoreKitProduct]

    @available(macOS 12.0, iOS 15.0, *)
    func purchase(
        productID: String,
        appAccountToken: UUID?
    ) async throws -> StorePurchaseOutcome

    @available(macOS 12.0, iOS 15.0, *)
    func transactionUpdates() async -> AsyncStream<StoreKitTransactionResult>

    @available(macOS 12.0, iOS 15.0, *)
    func unfinishedTransactions() async -> [StoreKitTransactionResult]

    @available(macOS 12.0, iOS 15.0, *)
    func currentEntitlements() async -> [StoreKitTransactionResult]

    @available(macOS 12.0, iOS 15.0, *)
    func finish(_ transaction: StoreKitVerifiedTransaction) async

    @available(macOS 12.0, iOS 15.0, *)
    func syncStore() async throws

    /// Cancels the single live transaction listener owned by the runtime.
    func shutdown()
}

extension StoreKitGateway {
    @available(macOS 12.0, iOS 15.0, *)
    func fetchProducts(for identifiers: Set<String>) async throws -> [StoreKitProduct] {
        throw StoreKitGatewayError.unavailable
    }

    @available(macOS 12.0, iOS 15.0, *)
    func purchase(
        productID: String,
        appAccountToken: UUID?
    ) async throws -> StorePurchaseOutcome {
        throw StoreKitGatewayError.unavailable
    }

    @available(macOS 12.0, iOS 15.0, *)
    func transactionUpdates() async -> AsyncStream<StoreKitTransactionResult> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    @available(macOS 12.0, iOS 15.0, *)
    func unfinishedTransactions() async -> [StoreKitTransactionResult] {
        []
    }

    @available(macOS 12.0, iOS 15.0, *)
    func currentEntitlements() async -> [StoreKitTransactionResult] {
        []
    }

    @available(macOS 12.0, iOS 15.0, *)
    func finish(_ transaction: StoreKitVerifiedTransaction) async {
        _ = transaction
    }

    @available(macOS 12.0, iOS 15.0, *)
    func syncStore() async throws {
        throw StoreKitGatewayError.unavailable
    }

    func shutdown() {}
}

/// StoreKit 2 implementation. Its one listener starts at construction and
/// broadcasts updates to later consumers without creating another listener.
@available(macOS 12.0, iOS 15.0, *)
internal final class StoreKit2Gateway: StoreKitGateway, @unchecked Sendable {
    private let updateHub: StoreKitTransactionUpdateHub
    private let listenerTask: Task<Void, Never>

    init() {
        let updateHub = StoreKitTransactionUpdateHub()
        self.updateHub = updateHub
        self.listenerTask = Task {
            for await verification in StoreKit.Transaction.updates {
                await updateHub.publish(Self.map(verification))
            }
            await updateHub.finish()
        }
    }

    deinit {
        shutdown()
    }

    func fetchProducts(for identifiers: Set<String>) async throws -> [StoreKitProduct] {
        do {
            let products = try await StoreKit.Product.products(for: Array(identifiers))
            return products.map {
                StoreKitProduct(
                    id: $0.id,
                    displayName: $0.displayName,
                    description: $0.description,
                    displayPrice: $0.displayPrice
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw StoreKitGatewayError.operationFailed(error.localizedDescription)
        }
    }

    func purchase(
        productID: String,
        appAccountToken: UUID?
    ) async throws -> StorePurchaseOutcome {
        let products = try await fetchProducts(for: [productID])
        guard products.contains(where: { $0.id == productID }) else {
            throw StoreKitGatewayError.productNotFound(productID)
        }

        do {
            let rawProducts = try await StoreKit.Product.products(for: [productID])
            guard let product = rawProducts.first(where: { $0.id == productID }) else {
                throw StoreKitGatewayError.productNotFound(productID)
            }
            var options = Set<StoreKit.Product.PurchaseOption>()
            if let appAccountToken {
                options.insert(.appAccountToken(appAccountToken))
            }
            switch try await product.purchase(options: options) {
            case let .success(verification):
                return .purchased(Self.map(verification))
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                throw StoreKitGatewayError.operationFailed("Unknown StoreKit purchase result")
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as StoreKitGatewayError {
            throw error
        } catch {
            throw StoreKitGatewayError.operationFailed(error.localizedDescription)
        }
    }

    func transactionUpdates() async -> AsyncStream<StoreKitTransactionResult> {
        await updateHub.stream()
    }

    func unfinishedTransactions() async -> [StoreKitTransactionResult] {
        var transactions: [StoreKitTransactionResult] = []
        for await verification in StoreKit.Transaction.unfinished {
            transactions.append(Self.map(verification))
        }
        return transactions
    }

    func currentEntitlements() async -> [StoreKitTransactionResult] {
        var transactions: [StoreKitTransactionResult] = []
        for await verification in StoreKit.Transaction.currentEntitlements {
            transactions.append(Self.map(verification))
        }
        return transactions
    }

    func finish(_ transaction: StoreKitVerifiedTransaction) async {
        await transaction.rawTransaction.finish()
    }

    func syncStore() async throws {
        do {
            try await StoreKit.AppStore.sync()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw StoreKitGatewayError.operationFailed(error.localizedDescription)
        }
    }

    func shutdown() {
        listenerTask.cancel()
        Task {
            await updateHub.finish()
        }
    }

    private static func map(
        _ verification: StoreKit.VerificationResult<StoreKit.Transaction>
    ) -> StoreKitTransactionResult {
        switch verification {
        case let .verified(transaction):
            return .verified(
                StoreKitVerifiedTransaction(
                    transaction: transaction,
                    jwsRepresentation: verification.jwsRepresentation
                )
            )
        case let .unverified(transaction, error):
            return .unverified(
                StoreKitUnverifiedTransaction(
                    id: transaction.id,
                    productID: transaction.productID,
                    reason: error.localizedDescription
                )
            )
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
private actor StoreKitTransactionUpdateHub {
    private var continuations: [UUID: AsyncStream<StoreKitTransactionResult>.Continuation] = [:]
    private var pending: [StoreKitTransactionResult] = []

    func stream() -> AsyncStream<StoreKitTransactionResult> {
        let identifier = UUID()
        let (stream, continuation) = AsyncStream<StoreKitTransactionResult>.makeStream()
        continuations[identifier] = continuation
        for transaction in pending {
            continuation.yield(transaction)
        }
        pending.removeAll()
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.remove(identifier) }
        }
        return stream
    }

    func publish(_ transaction: StoreKitTransactionResult) {
        if continuations.isEmpty {
            pending.append(transaction)
        } else {
            for continuation in continuations.values {
                continuation.yield(transaction)
            }
        }
    }

    func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
        pending.removeAll()
    }

    private func remove(_ identifier: UUID) {
        continuations.removeValue(forKey: identifier)
    }
}
