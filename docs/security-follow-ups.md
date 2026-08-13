# Security Follow-ups

## StoreKit transaction identity binding

**Status:** Deferred while the SDK is pre-release and not serving live applications.

**Production gate:** Resolve and test this item before enabling production purchases.

### Potential scenario

1. User A starts a StoreKit purchase.
2. User A logs out or the host switches the SDK to User B before StoreKit reports completion.
3. Logout invalidates the SDK session generation and cancels the current SDK transaction listener, but it cannot cancel Apple's StoreKit purchase flow.
4. StoreKit may retain the completed transaction as an unfinished or queued transaction.
5. A later transaction listener or recovery pass runs while User B is active.
6. Without an identity-binding check, the SDK could submit User A's transaction proof with User B's EzyRevenue `appUserID`.

This is a potential race condition identified during pre-release review, not a confirmed production exploit.

### Existing identity signal

For purchases initiated by this SDK, `AppAccountToken.make(appUserID:)` derives a deterministic UUID from the active EzyRevenue app user ID. The UUID is passed to StoreKit using `Product.PurchaseOption.appAccountToken`. StoreKit records that value in the signed transaction.

The current transaction wrapper retains the transaction ID, product ID, JWS representation, and raw StoreKit transaction handle, but the recovery path does not explicitly compare the transaction's `appAccountToken` with the token expected for the active SDK user.

### Required remediation

Before production launch:

- Carry the StoreKit transaction `appAccountToken` through the internal verified-transaction model.
- Before automatically submitting a transaction, compare it with `AppAccountToken.make(appUserID:)` for the captured active session.
- Do not submit or finish a mismatched transaction under the active user.
- Define handling for transactions without an app-account token, including legacy purchases and explicit restore behavior.
- Ensure queued transaction updates cannot bypass the same identity check after logout or login.
- Require the backend to verify the signed StoreKit JWS/receipt and enforce the same app-account-token-to-user binding rather than trusting the request `appUserId` alone.
- Preserve transaction ID replay and idempotency protection on the backend.

### Required regression coverage

Add tests for:

- A purchase initiated by User A that completes after switching to User B.
- A queued update delivered after logout and reinitialization.
- An unfinished transaction recovered under a mismatched user.
- A matching transaction that is submitted and finished normally.
- A mismatched transaction that is neither submitted nor finished.
- A transaction without an app-account token under the documented legacy/restore policy.

### Relevant implementation files

- `Sources/EzyRevenue/AppAccountToken.swift`
- `Sources/EzyRevenue/PurchaseCoordinator.swift`
- `Sources/EzyRevenue/StoreKitGateway.swift`
- `Sources/EzyRevenue/SessionCoordinator.swift`
