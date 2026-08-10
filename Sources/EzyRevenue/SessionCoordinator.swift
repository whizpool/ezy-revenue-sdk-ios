import Foundation

/// Identity generation captured by asynchronous work.
internal struct SessionGeneration: Equatable, Sendable {
    let sequence: UInt64
    let appUserID: String
}

/// Coordinates initialization, identity transitions, session restoration, and
/// one-shot authenticated request reauthentication.
internal final class SessionCoordinator: @unchecked Sendable {
    let backend: any EzyRevenueBackend
    let sessionStore: any SessionStore

    private let operationGate = AsyncOperationGate()
    private let stateLock = NSLock()
    private var state = State()
    private var logger: EzyRevenueLogger

    init(
        backend: any EzyRevenueBackend,
        sessionStore: any SessionStore,
        logger: EzyRevenueLogger = EzyRevenueLogger(level: .none)
    ) {
        self.backend = backend
        self.sessionStore = sessionStore
        self.logger = logger
    }

    private(set) var appUserID: String? {
        get { readState { $0.appUserID } }
        set { mutateState { $0.appUserID = newValue } }
    }

    var generation: UInt64 {
        readState { $0.generation }
    }

    var accessToken: String? {
        readState { $0.accessToken }
    }

    var isInitialized: Bool {
        readState { $0.isInitialized }
    }

    /// Replaces the logger when a host reinitializes with a new policy.
    func updateLogger(_ logger: EzyRevenueLogger) {
        stateLock.lock()
        self.logger = logger
        stateLock.unlock()
    }

    /// Restores a matching session or performs one login. A missing custom
    /// user ID uses the persisted identity when available, otherwise a fresh
    /// `$RCAnonymousID:<uuid>` is generated.
    func initialize(
        apiKeyFingerprint: String,
        requestedAppUserID: String?
    ) async -> EzyRevenueResult<Void> {
        do {
            return try await operationGate.withLock { [self] in
                try await initializeLocked(
                    apiKeyFingerprint: apiKeyFingerprint,
                    requestedAppUserID: requestedAppUserID
                )
            }
        } catch is CancellationError {
            clearActiveState()
            logError("session_initialize_cancelled")
            return .failure(.network)
        } catch {
            clearActiveState()
            logError("session_initialize_failed")
            return .failure(.internalError("Session initialization failed"))
        }
    }

    /// Switches to a custom identity and performs a fresh backend login.
    func login(appUserID: String) async -> EzyRevenueResult<Void> {
        let normalizedAppUserID = appUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAppUserID.isEmpty else {
            return .failure(.invalidConfiguration("appUserID must not be blank"))
        }

        do {
            return try await operationGate.withLock { [self] in
                let current = readState { $0 }
                guard current.isInitialized,
                      let fingerprint = current.configuredAPIKeyFingerprint else {
                    return .failure(.notInitialized)
                }
                if current.appUserID == normalizedAppUserID {
                    return .success(())
                }

                clearActiveState()
                do {
                    try await sessionStore.clear()
                } catch {
                    logError("session_login_failed: session clear failed")
                    return .failure(.internalError("Session clear failed"))
                }
                return try await authenticate(
                    appUserID: normalizedAppUserID,
                    apiKeyFingerprint: fingerprint
                )
            }
        } catch is CancellationError {
            clearActiveState()
            logError("session_login_cancelled")
            return .failure(.network)
        } catch {
            clearActiveState()
            logError("session_login_failed")
            return .failure(.internalError("Session login failed"))
        }
    }

    /// Executes one authenticated operation and retries it once after an
    /// authentication failure. A second 401 from the retry is returned as-is.
    func executeAuthenticated(
        _ operation: @escaping @Sendable (String?) async throws -> BackendResult
    ) async -> BackendResult {
        let current = readState { $0 }
        guard current.isInitialized, let appUserID = current.appUserID else {
            return .failure(.notInitialized)
        }
        let capturedGeneration = SessionGeneration(
            sequence: current.generation,
            appUserID: appUserID
        )

        let firstResult: BackendResult
        do {
            firstResult = try await operation(current.accessToken)
        } catch is CancellationError {
            return .failure(.network)
        } catch {
            return .failure(.network)
        }
        guard isAuthenticationFailure(firstResult) else { return firstResult }

        do {
            return try await operationGate.withLock { [self] in
                let latest = readState { $0 }
                guard latest.isInitialized,
                      latest.appUserID == capturedGeneration.appUserID,
                      latest.configuredAPIKeyFingerprint != nil else {
                    return .failure(.notInitialized)
                }

                // Another request may already have reauthenticated this same
                // identity while this one was in flight. Reuse that session;
                // otherwise perform exactly one fresh login.
                if latest.generation != capturedGeneration.sequence,
                   latest.accessToken != current.accessToken {
                    do {
                        return try await operation(latest.accessToken)
                    } catch {
                        return .failure(.network)
                    }
                }

                guard let fingerprint = latest.configuredAPIKeyFingerprint else {
                    return .failure(.notInitialized)
                }
                clearActiveState()
                do {
                    try await sessionStore.clear()
                } catch {
                    logError("session_reauthentication_failed: session clear failed")
                    return .failure(.internalError("Session clear failed"))
                }
                let loginResult = try await authenticate(
                    appUserID: capturedGeneration.appUserID,
                    apiKeyFingerprint: fingerprint
                )
                if case let .failure(error) = loginResult {
                    return .failure(error)
                }
                do {
                    return try await operation(accessToken)
                } catch is CancellationError {
                    return .failure(.network)
                } catch {
                    return .failure(.network)
                }
            }
        } catch is CancellationError {
            return .failure(.network)
        } catch {
            return .failure(.internalError("Reauthentication failed"))
        }
    }

    /// Best-effort backend logout followed by local invalidation and cleanup.
    func logout() async -> EzyRevenueResult<Void> {
        do {
            return try await operationGate.withLock { [self] in
                let current = readState { $0 }
                if let appUserID = current.appUserID {
                    do {
                        let result = try await backend.logout(appUserID: appUserID)
                        if case let .failure(error) = result {
                            logWarning(
                                "session_logout_notification_failed: \(error.localizedDescription)"
                            )
                        }
                    } catch {
                        logWarning("session_logout_notification_failed")
                    }
                }

                do {
                    try await sessionStore.clear()
                } catch {
                    clearAllState()
                    logError("session_logout_failed: session clear failed")
                    return .failure(.internalError("Session clear failed"))
                }

                clearAllState()
                return .success(())
            }
        } catch is CancellationError {
            // Local cleanup remains best-effort even if a caller cancels the
            // backend notification.
            clearAllState()
            return .success(())
        } catch {
            clearAllState()
            return .failure(.internalError("Session logout failed"))
        }
    }

    /// Activates an identity for generation-bound coordinator tests and future
    /// catalog/purchase work.
    @discardableResult
    func activate(appUserID: String) -> SessionGeneration {
        mutateState { state in
            if state.appUserID != appUserID {
                state.generation &+= 1
                state.appUserID = appUserID
            }
            return SessionGeneration(sequence: state.generation, appUserID: appUserID)
        }
    }

    /// Invalidates all work associated with the current identity.
    func invalidate() {
        clearActiveState()
    }

    /// Captures the active identity for a new asynchronous operation.
    func captureGeneration() -> SessionGeneration? {
        readState { state in
            guard let appUserID = state.appUserID else { return nil }
            return SessionGeneration(sequence: state.generation, appUserID: appUserID)
        }
    }

    /// Returns true only while the captured identity is still active.
    func isCurrent(_ captured: SessionGeneration) -> Bool {
        readState { state in
            state.generation == captured.sequence && state.appUserID == captured.appUserID
        }
    }

    private func initializeLocked(
        apiKeyFingerprint: String,
        requestedAppUserID: String?
    ) async throws -> EzyRevenueResult<Void> {
        guard !apiKeyFingerprint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.invalidConfiguration("apiKey fingerprint must not be blank"))
        }
        let requestedAppUserID = requestedAppUserID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let requestedAppUserID, requestedAppUserID.isEmpty {
            return .failure(.invalidConfiguration("appUserID must not be blank"))
        }

        let current = readState { $0 }
        if current.isInitialized,
           current.configuredAPIKeyFingerprint == apiKeyFingerprint,
           requestedAppUserID == nil || requestedAppUserID == current.appUserID {
            logDebug("session_initialize_idempotent")
            return .success(())
        }

        clearActiveState()
        setConfiguredFingerprint(apiKeyFingerprint)

        let savedSession: StoredSession?
        do {
            savedSession = try await sessionStore.load(apiKeyFingerprint: apiKeyFingerprint)
        } catch {
            logWarning("session_restore_failed: logging in again")
            try? await sessionStore.clear()
            savedSession = nil
        }

        let effectiveAppUserID = requestedAppUserID
            ?? savedSession?.appUserID
            ?? AnonymousAppUserID.generate()

        if let savedSession,
           savedSession.apiKeyFingerprint == apiKeyFingerprint,
           savedSession.appUserID == effectiveAppUserID {
            activate(savedSession)
            logDebug("session_restored")
            return .success(())
        }

        return try await authenticate(
            appUserID: effectiveAppUserID,
            apiKeyFingerprint: apiKeyFingerprint
        )
    }

    private func authenticate(
        appUserID: String,
        apiKeyFingerprint: String
    ) async throws -> EzyRevenueResult<Void> {
        logDebug("session_login_started")

        let response: BackendResult
        do {
            response = try await backend.login(appUserID: appUserID)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            clearActiveState()
            logError("session_login_failed: network")
            return .failure(.network)
        }

        switch response {
        case let .failure(error):
            clearActiveState()
            logError("session_login_failed: \(error.localizedDescription)")
            return .failure(error)

        case let .success(_, body):
            guard case let .success(accessToken) = BackendMapper.mapLoginAccessToken(from: body) else {
                clearActiveState()
                logError("session_login_failed: invalid response")
                return .failure(.invalidResponse)
            }

            let session = StoredSession(
                appUserID: appUserID,
                apiKeyFingerprint: apiKeyFingerprint,
                accessToken: accessToken
            )
            do {
                try await sessionStore.save(session)
            } catch {
                clearActiveState()
                logError("session_login_failed: session save failed")
                return .failure(.internalError("Session save failed"))
            }

            activate(session)
            if accessToken == nil {
                logDebug("session_login_succeeded: tokenless session")
            } else {
                logDebug("session_login_succeeded")
            }
            return .success(())
        }
    }

    private func activate(_ session: StoredSession) {
        mutateState { state in
            if state.appUserID != session.appUserID ||
                state.configuredAPIKeyFingerprint != session.apiKeyFingerprint {
                state.generation &+= 1
            }
            state.appUserID = session.appUserID
            state.configuredAPIKeyFingerprint = session.apiKeyFingerprint
            state.accessToken = session.accessToken
            state.isInitialized = true
        }
    }

    private func clearActiveState() {
        mutateState { state in
            state.generation &+= 1
            state.appUserID = nil
            state.accessToken = nil
            state.isInitialized = false
        }
    }

    private func clearAllState() {
        mutateState { state in
            state.generation &+= 1
            state.appUserID = nil
            state.accessToken = nil
            state.configuredAPIKeyFingerprint = nil
            state.isInitialized = false
        }
    }

    private func setConfiguredFingerprint(_ fingerprint: String) {
        mutateState { $0.configuredAPIKeyFingerprint = fingerprint }
    }

    private func isAuthenticationFailure(_ result: BackendResult) -> Bool {
        guard case let .failure(error) = result else { return false }
        return error == .authentication
    }

    private func readState<Value>(_ body: (State) -> Value) -> Value {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body(state)
    }

    private func mutateState<Value>(_ body: (inout State) -> Value) -> Value {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body(&state)
    }

    private func logDebug(_ message: String) {
        loggerSnapshot().debug(message)
    }

    private func logWarning(_ message: String) {
        loggerSnapshot().warning(message)
    }

    private func logError(_ message: String) {
        loggerSnapshot().error(message)
    }

    private func loggerSnapshot() -> EzyRevenueLogger {
        stateLock.lock()
        defer { stateLock.unlock() }
        return logger
    }

    private struct State {
        var appUserID: String?
        var accessToken: String?
        var configuredAPIKeyFingerprint: String?
        var generation: UInt64 = 0
        var isInitialized = false
    }
}
