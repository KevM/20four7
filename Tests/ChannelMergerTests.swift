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

    func test_appliesUserStateOverrides() {
        let channel = chan("a", video: "v1", source: .curated)
        let state = ChannelUserState(
            channelID: "a",
            isLiveExpectedOverride: false,
            customTitle: "Override Title"
        )
        
        let merged = ChannelMerger.merge(curated: [channel], user: [], userStates: [state])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.title, "Override Title")
        XCTAssertEqual(merged.first?.isLiveExpected, false)
    }

    func test_filtersHiddenChannels() {
        let c1 = chan("a", video: "v1", source: .curated)
        let c2 = chan("b", video: "v2", source: .curated)
        let state = ChannelUserState(channelID: "b", isHidden: true)
        
        let merged = ChannelMerger.merge(curated: [c1, c2], user: [], userStates: [state])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.id, "a")
    }

    func test_injectsFavsTagWhenFavorited() {
        let channel = chan("a", video: "v1", source: .curated)
        let state = ChannelUserState(channelID: "a", isFavorite: true)
        let merged = ChannelMerger.merge(curated: [channel], user: [], userStates: [state])
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged.first!.tagIDs.contains(Tag.favsID))
    }

    func test_noFavsTagWhenNotFavorited() {
        let channel = chan("a", video: "v1", source: .curated)
        let merged = ChannelMerger.merge(curated: [channel], user: [])
        XCTAssertFalse(merged.first!.tagIDs.contains(Tag.favsID))
    }

    func test_favsTagNotDuplicated() {
        let channel = chan("a", video: "v1", source: .curated)
        let state = ChannelUserState(channelID: "a", isFavorite: true)
        let merged = ChannelMerger.merge(curated: [channel], user: [], userStates: [state])
        XCTAssertEqual(merged.first!.tagIDs.filter { $0 == Tag.favsID }.count, 1)
    }
}
