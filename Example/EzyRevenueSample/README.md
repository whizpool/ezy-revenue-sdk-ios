# EzyRevenueSample

Small SwiftUI host app for the local `EzyRevenue` package.

- Bundle identifier: `com.whizpool.ezyrevenue.sample`
- Deployment target: iOS 15+
- StoreKit Configuration: `StoreKitConfiguration.storekit`
- SDK logging is selected once during initialization (`.verbose` in this diagnostic sample).
- The API key may be supplied through an xcconfig; the sample also contains its development fallback.

## Local configuration

Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and provide a development API key. The local file is gitignored. The tracked `Config/Default.xcconfig` supplies empty safe defaults for clean checkouts.

In Xcode, select the `EzyRevenueSample` scheme and run with `StoreKitConfiguration.storekit` as the StoreKit Configuration file. Initialize the SDK first, then load offerings and products; the sample creates one subscription button per backend package. The screen also demonstrates localized package prices, customer information, restore, logout, an expandable API request/response panel, and diagnostic logs.

## Sandbox/TestFlight

For real App Store testing, register the bundle identifier and products in App Store Connect, use a Sandbox tester or TestFlight build, and configure the production API key through a private xcconfig. The backend `CustomerInfo` response is the only source used by the sample to display entitlement state. Each subscription may expose `status` as `ACTIVE`, `EXPIRED`, or `nil`; `ACTIVE` means active, `EXPIRED` means expired, and `nil` means the SDK falls back to the subscription expiry date for `isActive`.
