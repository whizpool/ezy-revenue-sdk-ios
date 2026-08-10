import Foundation

/// A backend offering containing purchasable packages.
public struct Offering: Equatable, Sendable {
    public let identifier: String
    public let description: String?
    public let isDefault: Bool
    public let packages: [OfferingPackage]

    public init(
        identifier: String,
        description: String? = nil,
        isDefault: Bool = false,
        packages: [OfferingPackage] = []
    ) {
        self.identifier = identifier
        self.description = description
        self.isDefault = isDefault
        self.packages = packages
    }
}

/// A package within an offering.
public struct OfferingPackage: Equatable, Sendable {
    public let identifier: String
    public let platformProductIdentifier: String?
    public let products: [Product]

    public init(
        identifier: String,
        platformProductIdentifier: String? = nil,
        products: [Product] = []
    ) {
        self.identifier = identifier
        self.platformProductIdentifier = platformProductIdentifier
        self.products = products
    }
}

/// Product categories understood by the iOS SDK.
public enum ProductType: Equatable, Sendable {
    case subscription
    case nonConsumable
    case unknown(String)
}

/// Backend/store status associated with a product.
public enum ProductStatus: Equatable, Sendable {
    case active
    case approved
    case inactive
    case unknown(String)
}

/// A monetary price in integer micros, optionally enriched with StoreKit text.
public struct Price: Equatable, Sendable {
    public let amountMicros: Int64
    public let currencyCode: String
    public let displayPrice: String?

    public init(
        amountMicros: Int64,
        currencyCode: String,
        displayPrice: String? = nil
    ) {
        self.amountMicros = amountMicros
        self.currencyCode = currencyCode
        self.displayPrice = displayPrice
    }
}

/// An immutable backend product, optionally enriched with App Store data.
public struct Product: Equatable, Sendable {
    public let productID: String?
    public let identifier: String
    public let displayName: String
    public let type: ProductType
    public let storeStatus: ProductStatus
    public let productGroup: String?
    public let isActive: Bool
    public let price: Price?
    public let introductoryPrice: Price?
    public let isAvailableInAppStore: Bool

    public init(
        productID: String? = nil,
        identifier: String,
        displayName: String,
        type: ProductType,
        storeStatus: ProductStatus,
        productGroup: String? = nil,
        isActive: Bool,
        price: Price? = nil,
        introductoryPrice: Price? = nil,
        isAvailableInAppStore: Bool = false
    ) {
        self.productID = productID
        self.identifier = identifier
        self.displayName = displayName
        self.type = type
        self.storeStatus = storeStatus
        self.productGroup = productGroup
        self.isActive = isActive
        self.price = price
        self.introductoryPrice = introductoryPrice
        self.isAvailableInAppStore = isAvailableInAppStore
    }
}

/// One entitlement reported by the backend.
public struct EntitlementInfo: Equatable, Sendable {
    public let identifier: String
    public let isActive: Bool
    public let willRenew: Bool
    public let expirationDate: Date?
    public let purchaseDate: Date?
    public let productIdentifier: String?

    public init(
        identifier: String,
        isActive: Bool,
        willRenew: Bool = false,
        expirationDate: Date? = nil,
        purchaseDate: Date? = nil,
        productIdentifier: String? = nil
    ) {
        self.identifier = identifier
        self.isActive = isActive
        self.willRenew = willRenew
        self.expirationDate = expirationDate
        self.purchaseDate = purchaseDate
        self.productIdentifier = productIdentifier
    }
}

/// One subscription reported by the backend.
public struct SubscriptionInfo: Equatable, Sendable {
    public let productIdentifier: String
    public let expirationDate: Date?
    public let purchaseDate: Date?
    public let periodType: String?
    public let unsubscribeDetectedAt: Date?
    public let isActive: Bool
    public let willRenew: Bool

    public init(
        productIdentifier: String,
        expirationDate: Date? = nil,
        purchaseDate: Date? = nil,
        periodType: String? = nil,
        unsubscribeDetectedAt: Date? = nil,
        isActive: Bool,
        willRenew: Bool = false
    ) {
        self.productIdentifier = productIdentifier
        self.expirationDate = expirationDate
        self.purchaseDate = purchaseDate
        self.periodType = periodType
        self.unsubscribeDetectedAt = unsubscribeDetectedAt
        self.isActive = isActive
        self.willRenew = willRenew
    }
}

/// Backend-authoritative entitlements and subscriptions for an app user.
public struct CustomerInfo: Equatable, Sendable {
    public let requestDate: Date?
    public let originalAppUserID: String?
    public let entitlements: [String: EntitlementInfo]
    public let subscriptions: [String: SubscriptionInfo]

    public init(
        requestDate: Date? = nil,
        originalAppUserID: String? = nil,
        entitlements: [String: EntitlementInfo] = [:],
        subscriptions: [String: SubscriptionInfo] = [:]
    ) {
        self.requestDate = requestDate
        self.originalAppUserID = originalAppUserID
        self.entitlements = entitlements
        self.subscriptions = subscriptions
    }

    /// Store product identifiers of subscriptions currently active according to the backend.
    public var activeSubscriptions: Set<String> {
        Set(subscriptions.compactMap { $0.value.isActive ? $0.key : nil })
    }

    /// Returns whether the backend currently grants an entitlement.
    public func entitlementIsActive(_ identifier: String) -> Bool {
        entitlements[identifier]?.isActive == true
    }
}
