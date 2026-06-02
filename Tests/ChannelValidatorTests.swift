import XCTest
@testable import TwentyFourSeven

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

    func test_validateVideoEmbeddability_success() async {
        let session = makeMockSession()
        let expectedTitle = "My Amazing Video"
        let jsonString = "{\"title\": \"\(expectedTitle)\"}"
        let data = jsonString.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        let result = await ChannelValidator.validateVideoEmbeddability(videoID: "123", session: session)
        switch result {
        case .success(let title):
            XCTAssertEqual(title, expectedTitle)
        case .failure(let error):
            XCTFail("Expected success, but got: \(error)")
        }
    }

    func test_validateVideoEmbeddability_embeddingDisallowed() async {
        let session = makeMockSession()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let result = await ChannelValidator.validateVideoEmbeddability(videoID: "123", session: session)
        switch result {
        case .success(let title):
            XCTFail("Expected failure, but got success with title: \(title)")
        case .failure(let error):
            if case .embeddingDisallowed = error {
                // Passed!
            } else {
                XCTFail("Expected .embeddingDisallowed error, got \(error)")
            }
        }
    }

    func test_validateVideoEmbeddability_notFoundOrInvalid() async {
        let session = makeMockSession()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let result = await ChannelValidator.validateVideoEmbeddability(videoID: "123", session: session)
        switch result {
        case .success(let title):
            XCTFail("Expected failure, but got success with title: \(title)")
        case .failure(let error):
            if case .notFoundOrInvalid = error {
                // Passed!
            } else {
                XCTFail("Expected .notFoundOrInvalid error, got \(error)")
            }
        }
    }

    func test_validateVideoEmbeddability_networkError() async {
        let session = makeMockSession()
        struct DummyError: Error {}
        MockURLProtocol.requestHandler = { _ in
            throw DummyError()
        }

        let result = await ChannelValidator.validateVideoEmbeddability(videoID: "123", session: session)
        switch result {
        case .success(let title):
            XCTFail("Expected failure, but got success with title: \(title)")
        case .failure(let error):
            if case .networkError = error {
                // Passed!
            } else {
                XCTFail("Expected .networkError, got \(error)")
            }
        }
    }

    // MARK: - Error Retryability

    func test_isRetryable_embeddingDisallowedIsHardStop() {
        // The owner permanently disabled embedding; retrying can't change that.
        XCTAssertFalse(VideoValidationError.embeddingDisallowed.isRetryable)
    }

    func test_isRetryable_networkErrorIsRetryable() {
        struct DummyError: Error {}
        XCTAssertTrue(VideoValidationError.networkError(DummyError()).isRetryable)
    }

    func test_isRetryable_notFoundOrInvalidIsRetryable() {
        // Ambiguous: a transient non-200 blip is indistinguishable from a genuinely
        // private video, so the user is allowed to retry.
        XCTAssertTrue(VideoValidationError.notFoundOrInvalid.isRetryable)
    }

    // MARK: - Mock Helpers

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

