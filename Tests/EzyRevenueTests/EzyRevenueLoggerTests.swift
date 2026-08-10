import XCTest
@testable import EzyRevenue

final class EzyRevenueLoggerTests: XCTestCase {
    func testEachConfiguredLevelFiltersBySeverity() {
        let levels: [EzyRevenueLogLevel] = [.error, .warning, .info, .debug, .verbose]
        let messages: [EzyRevenueLogLevel] = [.error, .warning, .info, .debug, .verbose]

        for configuredLevel in levels {
            let capture = LogCapture()
            let logger = EzyRevenueLogger(
                level: configuredLevel,
                testSink: { level, message in
                    capture.append(level: level, message: message)
                }
            )

            for messageLevel in messages {
                logger.log(messageLevel, "message-\(messageLevel.rawValue)")
            }

            XCTAssertEqual(
                capture.events.map(\.level),
                messages.filter { severityRank($0) <= severityRank(configuredLevel) },
                "Unexpected filtering for \(configuredLevel)"
            )
        }
    }

    func testNoneSuppressesOSLogSinkAndHostCallback() {
        let sinkCapture = LogCapture()
        let callbackCapture = MessageCapture()
        let logger = EzyRevenueLogger(
            level: .none,
            onLog: { message in callbackCapture.append(message) },
            testSink: { level, message in
                sinkCapture.append(level: level, message: message)
            }
        )

        for level in EzyRevenueLogLevel.allCases {
            logger.log(level, "message-\(level.rawValue)")
        }

        XCTAssertTrue(sinkCapture.events.isEmpty)
        XCTAssertTrue(callbackCapture.messages.isEmpty)
    }

    func testEnabledDiagnosticsAreVerbatimInSinkAndCallback() {
        let sinkCapture = LogCapture()
        let callbackCapture = MessageCapture()
        let message = "apiKey=secret-key token=purchase-token url=/v1/subscribers/user"
        let logger = EzyRevenueLogger(
            level: .verbose,
            onLog: { value in callbackCapture.append(value) },
            testSink: { level, value in
                sinkCapture.append(level: level, message: value)
            }
        )

        logger.verbose(message)

        XCTAssertEqual(sinkCapture.events, [LogEvent(level: .verbose, message: message)])
        XCTAssertEqual(callbackCapture.messages, [message])
    }

    func testCallsBeforeInitializationAreSilent() async {
        let sdk = EzyRevenue()

        let result = await sdk.getProducts()

        XCTAssertEqual(result, .failure(.notInitialized))
        // The facade starts with a `.none` logger and has no callback before initialization.
    }

    func testInitializationFailureRespectsSelectedLevel() async {
        let noneCapture = MessageCapture()
        let noneSDK = EzyRevenue()
        _ = await noneSDK.initialize(
            configuration: EzyRevenueConfiguration(
                apiKey: "",
                logLevel: .none,
                onLog: { message in noneCapture.append(message) }
            )
        )
        XCTAssertTrue(noneCapture.messages.isEmpty)

        let errorCapture = MessageCapture()
        let errorSDK = EzyRevenue()
        _ = await errorSDK.initialize(
            configuration: EzyRevenueConfiguration(
                apiKey: "",
                logLevel: .error,
                onLog: { message in errorCapture.append(message) }
            )
        )
        XCTAssertEqual(errorCapture.messages.count, 1)
    }

    func testReinitializationReplacesTheRuntimeLoggingLevel() async {
        let firstCapture = MessageCapture()
        let secondCapture = MessageCapture()
        let sdk = EzyRevenue()

        _ = await sdk.initialize(
            configuration: EzyRevenueConfiguration(
                apiKey: "",
                logLevel: .none,
                onLog: { message in firstCapture.append(message) }
            )
        )
        _ = await sdk.initialize(
            configuration: EzyRevenueConfiguration(
                apiKey: "",
                logLevel: .error,
                onLog: { message in secondCapture.append(message) }
            )
        )
        _ = await sdk.getProducts()

        XCTAssertTrue(firstCapture.messages.isEmpty)
        XCTAssertEqual(secondCapture.messages.count, 2)
    }

    private func severityRank(_ level: EzyRevenueLogLevel) -> Int {
        switch level {
        case .none: Int.max
        case .error: 0
        case .warning: 1
        case .info: 2
        case .debug: 3
        case .verbose: 4
        }
    }
}

private struct LogEvent: Equatable {
    let level: EzyRevenueLogLevel
    let message: String
}

private final class LogCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [LogEvent] = []

    var events: [LogEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }

    func append(level: EzyRevenueLogLevel, message: String) {
        lock.lock()
        storedEvents.append(LogEvent(level: level, message: message))
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
