import OSLog

/// Internal runtime logger. Filtering happens before either OSLog or the host
/// callback, so `.none` is silent for every severity.
internal final class EzyRevenueLogger: @unchecked Sendable {
    private let configuredLevel: EzyRevenueLogLevel
    private let onLog: (@Sendable (String) -> Void)?
    private let testSink: (@Sendable (EzyRevenueLogLevel, String) -> Void)?
    private let osLog: OSLog

    init(
        level: EzyRevenueLogLevel,
        onLog: (@Sendable (String) -> Void)? = nil,
        testSink: (@Sendable (EzyRevenueLogLevel, String) -> Void)? = nil
    ) {
        self.configuredLevel = level
        self.onLog = onLog
        self.testSink = testSink
        self.osLog = OSLog(
            subsystem: "com.whizpool.ezyrevenue",
            category: "sdk"
        )
    }

    var level: EzyRevenueLogLevel {
        configuredLevel
    }

    func log(_ level: EzyRevenueLogLevel, _ message: String) {
        guard shouldEmit(level) else { return }

        emitToOSLog(level, message)
        testSink?(level, message)
        onLog?(message)
    }

    func error(_ message: String) {
        log(.error, message)
    }

    func warning(_ message: String) {
        log(.warning, message)
    }

    func info(_ message: String) {
        log(.info, message)
    }

    func debug(_ message: String) {
        log(.debug, message)
    }

    func verbose(_ message: String) {
        log(.verbose, message)
    }

    private func shouldEmit(_ messageLevel: EzyRevenueLogLevel) -> Bool {
        guard configuredLevel != .none, messageLevel != .none else { return false }
        return severityRank(messageLevel) <= severityRank(configuredLevel)
    }

    private func severityRank(_ level: EzyRevenueLogLevel) -> Int {
        switch level {
        case .none:
            return Int.max
        case .error:
            return 0
        case .warning:
            return 1
        case .info:
            return 2
        case .debug:
            return 3
        case .verbose:
            return 4
        }
    }

    private func emitToOSLog(_ level: EzyRevenueLogLevel, _ message: String) {
        let osLogType: OSLogType
        switch level {
        case .none:
            return
        case .error:
            osLogType = .error
        case .warning:
            osLogType = .default
        case .info:
            osLogType = .info
        case .debug, .verbose:
            osLogType = .debug
        }
        os_log("%{public}@", log: osLog, type: osLogType, message)
    }
}
