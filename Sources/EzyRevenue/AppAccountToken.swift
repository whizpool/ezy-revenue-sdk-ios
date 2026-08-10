import CommonCrypto
import Foundation

/// Creates the deterministic, one-way UUID passed to StoreKit as an account
/// token. The raw EzyRevenue app user ID is never placed in StoreKit metadata.
internal enum AppAccountToken {
    static func make(appUserID: String) -> UUID {
        let input = Data("com.whizpool.ezyrevenue.app-account-token:\(appUserID)".utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        input.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &digest)
        }

        // RFC 4122-compatible version/variant bits make the deterministic
        // digest a valid UUID accepted by StoreKit.
        digest[6] = (digest[6] & 0x0f) | 0x50
        digest[8] = (digest[8] & 0x3f) | 0x80
        let hex = digest.map { String(format: "%02x", $0) }
        let uuidString = [
            hex[0..<4].joined(),
            hex[4..<6].joined(),
            hex[6..<8].joined(),
            hex[8..<10].joined(),
            hex[10..<16].joined(),
        ].joined(separator: "-")
        return UUID(uuidString: uuidString)!
    }
}
