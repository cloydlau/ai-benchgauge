import AppKit

/// App resources are immutable; provider images are keyed by their contents so
/// a refreshed logo still replaces the previous one. Keep the decoded images
/// across recycled table cells without retaining an unbounded image history.
@MainActor
final class ModelLogoImageCache {
    static let shared = ModelLogoImageCache(resourceURL: Bundle.main.resourceURL)

    private final class BundledImage {
        let image: NSImage?
        init(_ image: NSImage?) { self.image = image }
    }

    private let resourceURL: URL?
    private let bundled = NSCache<NSString, BundledImage>()
    private let embedded = NSCache<NSData, NSImage>()

    init(resourceURL: URL?) {
        self.resourceURL = resourceURL
        bundled.countLimit = 128
        embedded.countLimit = 256
        bundled.totalCostLimit = 16 * 1024 * 1024
        embedded.totalCostLimit = 8 * 1024 * 1024
    }

    func bundledImage(key: String) -> NSImage? {
        if let cached = bundled.object(forKey: key as NSString) { return cached.image }
        let image = resourceURL.flatMap { directory in
            ["png", "ico", "jpg"].lazy.compactMap { ext in
                NSImage(contentsOf: directory.appending(path: "logos/\(key).\(ext)"))
            }.first
        }
        bundled.setObject(BundledImage(image), forKey: key as NSString, cost: cost(image))
        return image
    }

    func image(data: Data) -> NSImage? {
        let key = data as NSData
        if let cached = embedded.object(forKey: key) { return cached }
        guard let image = NSImage(data: data) else { return nil }
        embedded.setObject(image, forKey: key, cost: cost(image))
        return image
    }

    private func cost(_ image: NSImage?) -> Int {
        guard let image else { return 1 }
        return max(1, Int(image.size.width * image.size.height * 4))
    }
}
