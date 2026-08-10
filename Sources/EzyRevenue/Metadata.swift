import Foundation
import StoreKit

/// Metadata attached to backend requests.
internal struct RequestMetadata: Equatable, Sendable {
    let sdkVersion: String
    let appVersion: String?
    let deviceLocale: String?
    let platformVersion: String?
    let userCountry: String?
    let storefront: String?

    /// Country preferred for catalog and offerings behavior.
    var preferredCountryCode: String? {
        storefront ?? userCountry
    }
}

/// Collects request metadata without introducing another dependency boundary.
internal enum MetadataProvider {
    /// Collects live host/device/storefront values.
    static func current(userCountryCode: String? = nil) async -> RequestMetadata {
        let storefrontCountryCode: String?
        if #available(macOS 12.0, iOS 15.0, *) {
            storefrontCountryCode = await Storefront.current?.countryCode
        } else {
            storefrontCountryCode = nil
        }
        let operatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
        return make(
            sdkVersion: EzyRevenue.sdkVersion,
            appVersion: readAppVersion(),
            localeIdentifier: Locale.current.identifier,
            platformVersion: formatPlatformVersion(operatingSystemVersion),
            userCountryCode: userCountryCode,
            storefrontCountryCode: storefrontCountryCode
        )
    }

    /// Builds deterministic metadata for unit tests and future adapters.
    static func make(
        sdkVersion: String,
        appVersion: String?,
        localeIdentifier: String?,
        platformVersion: String?,
        userCountryCode: String?,
        storefrontCountryCode: String?
    ) -> RequestMetadata {
        RequestMetadata(
            sdkVersion: sdkVersion,
            appVersion: appVersion?.nonBlank,
            deviceLocale: normalizeLocale(localeIdentifier),
            platformVersion: platformVersion?.nonBlank,
            userCountry: normalizeCountryCode(userCountryCode),
            storefront: normalizeCountryCode(storefrontCountryCode)
        )
    }

    static func formatPlatformVersion(_ version: OperatingSystemVersion) -> String {
        var result = "iOS \(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 {
            result += ".\(version.patchVersion)"
        }
        return result
    }

    static func normalizeLocale(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let baseIdentifier = identifier
            .split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        let normalized = baseIdentifier.replacingOccurrences(of: "_", with: "-")
        return normalized.nonBlank
    }

    static func normalizeCountryCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 2,
              trimmed.unicodeScalars.allSatisfy({ scalar in
                  (65...90).contains(scalar.value) ||
                      (97...122).contains(scalar.value)
              }) else {
            return nil
        }
        return trimmed.uppercased()
    }

    private static func readAppVersion() -> String? {
        let keys = ["CFBundleShortVersionString", "CFBundleVersion"]
        for key in keys {
            if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
               let version = value.nonBlank {
                return version
            }
        }
        return nil
    }
}

private extension String {
    var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
