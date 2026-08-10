import SwiftUI
import EzyRevenue

struct ContentView: View {
    @StateObject private var model = SampleViewModel()

    var body: some View {
        NavigationView {
            Form {
                Section("Runtime") {
                    Text(model.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Initialize SDK") {
                        model.initialize()
                    }
                    .disabled(model.isBusy)

                    HStack {
                        Button("Refresh catalog") {
                            model.refreshCatalog()
                        }
                        .disabled(!model.isInitialized || model.isBusy)

                        Button("Load customer") {
                            model.loadCustomerInfo()
                        }
                        .disabled(!model.isInitialized || model.isBusy)
                    }

                    HStack {
                        Button("Restore purchases") {
                            model.restorePurchases()
                        }
                        .disabled(!model.isInitialized || model.isBusy)

                        Button("Log out") {
                            model.logOut()
                        }
                        .disabled(!model.isInitialized || model.isBusy)
                    }
                }

                Section("Offerings") {
                    if model.offerings.isEmpty {
                        Text("No offerings loaded")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.offerings, id: \.identifier) { offering in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(offering.identifier)
                                .font(.headline)
                            if let description = offering.description {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(offering.packages, id: \.identifier) { package in
                                Button {
                                    model.purchase(package: package)
                                } label: {
                                    HStack {
                                        Text(package.identifier)
                                        Spacer()
                                        Text(model.displayPrice(for: package))
                                    }
                                }
                                .disabled(!model.isInitialized || model.isBusy)
                            }
                        }
                    }
                }

                Section("Products") {
                    if model.products.isEmpty {
                        Text("No products loaded")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.products, id: \.identifier) { product in
                        Button {
                            model.purchase(product: product)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(product.displayName)
                                    Text(product.identifier)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(product.price?.displayPrice ?? "Unavailable")
                                    Text(product.isAvailableInAppStore ? "Available" : "Unavailable")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(!model.isInitialized || model.isBusy)
                    }
                }

                Section("Customer information") {
                    if let customerInfo = model.customerInfo {
                        Text("Original user: \(customerInfo.originalAppUserID ?? "-")")
                        Text("Active subscriptions: \(customerInfo.activeSubscriptions.sorted().joined(separator: ", "))")
                        Text("Active entitlements: \(customerInfo.entitlements.values.filter(\.isActive).count)")
                    } else {
                        Text("No customer information loaded")
                            .foregroundStyle(.secondary)
                    }
                    if let purchaseState = model.purchaseState {
                        Text(purchaseState)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("SDK diagnostics") {
                    if model.logs.isEmpty {
                        Text("Logs are emitted after initialization")
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            Text(model.logs.joined(separator: "\n"))
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 80, maxHeight: 180)
                    }
                }
            }
            .navigationTitle("EzyRevenue")
        }
    }
}

@MainActor
private final class SampleViewModel: ObservableObject {
    @Published var status = "Configure an API key, then initialize."
    @Published var purchaseState: String?
    @Published var offerings: [Offering] = []
    @Published var products: [Product] = []
    @Published var customerInfo: CustomerInfo?
    @Published var logs: [String] = []
    @Published var isBusy = false
    @Published var isInitialized = false

    private let sdk = EzyRevenue.shared

    func initialize() {
        perform("Initialize") {
            guard let apiKey = self.infoValue("EZY_REVENUE_API_KEY"), !apiKey.isEmpty else {
                self.status = "Missing EZY_REVENUE_API_KEY in the local xcconfig."
                return
            }
            let appUserID = self.infoValue("EZY_REVENUE_APP_USER_ID")
            let result = await self.sdk.initialize(
                configuration: EzyRevenueConfiguration(
                    apiKey: apiKey,
                    appUserID: appUserID,
                    logLevel: .verbose,
                    onLog: { [weak self] message in
                        Task { @MainActor in
                            self?.logs.append(message)
                        }
                    }
                )
            )
            guard case let .failure(error) = result else {
                self.isInitialized = true
                self.status = "Initialized as \(await self.sdk.appUserID ?? "unknown user")"
                await self.refreshCatalogValues()
                return
            }
            self.status = "Initialization failed: \(error.localizedDescription)"
        }
    }

    func refreshCatalog() {
        perform("Refresh catalog") {
            await self.refreshCatalogValues()
        }
    }

    func loadCustomerInfo() {
        perform("Load customer") {
            let result = await self.sdk.getCustomerInfo()
            self.applyCustomerResult(result)
        }
    }

    func purchase(package: OfferingPackage) {
        perform("Purchase") {
            let result = await self.sdk.purchasePackage(package)
            await self.applyPurchaseResult(result)
        }
    }

    func purchase(product: Product) {
        perform("Purchase") {
            let result = await self.sdk.purchaseProduct(product)
            await self.applyPurchaseResult(result)
        }
    }

    func restorePurchases() {
        perform("Restore") {
            let result = await self.sdk.restorePurchases()
            switch result {
            case let .success(customerInfo):
                self.customerInfo = customerInfo
                self.purchaseState = "Restore completed"
            case let .failure(error):
                self.purchaseState = "Restore failed: \(error.localizedDescription)"
            }
        }
    }

    func logOut() {
        perform("Log out") {
            let result = await self.sdk.logOut()
            switch result {
            case .success:
                self.isInitialized = false
                self.offerings = []
                self.products = []
                self.customerInfo = nil
                self.status = "Logged out"
            case let .failure(error):
                self.status = "Logout failed: \(error.localizedDescription)"
            }
        }
    }

    func displayPrice(for package: OfferingPackage) -> String {
        package.products.first?.price?.displayPrice ?? "Unavailable"
    }

    private func refreshCatalogValues() async {
        let offeringsResult = await sdk.getOfferings()
        let productsResult = await sdk.getProducts()
        switch offeringsResult {
        case let .success(offerings):
            self.offerings = offerings
        case let .failure(error):
            self.status = "Offerings failed: \(error.localizedDescription)"
        }
        switch productsResult {
        case let .success(products):
            self.products = products
        case let .failure(error):
            self.status = "Products failed: \(error.localizedDescription)"
        }
        let customerResult = await sdk.getCustomerInfo()
        applyCustomerResult(customerResult)
    }

    private func applyCustomerResult(_ result: EzyRevenueResult<CustomerInfo>) {
        switch result {
        case let .success(customerInfo):
            self.customerInfo = customerInfo
        case let .failure(error):
            self.status = "Customer info failed: \(error.localizedDescription)"
        }
    }

    private func applyPurchaseResult(
        _ result: EzyRevenueResult<PurchaseResult>
    ) async {
        switch result {
        case let .success(outcome):
            self.purchaseState = "Purchase: \(String(describing: outcome))"
            let customerResult = await sdk.getCustomerInfo()
            applyCustomerResult(customerResult)
        case let .failure(error):
            self.purchaseState = "Purchase failed: \(error.localizedDescription)"
        }
    }

    private func perform(
        _ operation: String,
        _ body: @escaping @MainActor () async -> Void
    ) {
        guard !isBusy else { return }
        isBusy = true
        status = "\(operation) in progress..."
        Task { @MainActor in
            await body()
            isBusy = false
        }
    }

    private func infoValue(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

#Preview {
    ContentView()
}
