import Foundation

/// Fixed-host URLSession adapter for the EzyRevenue backend.
@available(macOS 12.0, iOS 15.0, *)
internal final class URLSessionEzyRevenueBackend: EzyRevenueBackend, @unchecked Sendable {
    static let productionBaseURL = URL(string: "https://api-ezyrevenue.doctors-finder.com")!

    private let apiKey: String
    private let baseURL: URL
    private let urlSession: URLSession
    private let ownsSession: Bool
    private let metadataProvider: @Sendable () async -> RequestMetadata
    private let logger: EzyRevenueLogger

    /// The finite timeout applied to SDK-created URLSession requests.
    let requestTimeout: TimeInterval

    init(
        apiKey: String,
        baseURL: URL = URLSessionEzyRevenueBackend.productionBaseURL,
        urlSession: URLSession? = nil,
        requestTimeout: TimeInterval = 15,
        metadataProvider: @escaping @Sendable () async -> RequestMetadata = {
            await MetadataProvider.current()
        },
        logger: EzyRevenueLogger = EzyRevenueLogger(level: .none)
    ) {
        precondition(!apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        precondition(requestTimeout > 0)
        precondition(baseURL.scheme != nil && baseURL.host != nil)

        self.apiKey = apiKey
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
        self.metadataProvider = metadataProvider
        self.logger = logger

        if let urlSession {
            self.urlSession = urlSession
            self.ownsSession = false
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = requestTimeout
            configuration.timeoutIntervalForResource = requestTimeout
            configuration.waitsForConnectivity = false
            self.urlSession = URLSession(configuration: configuration)
            self.ownsSession = true
        }
    }

    deinit {
        if ownsSession {
            urlSession.invalidateAndCancel()
        }
    }

    func login(appUserID: String) async throws -> BackendResult {
        let body = try encode(LoginRequestBody(appUserID: appUserID))
        let request = try await makeRequest(
            path: ["v1", "auth", "login"],
            method: "POST",
            body: body
        )
        return try await execute(request, acceptedStatusCodes: [200, 201])
    }

    func logout(appUserID: String) async throws -> BackendResult {
        let body = try encode(LoginRequestBody(appUserID: appUserID))
        let request = try await makeRequest(
            path: ["v1", "auth", "logout"],
            method: "POST",
            body: body
        )
        return try await execute(request, acceptedStatusCodes: [200, 201])
    }

    func postReceipt(_ receipt: ReceiptRequest) async throws -> BackendResult {
        let body = try encode(ReceiptRequestBody(receipt: receipt))
        let request = try await makeRequest(
            path: ["v1", "receipts"],
            method: "POST",
            body: body
        )
        return try await execute(request, acceptedStatusCodes: [200, 201])
    }

    func fetchOfferings(
        appUserID: String,
        countryCode: String?,
        accessToken: String?
    ) async throws -> BackendResult {
        let queryItems = countryCode?.isEmpty == false
            ? [URLQueryItem(name: "country", value: countryCode)]
            : []
        let request = try await makeRequest(
            path: ["v1", "subscribers", appUserID, "offerings"],
            queryItems: queryItems,
            accessToken: accessToken
        )
        return try await execute(request, acceptedStatusCodes: [200])
    }

    func fetchProducts() async throws -> BackendResult {
        let request = try await makeRequest(path: ["v1", "products"])
        return try await execute(request, acceptedStatusCodes: [200])
    }

    func fetchCustomerInfo(
        appUserID: String,
        accessToken: String?
    ) async throws -> BackendResult {
        let request = try await makeRequest(
            path: ["v1", "subscribers", appUserID],
            accessToken: accessToken
        )
        return try await execute(request, acceptedStatusCodes: [200])
    }

    private func makeRequest(
        path: [String],
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        accessToken: String? = nil
    ) async throws -> URLRequest {
        guard let url = makeURL(path: path, queryItems: queryItems) else {
            throw BackendRequestError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let accessToken = accessToken?.nonBlank {
            request.setValue(accessToken, forHTTPHeaderField: "X-App-Access-Token")
        }

        #if DEBUG
        logger.verbose("backend_authorization: Bearer \(apiKey)")
        if let accessToken = accessToken?.nonBlank {
            logger.verbose("backend_app_access_token: \(accessToken)")
        }
        #endif

        let metadata = await metadataProvider()
        if let value = metadata.sdkVersion.nonBlank {
            request.setValue(value, forHTTPHeaderField: "X-SDK-Version")
        }
        if let value = metadata.appVersion {
            request.setValue(value, forHTTPHeaderField: "X-App-Version")
        }
        if let value = metadata.deviceLocale {
            request.setValue(value, forHTTPHeaderField: "X-Device-Locale")
        }
        if let value = metadata.platformVersion {
            request.setValue(value, forHTTPHeaderField: "X-Platform-Version")
        }
        if let value = metadata.userCountry {
            request.setValue(value, forHTTPHeaderField: "X-User-Country")
        }
        if let value = metadata.storefront {
            request.setValue(value, forHTTPHeaderField: "X-Storefront")
        }
        logger.debug(
            "backend_request: \(method) \(url.absoluteString)"
        )
        if let body,
           let bodyText = String(data: body, encoding: .utf8) {
            logger.verbose("backend_request_body: \(bodyText)")
        }
        return request
    }

    private func makeURL(
        path: [String],
        queryItems: [URLQueryItem]
    ) -> URL? {
        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "/?#%")
        let encodedPath = path.compactMap {
            $0.addingPercentEncoding(withAllowedCharacters: allowedCharacters)
        }
        guard encodedPath.count == path.count else { return nil }

        let base = baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString
        guard var components = URLComponents(
            string: base + "/" + encodedPath.joined(separator: "/")
        ) else {
            return nil
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    private func execute(
        _ request: URLRequest,
        acceptedStatusCodes: Set<Int>
    ) async throws -> BackendResult {
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                logger.error("backend_response_failed: response was not HTTP")
                return .failure(.network)
            }

            logger.debug("backend_response: status=\(response.statusCode)")
            if !data.isEmpty,
               let bodyText = String(data: data, encoding: .utf8) {
                logger.verbose("backend_response_body: \(bodyText)")
            }

            guard acceptedStatusCodes.contains(response.statusCode) else {
                logger.error("backend_response_rejected: status=\(response.statusCode)")
                return .failure(error(for: response.statusCode))
            }

            if !data.isEmpty,
               (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) == nil {
                return .failure(.invalidResponse)
            }
            return .success(statusCode: response.statusCode, body: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            logger.error("backend_request_failed: \(error.localizedDescription)")
            return .failure(.network)
        }
    }

    private func error(for statusCode: Int) -> EzyRevenueError {
        switch statusCode {
        case 401:
            return .authentication
        case 400..<500:
            return .backendRejected
        case 500...:
            return .network
        default:
            return .network
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private enum BackendRequestError: Error {
        case invalidURL
    }
}

private struct LoginRequestBody: Encodable {
    let appUserID: String

    enum CodingKeys: String, CodingKey {
        case appUserID = "appUserId"
    }
}

private struct ReceiptRequestBody: Encodable {
    let appUserID: String
    let store = "APP_STORE"
    let productIdentifier: String?
    let transactionID: String?
    let receiptData: String?
    let purchaseToken: String?
    let fetchToken: String?

    init(receipt: ReceiptRequest) {
        appUserID = receipt.appUserID
        productIdentifier = receipt.productIdentifier
        transactionID = receipt.transactionID
        receiptData = receipt.receiptData
        purchaseToken = receipt.purchaseToken
        fetchToken = receipt.fetchToken
    }

    enum CodingKeys: String, CodingKey {
        case appUserID = "appUserId"
        case store
        case productIdentifier
        case transactionID = "transactionId"
        case receiptData
        case purchaseToken
        case fetchToken
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appUserID, forKey: .appUserID)
        try container.encode(store, forKey: .store)
        try container.encodeIfPresent(productIdentifier, forKey: .productIdentifier)
        try container.encodeIfPresent(transactionID, forKey: .transactionID)
        try container.encodeIfPresent(receiptData, forKey: .receiptData)
        try container.encodeIfPresent(purchaseToken, forKey: .purchaseToken)
        try container.encodeIfPresent(fetchToken, forKey: .fetchToken)
    }
}

private extension String {
    var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
