import XCTest
@testable import Televista

final class SurferTests: XCTestCase {
    private let list = ["a", "b", "c"].map {
        Channel(id: $0, title: $0, youTubeVideoID: "v\($0)", source: .curated, isLiveExpected: true)
    }

    func test_next() {
        XCTAssertEqual(Surfer.channel(after: "a", in: list, direction: .next)?.id, "b")
    }
    func test_nextWrapsAround() {
        XCTAssertEqual(Surfer.channel(after: "c", in: list, direction: .next)?.id, "a")
    }
    func test_previousWrapsAround() {
        XCTAssertEqual(Surfer.channel(after: "a", in: list, direction: .previous)?.id, "c")
    }
    func test_unknownCurrentReturnsFirst() {
        XCTAssertEqual(Surfer.channel(after: "zzz", in: list, direction: .next)?.id, "a")
    }
    func test_emptyListReturnsNil() {
        XCTAssertNil(Surfer.channel(after: "a", in: [], direction: .next))
    }
}
