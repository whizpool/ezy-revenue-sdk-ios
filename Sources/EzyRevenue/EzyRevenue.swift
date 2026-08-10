/// Application-scoped entry point for the EzyRevenue iOS SDK.
///
/// Runtime wiring is added in the following implementation steps. The public
/// surface is defined here so host applications can compile against the v1 API
/// while the internal coordinators are built behind it.
public actor EzyRevenue {
    /// The shared application-scoped SDK instance.
    public static let shared = EzyRevenue()

    /// The SDK version sent to the EzyRevenue backend.
    public static let sdkVersion = "1.0.0"

    /// Creates the internal runtime instance used by the shared facade and tests.
    init() {}

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
        _ = appUserID
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Fetches offerings for the active identity.
    public func getOfferings() async -> EzyRevenueResult<[Offering]> {
        .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Fetches the complete product catalog.
    public func getProducts() async -> EzyRevenueResult<[Product]> {
        .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Fetches backend-authoritative customer information.
    public func getCustomerInfo() async -> EzyRevenueResult<CustomerInfo> {
        .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Purchases an offering package.
    public func purchasePackage(
        _ package: OfferingPackage
    ) async -> EzyRevenueResult<PurchaseResult> {
        _ = package
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Purchases a catalog product.
    public func purchaseProduct(
        _ product: Product
    ) async -> EzyRevenueResult<PurchaseResult> {
        _ = product
        return .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Restores purchases without initiating a new charge.
    public func restorePurchases() async -> EzyRevenueResult<CustomerInfo> {
        .failure(.internalError("Runtime wiring is not available yet"))
    }

    /// Ends the active SDK session and clears local runtime state.
    public func logOut() async -> EzyRevenueResult<Void> {
        .failure(.internalError("Runtime wiring is not available yet"))
    }
}
