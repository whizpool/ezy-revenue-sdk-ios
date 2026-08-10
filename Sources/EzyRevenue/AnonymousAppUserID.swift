import Foundation

/// Generates the persistent anonymous identity used when the host omits one.
internal enum AnonymousAppUserID {
    static let prefix = "$RCAnonymousID:"

    static func generate() -> String {
        prefix + UUID().uuidString.lowercased()
    }

    static func isAnonymous(_ appUserID: String) -> Bool {
        appUserID.hasPrefix(prefix)
    }
}
