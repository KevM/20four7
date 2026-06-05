import XCTest
@testable import TwentyFourSeven

final class ChannelSearchTests: XCTestCase {
    private let tagsByID: [String: Tag] = [
        "nature": Tag(id: "nature", name: "Nature", symbol: "leaf", kind: .editorial),
        "lofi": Tag(id: "lofi", name: "Lofi", symbol: "music.note", kind: .editorial),
        "café": Tag(id: "café", name: "Café Music", symbol: "cup.and.saucer", kind: .user)
    ]

    private var channels: [Channel] {
        [
            Channel(id: "c1", title: "Forest Sounds", youTubeVideoID: "v1", source: .curated,
                    isLiveExpected: true, tagIDs: ["nature"]),
            Channel(id: "c2", title: "Study Beats", youTubeVideoID: "v2", source: .curated,
                    isLiveExpected: true, tagIDs: ["lofi"]),
            Channel(id: "c3", title: "Café Ambient", youTubeVideoID: "v3", source: .curated,
                    isLiveExpected: true, tagIDs: ["café"]),
            Channel(id: "c4", title: "Rainy Afternoon", youTubeVideoID: "v4", source: .curated,
                    isLiveExpected: true, tagIDs: ["nature", "lofi"])
        ]
    }

    /// IDs of channels that match (non-nil score), order-independent.
    private func matches(_ query: String) -> Set<String> {
        Set(channels.compactMap { ChannelSearch.score($0, query: query, tagsByID: tagsByID) != nil ? $0.id : nil })
    }

    private func channel(_ title: String, tagIDs: [String] = []) -> Channel {
        Channel(id: title, title: title, youTubeVideoID: "vid",
                source: .curated, isLiveExpected: true, tagIDs: tagIDs)
    }

    func test_emptyOrWhitespaceQueryMatchesAll() {
        XCTAssertEqual(matches(""), ["c1", "c2", "c3", "c4"])
        XCTAssertEqual(matches("   \n  "), ["c1", "c2", "c3", "c4"])
    }

    func test_titleSubstringMatch() {
        XCTAssertEqual(matches("Forest"), ["c1"])
        XCTAssertEqual(matches("Rainy"), ["c4"])
        XCTAssertEqual(matches("Ambient"), ["c3"])
    }

    func test_tagNameMatch() {
        XCTAssertEqual(matches("Nature"), ["c1", "c4"])
        XCTAssertEqual(matches("Lofi"), ["c2", "c4"])
    }

    func test_caseAndDiacriticInsensitivity() {
        XCTAssertEqual(matches("cafe"), ["c3"])
        XCTAssertEqual(matches("CAFÉ"), ["c3"])
        XCTAssertEqual(matches("forest"), ["c1"])
    }

    // MARK: - Multi-token (AND across tokens, OR across fields)

    func test_multiTokenMatchesAcrossNonAdjacentWords() {
        // "Norway Rail" never occurs literally, but each token is a contiguous
        // substring of a different word ("Norway's", "Railway").
        let ch = channel("The Best Of Norway's Railway SPRING and SUMMER Cab Views")
        XCTAssertNotNil(ChannelSearch.score(ch, query: "Norway Rail", tagsByID: [:]))
    }

    func test_multiTokenRequiresEveryToken() {
        let ch = channel("Norway Railway Cab View")
        XCTAssertNil(ChannelSearch.score(ch, query: "Norway lofi", tagsByID: [:]))
    }

    func test_multiTokenMatchesAcrossTitleAndTag() {
        // "Rainy" matches the title; "Nature" matches the tag name.
        XCTAssertEqual(matches("Rainy Nature"), ["c4"])
    }

    // MARK: - Fuzzy tiers

    func test_subsequenceAbbreviationMatches() {
        let norway = channel("Norway")
        XCTAssertNotNil(ChannelSearch.score(norway, query: "nrwy", tagsByID: [:]))
        XCTAssertNotNil(ChannelSearch.score(norway, query: "noway", tagsByID: [:]))
    }

    func test_typoToleranceMatchesTransposition() {
        // "norwya" is not a subsequence of "norway" (order breaks), so this
        // exercises the edit-distance tier.
        let norway = channel("Norway")
        XCTAssertNotNil(ChannelSearch.score(norway, query: "norwya", tagsByID: [:]))
    }

    func test_shortTokensGetNoTypoTolerance() {
        // "bat" is edit-distance 1 from "Cat" but is not a subsequence of it, and
        // 3-char tokens get a typo budget of 0 — so it must not match.
        XCTAssertNil(ChannelSearch.score(channel("Cat"), query: "bat", tagsByID: [:]))
        // A 4-char token does earn typo tolerance: "raon" -> "Rain" (one substitution).
        XCTAssertNotNil(ChannelSearch.score(channel("Rain"), query: "raon", tagsByID: [:]))
    }

    // MARK: - Ranking (score ordering)

    func test_exactOutranksLooseSubsequence() {
        let exact = channel("Rain")
        let loose = channel("Relaxing And Intense") // r-a-i-n as a scattered subsequence
        let exactScore = ChannelSearch.score(exact, query: "rain", tagsByID: [:])
        let looseScore = ChannelSearch.score(loose, query: "rain", tagsByID: [:])
        XCTAssertNotNil(exactScore)
        if let looseScore {
            XCTAssertGreaterThan(exactScore!, looseScore)
        }
    }

    func test_titleMatchesOutrankEquivalentTagMatches() {
        // Identical-quality (whole-field exact) match in each field; the title's
        // higher field weight must win. Guards the field-weighting structure that
        // a future low-weight `description` field will rely on.
        let tags = ["zen": Tag(id: "zen", name: "Zen", kind: .editorial)]
        let titleHit = channel("Zen")
        let tagHit = Channel(id: "t", title: "Quiet Stream", youTubeVideoID: "vid",
                             source: .curated, isLiveExpected: true, tagIDs: ["zen"])
        let titleScore = ChannelSearch.score(titleHit, query: "zen", tagsByID: tags)!
        let tagScore = ChannelSearch.score(tagHit, query: "zen", tagsByID: tags)!
        XCTAssertGreaterThan(titleScore, tagScore)
    }

    func test_tighterSubsequenceOutranksLooser() {
        let tight = channel("Norway")               // "nrwy" packed into 6 chars
        let loose = channel("New Orleans Riverway")  // same letters, sprawled out
        let tightScore = ChannelSearch.score(tight, query: "nrwy", tagsByID: [:])
        let looseScore = ChannelSearch.score(loose, query: "nrwy", tagsByID: [:])
        XCTAssertNotNil(tightScore)
        if let looseScore {
            XCTAssertGreaterThan(tightScore!, looseScore)
        }
    }
}
