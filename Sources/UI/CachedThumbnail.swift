import SwiftUI
import ImageIO
import UIKit

/// In-memory cache of decoded, downsampled thumbnails. It's checked *synchronously*
/// at view init so a reappearing tile renders its image on the first frame — which
/// eliminates the placeholder flash you get from `AsyncImage`, which resets to its
/// empty phase every time the view is recreated (e.g. scrolling tiles in and out).
enum ThumbnailCache {
    // NSCache is documented thread-safe; the compiler can't see that.
    nonisolated(unsafe) static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 500
        return cache
    }()

    static func key(for url: URL, maxPixel: Int) -> NSString {
        "\(url.absoluteString)@\(maxPixel)" as NSString
    }
}

/// `UIImage` is immutable and safe to read across threads once created; this lets us
/// hand a downsampled image back from a detached task under Swift 6 concurrency.
private struct SendableImage: @unchecked Sendable {
    let image: UIImage
}

/// Drop-in thumbnail view: fills its frame, loads once, and serves repeat appearances
/// synchronously from `ThumbnailCache` so there's no flash back to the placeholder.
struct CachedThumbnail: View {
    private let url: URL?
    private let maxPixel: Int
    @State private var image: UIImage?

    /// Assume up to @3x. Sources (≤1280px) cap the result, so over-estimating scale on
    /// lower-DPI devices only avoids unnecessary downsampling — it never upscales.
    private static let assumedScale: CGFloat = 3

    /// - Parameter targetHeight: the tile's point height. The source is downsampled to
    ///   cover a 16:9 fill at this height, bounding the bitmap we keep in memory.
    init(url: URL?, targetHeight: CGFloat) {
        self.url = url
        self.maxPixel = max(1, Int((targetHeight * 16.0 / 9.0 * Self.assumedScale).rounded()))
        if let url {
            _image = State(initialValue: ThumbnailCache.shared.object(forKey: ThumbnailCache.key(for: url, maxPixel: maxPixel)))
        }
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.08)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard image == nil, let url else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        if Task.isCancelled { return }

        let maxPixel = self.maxPixel
        // Decode/downsample off the main actor; return a boxed image we can store.
        let boxed = await Task.detached(priority: .utility) {
            downsample(data: data, maxPixel: maxPixel).map(SendableImage.init)
        }.value

        guard let boxed, !Task.isCancelled else { return }
        ThumbnailCache.shared.setObject(boxed.image, forKey: ThumbnailCache.key(for: url, maxPixel: maxPixel))
        image = boxed.image
    }
}

/// Decodes `data` directly to a thumbnail no larger than `maxPixel` on its longest
/// edge, so the full-resolution bitmap is never realized in memory.
private func downsample(data: Data, maxPixel: Int) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(
        data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary
    ) else {
        return nil
    }
    let options = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ] as CFDictionary
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
        return nil
    }
    return UIImage(cgImage: cgImage)
}
