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
    private var logger = EzyRevenueLogger(level: .none)

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
        // Selecting a level is the first initialization action. The initial
        // logger is `.none`, so calls made before this method remain silent.
        logger = EzyRevenueLogger(
            level: configuration.logLevel,
            onLog: configuration.onLog
        )
        logger.debug("initialize_started")

        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.error("initialize_failed: apiKey must not be blank")
            return .failure(.invalidConfiguration("apiKey must not be blank"))
        }
        if let appUserID = configuration.appUserID,
           appUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logger.error("initialize_failed: appUserID must not be blank")
            return .failure(.invalidConfiguration("appUserID must not be blank"))
        }

        logger.error("initialize_failed: Runtime wiring is not available yet")
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Switches the active SDK identity to a custom application user ID.
    public func logIn(appUserID: String) async -> EzyRevenueResult<Void> {
        guard initialized else { return notInitialized(operation: "logIn") }
        guard !appUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.error("logIn_failed: appUserID must not be blank")
            return .failure(.invalidConfiguration("appUserID must not be blank"))
        }
        logger.error("logIn_failed: Runtime wiring is not available yet")
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Fetches offerings for the active identity.
    public func getOfferings() async -> EzyRevenueResult<[Offering]> {
        guard initialized else { return notInitialized(operation: "getOfferings") }
        logger.error("getOfferings_failed: Runtime wiring is not available yet")
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Fetches the complete product catalog.
    public func getProducts() async -> EzyRevenueResult<[Product]> {
        guard initialized else { return notInitialized(operation: "getProducts") }
        logger.error("getProducts_failed: Runtime wiring is not available yet")
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Fetches backend-authoritative customer information.
    public func getCustomerInfo() async -> EzyRevenueResult<CustomerInfo> {
        guard initialized else { return notInitialized(operation: "getCustomerInfo") }
        logger.error("getCustomerInfo_failed: Runtime wiring is not available yet")
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Purchases an offering package.
    public func purchasePackage(
        _ package: OfferingPackage
    ) async -> EzyRevenueResult<PurchaseResult> {
        guard initialized else { return notInitialized(operation: "purchasePackage") }
        _ = package
        logger.error("purchasePackage_failed: Runtime wiring is not available yet")
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Purchases a catalog product.
    public func purchaseProduct(
        _ product: Product
    ) async -> EzyRevenueResult<PurchaseResult> {
        guard initialized else { return notInitialized(operation: "purchaseProduct") }
        _ = product
        logger.error("purchaseProduct_failed: Runtime wiring is not available yet")
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Restores purchases without initiating a new charge.
    public func restorePurchases() async -> EzyRevenueResult<CustomerInfo> {
        guard initialized else { return notInitialized(operation: "restorePurchases") }
        logger.error("restorePurchases_failed: Runtime wiring is not available yet")
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Ends the active SDK session and clears local runtime state.
    public func logOut() async -> EzyRevenueResult<Void> {
        guard initialized else { return notInitialized(operation: "logOut") }
        logger.error("logOut_failed: Runtime wiring is not available yet")
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    private func notInitialized<T>(operation: String) -> EzyRevenueResult<T> {
        logger.error("\(operation)_failed: SDK is not initialized")
        return .failure(.notInitialized)
    }
}
