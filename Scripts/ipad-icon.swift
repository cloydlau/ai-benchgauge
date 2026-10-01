import AppKit
import Foundation

// Own vector artwork, rendered to Apple's required opaque 1024px app icon.
let size = 1024
// AppKit cannot draw into the previous packed 24-bit RGB representation.
// Use a supported opaque 32-bit Core Graphics context, then encode its image.
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
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
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
let png = bitmap.representation(using: .png, properties: [:])!
// AppKit adds EXIF even to a drawing. Export no EXIF, text or timestamp chunks;
// copy the image and color chunks unchanged so the rendered artwork is identical.
let privateChunks: Set<String> = ["eXIf", "tEXt", "iTXt", "zTXt", "tIME"]
var clean = Data(png.prefix(8))
var offset = 8
while offset < png.count {
    guard offset + 12 <= png.count else { fatalError("Incomplete generated PNG") }
    let size = png[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
    let end = offset + size + 12
    guard end <= png.count else { fatalError("Incomplete generated PNG chunk") }
    let kind = String(decoding: png[offset + 4..<offset + 8], as: UTF8.self)
    if !privateChunks.contains(kind) { clean.append(png[offset..<end]) }
    offset = end
}
try clean.write(to: URL(fileURLWithPath: output))
