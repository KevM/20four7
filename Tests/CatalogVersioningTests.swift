import XCTest
@testable import TwentyFourSeven

final class CatalogVersioningTests: XCTestCase {
    func test_updatesWhenRemoteNewer() {
        XCTAssertTrue(CatalogVersioning.shouldUpdate(cached: 6, remote: 7))
    }
    func test_doesNotUpdateWhenSameOrOlder() {
        XCTAssertFalse(CatalogVersioning.shouldUpdate(cached: 7, remote: 7))
        XCTAssertFalse(CatalogVersioning.shouldUpdate(cached: 8, remote: 7))
    }
    func test_updatesWhenNothingCached() {
        XCTAssertTrue(CatalogVersioning.shouldUpdate(cached: nil, remote: 1))
    }
    func test_appVersionGate() {
        XCTAssertTrue(CatalogVersioning.appSatisfies(minVersion: "1.0.0", appVersion: "1.2.0"))
        XCTAssertTrue(CatalogVersioning.appSatisfies(minVersion: nil, appVersion: "1.0.0"))
        XCTAssertFalse(CatalogVersioning.appSatisfies(minVersion: "2.0.0", appVersion: "1.9.9"))
    }
}
