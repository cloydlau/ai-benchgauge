import AppKit
import QuartzCore

/// Captures the on-screen leaderboard panel without screen-recording permission.
/// `cacheDisplay` redraws AppKit cells; `layer.render` keeps SwiftUI layers that
/// cacheDisplay sometimes skips. The table region decides which result is real.
@MainActor
enum PanelScreenshot {
    /// `omittingTopBand` is in view points, origin at the top-left, y downward.
    /// The quota row uses that rect so the shared image does not include it.
    /// `omittedBand` is false when a band was requested but could not be removed.
    static func capture(
        view: NSView,
        omittingTopBand band: CGRect? = nil
    ) -> (image: NSImage, png: Data, omittedBand: Bool)? {
        view.layoutSubtreeIfNeeded()
        view.window?.displayIfNeeded()
        CATransaction.flush()

        guard let rep = bestRepresentation(of: view) else { return nil }
        return flattenedCapture(from: rep, view: view, omittingTopBand: band)
    }

    static let quotaStripIdentifier = NSUserInterfaceItemIdentifier("ai-leaderboard.quota-strip")

    /// Full-width band covering the quota chip row, in top-left view points.
    /// Nil when the row is absent or the measured frame is not a header band.
    static func quotaStripBand(in host: NSView) -> CGRect? {
        guard let anchor = descendant(of: host, identified: quotaStripIdentifier) else { return nil }
        let frame = anchor.convert(anchor.bounds, to: host)
        let topDown = topDownRect(frame, in: host)
        guard topDown.width > 1, topDown.height > 8, host.bounds.width > 1, host.bounds.height > 1 else {
            return nil
        }
        var band = CGRect(x: 0, y: topDown.minY, width: host.bounds.width, height: topDown.height)
        // One point of the surrounding header fill, so a Retina rounding sliver
        // of a chip border cannot survive the cut.
        let bleed: CGFloat = 1
        if band.minY > bleed {
            band.origin.y -= bleed
            band.size.height += bleed
        }
        if band.maxY + bleed < host.bounds.height {
            band.size.height += bleed
        }
        guard band.minY >= 16,
              band.height >= 8,
              band.height < host.bounds.height * 0.45,
              band.maxY <= host.bounds.height - 24 else { return nil }
        return band
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
    private static func flattenedCapture(
        from rep: NSBitmapImageRep,
        view: NSView,
        omittingTopBand band: CGRect?
    ) -> (image: NSImage, png: Data, omittedBand: Bool)? {
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
        var output = flattened
        var outputSize = pointSize
        var omittedBand = false
        if let band,
           let cropped = omittingHorizontalBand(flattened, band: band, viewSize: view.bounds.size) {
            output = cropped.image
            outputSize = NSSize(width: pointSize.width, height: cropped.pointSize.height)
            omittedBand = true
        }

        let bitmap = NSBitmapImageRep(cgImage: output)
        bitmap.size = outputSize
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let image = NSImage(size: outputSize)
        image.addRepresentation(bitmap)
        return (image, png, omittedBand)
    }

    /// Drops a horizontal band and closes the gap. `band` is in points with a
    /// top-left origin. The image comes from `CGContext.makeImage()`, whose
    /// crop rect is bottom-left, so the header slice is the high-y end.
    static func omittingHorizontalBand(
        _ image: CGImage,
        band: CGRect,
        viewSize: CGSize
    ) -> (image: CGImage, pointSize: CGSize)? {
        guard viewSize.width > 1, viewSize.height > 1, image.width > 1, image.height > 1 else { return nil }
        var top = band.minY
        var bottom = band.maxY
        if top < 0 { top = 0 }
        if bottom > viewSize.height { bottom = viewSize.height }
        guard bottom - top > 0.5 else { return nil }

        let scaleY = CGFloat(image.height) / viewSize.height
        // Floor the top and ceil the bottom so a Retina rounding sliver of the
        // quota chips cannot survive the cut.
        let pixelTop = Int(floor(top * scaleY))
        let pixelBottom = Int(ceil(bottom * scaleY))
        guard pixelTop >= 0, pixelBottom <= image.height, pixelBottom - pixelTop >= 1 else { return nil }
        let newHeight = image.height - (pixelBottom - pixelTop)
        guard newHeight > 1 else { return nil }

        let width = image.width
        let topPixels = pixelTop
        let bottomPixels = image.height - pixelBottom
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.interpolationQuality = .none
        // Table slice sits at CG y = 0 (visual bottom) and is drawn there.
        if bottomPixels > 0,
           let body = image.cropping(to: CGRect(
            x: 0,
            y: 0,
            width: CGFloat(width),
            height: CGFloat(bottomPixels)
           )) {
            context.draw(body, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(bottomPixels)))
        }
        // Header slice is the high-y end. Draw it above the table slice.
        if topPixels > 0,
           let header = image.cropping(to: CGRect(
            x: 0,
            y: CGFloat(image.height - topPixels),
            width: CGFloat(width),
            height: CGFloat(topPixels)
           )) {
            context.draw(
                header,
                in: CGRect(x: 0, y: CGFloat(bottomPixels), width: CGFloat(width), height: CGFloat(topPixels))
            )
        }
        guard let joined = context.makeImage(), joined.height == newHeight else { return nil }
        let pointHeight = viewSize.height * CGFloat(newHeight) / CGFloat(image.height)
        return (joined, CGSize(width: viewSize.width, height: pointHeight))
    }

    private static func topDownRect(_ frame: CGRect, in host: NSView) -> CGRect {
        guard !host.isFlipped else { return frame }
        return CGRect(
            x: frame.origin.x,
            y: host.bounds.height - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private static func descendant(
        of view: NSView,
        identified identifier: NSUserInterfaceItemIdentifier
    ) -> NSView? {
        if view.identifier == identifier { return view }
        for subview in view.subviews {
            if let found = descendant(of: subview, identified: identifier) { return found }
        }
        return nil
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
