/// Owns in-memory catalog and customer snapshots for one SDK runtime.
internal final class CatalogCoordinator: @unchecked Sendable {
    let backend: any EzyRevenueBackend
    let storeKitGateway: any StoreKitGateway

    private(set) var offerings: [Offering] = []
    private(set) var currentOffering: Offering?
    private(set) var products: [Product] = []
    private(set) var customerInfo: CustomerInfo?

    init(
        backend: any EzyRevenueBackend,
        storeKitGateway: any StoreKitGateway
    ) {
        self.backend = backend
        self.storeKitGateway = storeKitGateway
    }

    /// Commits offerings only if the originating identity is still active.
    @discardableResult
    func commitOfferings(
        _ offerings: [Offering],
        currentOffering: Offering?,
        for generation: SessionGeneration,
        session: SessionCoordinator
    ) -> Bool {
        guard session.isCurrent(generation) else { return false }
        self.offerings = offerings
        self.currentOffering = currentOffering
        return true
    }

    /// Commits products only if the originating identity is still active.
    @discardableResult
    func commitProducts(
        _ products: [Product],
        for generation: SessionGeneration,
        session: SessionCoordinator
    ) -> Bool {
        guard session.isCurrent(generation) else { return false }
        self.products = products
        return true
    }

    /// Commits customer information only if the originating identity is current.
    @discardableResult
    func commitCustomerInfo(
        _ customerInfo: CustomerInfo,
        for generation: SessionGeneration,
        session: SessionCoordinator
    ) -> Bool {
        guard session.isCurrent(generation) else { return false }
        self.customerInfo = customerInfo
        return true
    }

    /// Loads offerings for the active identity, then enriches their products
    /// with one batched StoreKit lookup before committing the snapshot.
    @available(macOS 12.0, iOS 15.0, *)
    func loadOfferings(
        countryCode: String?,
        session: SessionCoordinator
    ) async -> EzyRevenueResult<[Offering]> {
        guard let generation = session.captureGeneration() else {
            return .failure(.notInitialized)
        }
        let backendResult = await session.executeAuthenticated { [backend] accessToken in
            do {
                return try await backend.fetchOfferings(
                    appUserID: generation.appUserID,
                    countryCode: countryCode,
                    accessToken: accessToken
                )
            } catch {
                return .failure(.network)
            }
        }
        guard case let .success(_, body) = backendResult else {
            if case let .failure(error) = backendResult {
                return .failure(error)
            }
            return .failure(.network)
        }
        guard case let .success(snapshot) = BackendMapper.mapOfferings(from: body) else {
            return .failure(.invalidResponse)
        }

        let enriched = await enrichOfferings(snapshot.offerings)
        let currentIdentifier = snapshot.currentOffering?.identifier
        let current = enriched.first {
            $0.identifier == currentIdentifier
        }
        guard commitOfferings(
            enriched,
            currentOffering: current,
            for: generation,
            session: session
        ) else {
            return .failure(.notInitialized)
        }
        return .success(enriched)
    }

    /// Loads the complete backend product catalog and enriches it with one
    /// batched StoreKit lookup before committing the snapshot.
    @available(macOS 12.0, iOS 15.0, *)
    func loadProducts(
        session: SessionCoordinator
    ) async -> EzyRevenueResult<[Product]> {
        guard let generation = session.captureGeneration() else {
            return .failure(.notInitialized)
        }
        let backendResult = await session.executeAuthenticated { [backend] _ in
            do {
                return try await backend.fetchProducts()
            } catch {
                return .failure(.network)
            }
        }
        guard case let .success(_, body) = backendResult else {
            if case let .failure(error) = backendResult {
                return .failure(error)
            }
            return .failure(.network)
        }
        guard case let .success(products) = BackendMapper.mapProducts(from: body) else {
            return .failure(.invalidResponse)
        }

        let enriched = await enrichProducts(products)
        guard commitProducts(enriched, for: generation, session: session) else {
            return .failure(.notInitialized)
        }
        return .success(enriched)
    }

    /// Loads StoreKit details in one batch and enriches backend products. A
    /// StoreKit lookup failure leaves the backend catalog intact and marked as
    /// unavailable.
    @available(macOS 12.0, iOS 15.0, *)
    func enrichProducts(_ products: [Product]) async -> [Product] {
        let identifiers = Set(products.map(\.identifier).filter { !$0.isEmpty })
        let storeProducts = await fetchStoreProducts(for: identifiers)
        return products.map { enrich($0, with: storeProducts[$0.identifier]) }
    }

    /// Enriches products nested inside offerings without dropping backend
    /// offerings when one or more App Store products are unavailable.
    @available(macOS 12.0, iOS 15.0, *)
    func enrichOfferings(_ offerings: [Offering]) async -> [Offering] {
        let identifiers = Set(
            offerings.flatMap { offering in
                offering.packages.flatMap { package in
                    ([package.platformProductIdentifier].compactMap { $0 }) +
                        package.products.map(\.identifier)
                }
            }
        )
        let storeProducts = await fetchStoreProducts(for: identifiers)
        return offerings.map { offering in
            Offering(
                identifier: offering.identifier,
                description: offering.description,
                isDefault: offering.isDefault,
                packages: offering.packages.map { package in
                    OfferingPackage(
                        identifier: package.identifier,
                        platformProductIdentifier: package.platformProductIdentifier,
                        products: package.products.map {
                            enrich($0, with: storeProducts[$0.identifier])
                        }
                    )
                }
            )
        }
    }

    /// Resolves the one StoreKit identifier allowed for a package purchase.
    /// A package platform identifier and nested backend identifiers must agree.
    static func storeKitIdentifier(
        for package: OfferingPackage
    ) -> EzyRevenueResult<String> {
        let nestedIdentifiers = package.products.map(\.identifier).filter { !$0.isEmpty }
        if let platformIdentifier = package.platformProductIdentifier,
           !platformIdentifier.isEmpty {
            guard nestedIdentifiers.allSatisfy({ $0 == platformIdentifier }) else {
                return .failure(.invalidConfiguration(
                    "Offering package StoreKit identifiers must agree"
                ))
            }
            return .success(platformIdentifier)
        }

        guard Set(nestedIdentifiers).count == 1,
              let identifier = nestedIdentifiers.first else {
            return .failure(.invalidConfiguration(
                "Offering package must contain one StoreKit product identifier"
            ))
        }
        return .success(identifier)
    }

    /// Clears all snapshots during identity changes and logout.
    func clear() {
        offerings = []
        currentOffering = nil
        products = []
        customerInfo = nil
    }

    @available(macOS 12.0, iOS 15.0, *)
    private func fetchStoreProducts(
        for identifiers: Set<String>
    ) async -> [String: StoreKitProduct] {
        guard !identifiers.isEmpty else { return [:] }
        do {
            let products = try await storeKitGateway.fetchProducts(for: identifiers)
            return Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        } catch {
            return [:]
        }
    }

    @available(macOS 12.0, iOS 15.0, *)
    private func enrich(
        _ product: Product,
        with storeProduct: StoreKitProduct?
    ) -> Product {
        guard let storeProduct else {
            return Product(
                productID: product.productID,
                identifier: product.identifier,
                displayName: product.displayName,
                type: product.type,
                storeStatus: product.storeStatus,
                productGroup: product.productGroup,
                isActive: product.isActive,
                price: product.price,
                introductoryPrice: product.introductoryPrice,
                isAvailableInAppStore: false
            )
        }

        let introductoryPrice = storeProduct.introductoryOffer.map {
            Price(
                amountMicros: $0.priceMicros,
                currencyCode: storeProduct.currencyCode,
                displayPrice: $0.displayPrice
            )
        } ?? product.introductoryPrice
        return Product(
            productID: product.productID,
            identifier: product.identifier,
            displayName: product.displayName,
            type: product.type,
            storeStatus: product.storeStatus,
            productGroup: product.productGroup,
            isActive: product.isActive,
            price: Price(
                amountMicros: storeProduct.priceMicros,
                currencyCode: storeProduct.currencyCode,
                displayPrice: storeProduct.displayPrice
            ),
            introductoryPrice: introductoryPrice,
            isAvailableInAppStore: true
        )
    }
}
