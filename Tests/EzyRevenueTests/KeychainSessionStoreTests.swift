import XCTest
@testable import EzyRevenue

final class KeychainSessionStoreTests: XCTestCase {
    func testAPIKeyFingerprintIsStableAndDoesNotExposeTheAPIKey() {
        let fingerprint = APIKeyFingerprint.make("hello")

        XCTAssertEqual(
            fingerprint,
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
        XCTAssertFalse(fingerprint.contains("hello"))
    }

    func testSessionRoundTripsAsOneRecordWithRequiredAccessibility() async throws {
        let client = InMemoryKeychainClient()
        let store = KeychainSessionStore(
            service: "test.service",
            account: "session",
            client: client
        )
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let session = StoredSession(
            appUserID: "$RCAnonymousID:abc",
            apiKeyFingerprint: "fingerprint",
            accessToken: "access-token",
            createdAt: createdAt
        )

        try await store.save(session)
        let loaded = try await store.load(apiKeyFingerprint: "fingerprint")

        XCTAssertEqual(loaded, session)
        XCTAssertEqual(client.writeCount, 1)
        XCTAssertEqual(
            client.lastAccessibility,
            .afterFirstUnlockThisDeviceOnly
        )
    }

    func testIdentityOnlyRecordRoundTripsWithoutAppearingAuthenticated() async throws {
        let client = InMemoryKeychainClient()
        let store = KeychainSessionStore(client: client)
        let session = StoredSession(
            appUserID: "$RCAnonymousID:after-logout",
            apiKeyFingerprint: "fingerprint",
            accessToken: nil,
            isAuthenticated: false
        )

        try await store.save(session)
        let loaded = try await store.load(apiKeyFingerprint: "fingerprint")

        XCTAssertEqual(loaded, session)
        XCTAssertFalse(loaded?.isAuthenticated == true)
    }

    func testDifferentAPIKeyFingerprintDoesNotReuseOrDeleteTheRecord() async throws {
        let client = InMemoryKeychainClient()
        let store = KeychainSessionStore(client: client)
        try await store.save(
            StoredSession(
                appUserID: "user",
                apiKeyFingerprint: "project-a",
                accessToken: nil
            )
        )

        let loaded = try await store.load(apiKeyFingerprint: "project-b")

        XCTAssertNil(loaded)
        XCTAssertEqual(client.deleteCount, 0)
    }

    func testUnreadableRecordIsClearedAndTreatedAsMissing() async throws {
        let client = InMemoryKeychainClient()
        client.data = Data("not-json".utf8)
        let logCapture = MessageCapture()
        let store = KeychainSessionStore(
            client: client,
            logger: EzyRevenueLogger(
                level: .error,
                onLog: { message in logCapture.append(message) }
            )
        )

        let loaded = try await store.load(apiKeyFingerprint: "fingerprint")

        XCTAssertNil(loaded)
        XCTAssertNil(client.data)
        XCTAssertEqual(client.deleteCount, 1)
        XCTAssertEqual(logCapture.messages.count, 1)
    }

    func testInvalidSessionCannotBeSaved() async {
        let client = InMemoryKeychainClient()
        let store = KeychainSessionStore(client: client)
        let invalid = StoredSession(
            appUserID: " ",
            apiKeyFingerprint: "fingerprint",
            accessToken: nil
        )

        do {
            try await store.save(invalid)
            XCTFail("Invalid session should not be persisted")
        } catch let error as SessionStoreError {
            XCTAssertEqual(error, .invalidRecord)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(client.writeCount, 0)
    }

    func testClearRemovesThePersistedRecord() async throws {
        let client = InMemoryKeychainClient()
        let store = KeychainSessionStore(client: client)
        try await store.save(
            StoredSession(
                appUserID: "user",
                apiKeyFingerprint: "fingerprint",
                accessToken: nil
            )
        )

        try await store.clear()

        XCTAssertNil(client.data)
        XCTAssertEqual(client.deleteCount, 1)
        let loaded = try await store.load(apiKeyFingerprint: "fingerprint")
        XCTAssertNil(loaded)
    }
}

private final class InMemoryKeychainClient: KeychainRecordClient, @unchecked Sendable {
    private let lock = NSLock()
    private var storedData: Data?
    private var storedWriteCount = 0
    private var storedDeleteCount = 0
    private var storedAccessibility: KeychainItemAccessibility?

    var data: Data? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedData
        }
        set {
            lock.lock()
            storedData = newValue
            lock.unlock()
        }
    }

    var writeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedWriteCount
    }

    var deleteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedDeleteCount
    }

    var lastAccessibility: KeychainItemAccessibility? {
        lock.lock()
        defer { lock.unlock() }
        return storedAccessibility
    }

    func read(service: String, account: String) throws -> Data? {
        data
    }

    func write(
        _ data: Data,
        service: String,
        account: String,
        accessibility: KeychainItemAccessibility
    ) throws {
        lock.lock()
        storedData = data
        storedWriteCount += 1
        storedAccessibility = accessibility
        lock.unlock()
    }

    func delete(service: String, account: String) throws {
        lock.lock()
        storedData = nil
        storedDeleteCount += 1
        lock.unlock()
    }
}

private final class MessageCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedMessages: [String] = []

    var messages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedMessages
    }

    func append(_ message: String) {
        lock.lock()
        storedMessages.append(message)
        lock.unlock()
    }
}
