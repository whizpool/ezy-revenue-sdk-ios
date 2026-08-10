import Foundation
import Security

/// The only keychain accessibility policy used by the SDK.
internal enum KeychainItemAccessibility: Equatable, Sendable {
    case afterFirstUnlockThisDeviceOnly
}

/// Small internal seam around Security.framework so record behavior can be
/// tested without depending on a host keychain.
internal protocol KeychainRecordClient: Sendable {
    func read(service: String, account: String) throws -> Data?
    func write(
        _ data: Data,
        service: String,
        account: String,
        accessibility: KeychainItemAccessibility
    ) throws
    func delete(service: String, account: String) throws
}

/// Persists one Codable SDK session record in a non-synchronizable Keychain
/// generic-password item.
internal final class KeychainSessionStore: SessionStore, @unchecked Sendable {
    static let defaultService = "com.whizpool.ezyrevenue.session"
    static let defaultAccount = "current"

    private let service: String
    private let account: String
    private let client: any KeychainRecordClient
    private let logger: EzyRevenueLogger
    private let lock = NSLock()

    init(
        service: String = KeychainSessionStore.defaultService,
        account: String = KeychainSessionStore.defaultAccount,
        client: any KeychainRecordClient = SecurityKeychainRecordClient(),
        logger: EzyRevenueLogger = EzyRevenueLogger(level: .none)
    ) {
        self.service = service
        self.account = account
        self.client = client
        self.logger = logger
    }

    func save(_ session: StoredSession) async throws {
        try withLock {
            try validate(session)
            let data = try JSONEncoder().encode(session)
            try client.write(
                data,
                service: service,
                account: account,
                accessibility: .afterFirstUnlockThisDeviceOnly
            )
        }
    }

    func load(apiKeyFingerprint: String) async throws -> StoredSession? {
        let data: Data?
        do {
            data = try withLock {
                try client.read(service: service, account: account)
            }
        } catch {
            clearUnreadableRecord()
            return nil
        }

        guard let data else { return nil }

        do {
            let session = try JSONDecoder().decode(StoredSession.self, from: data)
            try validate(session)
            guard session.apiKeyFingerprint == apiKeyFingerprint else {
                return nil
            }
            return session
        } catch {
            clearUnreadableRecord()
            return nil
        }
    }

    func clear() async throws {
        try withLock {
            try client.delete(service: service, account: account)
        }
    }

    private func validate(_ session: StoredSession) throws {
        guard !session.appUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !session.apiKeyFingerprint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw SessionStoreError.invalidRecord
        }
    }

    private func clearUnreadableRecord() {
        logger.error("session_store_unreadable: clearing persisted session")
        try? withLock {
            try client.delete(service: service, account: account)
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

/// Security.framework implementation used in production.
private struct SecurityKeychainRecordClient: KeychainRecordClient {
    func read(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as AnyHashable] = true as NSNumber
        query[kSecMatchLimit as AnyHashable] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as NSDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw SessionStoreError.invalidRecord
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw SessionStoreError.keychainStatus(status)
        }
    }

    func write(
        _ data: Data,
        service: String,
        account: String,
        accessibility: KeychainItemAccessibility
    ) throws {
        let query = baseQuery(service: service, account: account)
        var attributes: [AnyHashable: Any] = [
            kSecValueData as AnyHashable: data,
            kSecAttrAccessible as AnyHashable: accessibilityValue(accessibility),
        ]

        var status = SecItemUpdate(query as NSDictionary, attributes as NSDictionary)
        if status == errSecItemNotFound {
            attributes.merge(query) { current, _ in current }
            status = SecItemAdd(attributes as NSDictionary, nil)
        }

        guard status == errSecSuccess else {
            throw SessionStoreError.keychainStatus(status)
        }
    }

    func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as NSDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SessionStoreError.keychainStatus(status)
        }
    }

    private func baseQuery(service: String, account: String) -> [AnyHashable: Any] {
        [
            kSecClass as AnyHashable: kSecClassGenericPassword,
            kSecAttrService as AnyHashable: service as NSString,
            kSecAttrAccount as AnyHashable: account as NSString,
            // Do not opt this item into iCloud Keychain synchronization.
            kSecAttrSynchronizable as AnyHashable: false as NSNumber,
        ]
    }

    private func accessibilityValue(_ accessibility: KeychainItemAccessibility) -> Any {
        switch accessibility {
        case .afterFirstUnlockThisDeviceOnly:
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
    }
}
