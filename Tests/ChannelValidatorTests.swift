import XCTest
@testable import Televista

final class ChannelValidatorTests: XCTestCase {
    func test_rejectsUnparseableInput() {
        let result = ChannelValidator.parseReference("just some text")
        XCTAssertNil(result)
    }
    func test_acceptsVideoURL() {
        let result = ChannelValidator.parseReference("https://youtu.be/jfKfPfyJRdk")
        XCTAssertEqual(result, .video(id: "jfKfPfyJRdk"))
    }
    func test_buildsChannelFromVideoReference() {
        let channel = ChannelValidator.makeUserChannel(
            from: .video(id: "jfKfPfyJRdk"), title: "Lofi", tagIDs: ["lofi"], now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(channel?.youTubeVideoID, "jfKfPfyJRdk")
        XCTAssertEqual(channel?.source, .user)
        XCTAssertEqual(channel?.tagIDs, ["lofi"])
    }
    func test_handleReferenceCannotBecomeChannelDirectly() {
        // Handles need resolution to a video id; not supported offline in #1.
        let channel = ChannelValidator.makeUserChannel(
            from: .handle("LofiGirl"), title: "Lofi", tagIDs: [], now: Date())
        XCTAssertNil(channel)
    }
}
