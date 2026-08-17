# EzyRevenue iOS SDK

Official Swift Package Manager SDK for [EzyRevenue](https://ezyrevenue.com/) — handle iOS subscriptions, one-time purchases, product catalogs, user identity, and entitlement management.

For documentation, product configuration, and account dashboard, visit [https://ezyrevenue.com/](https://ezyrevenue.com/).

> **Status:** pre-release internal SDK (`1.0.1`).

## Features

- Initialize with an EzyRevenue configuration and an explicit user identity.
- Support persistent anonymous users and authenticated app users.
- Switch users with `logIn(appUserID:)` and `logOut()`.
- Load offerings and products configured for the app.
- Enrich products with localized App Store pricing through StoreKit 2.
- Purchase subscriptions and supported non-consumable products.
- Restore purchases without starting a new charge.
- Read customer information, subscriptions, and entitlements.
- Return typed results and typed errors.
- Configure SDK diagnostics with `EzyRevenueLogLevel`.

The SDK does not provide paywall UI, subscription-management UI, or analytics. The host app
owns the UI and decides which features to show after checking `CustomerInfo`.

## Requirements

- iOS 15 or newer
- Swift concurrency
- StoreKit 2
- Xcode with Swift Package Manager support

The package manifest also declares macOS support, but StoreKit-based SDK operations require a
platform version that supports the StoreKit 2 APIs used by the SDK.

## Network and timeout behavior

- Each SDK-created backend request has a **30-second timeout** covering the request and resource
  operation. A timeout is returned as `.network`.
- No internet connection, DNS/TLS failures, other transport failures, and backend 5xx responses
  are returned as `.network`.
- The SDK does not loop-retry ordinary network failures. Retry the relevant SDK operation after
  connectivity or the service is available again. Authentication failures may trigger one
  automatic re-login where applicable.
- The 30-second limit applies to each backend request, not necessarily the total duration of an
  operation such as initialization, which may also recover unfinished StoreKit transactions.
- StoreKit purchase UI remains controlled by StoreKit. A slow user decision is not treated as a
  backend request timeout; the SDK waits for StoreKit to report completion, pending, or
  cancellation.
- If purchase verification cannot complete, the StoreKit transaction is not finished and remains
  recoverable through a later initialization or `restorePurchases()` call.

## Installation

### Swift Package Manager

Add the package to the host application's dependencies:

```swift
.package(
    url: "https://github.com/whizpool/ezy-revenue-sdk-ios.git",
    from: "1.0.1"
)
```

Then add the `EzyRevenue` product to the application target:

```swift
.product(name: "EzyRevenue", package: "ezy-revenue-sdk-ios")
```

For local development, add the package by path instead:

```swift
.package(path: "../ezy-revenue-sdk-ios")
```

The public package URL and released version will be confirmed when distribution is available.

## App Store setup

Before testing purchases:

1. Create subscriptions and supported non-consumable products in App Store Connect.
2. Configure matching product identifiers in the [EzyRevenue dashboard](https://ezyrevenue.com/).
3. Configure the required subscription groups and subscription durations.
4. Use a StoreKit Configuration file for local testing, or a Sandbox tester/TestFlight build
   for App Store testing.
5. Confirm the product is available for the selected testing environment.

Products unavailable in the App Store remain in the catalog but are marked with
`isAvailableInAppStore == false`. Never hardcode prices; use the `Price` returned by the SDK.

## Quick start

All SDK operations are asynchronous. They can be called from a Swift concurrency task, actor,
ViewModel, or other appropriate application scope.

```swift
import EzyRevenue

let sdk = EzyRevenue.shared

let result = await sdk.initialize(
    configuration: EzyRevenueConfiguration(
        apiKey: "YOUR_EZY_REVENUE_SDK_KEY",
        // Pass a stable app user ID, or nil for persistent anonymous use.
        appUserID: nil,
        logLevel: .none
    )
)

switch result {
case .success:
    switch await sdk.getOfferings() {
    case let .success(offerings):
        showPaywall(offerings)
    case let .failure(error):
        showError(error)
    }
case let .failure(error):
    showError(error)
}
```

`EzyRevenue` is an actor. Await its public methods and properties when accessing it from
outside the actor. The SDK does not require a view controller or retain UI objects.

## Identity

Choose the identity during initialization:

- Pass a stable authenticated app user ID for an account-based user.
- Pass `nil` to create or reuse a persistent anonymous identity.

When an anonymous user signs in, call `logIn(appUserID:)`:

```swift
switch await EzyRevenue.shared.logIn(appUserID: user.id) {
case .success:
    await refreshEntitlements()
case let .failure(error):
    showError(error)
}
```

When the user signs out, call `logOut()`. Initialize again before making another SDK call:

```swift
let result = await EzyRevenue.shared.logOut()
```

## Catalog functions

### `getOfferings()`

Loads offerings for the active user and enriches available products with localized App Store
pricing:

```swift
switch await EzyRevenue.shared.getOfferings() {
case let .success(offerings):
    let currentOffering = await EzyRevenue.shared.currentOffering
    showPaywall(offerings, currentOffering: currentOffering)
case let .failure(error):
    showError(error)
}
```

`EzyRevenue.shared.offerings` and `currentOffering` are cached snapshots. Reading them does not
load fresh data. Call `getOfferings()` when the latest catalog is required.

An empty offerings array is a valid successful result. Do not assume that `currentOffering` is
non-nil.

### `getProducts()`

Loads the complete product catalog and returns App Store availability and pricing when
available:

```swift
switch await EzyRevenue.shared.getProducts() {
case let .success(products):
    displayProducts(products)
case let .failure(error):
    showError(error)
}
```

Use `product.price?.displayPrice` for localized display text. The SDK does not guarantee that
every catalog product is currently available in the App Store.

## Purchase functions

Use only `OfferingPackage` and `Product` instances returned by `getOfferings()` or
`getProducts()`.

### Purchase an offering package

```swift
func purchase(package: OfferingPackage) {
    Task {
        switch await EzyRevenue.shared.purchasePackage(package) {
        case let .success(result):
            handlePurchaseResult(result)
        case let .failure(error):
            showError(error)
        }
    }
}
```

### Purchase a product

```swift
Task {
    switch await EzyRevenue.shared.purchaseProduct(product) {
    case let .success(result):
        handlePurchaseResult(result)
    case let .failure(error):
        showError(error)
    }
}
```

Only one purchase flow can be active at a time. Disable repeated purchase actions while a
purchase is running and handle `purchaseInProgress` if another request is made.

### Purchase results

| Result | Meaning | App behavior |
|---|---|---|
| `.purchased` | StoreKit completed the purchase and SDK processing succeeded | Refresh `CustomerInfo` before granting access |
| `.pending` | StoreKit accepted the purchase, but payment is not complete | Show a pending state; do not grant access |
| `.cancelled` | The user closed or cancelled the purchase UI | Treat as a cancellation, not a failure |

A `.purchased` result is not itself an entitlement decision. Always call `getCustomerInfo()`
and use the returned entitlement state to update premium UI.

## Customer information and entitlements

```swift
switch await EzyRevenue.shared.getCustomerInfo() {
case let .success(customerInfo):
    let isPremium = customerInfo.entitlementIsActive("premium")
    updatePremiumUI(isPremium)
case let .failure(error):
    showError(error)
}
```

Entitlement identifiers are configured for your app. `CustomerInfo` includes:

- `entitlements` — entitlement values keyed by identifier.
- `subscriptions` — subscription values keyed by product identifier.
- `activeSubscriptions` — subscription identifiers currently marked active.
- `requestDate` — the timestamp associated with the customer snapshot.
- `originalAppUserID` — the identity represented by the snapshot.

The SDK does not automatically refresh entitlement UI. Refresh customer information after a
purchase, when the app returns to the foreground, and whenever a premium-access decision is
needed.

### Restore purchases

`restorePurchases()` restores the user's existing StoreKit purchases without starting a new
charge and returns refreshed customer information:

```swift
switch await EzyRevenue.shared.restorePurchases() {
case let .success(customerInfo):
    updatePremiumUI(customerInfo.entitlementIsActive("premium"))
case let .failure(error):
    showError(error)
}
```

## Supported products and limitations

Supported:

- StoreKit subscriptions.
- StoreKit non-consumable products.
- Subscription introductory offers when available from the App Store.
- Purchase restoration and entitlement refresh.

Not currently supported:

- Consumable product purchases.
- Subscription upgrades, downgrades, or proration APIs.
- Paywall or subscription-management UI.
- Automatic background entitlement UI updates.
- More than one active purchase flow at a time.

## Public API reference

### `EzyRevenue`

`EzyRevenue` is an actor. The shared application-scoped instance is `EzyRevenue.shared`.

| Member | Purpose |
|---|---|
| `initialize(configuration:)` | Starts or restores the SDK session for the selected identity. |
| `logIn(appUserID:)` | Switches to a stable authenticated app user ID. |
| `getOfferings()` | Loads offerings and App Store pricing. |
| `getProducts()` | Loads the full product catalog and App Store pricing. |
| `getCustomerInfo()` | Loads current customer entitlements and subscriptions. |
| `purchasePackage(_:)` | Starts a purchase for an offering package. |
| `purchaseProduct(_:)` | Starts a purchase for a catalog product. |
| `restorePurchases()` | Restores owned purchases and returns refreshed customer information. |
| `logOut()` | Ends the active SDK session and clears SDK state. Call `initialize()` again afterward. |
| `isInitialized` | Indicates whether the SDK is ready for operations. |
| `appUserID` | Returns the active custom or anonymous user ID. |
| `offerings` | Returns the cached offerings snapshot. |
| `currentOffering` | Returns the cached current offering, if one is available. |
| `products` | Returns the cached product snapshot. |
| `customerInfo` | Returns the cached customer information snapshot. |
| `sdkVersion` | Returns the SDK version. |

### `EzyRevenueConfiguration`

| Field | Description |
|---|---|
| `apiKey: String` | Application key assigned for EzyRevenue. |
| `appUserID: String?` | Stable app user ID, or `nil` for anonymous use. |
| `logLevel: EzyRevenueLogLevel` | SDK logging threshold. Required during initialization. |
| `userCountryCode: String?` | Optional two-letter country code from account or storefront data. |
| `onLog: ((String) -> Void)?` | Optional callback for messages allowed by `logLevel`. |

Use named arguments when constructing the configuration so the identity choice is explicit.

### `EzyRevenueLogLevel`

Available levels are:

- `.none` — no SDK diagnostics.
- `.error` — errors only.
- `.warning` — warnings and errors.
- `.info` — informational messages, warnings, and errors.
- `.debug` — debug messages and higher-severity messages.
- `.verbose` — all available diagnostics.

Use `.none` in production unless diagnostic logging is required. Do not share logs that may
contain user or purchase-related information.

### `EzyRevenueResult`

The public result type is Swift's `Result` with `EzyRevenueError` as its failure type:

```swift
typealias EzyRevenueResult<Value> = Result<Value, EzyRevenueError>
```

### `EzyRevenueError`

| Error | Meaning |
|---|---|
| `.invalidConfiguration` | Input or configuration is invalid. |
| `.notInitialized` | `initialize()` has not completed successfully, or `logOut()` was called. |
| `.authentication` | The active session could not be authenticated. |
| `.network` | A service request could not complete. |
| `.invalidResponse` | A service response could not be interpreted. |
| `.billingUnavailable` | StoreKit is unavailable for the requested operation. |
| `.purchaseInProgress` | Another purchase is already active. |
| `.purchaseFailed` | StoreKit or SDK purchase processing failed. |
| `.unverifiedTransaction` | StoreKit could not verify the transaction. |
| `.backendRejected` | Purchase processing was rejected by the service. |
| `.internalError` | An unexpected SDK error occurred. |

## Public models

### `Offering`

- `identifier: String`
- `description: String?`
- `isDefault: Bool`
- `packages: [OfferingPackage]`

### `OfferingPackage`

- `identifier: String`
- `platformProductIdentifier: String?`
- `products: [Product]`

### `Product`

- `productID: String?`
- `identifier: String`
- `displayName: String`
- `type: ProductType`
- `storeStatus: ProductStatus`
- `productGroup: String?`
- `isActive: Bool`
- `price: Price?`
- `introductoryPrice: Price?`
- `isAvailableInAppStore: Bool`

`ProductType` includes `.subscription`, `.nonConsumable`, and `.unknown(String)`.
`ProductStatus` includes `.active`, `.approved`, `.inactive`, and `.unknown(String)`.

### `Price`

- `amountMicros: Int64`
- `currencyCode: String`
- `displayPrice: String?`

`amountMicros` uses integer micros. Prefer `displayPrice` for localized UI text.

### `CustomerInfo`

- `requestDate: Date?`
- `originalAppUserID: String?`
- `entitlements: [String: EntitlementInfo]`
- `subscriptions: [String: SubscriptionInfo]`
- `activeSubscriptions: Set<String>`
- `entitlementIsActive(_:) -> Bool`

`EntitlementInfo` provides `identifier`, `isActive`, `willRenew`, `expirationDate`,
`purchaseDate`, and `productIdentifier`.

`SubscriptionInfo` provides `productIdentifier`, `expirationDate`, `purchaseDate`, `periodType`,
`unsubscribeDetectedAt`, `status`, `isActive`, and `willRenew`.

## Threading and lifecycle

- `EzyRevenue` is an actor and serializes access to SDK state.
- Public operations are asynchronous and return typed results.
- Initialize once when the app starts, typically using application-level code.
- Re-initializing with a different identity updates the active SDK session.
- Call `logOut()` when the host user signs out, then initialize again for the next user.
- StoreKit transaction updates and unfinished transactions are handled by the SDK.
- The SDK does not retain view controllers or other UI objects.

## Testing

For local StoreKit testing:

1. Add a StoreKit Configuration file to the Xcode scheme.
2. Define subscription and non-consumable products with identifiers matching the catalog.
3. Initialize the SDK with a development configuration.
4. Exercise purchase, pending, cancellation, restoration, and entitlement refresh flows.

For App Store testing, use a Sandbox tester or a TestFlight build configured with the correct
products.

Run package tests from the repository root:

```bash
swift test
```

Do not commit private development credentials or signing configuration.

## Troubleshooting

### Products have no price

- Confirm the product is available in App Store Connect or the StoreKit Configuration file.
- Confirm product identifiers match the app's catalog configuration.
- Confirm the selected Xcode scheme uses the intended StoreKit Configuration file.
- Check `isAvailableInAppStore` before enabling a purchase action.

### A purchase dialog does not open

- Confirm the product was returned by `getOfferings()` or `getProducts()`.
- Confirm the product is active and supported.
- Confirm StoreKit is available on the device or simulator.
- Disable repeated actions while another purchase is active.

### The user completes payment but access is not visible

1. Call `getCustomerInfo()`.
2. If needed, call `restorePurchases()` and inspect the returned customer information.
3. Do not start a second purchase to resolve the issue.

### Entitlements do not update

Call `getCustomerInfo()` again after the service has had time to process the purchase. The SDK
does not infer entitlement state from local UI state.

### A request times out or there is no internet

The SDK returns `.network` after the 30-second backend request timeout or when there is no usable
connection. Show a retry action or retry from the app when connectivity is restored. Do not assume
a timeout means a purchase was not made; use `restorePurchases()` or `getCustomerInfo()` to
reconcile purchase and entitlement state.

## Security guidance

- Grant premium access only after checking the returned customer information.
- Do not rely on a locally stored premium flag as the source of truth.
- Use `.none` in production unless diagnostic logging is required.
- Do not share SDK logs containing user or purchase-related information.
- Keep private development credentials and signing configuration outside source control.

## Sample application

`Example/EzyRevenueSample` demonstrates initialization, catalog loading, localized prices,
purchases, restoration, customer information, logout, StoreKit Configuration testing, and
logging. It is intended for basic integration and manual StoreKit testing, not as a production
application architecture.
