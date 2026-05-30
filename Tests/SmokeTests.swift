import XCTest
@testable import Televista

final class SmokeTests: XCTestCase {
    func test_configHasManifestBase() {
        XCTAssertEqual(Config.supportedSchemaVersion, 1)
        XCTAssertFalse(Config.catalogBaseURL.absoluteString.isEmpty)
    }
}
