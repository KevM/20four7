import XCTest
@testable import TwentyFourSeven

final class ChannelRankerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func test_playCountOnlyWhenNoWatchAndStaleRecency() {
        // lastPlayed 8 days ago -> recency 0, no watch -> score == playCount
        let lastPlayed = now.addingTimeInterval(-8 * 24 * 3600)
        let score = ChannelRanker.score(
            playCount: 5, watchSeconds: 0,
            lastPlayedDate: lastPlayed, dateAdded: lastPlayed, now: now)
        XCTAssertEqual(score, 5, accuracy: 0.0001)
    }

    func test_freshRecencyAddsFullBoost() {
        // lastPlayed == now -> full 10 recency, no watch
        let score = ChannelRanker.score(
            playCount: 0, watchSeconds: 0,
            lastPlayedDate: now, dateAdded: now, now: now)
        XCTAssertEqual(score, 10, accuracy: 0.0001)
    }

    func test_dwellBoostIsLogCompressed() {
        // 48h watched, stale recency (8 days) so only dwell shows.
        let stale = now.addingTimeInterval(-8 * 24 * 3600)
        let score = ChannelRanker.score(
            playCount: 0, watchSeconds: 48 * 3600,
            lastPlayedDate: stale, dateAdded: stale, now: now)
        // 4 * log2(1 + 48) ~= 22.46
        XCTAssertEqual(score, 4.0 * log2(49), accuracy: 0.0001)
    }

    func test_twoDayDwellBeatsManyTaps() {
        let stale = now.addingTimeInterval(-8 * 24 * 3600)
        let eagleCam = ChannelRanker.score(
            playCount: 1, watchSeconds: 48 * 3600,
            lastPlayedDate: stale, dateAdded: stale, now: now)
        let tappy = ChannelRanker.score(
            playCount: 9, watchSeconds: 0,
            lastPlayedDate: stale, dateAdded: stale, now: now)
        XCTAssertGreaterThan(eagleCam, tappy)
    }

    func test_dwellHasDiminishingReturns() {
        let stale = now.addingTimeInterval(-8 * 24 * 3600)
        let twoDays = ChannelRanker.score(
            playCount: 0, watchSeconds: 48 * 3600,
            lastPlayedDate: stale, dateAdded: stale, now: now)
        let eightDays = ChannelRanker.score(
            playCount: 0, watchSeconds: 192 * 3600,
            lastPlayedDate: stale, dateAdded: stale, now: now)
        // 4x the watch time past 2 days adds < 10 extra points.
        XCTAssertLessThan(eightDays - twoDays, 10)
    }

    func test_nilLastPlayedFallsBackToDateAdded() {
        let added = now.addingTimeInterval(-3.5 * 24 * 3600) // half the window
        let score = ChannelRanker.score(
            playCount: 0, watchSeconds: 0,
            lastPlayedDate: nil, dateAdded: added, now: now)
        XCTAssertEqual(score, 5, accuracy: 0.0001) // 10 * (1 - 0.5)
    }
}
