/// Application-scoped entry point for the EzyRevenue iOS SDK.
///
/// The facade is actor-isolated. Its coordinators and external ports are
/// constructed manually in one internal component graph.
public actor EzyRevenue {
    /// The shared application-scoped SDK instance.
    public static let shared = EzyRevenue()

    /// The SDK version sent to the EzyRevenue backend.
    public static let sdkVersion = "1.0.0"

    private var component: EzyRevenueComponent
    private let usesInjectedComponent: Bool
    private var initialized = false
    private var logger = EzyRevenueLogger(level: .none)
    private var configuredAPIKeyFingerprint: String?
    private var userCountryCode: String?
    private var initializationTask: Task<EzyRevenueResult<Void>, Never>?

    /// Creates the internal runtime instance used by the shared facade and tests.
    init() {
        self.component = .unavailable()
        self.usesInjectedComponent = false
    }

    /// Creates a facade with explicitly supplied test boundaries.
    internal init(component: EzyRevenueComponent) {
        self.component = component
        self.usesInjectedComponent = true
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
        // Concurrent callers share the first initialization operation. A
        // second configuration waits rather than racing identity transitions.
        if let initializationTask {
            return await initializationTask.value
        }

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

        let task = Task { [configuration] in
            await self.performInitialize(configuration: configuration)
        }
        initializationTask = task
        let result = await task.value
        initializationTask = nil
        return result
    }

    /// Switches the active SDK identity to a custom application user ID.
    public func logIn(appUserID: String) async -> EzyRevenueResult<Void> {
        guard initialized else { return notInitialized(operation: "logIn") }
        guard !appUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.error("logIn_failed: appUserID must not be blank")
            return .failure(.invalidConfiguration("appUserID must not be blank"))
        }

        let result = await component.sessionCoordinator.login(appUserID: appUserID)
        if case .success = result {
            component.catalogCoordinator.clear()
            component.purchaseCoordinator.clear()
            if #available(macOS 12.0, iOS 15.0, *) {
                component.purchaseCoordinator.startTransactionListener(
                    session: component.sessionCoordinator
                )
            }
            initialized = true
            logger.info("logIn_succeeded")
        } else {
            initialized = false
        }
        return result
    }

    /// Fetches offerings for the active identity.
    public func getOfferings() async -> EzyRevenueResult<[Offering]> {
        guard initialized else { return notInitialized(operation: "getOfferings") }
        guard #available(macOS 12.0, iOS 15.0, *) else {
            logger.error("getOfferings_failed: StoreKit 2 requires iOS 15")
            return .failure(.billingUnavailable)
        }
        let metadata = await MetadataProvider.current(userCountryCode: userCountryCode)
        let result = await component.catalogCoordinator.loadOfferings(
            countryCode: metadata.preferredCountryCode,
            session: component.sessionCoordinator
        )
        if case let .failure(error) = result {
            logger.error("getOfferings_failed: \(error.localizedDescription)")
        }
        return result
    }

    /// Fetches the complete product catalog.
    public func getProducts() async -> EzyRevenueResult<[Product]> {
        guard initialized else { return notInitialized(operation: "getProducts") }
        guard #available(macOS 12.0, iOS 15.0, *) else {
            logger.error("getProducts_failed: StoreKit 2 requires iOS 15")
            return .failure(.billingUnavailable)
        }
        let result = await component.catalogCoordinator.loadProducts(
            session: component.sessionCoordinator
        )
        if case let .failure(error) = result {
            logger.error("getProducts_failed: \(error.localizedDescription)")
        }
        return result
    }

    /// Fetches backend-authoritative customer information.
    public func getCustomerInfo() async -> EzyRevenueResult<CustomerInfo> {
        guard initialized else { return notInitialized(operation: "getCustomerInfo") }
        let result = await component.catalogCoordinator.loadCustomerInfo(
            session: component.sessionCoordinator
        )
        if case let .failure(error) = result {
            logger.error("getCustomerInfo_failed: \(error.localizedDescription)")
        }
        return result
    }

    /// Purchases an offering package.
    public func purchasePackage(
        _ package: OfferingPackage
    ) async -> EzyRevenueResult<PurchaseResult> {
        guard initialized else { return notInitialized(operation: "purchasePackage") }
        guard #available(macOS 12.0, iOS 15.0, *) else {
            logger.error("purchasePackage_failed: StoreKit 2 requires iOS 15")
            return .failure(.billingUnavailable)
        }
        let result = await component.purchaseCoordinator.purchasePackage(
            package,
            session: component.sessionCoordinator
        )
        let mapped = mapPurchaseResult(result)
        if case let .failure(error) = mapped {
            logger.error("purchasePackage_failed: \(error.localizedDescription)")
        }
        return mapped
    }

    /// Purchases a catalog product.
    public func purchaseProduct(
        _ product: Product
    ) async -> EzyRevenueResult<PurchaseResult> {
        guard initialized else { return notInitialized(operation: "purchaseProduct") }
        guard #available(macOS 12.0, iOS 15.0, *) else {
            logger.error("purchaseProduct_failed: StoreKit 2 requires iOS 15")
            return .failure(.billingUnavailable)
        }
        let result = await component.purchaseCoordinator.purchaseProduct(
            product,
            session: component.sessionCoordinator
        )
        let mapped = mapPurchaseResult(result)
        if case let .failure(error) = mapped {
            logger.error("purchaseProduct_failed: \(error.localizedDescription)")
        }
        return mapped
    }

    /// Restores purchases without initiating a new charge.
    public func restorePurchases() async -> EzyRevenueResult<CustomerInfo> {
        guard initialized else { return notInitialized(operation: "restorePurchases") }
        guard #available(macOS 12.0, iOS 15.0, *) else {
            logger.error("restorePurchases_failed: StoreKit 2 requires iOS 15")
            return .failure(.billingUnavailable)
        }
        let restoreResult = await component.purchaseCoordinator.restorePurchases(
            session: component.sessionCoordinator
        )
        if case let .failure(error) = restoreResult {
            logger.error("restorePurchases_failed: \(error.localizedDescription)")
            return .failure(error)
        }

        let customerResult = await component.catalogCoordinator.loadCustomerInfo(
            session: component.sessionCoordinator
        )
        if case let .failure(error) = customerResult {
            logger.error("restorePurchases_failed: \(error.localizedDescription)")
        }
        return customerResult
    }

    /// Ends the active SDK session and clears local runtime state.
    public func logOut() async -> EzyRevenueResult<Void> {
        guard initialized else { return notInitialized(operation: "logOut") }

        let result = await component.sessionCoordinator.logout()
        component.catalogCoordinator.clear()
        component.purchaseCoordinator.clear()
        initialized = false
        if case .success = result {
            logger.info("logOut_succeeded")
        }
        return result
    }

    private func performInitialize(
        configuration: EzyRevenueConfiguration
    ) async -> EzyRevenueResult<Void> {
        let fingerprint = APIKeyFingerprint.make(configuration.apiKey)

        if !usesInjectedComponent,
           configuredAPIKeyFingerprint != fingerprint {
            if initialized {
                _ = await component.sessionCoordinator.logout()
                component.catalogCoordinator.clear()
                component.purchaseCoordinator.clear()
                initialized = false
            }

            guard #available(macOS 12.0, iOS 15.0, *) else {
                logger.error("initialize_failed: StoreKit 2 requires iOS 15")
                return .failure(.billingUnavailable)
            }
            component = .runtime(
                apiKey: configuration.apiKey,
                userCountryCode: configuration.userCountryCode,
                logger: logger
            )
        } else {
            component.sessionCoordinator.updateLogger(logger)
            component.purchaseCoordinator.updateLogger(logger)
        }

        let previousAppUserID = component.sessionCoordinator.appUserID
        let result = await component.sessionCoordinator.initialize(
            apiKeyFingerprint: fingerprint,
            requestedAppUserID: configuration.appUserID
        )
        if case .success = result {
            if previousAppUserID != component.sessionCoordinator.appUserID {
                component.catalogCoordinator.clear()
                component.purchaseCoordinator.clear()
            }
            configuredAPIKeyFingerprint = fingerprint
            userCountryCode = configuration.userCountryCode
            initialized = true
            if #available(macOS 12.0, iOS 15.0, *) {
                component.purchaseCoordinator.startTransactionListener(
                    session: component.sessionCoordinator
                )
                await component.purchaseCoordinator.recoverUnfinishedTransactions(
                    session: component.sessionCoordinator
                )
            }
            logger.info("initialize_succeeded")
        } else {
            initialized = false
        }
        return result
    }

    @available(macOS 12.0, iOS 15.0, *)
    private func mapPurchaseResult(
        _ result: EzyRevenueResult<PurchaseFlowResult>
    ) -> EzyRevenueResult<PurchaseResult> {
        switch result {
        case let .success(flowResult):
            switch flowResult {
            case .purchased:
                return .success(.purchased)
            case .pending:
                return .success(.pending)
            case .cancelled:
                return .success(.cancelled)
            }
        case let .failure(error):
            return .failure(error)
        }
    }

    private func notInitialized<T>(operation: String) -> EzyRevenueResult<T> {
        logger.error("\(operation)_failed: SDK is not initialized")
        return .failure(.notInitialized)
    }
}
