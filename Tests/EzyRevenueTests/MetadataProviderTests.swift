import Foundation
import XCTest
@testable import EzyRevenue

final class MetadataProviderTests: XCTestCase {
    func testMetadataNormalizesLocaleAndCountryAndPrefersStorefront() {
        let metadata = MetadataProvider.make(
            sdkVersion: "1.0.0",
            appVersion: "2.4.1",
            localeIdentifier: "en_US@calendar=gregorian",
            platformVersion: "iOS 17.5",
            userCountryCode: "gb",
            storefrontCountryCode: "us"
        )

        XCTAssertEqual(metadata.sdkVersion, "1.0.0")
        XCTAssertEqual(metadata.appVersion, "2.4.1")
        XCTAssertEqual(metadata.deviceLocale, "en-US")
        XCTAssertEqual(metadata.platformVersion, "iOS 17.5")
        XCTAssertEqual(metadata.userCountry, "GB")
        XCTAssertEqual(metadata.storefront, "US")
        XCTAssertEqual(metadata.preferredCountryCode, "US")
    }

    func testCountryFallbackIsUsedWhenStorefrontIsUnavailable() {
        let metadata = MetadataProvider.make(
            sdkVersion: "1.0.0",
            appVersion: nil,
            localeIdentifier: "fr_FR",
            platformVersion: nil,
            userCountryCode: "ca",
            storefrontCountryCode: nil
        )

        XCTAssertEqual(metadata.deviceLocale, "fr-FR")
        XCTAssertNil(metadata.appVersion)
        XCTAssertNil(metadata.platformVersion)
        XCTAssertEqual(metadata.preferredCountryCode, "CA")
    }

    func testInvalidCountryValuesAreOmitted() {
        let metadata = MetadataProvider.make(
            sdkVersion: "1.0.0",
            appVersion: " ",
            localeIdentifier: " ",
            platformVersion: " ",
            userCountryCode: "USA",
            storefrontCountryCode: "?"
        )

        XCTAssertNil(metadata.appVersion)
        XCTAssertNil(metadata.deviceLocale)
        XCTAssertNil(metadata.platformVersion)
        XCTAssertNil(metadata.userCountry)
        XCTAssertNil(metadata.storefront)
        XCTAssertNil(metadata.preferredCountryCode)
    }

    func testPlatformVersionFormattingIsDeterministic() {
        XCTAssertEqual(
            MetadataProvider.formatPlatformVersion(
                OperatingSystemVersion(majorVersion: 17, minorVersion: 5, patchVersion: 0)
            ),
            "iOS 17.5"
        )
        XCTAssertEqual(
            MetadataProvider.formatPlatformVersion(
                OperatingSystemVersion(majorVersion: 17, minorVersion: 5, patchVersion: 1)
            ),
            "iOS 17.5.1"
        )
    }
}
