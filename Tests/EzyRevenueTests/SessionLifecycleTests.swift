import XCTest
@testable import EzyRevenue

final class SessionLifecycleTests: XCTestCase {
    func testMatchingStoredSessionRestoresWithoutBackendLogin() async {
        let backend = TestBackend()
        let store = TestSessionStore()
        store.session = StoredSession(
            appUserID: "$RCAnonymousID:saved",
            apiKeyFingerprint: "project",
            accessToken: "saved-token"
        )
        let session = SessionCoordinator(backend: backend, sessionStore: store)

        let result = await session.initialize(
            apiKeyFingerprint: "project",
            requestedAppUserID: nil
        )

        assertSuccess(result)
        XCTAssertEqual(session.appUserID, "$RCAnonymousID:saved")
        XCTAssertEqual(session.accessToken, "saved-token")
        XCTAssertTrue(backend.loginIDs.isEmpty)
    }

    func testInitializationIsIdempotentAndLoginSwitchesIdentity() async {
        let backend = TestBackend()
        let store = TestSessionStore()
        let session = SessionCoordinator(backend: backend, sessionStore: store)

        assertSuccess(await session.initialize(
            apiKeyFingerprint: "project",
            requestedAppUserID: "user-a"
        ))
        assertSuccess(await session.initialize(
            apiKeyFingerprint: "project",
            requestedAppUserID: "user-a"
        ))
        assertSuccess(await session.login(appUserID: "user-b"))

        XCTAssertEqual(backend.loginIDs, ["user-a", "user-b"])
        XCTAssertEqual(session.appUserID, "user-b")
    }

    func testLogoutIsBestEffortAndInvalidatesGeneration() async {
        let backend = TestBackend()
        backend.logoutResult = .failure(.network)
        let store = TestSessionStore()
        let session = SessionCoordinator(backend: backend, sessionStore: store)
        assertSuccess(await session.initialize(
            apiKeyFingerprint: "project",
            requestedAppUserID: "user-a"
        ))
        let generation = try! XCTUnwrap(session.captureGeneration())

        assertSuccess(await session.logout())

        XCTAssertFalse(session.isInitialized)
        XCTAssertFalse(session.isCurrent(generation))
        XCTAssertTrue(store.session?.appUserID.hasPrefix(AnonymousAppUserID.prefix) == true)
        XCTAssertFalse(store.session?.isAuthenticated == true)
    }

    func testLogoutIdentityIsReusedAndReloggedOnNextInitialization() async {
        let backend = TestBackend()
        let store = TestSessionStore()
        let session = SessionCoordinator(backend: backend, sessionStore: store)
        assertSuccess(await session.initialize(
            apiKeyFingerprint: "project",
            requestedAppUserID: "user-a"
        ))
        assertSuccess(await session.logout())
        let anonymousID = try! XCTUnwrap(store.session?.appUserID)

        assertSuccess(await session.initialize(
            apiKeyFingerprint: "project",
            requestedAppUserID: nil
        ))

        XCTAssertEqual(session.appUserID, anonymousID)
        XCTAssertEqual(backend.loginIDs, ["user-a", anonymousID])
        XCTAssertTrue(store.session?.isAuthenticated == true)
    }

    func testAuthenticatedRequestRetriesExactlyOnceAfterAuthenticationFailure() async {
        let backend = TestBackend()
        backend.loginResults = [
            .success(statusCode: 200, body: makeLoginBody()),
            .success(statusCode: 200, body: makeLoginBody(token: "new-token")),
        ]
        let session = SessionCoordinator(backend: backend, sessionStore: TestSessionStore())
        assertSuccess(await session.initialize(
            apiKeyFingerprint: "project",
            requestedAppUserID: "user-a"
        ))
        let calls = ResponseSequence([
            .failure(.authentication),
            .success(statusCode: 200, body: Data("{}".utf8)),
        ])

        let result = await session.executeAuthenticated { token in
            calls.next(token)
        }

        XCTAssertEqual(result, .success(statusCode: 200, body: Data("{}".utf8)))
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(backend.loginIDs, ["user-a", "user-a"])
    }

    private func assertSuccess(
        _ result: EzyRevenueResult<Void>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success = result else {
            XCTFail("Expected success, got \(result)", file: file, line: line)
            return
        }
    }
}

private final class ResponseSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [BackendResult]
    private var invocationCount = 0

    init(_ values: [BackendResult]) {
        self.values = values
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return invocationCount
    }

    func next(_ token: String?) -> BackendResult {
        lock.lock()
        defer { lock.unlock() }
        _ = token
        invocationCount += 1
        return values.removeFirst()
    }
}
