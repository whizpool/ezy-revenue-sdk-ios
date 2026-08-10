import Foundation

/// Stable error categories returned by EzyRevenue operations.
public enum EzyRevenueError: Error, Equatable, Sendable {
    /// The supplied initialization or operation input is invalid.
    case invalidConfiguration(String)

    /// The SDK has not completed initialization.
    case notInitialized

    /// The backend rejected or could not authenticate the active session.
    case authentication

    /// A request could not be completed because of transport or server failure.
    case network

    /// A successful backend response did not match the required contract.
    case invalidResponse

    /// StoreKit is unavailable for the requested operation.
    case billingUnavailable

    /// Another purchase operation is already active.
    case purchaseInProgress

    /// StoreKit or the backend rejected the purchase operation.
    case purchaseFailed

    /// StoreKit returned a transaction that could not be verified.
    case unverifiedTransaction

    /// The backend rejected a verified store transaction.
    case backendRejected

    /// An unexpected SDK failure occurred.
    case internalError(String)
}

extension EzyRevenueError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            return message
        case .notInitialized:
            return "EzyRevenue has not been initialized."
        case .authentication:
            return "EzyRevenue authentication failed."
        case .network:
            return "The EzyRevenue network request failed."
        case .invalidResponse:
            return "The EzyRevenue backend response was invalid."
        case .billingUnavailable:
            return "StoreKit is unavailable."
        case .purchaseInProgress:
            return "Another purchase is already in progress."
        case .purchaseFailed:
            return "The purchase failed."
        case .unverifiedTransaction:
            return "The StoreKit transaction could not be verified."
        case .backendRejected:
            return "The backend rejected the store transaction."
        case let .internalError(message):
            return message
        }
    }
}

/// Result type used by the public EzyRevenue API.
public typealias EzyRevenueResult<Value> = Result<Value, EzyRevenueError>

/// Outcome of a StoreKit purchase flow after the store response is handled.
public enum PurchaseResult: Equatable, Sendable {
    /// The store reported a completed purchase and backend processing succeeded.
    case purchased

    /// The store requires the purchase to remain pending.
    case pending

    /// The user cancelled the StoreKit purchase UI.
    case cancelled
}
