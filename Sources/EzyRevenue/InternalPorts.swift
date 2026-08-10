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

/// One small persisted record for the active SDK identity and backend session.
internal struct StoredSession: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let appUserID: String
    let apiKeyFingerprint: String
    let accessToken: String?
    let createdAt: Date
    let isAuthenticated: Bool
    let schemaVersion: Int

    init(
        appUserID: String,
        apiKeyFingerprint: String,
        accessToken: String?,
        createdAt: Date = Date(),
        isAuthenticated: Bool = true,
        schemaVersion: Int = StoredSession.currentSchemaVersion
    ) {
        self.appUserID = appUserID
        self.apiKeyFingerprint = apiKeyFingerprint
        self.accessToken = accessToken
        self.createdAt = createdAt
        self.isAuthenticated = isAuthenticated
        self.schemaVersion = schemaVersion
    }

    private enum CodingKeys: String, CodingKey {
        case appUserID
        case apiKeyFingerprint
        case accessToken
        case createdAt
        case isAuthenticated
        case schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appUserID = try container.decode(String.self, forKey: .appUserID)
        apiKeyFingerprint = try container.decode(String.self, forKey: .apiKeyFingerprint)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        // Records written before the identity-only marker existed are active
        // sessions and remain backward compatible.
        isAuthenticated = try container.decodeIfPresent(Bool.self, forKey: .isAuthenticated) ?? true
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? StoredSession.currentSchemaVersion
    }
}

/// Keychain-backed session boundary.
internal protocol SessionStore: Sendable {
    func save(_ session: StoredSession) async throws
    func load(apiKeyFingerprint: String) async throws -> StoredSession?
    func clear() async throws
}

/// Default behavior keeps test-only boundary fakes source-compatible until
/// session coordination is wired to persistence.
extension SessionStore {
    func save(_ session: StoredSession) async throws {
        throw SessionStoreError.unavailable
    }

    func load(apiKeyFingerprint: String) async throws -> StoredSession? {
        throw SessionStoreError.unavailable
    }

    func clear() async throws {
        throw SessionStoreError.unavailable
    }
}

internal enum SessionStoreError: Error, Equatable, Sendable {
    case unavailable
    case invalidRecord
    case keychainStatus(Int32)
}
