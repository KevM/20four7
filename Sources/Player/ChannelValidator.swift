import Foundation

enum VideoValidationError: Error, LocalizedError {
    case embeddingDisallowed
    case notFoundOrInvalid
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .embeddingDisallowed:
            return "This video cannot be embedded. The owner has disabled embedding for external apps."
        case .notFoundOrInvalid:
            return "This video could not be found or is private/invalid."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

/// Add-time validation for user channels. Parsing + channel construction are pure
/// and unit-tested; embeddability is verified live by attempting to load in the
/// player (the UI surfaces `embeddingDisallowed` if YouTube rejects it).
enum ChannelValidator {
    static func parseReference(_ input: String) -> YouTubeReference? {
        YouTubeURLParser.parse(input)
    }

    /// Builds a `.user` channel from a video reference. Handles are not directly
    /// playable in sub-project #1 (they require API resolution to a video id).
    static func makeUserChannel(from reference: YouTubeReference, title: String,
                                tagIDs: [String], now: Date) -> Channel? {
        guard case let .video(id) = reference else { return nil }
        let resolvedTitle = title.trimmingCharacters(in: .whitespaces)
        return Channel(
            id: "user-\(id)",
            title: resolvedTitle.isEmpty ? "Untitled" : resolvedTitle,
            youTubeVideoID: id,
            source: .user,
            isLiveExpected: true,
            dateAdded: now,
            tagIDs: tagIDs
        )
    }

    /// Validates YouTube video embeddability by checking the oEmbed endpoint.
    /// Returns the video's title if successful, or a specific validation error.
    static func validateVideoEmbeddability(
        videoID: String,
        session: URLSession = .shared
    ) async -> Result<String, VideoValidationError> {
        let urlString = "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoID)&format=json"
        guard let url = URL(string: urlString) else {
            return .failure(.notFoundOrInvalid)
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.notFoundOrInvalid)
            }

            if httpResponse.statusCode == 200 {
                struct YouTubeOEmbed: Codable {
                    let title: String
                }
                let oembed = try JSONDecoder().decode(YouTubeOEmbed.self, from: data)
                return .success(oembed.title)
            } else if httpResponse.statusCode == 401 {
                return .failure(.embeddingDisallowed)
            } else {
                return .failure(.notFoundOrInvalid)
            }
        } catch {
            return .failure(.networkError(error))
        }
    }
}

