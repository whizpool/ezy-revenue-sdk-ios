import Foundation

/// Raw result returned by the backend adapter before domain mapping.
internal enum BackendResult: Equatable, Sendable {
    case success(statusCode: Int, body: Data)
    case failure(EzyRevenueError)
}

/// Store proof submitted to `/v1/receipts`.
internal struct ReceiptRequest: Equatable, Sendable {
    let appUserID: String
    let productIdentifier: String?
    let transactionID: String?
    let receiptData: String?
    let purchaseToken: String?
    let fetchToken: String?

    init(
        appUserID: String,
        productIdentifier: String? = nil,
        transactionID: String? = nil,
        receiptData: String? = nil,
        purchaseToken: String? = nil,
        fetchToken: String? = nil
    ) {
        self.appUserID = appUserID
        self.productIdentifier = productIdentifier
        self.transactionID = transactionID
        self.receiptData = receiptData
        self.purchaseToken = purchaseToken
        self.fetchToken = fetchToken
    }
}

/// Backend boundary used by the session, catalog, and purchase coordinators.
internal protocol EzyRevenueBackend: Sendable {
    func login(appUserID: String) async throws -> BackendResult
    func logout(appUserID: String) async throws -> BackendResult
    func postReceipt(_ receipt: ReceiptRequest) async throws -> BackendResult
    func fetchOfferings(
        appUserID: String,
        countryCode: String?,
        accessToken: String?
    ) async throws -> BackendResult
    func fetchProducts() async throws -> BackendResult
    func fetchCustomerInfo(
        appUserID: String,
        accessToken: String?
    ) async throws -> BackendResult
}

/// Default behavior keeps the architecture compilable until the corresponding
/// coordinator/adapter step wires each operation.
extension EzyRevenueBackend {
    func login(appUserID: String) async throws -> BackendResult {
        .failure(.internalError("Backend login is not available yet"))
    }

    func logout(appUserID: String) async throws -> BackendResult {
        .failure(.internalError("Backend logout is not available yet"))
    }

    func postReceipt(_ receipt: ReceiptRequest) async throws -> BackendResult {
        .failure(.internalError("Receipt submission is not available yet"))
    }

    func fetchOfferings(
        appUserID: String,
        countryCode: String?,
        accessToken: String?
    ) async throws -> BackendResult {
        .failure(.internalError("Backend offerings are not available yet"))
    }

    func fetchProducts() async throws -> BackendResult {
        .failure(.internalError("Backend products are not available yet"))
    }

    func fetchCustomerInfo(
        appUserID: String,
        accessToken: String?
    ) async throws -> BackendResult {
        .failure(.internalError("Backend customer info is not available yet"))
    }
}

/// Keychain-backed session boundary.
internal protocol SessionStore: Sendable {}

/// StoreKit boundary used by catalog and purchase flows.
internal protocol StoreKitGateway: Sendable {}
