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

    func test_favsTagMetadata() {
        XCTAssertEqual(Tag.favsID, "favs")
        XCTAssertEqual(Tag.favs.id, "favs")
        XCTAssertEqual(Tag.favs.name, "Favorites")
        XCTAssertEqual(Tag.favs.symbol, "star.fill")
        XCTAssertEqual(Tag.favs.kind, .derived)
    }

    func test_favsBehavesAsNormalTagInFilter() {
        let favChannels = [
            Channel(id: "f", title: "Fav", youTubeVideoID: "v9", source: .curated,
                    isLiveExpected: true, tagIDs: [Tag.favsID]),
            Channel(id: "x", title: "Other", youTubeVideoID: "v8", source: .curated,
                    isLiveExpected: true, tagIDs: ["rain"]),
        ]
        let result = TagFilter.filter(favChannels, anyOf: [Tag.favsID])
        XCTAssertEqual(Set(result.map(\.id)), ["f"])
    }
}
