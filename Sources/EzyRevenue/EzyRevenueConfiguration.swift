/// Controls diagnostic output emitted by EzyRevenue.
public enum EzyRevenueLogLevel: String, CaseIterable, Equatable, Sendable {
    /// Disables all EzyRevenue OSLog output and host callback output.
    case none

    /// Emits errors only.
    case error

    /// Emits warnings and errors.
    case warning

    /// Emits informational messages, warnings, and errors.
    case info

    /// Emits debug messages and messages at higher severity.
    case debug

    /// Emits all available diagnostics.
    case verbose
}

/// Configuration selected once when the SDK is initialized.
public struct EzyRevenueConfiguration: Sendable {
    /// EzyRevenue API key. It is validated when ``EzyRevenue/initialize(configuration:)`` runs.
    public let apiKey: String

    /// Host application identity, or `nil` to use the SDK-managed anonymous identity.
    public let appUserID: String?

    /// Required logging choice for this SDK runtime.
    public let logLevel: EzyRevenueLogLevel

    /// Optional country associated with the host user.
    public let userCountryCode: String?

    /// Optional host callback for messages permitted by ``logLevel``.
    public let onLog: (@Sendable (String) -> Void)?

    /// Creates an SDK configuration.
    ///
    /// `logLevel` intentionally has no default. The host must make the
    /// logging decision once during initialization, including choosing `.none`.
    public init(
        apiKey: String,
        appUserID: String? = nil,
        logLevel: EzyRevenueLogLevel,
        userCountryCode: String? = nil,
        onLog: (@Sendable (String) -> Void)? = nil
    ) {
        self.apiKey = apiKey
        self.appUserID = appUserID
        self.logLevel = logLevel
        self.userCountryCode = userCountryCode
        self.onLog = onLog
    }
}
