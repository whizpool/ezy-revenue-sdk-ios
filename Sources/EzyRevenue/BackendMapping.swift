import Foundation

/// Offering data plus the backend-selected current offering.
internal struct OfferingSnapshot: Equatable, Sendable {
    let offerings: [Offering]
    let currentOffering: Offering?
}

/// Internal transport-to-domain mapper. DTOs intentionally remain private to
/// the SDK target and unknown JSON fields are ignored by Decodable.
internal enum BackendMapper {
    static func mapLoginAccessToken(from data: Data) -> EzyRevenueResult<String?> {
        do {
            let response = try decode(LoginResponseDTO.self, from: data)
            return .success(response.appAccessToken?.nonBlank)
        } catch {
            return .failure(.invalidResponse)
        }
    }

    static func mapOfferings(from data: Data) -> EzyRevenueResult<OfferingSnapshot> {
        do {
            let response = try decode(OfferingsResponseDTO.self, from: data)
            let offerings = try response.offerings.map(mapOffering)
            let currentOffering = selectCurrentOffering(
                from: offerings,
                explicitIdentifier: response.currentOfferingID
            )
            return .success(
                OfferingSnapshot(
                    offerings: offerings,
                    currentOffering: currentOffering
                )
            )
        } catch is MappingFailure {
            return .failure(.invalidResponse)
        } catch {
            return .failure(.invalidResponse)
        }
    }

    static func mapProducts(from data: Data) -> EzyRevenueResult<[Product]> {
        do {
            let response = try decode(ProductsResponseDTO.self, from: data)
            guard response.success else { throw MappingFailure.invalid }
            return .success(try response.data.map(mapProduct))
        } catch is MappingFailure {
            return .failure(.invalidResponse)
        } catch {
            return .failure(.invalidResponse)
        }
    }

    static func mapCustomerInfo(from data: Data) -> EzyRevenueResult<CustomerInfo> {
        do {
            let response = try decode(CustomerResponseDTO.self, from: data)
            guard let requestDate = try parseDate(response.requestDate) else {
                throw MappingFailure.invalid
            }
            var entitlements: [String: EntitlementInfo] = [:]
            for (identifier, dto) in response.subscriber.entitlements {
                entitlements[identifier] = try mapEntitlement(
                    identifier: identifier,
                    dto: dto,
                    requestDate: requestDate
                )
            }
            var subscriptions: [String: SubscriptionInfo] = [:]
            for (productIdentifier, dto) in response.subscriber.subscriptions {
                subscriptions[productIdentifier] = try mapSubscription(
                    productIdentifier: productIdentifier,
                    dto: dto,
                    requestDate: requestDate
                )
            }
            return .success(
                CustomerInfo(
                    requestDate: requestDate,
                    originalAppUserID: response.subscriber.originalAppUserID,
                    entitlements: entitlements,
                    subscriptions: subscriptions
                )
            )
        } catch is MappingFailure {
            return .failure(.invalidResponse)
        } catch {
            return .failure(.invalidResponse)
        }
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data
    ) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    private static func mapOffering(_ dto: OfferingDTO) throws -> Offering {
        guard !dto.identifier.isBlank else { throw MappingFailure.invalid }
        return Offering(
            identifier: dto.identifier,
            description: dto.description,
            isDefault: dto.isDefault ?? false,
            packages: try dto.packages.map(mapPackage)
        )
    }

    private static func mapPackage(_ dto: OfferingPackageDTO) throws -> OfferingPackage {
        guard !dto.identifier.isBlank else { throw MappingFailure.invalid }
        return OfferingPackage(
            identifier: dto.identifier,
            platformProductIdentifier: dto.platformProductIdentifier?.nonBlank,
            products: try dto.products.map(mapProduct)
        )
    }

    private static func mapProduct(_ dto: ProductDTO) throws -> Product {
        guard !dto.identifier.isBlank, !dto.displayName.isBlank else {
            throw MappingFailure.invalid
        }

        let type = try mapProductType(dto.type)
        let status = mapProductStatus(dto.storeStatus)
        let isActive = dto.isActive ?? status.isActiveFallback
        let price = try dto.price.map(mapPrice)
        let introductoryPrice = try dto.introductoryPrice.map(mapPrice)

        return Product(
            productID: dto.productID?.nonBlank,
            identifier: dto.identifier,
            displayName: dto.displayName,
            type: type,
            storeStatus: status,
            productGroup: dto.productGroup?.nonBlank,
            isActive: isActive,
            price: price,
            introductoryPrice: introductoryPrice,
            isAvailableInAppStore: false
        )
    }

    private static func mapPrice(_ dto: PriceDTO) throws -> Price {
        guard dto.amount >= 0, !dto.currency.isBlank else {
            throw MappingFailure.invalid
        }
        return Price(
            amountMicros: dto.amount,
            currencyCode: dto.currency,
            displayPrice: nil
        )
    }

    private static func mapProductType(_ value: String) throws -> ProductType {
        switch value.normalizedToken {
        case "subscription":
            return .subscription
        case "non_consumable", "nonconsumable":
            return .nonConsumable
        default:
            throw MappingFailure.invalid
        }
    }

    private static func mapProductStatus(_ value: String) -> ProductStatus {
        switch value.normalizedToken {
        case "active":
            return .active
        case "approved":
            return .approved
        case "inactive":
            return .inactive
        default:
            return .unknown(value)
        }
    }

    private static func selectCurrentOffering(
        from offerings: [Offering],
        explicitIdentifier: String?
    ) -> Offering? {
        if let explicitIdentifier = explicitIdentifier?.nonBlank {
            let matches = offerings.filter { $0.identifier == explicitIdentifier }
            return matches.count == 1 ? matches[0] : nil
        }

        let defaults = offerings.filter(\.isDefault)
        return defaults.count == 1 ? defaults[0] : nil
    }

    private static func mapEntitlement(
        identifier: String,
        dto: EntitlementDTO,
        requestDate: Date
    ) throws -> EntitlementInfo {
        let expirationDate = try parseDate(dto.expirationDate)
        let purchaseDate = try parseDate(dto.purchaseDate)
        let isActive = dto.isActive ?? isActive(expirationDate: expirationDate, at: requestDate)
        return EntitlementInfo(
            identifier: identifier,
            isActive: isActive,
            willRenew: dto.willRenew ?? false,
            expirationDate: expirationDate,
            purchaseDate: purchaseDate,
            productIdentifier: dto.productIdentifier?.nonBlank
        )
    }

    private static func mapSubscription(
        productIdentifier: String,
        dto: SubscriptionDTO,
        requestDate: Date
    ) throws -> SubscriptionInfo {
        let expirationDate = try parseDate(dto.expirationDate)
        let purchaseDate = try parseDate(dto.purchaseDate)
        let unsubscribeDetectedAt = try parseDate(dto.unsubscribeDetectedAt)
        let isActive = dto.isActive ?? isActive(expirationDate: expirationDate, at: requestDate)
        let willRenew = dto.willRenew ?? (isActive && unsubscribeDetectedAt == nil)
        return SubscriptionInfo(
            productIdentifier: productIdentifier,
            expirationDate: expirationDate,
            purchaseDate: purchaseDate,
            periodType: dto.periodType?.nonBlank,
            unsubscribeDetectedAt: unsubscribeDetectedAt,
            isActive: isActive,
            willRenew: willRenew
        )
    }

    private static func parseDate(_ value: String?) throws -> Date? {
        guard let value else { return nil }
        guard !value.isEmpty else { throw MappingFailure.invalid }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw MappingFailure.invalid
        }
        return date
    }

    private static func isActive(expirationDate: Date?, at requestDate: Date) -> Bool {
        guard let expirationDate else { return true }
        return expirationDate > requestDate
    }

    private enum MappingFailure: Error {
        case invalid
    }
}

private struct LoginResponseDTO: Decodable {
    let appAccessToken: String?

    enum CodingKeys: String, CodingKey {
        case appAccessToken = "appAccessToken"
    }
}

private struct OfferingsResponseDTO: Decodable {
    let currentOfferingID: String?
    let offerings: [OfferingDTO]

    enum CodingKeys: String, CodingKey {
        case currentOfferingID = "current_offering_id"
        case offerings
    }
}

private struct OfferingDTO: Decodable {
    let identifier: String
    let description: String?
    let isDefault: Bool?
    let packages: [OfferingPackageDTO]
}

private struct OfferingPackageDTO: Decodable {
    let identifier: String
    let platformProductIdentifier: String?
    let products: [ProductDTO]

    enum CodingKeys: String, CodingKey {
        case identifier
        case platformProductIdentifier = "platform_product_identifier"
        case products
    }
}

private struct ProductsResponseDTO: Decodable {
    let success: Bool
    let data: [ProductDTO]
}

private struct ProductDTO: Decodable {
    let productID: String?
    let identifier: String
    let displayName: String
    let type: String
    let storeStatus: String
    let productGroup: String?
    let isActive: Bool?
    let price: PriceDTO?
    let introductoryPrice: PriceDTO?

    enum CodingKeys: String, CodingKey {
        case productID = "productId"
        case identifier
        case displayName
        case type
        case storeStatus
        case productGroup
        case isActive
        case price
        case introductoryPrice
    }
}

private struct PriceDTO: Decodable {
    let amount: Int64
    let currency: String
}

private struct CustomerResponseDTO: Decodable {
    let requestDate: String
    let subscriber: SubscriberDTO

    enum CodingKeys: String, CodingKey {
        case requestDate = "request_date"
        case subscriber
    }
}

private struct SubscriberDTO: Decodable {
    let originalAppUserID: String
    let entitlements: [String: EntitlementDTO]
    let subscriptions: [String: SubscriptionDTO]

    enum CodingKeys: String, CodingKey {
        case originalAppUserID = "original_app_user_id"
        case entitlements
        case subscriptions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        originalAppUserID = try container.decode(String.self, forKey: .originalAppUserID)
        entitlements = try container.decodeIfPresent(
            [String: EntitlementDTO].self,
            forKey: .entitlements
        ) ?? [:]
        subscriptions = try container.decodeIfPresent(
            [String: SubscriptionDTO].self,
            forKey: .subscriptions
        ) ?? [:]
    }
}

private struct EntitlementDTO: Decodable {
    let expirationDate: String?
    let purchaseDate: String?
    let productIdentifier: String?
    let isActive: Bool?
    let willRenew: Bool?

    enum CodingKeys: String, CodingKey {
        case expirationDate = "expires_date"
        case purchaseDate = "purchase_date"
        case productIdentifier = "product_identifier"
        case isActive = "is_active"
        case willRenew = "will_renew"
    }
}

private struct SubscriptionDTO: Decodable {
    let expirationDate: String?
    let purchaseDate: String?
    let unsubscribeDetectedAt: String?
    let periodType: String?
    let isActive: Bool?
    let willRenew: Bool?

    enum CodingKeys: String, CodingKey {
        case expirationDate = "expires_date"
        case purchaseDate = "purchase_date"
        case unsubscribeDetectedAt = "unsubscribe_detected_at"
        case periodType = "period_type"
        case isActive = "is_active"
        case willRenew = "will_renew"
    }
}

private extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var nonBlank: String? {
        isBlank ? nil : self
    }

    var normalizedToken: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
    }
}

private extension ProductStatus {
    var isActiveFallback: Bool {
        switch self {
        case .active, .approved:
            return true
        case .inactive, .unknown:
            return false
        }
    }
}
