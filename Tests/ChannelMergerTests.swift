import XCTest
@testable import TwentyFourSeven

final class ChannelMergerTests: XCTestCase {
    private func chan(_ id: String, video: String, source: ChannelSource) -> Channel {
        Channel(id: id, title: id, youTubeVideoID: video, source: source, isLiveExpected: true)
    }

    func test_mergesBothSources() {
        let merged = ChannelMerger.merge(
            curated: [chan("a", video: "v1", source: .curated)],
            user: [chan("b", video: "v2", source: .user)])
        XCTAssertEqual(Set(merged.map(\.id)), ["a", "b"])
    }

    func test_userWinsOnDuplicateVideoID() {
        let merged = ChannelMerger.merge(
            curated: [chan("a", video: "dup", source: .curated)],
            user: [chan("b", video: "dup", source: .user)])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.source, .user)
    }
}
