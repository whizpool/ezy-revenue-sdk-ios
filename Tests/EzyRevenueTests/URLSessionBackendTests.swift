import Foundation
import XCTest
@testable import EzyRevenue

@available(macOS 12.0, *)
final class URLSessionBackendTests: XCTestCase {
    func testLoginUsesTheFixedRouteBodyAndMetadataHeaders() async throws {
        let recorder = RequestRecorder()
        StubURLProtocol.handler = { request in
            recorder.record(request)
            return StubResponse(statusCode: 201, body: Data("{}".utf8))
        }
        defer { StubURLProtocol.handler = nil }
        let backend = makeBackend()

        let result = try await backend.login(appUserID: "user-42")

        guard case let .success(statusCode, body) = result else {
            return XCTFail("Expected a successful login response: \(result)")
        }
        XCTAssertEqual(statusCode, 201)
        XCTAssertEqual(body, Data("{}".utf8))
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/auth/login")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-api-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-SDK-Version"), "1.0.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-App-Version"), "2.1.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Device-Locale"), "en-US")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Platform-Version"), "iOS 17.5")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-User-Country"), "GB")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Storefront"), "US")

        let bodyObject = try XCTUnwrap(jsonObject(for: request))
        XCTAssertEqual(bodyObject["appUserId"] as? String, "user-42")
    }

    func testLogoutUsesTheAuthLogoutRouteAndJSONBody() async throws {
        let recorder = RequestRecorder()
        StubURLProtocol.handler = { request in
            recorder.record(request)
            return StubResponse(statusCode: 200, body: Data("{}".utf8))
        }
        defer { StubURLProtocol.handler = nil }

        _ = try await makeBackend().logout(appUserID: "user-42")

        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/auth/logout")
        XCTAssertEqual(
            try XCTUnwrap(jsonObject(for: request))["appUserId"] as? String,
            "user-42"
        )
    }

    func testOfferingsSafelyEncodesReservedUserIDAndOptionalAccessToken() async throws {
        let recorder = RequestRecorder()
        StubURLProtocol.handler = { request in
            recorder.record(request)
            return StubResponse(statusCode: 200, body: Data("{}".utf8))
        }
        defer { StubURLProtocol.handler = nil }
        let backend = makeBackend()

        _ = try await backend.fetchOfferings(
            appUserID: "user /?%é",
            countryCode: "US",
            accessToken: "session-token"
        )

        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.percentEncodedPath,
            "/v1/subscribers/user%20%2F%3F%25%C3%A9/offerings"
        )
        XCTAssertEqual(request.url?.query, "country=US")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-App-Access-Token"),
            "session-token"
        )
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
    }

    func testCustomerInfoUsesSubscriberRouteAndOptionalAccessToken() async throws {
        let recorder = RequestRecorder()
        StubURLProtocol.handler = { request in
            recorder.record(request)
            return StubResponse(statusCode: 200, body: Data("{}".utf8))
        }
        defer { StubURLProtocol.handler = nil }

        _ = try await makeBackend().fetchCustomerInfo(
            appUserID: "user/42",
            accessToken: "session-token"
        )

        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.path, "/v1/subscribers/user/42")
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.percentEncodedPath,
            "/v1/subscribers/user%2F42"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-App-Access-Token"), "session-token")
    }

    func testProductsUsesTheFixedCatalogRouteAndGETSemantics() async throws {
        let recorder = RequestRecorder()
        StubURLProtocol.handler = { request in
            recorder.record(request)
            return StubResponse(statusCode: 200, body: Data("[]".utf8))
        }
        defer { StubURLProtocol.handler = nil }
        let backend = makeBackend()

        let result = try await backend.fetchProducts()

        guard case .success = result else {
            return XCTFail("Expected products to succeed: \(result)")
        }
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/v1/products")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
    }

    func testReceiptBodyUsesAPPSTOREAndOmitsUnavailableOptionalFields() async throws {
        let recorder = RequestRecorder()
        StubURLProtocol.handler = { request in
            recorder.record(request)
            return StubResponse(statusCode: 200, body: Data("{}".utf8))
        }
        defer { StubURLProtocol.handler = nil }
        let backend = makeBackend()

        _ = try await backend.postReceipt(
            ReceiptRequest(
                appUserID: "user-42",
                productIdentifier: "com.example.premium",
                fetchToken: "verified-jws"
            )
        )

        let request = try XCTUnwrap(recorder.request)
        let bodyObject = try XCTUnwrap(jsonObject(for: request))
        XCTAssertEqual(bodyObject["appUserId"] as? String, "user-42")
        XCTAssertEqual(bodyObject["store"] as? String, "APP_STORE")
        XCTAssertEqual(bodyObject["productIdentifier"] as? String, "com.example.premium")
        XCTAssertEqual(bodyObject["fetchToken"] as? String, "verified-jws")
        XCTAssertNil(bodyObject["transactionId"])
        XCTAssertNil(bodyObject["receiptData"])
        XCTAssertNil(bodyObject["purchaseToken"])
    }

    func testStatusCodesMapToStableBackendErrors() async throws {
        let cases: [(Int, EzyRevenueError)] = [
            (400, .backendRejected),
            (401, .authentication),
            (500, .network),
        ]

        for (statusCode, expectedError) in cases {
            StubURLProtocol.handler = { _ in
                StubResponse(statusCode: statusCode, body: Data("{}".utf8))
            }
            let result = try await makeBackend().fetchProducts()
            XCTAssertEqual(result, .failure(expectedError))
        }
        StubURLProtocol.handler = nil
    }

    func testMalformedSuccessfulJSONMapsToInvalidResponse() async throws {
        StubURLProtocol.handler = { _ in
            StubResponse(statusCode: 200, body: Data("not-json".utf8))
        }
        defer { StubURLProtocol.handler = nil }

        let result = try await makeBackend().fetchProducts()

        XCTAssertEqual(result, .failure(.invalidResponse))
    }

    func testAdapterUsesFiniteRequestTimeout() {
        XCTAssertEqual(makeBackend(requestTimeout: 3).requestTimeout, 3)
    }

    func testCancellationPropagatesInsteadOfBecomingANetworkFailure() async throws {
        let startSignal = RequestStartSignal()
        StubURLProtocol.startSignal = startSignal
        StubURLProtocol.handler = { _ in
            StubResponse(statusCode: 200, body: Data("{}".utf8))
        }
        defer {
            StubURLProtocol.startSignal = nil
            StubURLProtocol.handler = nil
        }

        let backend = makeBackend()
        let task = Task {
            try await backend.fetchProducts()
        }
        await startSignal.waitUntilStarted()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelled backend request should not return a result")
        } catch is CancellationError {
            // Expected.
        } catch let error as URLError where error.code == .cancelled {
            // Also accepted for URLSession's cancellation representation.
        }
    }

    private func makeBackend(requestTimeout: TimeInterval = 30) -> URLSessionEzyRevenueBackend {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        let metadata = RequestMetadata(
            sdkVersion: "1.0.0",
            appVersion: "2.1.0",
            deviceLocale: "en-US",
            platformVersion: "iOS 17.5",
            userCountry: "GB",
            storefront: "US"
        )
        return URLSessionEzyRevenueBackend(
            apiKey: "test-api-key",
            baseURL: URL(string: "https://api.test")!,
            urlSession: urlSession,
            requestTimeout: requestTimeout,
            metadataProvider: { metadata }
        )
    }

    private func jsonObject(for request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private struct StubResponse: Sendable {
    let statusCode: Int
    let body: Data
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequest: URLRequest?

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequest
    }

    func record(_ request: URLRequest) {
        lock.lock()
        recordedRequest = request
        lock.unlock()
    }
}

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> StubResponse)?
    nonisolated(unsafe) static var startSignal: RequestStartSignal?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        if let startSignal = Self.startSignal {
            Task { await startSignal.markStarted() }
            return
        }

        var requestForHandler = request
        if requestForHandler.httpBody == nil,
           let bodyStream = requestForHandler.httpBodyStream {
            bodyStream.open()
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while bodyStream.hasBytesAvailable {
                let count = bodyStream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            bodyStream.close()
            requestForHandler.httpBody = body
        }
        let responseData = handler(requestForHandler)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: responseData.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseData.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private actor RequestStartSignal {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func markStarted() {
        started = true
        continuation?.resume()
        continuation = nil
    }
}
