/// Application-scoped entry point for the EzyRevenue iOS SDK.
///
/// The facade is actor-isolated. Its coordinators and external ports are
/// constructed manually in one internal component graph.
public actor EzyRevenue {
    /// The shared application-scoped SDK instance.
    public static let shared = EzyRevenue()

    /// The SDK version sent to the EzyRevenue backend.
    public static let sdkVersion = "1.0.0"

    private let component: EzyRevenueComponent
    private var initialized = false

    /// Creates the internal runtime instance used by the shared facade and tests.
    init() {
        self.component = .unavailable()
    }

    /// Creates a facade with explicitly supplied test boundaries.
    internal init(component: EzyRevenueComponent) {
        self.component = component
    }

    /// Whether initialization has completed successfully.
    public var isInitialized: Bool {
        initialized
    }

    /// The active custom or SDK-generated app user ID, when available.
    public var appUserID: String? {
        component.sessionCoordinator.appUserID
    }

    /// Last committed offerings snapshot.
    public var offerings: [Offering] {
        component.catalogCoordinator.offerings
    }

    /// Current offering from the last committed offerings snapshot.
    public var currentOffering: Offering? {
        component.catalogCoordinator.currentOffering
    }

    /// Last committed product snapshot.
    public var products: [Product] {
        component.catalogCoordinator.products
    }

    /// Last committed backend customer snapshot.
    public var customerInfo: CustomerInfo? {
        component.catalogCoordinator.customerInfo
    }

    /// Initializes the SDK for the supplied configuration.
    public func initialize(
        configuration: EzyRevenueConfiguration
    ) async -> EzyRevenueResult<Void> {
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.invalidConfiguration("apiKey must not be blank"))
        }
        if let appUserID = configuration.appUserID,
           appUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure(.invalidConfiguration("appUserID must not be blank"))
        }
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Switches the active SDK identity to a custom application user ID.
    public func logIn(appUserID: String) async -> EzyRevenueResult<Void> {
        guard initialized else { return .failure(.notInitialized) }
        guard !appUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.invalidConfiguration("appUserID must not be blank"))
        }
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Fetches offerings for the active identity.
    public func getOfferings() async -> EzyRevenueResult<[Offering]> {
        guard initialized else { return .failure(.notInitialized) }
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Fetches the complete product catalog.
    public func getProducts() async -> EzyRevenueResult<[Product]> {
        guard initialized else { return .failure(.notInitialized) }
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Fetches backend-authoritative customer information.
    public func getCustomerInfo() async -> EzyRevenueResult<CustomerInfo> {
        guard initialized else { return .failure(.notInitialized) }
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Purchases an offering package.
    public func purchasePackage(
        _ package: OfferingPackage
    ) async -> EzyRevenueResult<PurchaseResult> {
        guard initialized else { return .failure(.notInitialized) }
        _ = package
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Purchases a catalog product.
    public func purchaseProduct(
        _ product: Product
    ) async -> EzyRevenueResult<PurchaseResult> {
        guard initialized else { return .failure(.notInitialized) }
        _ = product
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Restores purchases without initiating a new charge.
    public func restorePurchases() async -> EzyRevenueResult<CustomerInfo> {
        guard initialized else { return .failure(.notInitialized) }
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Ends the active SDK session and clears local runtime state.
    public func logOut() async -> EzyRevenueResult<Void> {
        guard initialized else { return .failure(.notInitialized) }
        return .failure(.internalError("Runtime wiring is not available yet"))
    }
}
