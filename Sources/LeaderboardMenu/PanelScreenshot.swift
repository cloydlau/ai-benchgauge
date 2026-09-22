import AppKit
import QuartzCore

/// Captures the on-screen leaderboard panel without screen-recording permission.
/// `cacheDisplay` redraws AppKit cells; `layer.render` keeps SwiftUI layers that
/// cacheDisplay sometimes skips. The table region decides which result is real.
@MainActor
enum PanelScreenshot {
    static func capture(view: NSView) -> (image: NSImage, png: Data)? {
        view.layoutSubtreeIfNeeded()
        view.window?.displayIfNeeded()
        CATransaction.flush()

        guard let rep = bestRepresentation(of: view) else { return nil }
        let image = flattenedImage(from: rep, view: view)
        guard let png = pngData(from: image) else { return nil }
        return (image, png)
    }

    static func copyToPasteboard(image: NSImage, png: Data) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        return pasteboard.writeObjects([item])
    }

    private static func bestRepresentation(of view: NSView) -> NSBitmapImageRep? {
        let cached = cacheDisplayRepresentation(of: view)
        let layered = layerRepresentation(of: view)
        let cachedScore = tableRegionVariety(cached)
        let layeredScore = tableRegionVariety(layered)
        // Sampling can fail on some bitmap formats. Don't discard a redraw then.
        if cachedScore == 0, layeredScore == 0 {
            return cached ?? layered
        }
        // Prefer a fresh redraw when the table actually painted.
        if cachedScore >= 3 { return cached }
        if layeredScore >= 3 { return layered }
        if max(cachedScore, layeredScore) < 2 { return nil }
        if cachedScore >= layeredScore { return cached }
        return layered
    }

    private static func cacheDisplayRepresentation(of view: NSView) -> NSBitmapImageRep? {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        if rep.size.width < 1 || rep.size.height < 1 {
            rep.size = bounds.size
        }
        return rep
    }

    private static func layerRepresentation(of view: NSView) -> NSBitmapImageRep? {
        guard let layer = view.layer else { return nil }
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let scale = max(view.window?.backingScaleFactor ?? 2, 1)
        let pixelsWide = max(Int((bounds.width * scale).rounded(.up)), 1)
        let pixelsHigh = max(Int((bounds.height * scale).rounded(.up)), 1)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: pixelsWide,
                height: pixelsHigh,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(opaqueBackground(for: view))
        context.fill(CGRect(origin: .zero, size: bounds.size))
        // Layer space is y-up. An unflipped bitmap context already matches it.
        layer.render(in: context)
        guard let cgImage = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = bounds.size
        return rep
    }

    /// Header text can look "successful" even when the table did not paint.
    /// Sample only the table band.
    private static func tableRegionVariety(_ rep: NSBitmapImageRep?) -> Int {
        guard let rep else { return 0 }
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width > 8, height > 8 else { return 0 }
        var colors = Set<UInt32>()
        let xs = [0.08, 0.2, 0.36, 0.52, 0.7, 0.88]
        let ys = [0.3, 0.42, 0.54, 0.66, 0.78, 0.9]
        for yFraction in ys {
            for xFraction in xs {
                let x = min(width - 1, max(0, Int((Double(width - 1) * xFraction).rounded())))
                let y = min(height - 1, max(0, Int((Double(height - 1) * yFraction).rounded())))
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.2 else { continue }
                let red = UInt32((color.redComponent * 16).rounded())
                let green = UInt32((color.greenComponent * 16).rounded())
                let blue = UInt32((color.blueComponent * 16).rounded())
                colors.insert((red << 10) | (green << 5) | blue)
            }
        }
        return colors.count
    }

    private static func flattenedImage(from rep: NSBitmapImageRep, view: NSView) -> NSImage {
        let size = rep.size.width > 1 && rep.size.height > 1
            ? rep.size
            : NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        let source = NSImage(size: size)
        source.addRepresentation(rep)

        let scale = max(view.window?.backingScaleFactor ?? 2, 1)
        let pixelsWide = max(Int((size.width * scale).rounded(.up)), 1)
        let pixelsHigh = max(Int((size.height * scale).rounded(.up)), 1)
        guard let flattened = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: flattened) else {
            return source
        }
        flattened.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: size).fill()
            source.draw(
                in: NSRect(origin: .zero, size: size),
                from: NSRect(origin: .zero, size: size),
                operation: .sourceOver,
                fraction: 1
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(flattened)
        return image
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func opaqueBackground(for view: NSView) -> CGColor {
        var resolved = NSColor.windowBackgroundColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = NSColor.windowBackgroundColor
        }
        return (resolved.usingColorSpace(.sRGB) ?? resolved).cgColor
    }
}
