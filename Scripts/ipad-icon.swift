import AppKit
import Foundation

// Own vector artwork, rendered to Apple's required opaque 1024px app icon.
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                             bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.035, green: 0.065, blue: 0.12, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
let colors = [NSColor(calibratedRed: 0.24, green: 0.72, blue: 0.86, alpha: 1),
              NSColor(calibratedRed: 0.43, green: 0.86, blue: 0.64, alpha: 1),
              NSColor(calibratedRed: 0.69, green: 0.59, blue: 0.97, alpha: 1)]
for (index, height) in [280, 430, 590].enumerated() {
    colors[index].setFill()
    NSBezierPath(roundedRect: NSRect(x: 190 + index * 225, y: 195, width: 180, height: height), xRadius: 34, yRadius: 34).fill()
}
NSGraphicsContext.restoreGraphicsState()
let output = CommandLine.arguments.dropFirst().first ?? "apps/ipad/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
