/// Identity generation captured by asynchronous work.
internal struct SessionGeneration: Equatable, Sendable {
    let sequence: UInt64
    let appUserID: String
}

/// Owns identity transitions and the generation used to reject stale work.
internal final class SessionCoordinator {
    let backend: any EzyRevenueBackend
    let sessionStore: any SessionStore

    private(set) var appUserID: String?
    private(set) var generation: UInt64 = 0

    init(
        backend: any EzyRevenueBackend,
        sessionStore: any SessionStore
    ) {
        self.backend = backend
        self.sessionStore = sessionStore
    }

    /// Activates an identity and returns a token for work started for that user.
    /// Reusing the same active identity does not invalidate its generation.
    @discardableResult
    func activate(appUserID: String) -> SessionGeneration {
        if self.appUserID != appUserID {
            generation &+= 1
            self.appUserID = appUserID
        }
        return SessionGeneration(sequence: generation, appUserID: appUserID)
    }

    /// Invalidates all work associated with the current identity.
    func invalidate() {
        generation &+= 1
        appUserID = nil
    }

    /// Captures the active identity for a new asynchronous operation.
    func captureGeneration() -> SessionGeneration? {
        guard let appUserID else { return nil }
        return SessionGeneration(sequence: generation, appUserID: appUserID)
    }

    /// Returns true only while the captured identity is still active.
    func isCurrent(_ captured: SessionGeneration) -> Bool {
        generation == captured.sequence && appUserID == captured.appUserID
    }
}
