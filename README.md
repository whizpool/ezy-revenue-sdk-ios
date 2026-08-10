# EzyRevenue iOS SDK

Lean Swift Package Manager SDK for EzyRevenue subscriptions and entitlements.

## Requirements

- iOS 15+
- Swift concurrency and StoreKit 2
- Backend API key configured by the host app

## Usage

```swift
import EzyRevenue

let result = await EzyRevenue.shared.initialize(
    configuration: EzyRevenueConfiguration(
        apiKey: "your-api-key",
        logLevel: .none
    )
)

if case .success = result {
    let offerings = await EzyRevenue.shared.getOfferings()
    let customerInfo = await EzyRevenue.shared.getCustomerInfo()
}
```

Select logging once during initialization. Use `.none` for silent operation. The SDK persists identity/session state in Keychain, submits verified StoreKit transactions to the backend before finishing them, and treats backend `CustomerInfo` as the entitlement authority.

The package uses the fixed production backend host defined by the SDK contract. It does not expose a paywall UI, analytics, consumables, or a custom durable transaction queue.

## Sample app

`Example/EzyRevenueSample` demonstrates initialization, catalog loading, localized prices, purchases, restore, customer information, logout, StoreKit Configuration testing, and diagnostic logging. Copy `Config/Local.xcconfig.example` to the ignored `Config/Local.xcconfig` for local credentials.

See `docs/ios-sdk-cross-platform-contract.md` for the exact backend and StoreKit receipt contract.
