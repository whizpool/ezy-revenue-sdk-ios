import CommonCrypto
import Foundation

/// Stable project identifier used for session scoping without retaining the API key.
internal enum APIKeyFingerprint {
    static func make(_ apiKey: String) -> String {
        let data = Data(apiKey.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(
                buffer.baseAddress,
                CC_LONG(buffer.count),
                &digest
            )
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
