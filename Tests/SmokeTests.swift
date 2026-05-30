import XCTest
@testable import TwentyFourSeven

final class SmokeTests: XCTestCase {
    func test_configHasManifestBase() {
        XCTAssertEqual(Config.supportedSchemaVersion, 1)
        XCTAssertFalse(Config.catalogBaseURL.absoluteString.isEmpty)
    }
}
