import Foundation
@testable import EzyRevenue

final class TestBackend: EzyRevenueBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var storedLoginResults: [BackendResult] = []
    private var storedReceiptResults: [BackendResult] = []
    private var storedLoginIDs: [String] = []
    private var storedLogoutIDs: [String] = []
    private var storedReceipts: [ReceiptRequest] = []
    private var storedOfferingsCalls: [(String, String?, String?)] = []
    private var storedCustomerCalls: [(String, String?)] = []
    private var storedLoginResult: BackendResult = .success(
        statusCode: 200,
        body: Data("{}".utf8)
    )
    private var storedLogoutResult: BackendResult = .success(
        statusCode: 200,
        body: Data("{}".utf8)
    )
    private var storedOfferingsResult: BackendResult = .success(
        statusCode: 200,
        body: Data("{\"offerings\":[]}".utf8)
    )
    private var storedProductsResult: BackendResult = .success(
        statusCode: 200,
        body: Data("{\"success\":true,\"data\":[]}".utf8)
    )
    private var storedCustomerResult: BackendResult = .success(
        statusCode: 200,
        body: Data(
            "{\"request_date\":\"2026-01-01T00:00:00Z\",\"subscriber\":{\"original_app_user_id\":\"user\"}}".utf8
        )
    )

    var loginResult: BackendResult {
        get { withLock { storedLoginResult } }
        set { withLock { storedLoginResult = newValue } }
    }

    var loginResults: [BackendResult] {
        get { withLock { storedLoginResults } }
        set { withLock { storedLoginResults = newValue } }
    }

    var logoutResult: BackendResult {
        get { withLock { storedLogoutResult } }
        set { withLock { storedLogoutResult = newValue } }
    }

    var offeringsResult: BackendResult {
        get { withLock { storedOfferingsResult } }
        set { withLock { storedOfferingsResult = newValue } }
    }

    var productsResult: BackendResult {
        get { withLock { storedProductsResult } }
        set { withLock { storedProductsResult = newValue } }
    }

    var customerResult: BackendResult {
        get { withLock { storedCustomerResult } }
        set { withLock { storedCustomerResult = newValue } }
    }

    var receiptResults: [BackendResult] {
        get { withLock { storedReceiptResults } }
        set { withLock { storedReceiptResults = newValue } }
    }

    var loginIDs: [String] { withLock { storedLoginIDs } }
    var logoutIDs: [String] { withLock { storedLogoutIDs } }
    var receipts: [ReceiptRequest] { withLock { storedReceipts } }
    var offeringsCalls: [(String, String?, String?)] { withLock { storedOfferingsCalls } }
    var customerCalls: [(String, String?)] { withLock { storedCustomerCalls } }

    func login(appUserID: String) async throws -> BackendResult {
        withLock {
            storedLoginIDs.append(appUserID)
            if storedLoginResults.isEmpty {
                return storedLoginResult
            }
            return storedLoginResults.removeFirst()
        }
    }

    func logout(appUserID: String) async throws -> BackendResult {
        withLock {
            storedLogoutIDs.append(appUserID)
            return storedLogoutResult
        }
    }

    func postReceipt(_ receipt: ReceiptRequest) async throws -> BackendResult {
        withLock {
            storedReceipts.append(receipt)
            if storedReceiptResults.isEmpty {
                return .success(statusCode: 200, body: Data("{}".utf8))
            }
            return storedReceiptResults.removeFirst()
        }
    }

    func fetchOfferings(
        appUserID: String,
        countryCode: String?,
        accessToken: String?
    ) async throws -> BackendResult {
        withLock {
            storedOfferingsCalls.append((appUserID, countryCode, accessToken))
            return storedOfferingsResult
        }
    }

    func fetchProducts() async throws -> BackendResult {
        withLock { storedProductsResult }
    }

    func fetchCustomerInfo(
        appUserID: String,
        accessToken: String?
    ) async throws -> BackendResult {
        withLock {
            storedCustomerCalls.append((appUserID, accessToken))
            return storedCustomerResult
        }
    }

    private func withLock<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

final class TestSessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedSession: StoredSession?
    private var storedClearCount = 0

    var session: StoredSession? {
        get { withLock { storedSession } }
        set { withLock { storedSession = newValue } }
    }

    var clearCount: Int { withLock { storedClearCount } }

    func save(_ session: StoredSession) async throws {
        withLock { storedSession = session }
    }

    func load(apiKeyFingerprint: String) async throws -> StoredSession? {
        withLock {
            storedSession?.apiKeyFingerprint == apiKeyFingerprint ? storedSession : nil
        }
    }

    func clear() async throws {
        withLock {
            storedSession = nil
            storedClearCount += 1
        }
    }

    private func withLock<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

@available(macOS 12.0, iOS 15.0, *)
final class TestStoreKitGateway: StoreKitGateway, @unchecked Sendable {
    private let lock = NSLock()
    private let updatesStream: AsyncStream<StoreKitTransactionResult>
    private let updatesContinuation: AsyncStream<StoreKitTransactionResult>.Continuation
    private var storedProducts: [StoreKitProduct] = []
    private var storedPurchaseOutcome: StorePurchaseOutcome = .cancelled
    private var storedUnfinished: [StoreKitTransactionResult] = []
    private var storedCurrentEntitlements: [StoreKitTransactionResult] = []
    private var storedPurchaseIDs: [String] = []
    private var storedAccountTokens: [UUID?] = []
    private var storedFinishedIDs: [UInt64] = []
    private var storedSyncCount = 0
    private var storedPurchaseError = false
    private var storedSyncError = false

    init() {
        let stream = AsyncStream<StoreKitTransactionResult>.makeStream()
        updatesStream = stream.stream
        updatesContinuation = stream.continuation
    }

    var products: [StoreKitProduct] {
        get { withLock { storedProducts } }
        set { withLock { storedProducts = newValue } }
    }

    var purchaseOutcome: StorePurchaseOutcome {
        get { withLock { storedPurchaseOutcome } }
        set { withLock { storedPurchaseOutcome = newValue } }
    }

    var unfinished: [StoreKitTransactionResult] {
        get { withLock { storedUnfinished } }
        set { withLock { storedUnfinished = newValue } }
    }

    var currentEntitlements: [StoreKitTransactionResult] {
        get { withLock { storedCurrentEntitlements } }
        set { withLock { storedCurrentEntitlements = newValue } }
    }

    var purchaseIDs: [String] { withLock { storedPurchaseIDs } }
    var accountTokens: [UUID?] { withLock { storedAccountTokens } }
    var finishedIDs: [UInt64] { withLock { storedFinishedIDs } }
    var syncCount: Int { withLock { storedSyncCount } }

    var purchaseError: Bool {
        get { withLock { storedPurchaseError } }
        set { withLock { storedPurchaseError = newValue } }
    }

    var syncError: Bool {
        get { withLock { storedSyncError } }
        set { withLock { storedSyncError = newValue } }
    }

    func fetchProducts(for identifiers: Set<String>) async throws -> [StoreKitProduct] {
        withLock { storedProducts.filter { identifiers.contains($0.id) } }
    }

    func purchase(
        productID: String,
        appAccountToken: UUID?
    ) async throws -> StorePurchaseOutcome {
        let values = withLock { () -> (Bool, StorePurchaseOutcome) in
            storedPurchaseIDs.append(productID)
            storedAccountTokens.append(appAccountToken)
            return (storedPurchaseError, storedPurchaseOutcome)
        }
        if values.0 { throw StoreKitGatewayError.operationFailed("purchase") }
        return values.1
    }

    func transactionUpdates() async -> AsyncStream<StoreKitTransactionResult> {
        updatesStream
    }

    func unfinishedTransactions() async -> [StoreKitTransactionResult] {
        withLock { storedUnfinished }
    }

    func currentEntitlements() async -> [StoreKitTransactionResult] {
        withLock { storedCurrentEntitlements }
    }

    func finish(_ transaction: StoreKitVerifiedTransaction) async {
        withLock { storedFinishedIDs.append(transaction.id) }
    }

    func syncStore() async throws {
        let shouldFail = withLock {
            storedSyncCount += 1
            return storedSyncError
        }
        if shouldFail { throw StoreKitGatewayError.operationFailed("sync") }
    }

    func emit(_ update: StoreKitTransactionResult) {
        updatesContinuation.yield(update)
    }

    func shutdown() {
        updatesContinuation.finish()
    }

    private func withLock<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

@available(macOS 12.0, iOS 15.0, *)
func makeVerifiedTransaction(
    id: UInt64 = 42,
    productID: String = "com.example.premium.monthly",
    jws: String = "verified-jws"
) -> StoreKitTransactionResult {
    .verified(
        StoreKitVerifiedTransaction(
            id: id,
            productID: productID,
            jwsRepresentation: jws
        )
    )
}

func makeLoginBody(token: String? = nil) -> Data {
    if let token {
        return Data("{\"appAccessToken\":\"\(token)\"}".utf8)
    }
    return Data("{}".utf8)
}
