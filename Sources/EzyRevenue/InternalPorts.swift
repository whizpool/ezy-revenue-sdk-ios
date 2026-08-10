/// Backend boundary used by the session, catalog, and purchase coordinators.
///
/// Endpoint requirements are added with the networking implementation so this
/// boundary does not grow speculative methods.
internal protocol EzyRevenueBackend: Sendable {}

/// Keychain-backed session boundary.
internal protocol SessionStore: Sendable {}

/// StoreKit boundary used by catalog and purchase flows.
internal protocol StoreKitGateway: Sendable {}
