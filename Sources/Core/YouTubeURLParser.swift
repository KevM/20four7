import Foundation

enum YouTubeReference: Equatable, Sendable {
    case video(id: String)
    case handle(String)
}

enum YouTubeURLParser {
    private static let idCharacters = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")

    static func parse(_ raw: String) -> YouTubeReference? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        // Bare handle: "@name"
        if input.hasPrefix("@") {
            let name = String(input.dropFirst())
            return name.isEmpty ? nil : .handle(name)
        }

        // Bare 11-char video id (no scheme, no slashes).
        if !input.contains("/"), isValidVideoID(input) {
            return .video(id: input)
        }

        guard let components = URLComponents(string: normalizedURLString(input)) else { return nil }
        let path = components.path

        // /watch?v=ID
        if let v = components.queryItems?.first(where: { $0.name == "v" })?.value,
           isValidVideoID(v) {
            return .video(id: v)
        }
        // youtu.be/ID  or  /live/ID  or  /embed/ID
        let segments = path.split(separator: "/").map(String.init)
        if let host = components.host, host.contains("youtu.be"),
           let id = segments.first, isValidVideoID(id) {
            return .video(id: id)
        }
        if let idx = segments.firstIndex(where: { $0 == "live" || $0 == "embed" }),
           idx + 1 < segments.count, isValidVideoID(segments[idx + 1]) {
            return .video(id: segments[idx + 1])
        }
        // /@handle
        if let handleSeg = segments.first(where: { $0.hasPrefix("@") }) {
            return .handle(String(handleSeg.dropFirst()))
        }
        return nil
    }

    private static func normalizedURLString(_ s: String) -> String {
        s.contains("://") ? s : "https://\(s)"
    }

    private static func isValidVideoID(_ s: String) -> Bool {
        s.count == 11 && s.unicodeScalars.allSatisfy { idCharacters.contains($0) }
    }
}
