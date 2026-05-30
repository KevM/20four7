import XCTest
@testable import TwentyFourSeven

final class TagFilterTests: XCTestCase {
    private let channels = [
        Channel(id: "fire", title: "Fire", youTubeVideoID: "v1", source: .curated,
                isLiveExpected: true, tagIDs: ["fireplace"]),
        Channel(id: "rain", title: "Rain", youTubeVideoID: "v2", source: .curated,
                isLiveExpected: true, tagIDs: ["rain"]),
        Channel(id: "both", title: "Both", youTubeVideoID: "v3", source: .curated,
                isLiveExpected: true, tagIDs: ["fireplace", "lofi"]),
    ]

    func test_emptySelectionReturnsAll() {
        XCTAssertEqual(TagFilter.filter(channels, anyOf: []).count, 3)
    }

    func test_unionSemantics() {
        let result = TagFilter.filter(channels, anyOf: ["fireplace"])
        XCTAssertEqual(Set(result.map(\.id)), ["fire", "both"])
    }

    func test_multipleTagsUnion() {
        let result = TagFilter.filter(channels, anyOf: ["rain", "lofi"])
        XCTAssertEqual(Set(result.map(\.id)), ["rain", "both"])
    }
}
