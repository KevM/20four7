import XCTest
@testable import Televista

final class YouTubeURLParserTests: XCTestCase {
    func test_parsesWatchURL() {
        XCTAssertEqual(YouTubeURLParser.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
                       .video(id: "dQw4w9WgXcQ"))
    }
    func test_parsesShortURL() {
        XCTAssertEqual(YouTubeURLParser.parse("https://youtu.be/dQw4w9WgXcQ?t=10"),
                       .video(id: "dQw4w9WgXcQ"))
    }
    func test_parsesLiveURL() {
        XCTAssertEqual(YouTubeURLParser.parse("https://www.youtube.com/live/dQw4w9WgXcQ"),
                       .video(id: "dQw4w9WgXcQ"))
    }
    func test_parsesBareID() {
        XCTAssertEqual(YouTubeURLParser.parse("dQw4w9WgXcQ"), .video(id: "dQw4w9WgXcQ"))
    }
    func test_parsesHandle() {
        XCTAssertEqual(YouTubeURLParser.parse("@LofiGirl"), .handle("LofiGirl"))
        XCTAssertEqual(YouTubeURLParser.parse("https://www.youtube.com/@LofiGirl"),
                       .handle("LofiGirl"))
    }
    func test_rejectsGarbage() {
        XCTAssertNil(YouTubeURLParser.parse("not a youtube link"))
        XCTAssertNil(YouTubeURLParser.parse(""))
    }
}
