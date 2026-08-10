import Foundation

/// Reads the locally available App Store receipt without making receipt data
/// a public SDK model or a persisted credential.
internal enum AppReceiptProvider {
    static func base64Receipt() -> String? {
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              let data = try? Data(contentsOf: receiptURL),
              !data.isEmpty else {
            return nil
        }
        return data.base64EncodedString()
    }
}
