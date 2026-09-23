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
        return flattenedCapture(from: rep, view: view)
    }

    static func copyToPasteboard(image: NSImage, png: Data) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        // Build TIFF from the same PNG bytes. NSImage.tiffRepresentation redraws
        // through the point size and can put a Retina capture back in the corner.
        if let rep = NSBitmapImageRep(data: png),
           let tiff = rep.representation(using: .tiff, properties: [:]) {
            item.setData(tiff, forType: .tiff)
        } else if let tiff = image.tiffRepresentation {
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
        // cacheDisplay often skips SwiftUI header text. A table-only bitmap
        // then has a blank top-right. Require the header to have painted too.
        let cachedHeader = headerRegionVariety(cached)
        let layeredHeader = headerRegionVariety(layered)
        if cachedScore >= 3, cachedHeader >= 2 { return cached }
        if layeredScore >= 3, layeredHeader >= 2 { return layered }
        if layeredHeader > cachedHeader, max(layeredScore, layeredHeader) >= 2 { return layered }
        if cachedScore >= 3 { return cached }
        if layeredScore >= 3 { return layered }
        if max(cachedScore, layeredScore) < 2 { return nil }
        if cachedHeader >= layeredHeader, cachedScore >= layeredScore { return cached }
        if layeredScore >= cachedScore { return layered }
        return cached ?? layered
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

    /// Trailing header (title row / schedule). A blank corner here is the
    /// failure mode where SwiftUI text never made it into the bitmap.
    private static func headerRegionVariety(_ rep: NSBitmapImageRep?) -> Int {
        regionVariety(rep, xs: [0.72, 0.8, 0.88, 0.94], ys: [0.04, 0.08, 0.12, 0.16])
    }

    /// Header text can look "successful" even when the table did not paint.
    /// Sample only the table band.
    private static func tableRegionVariety(_ rep: NSBitmapImageRep?) -> Int {
        regionVariety(rep, xs: [0.08, 0.2, 0.36, 0.52, 0.7, 0.88], ys: [0.3, 0.42, 0.54, 0.66, 0.78, 0.9])
    }

    private static func regionVariety(
        _ rep: NSBitmapImageRep?,
        xs: [Double],
        ys: [Double]
    ) -> Int {
        guard let rep else { return 0 }
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width > 8, height > 8 else { return 0 }
        var colors = Set<UInt32>()
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

    /// Copy captured pixels 1:1. `NSImage.draw` uses the point size, which on a
    /// Retina bitmap is half the pixel buffer, so the picture lands in the
    /// bottom-left quarter and the top-right stays transparent.
    private static func flattenedCapture(from rep: NSBitmapImageRep, view: NSView) -> (image: NSImage, png: Data)? {
        guard let source = rep.cgImage, source.width > 1, source.height > 1 else { return nil }
        let pixelsWide = source.width
        let pixelsHigh = source.height
        let scale = max(view.window?.backingScaleFactor ?? 2, 1)
        let pointSize = rep.size.width > 1 && rep.size.height > 1
            ? rep.size
            : NSSize(width: CGFloat(pixelsWide) / scale, height: CGFloat(pixelsHigh) / scale)

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
        context.setFillColor(opaqueBackground(for: view))
        context.fill(CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        let drawing = quarterFilledSource(source, rep: rep) ?? source
        context.draw(drawing, in: CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        guard let flattened = context.makeImage() else { return nil }

        let bitmap = NSBitmapImageRep(cgImage: flattened)
        bitmap.size = pointSize
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let image = NSImage(size: pointSize)
        image.addRepresentation(bitmap)
        return (image, png)
    }


    /// A Retina buffer drawn in points keeps the whole panel in the bottom-left
    /// quarter. Crop that quadrant so it can be scaled back to the full image.
    private static func quarterFilledSource(_ image: CGImage, rep: NSBitmapImageRep) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 32, height > 32, width == rep.pixelsWide, height == rep.pixelsHigh else { return nil }
        func opaque(_ x: Int, _ y: Int) -> Bool {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
            return color.alphaComponent > 0.2
        }
        // colorAt is top-left. A quarter-filled capture is empty on the top row
        // and painted only in the bottom-left half.
        if opaque(8, 8) || opaque(width - 8, 8) || opaque(width - 8, height / 4) {
            return nil
        }
        guard opaque(8, height - 8), opaque(width / 4, height * 3 / 4) else { return nil }
        return image.cropping(to: CGRect(
            x: 0,
            y: height / 2,
            width: width / 2,
            height: height / 2
        ))
    }

    private static func opaqueBackground(for view: NSView) -> CGColor {
        var resolved = NSColor.windowBackgroundColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = NSColor.windowBackgroundColor
        }
        return (resolved.usingColorSpace(.sRGB) ?? resolved).cgColor
    }
}
