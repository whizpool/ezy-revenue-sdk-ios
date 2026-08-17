import XCTest
@testable import EzyRevenue

final class EzyRevenuePackageTests: XCTestCase {
    func testPackageExposesSDKVersion() {
        XCTAssertEqual(EzyRevenue.sdkVersion, "1.0.1")
    }
}
