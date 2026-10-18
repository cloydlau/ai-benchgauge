import AppKit
import Foundation

// The selected D geometry is shared by every exported platform and size.
struct Design: Decodable {
    let material: String?
    let artwork: String?
    let canvas: CGFloat
    let tileRadius: CGFloat
    let background: [String]
    let accent: [String]
    let accentStart: [CGFloat]
    let accentEnd: [CGFloat]
    let ink: String
    let lineWidth: CGFloat
    let nodes: [[CGFloat]]
    let edges: [[Int]]
    let outputCoreRadius: CGFloat
}
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let directory = root.appending(path: "assets/brand")
let design = try JSONDecoder().decode(Design.self, from: Data(contentsOf: directory.appending(path: "design.json")))
// Keep the user-approved rendered material as the icon master. The vector
// geometry remains authoritative for small transparent and monochrome marks.
let artworkData = try design.artwork.map { try Data(contentsOf: directory.appending(path: $0)) }
let artworkImage = artworkData.map { NSBitmapImageRep(data: $0)!.cgImage! }
let colorSpace = CGColorSpaceCreateDeviceRGB()
func color(_ hex: String) -> CGColor {
    let value = UInt32(hex.dropFirst(), radix: 16)!
    return CGColor(colorSpace: colorSpace, components: [CGFloat((value >> 16) & 255) / 255,
        CGFloat((value >> 8) & 255) / 255, CGFloat(value & 255) / 255, 1])!
}
func point(_ coordinates: [CGFloat]) -> CGPoint { CGPoint(x: coordinates[0], y: coordinates[1]) }
func gradient(_ context: CGContext, colors: [String], start: CGPoint, end: CGPoint) {
    let value = CGGradient(colorsSpace: colorSpace, colors: colors.map(color) as CFArray, locations: [0, 1])!
    context.drawLinearGradient(value, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
func accent(_ context: CGContext, colors: [String]? = nil) {
    gradient(context, colors: colors ?? design.accent, start: point(design.accentStart), end: point(design.accentEnd))
}
let metalLocations: [CGFloat] = [0, 0.14, 0.32, 0.53, 0.64, 0.76, 0.92, 1]
let darkMetal = ["#727C88", "#F5F7FA", "#D6DDE5", "#A1ACBA", "#404A58", "#8E9CAA", "#E5ECF3", "#687584"]
let lightMetal = ["#414B59", "#AEB9C5", "#EDF1F5", "#788594", "#253140", "#697787", "#BDC7D2", "#465362"]
func metalGradient(_ context: CGContext, colors: [String], locations: [CGFloat], start: CGPoint, end: CGPoint) {
    let value = CGGradient(colorsSpace: colorSpace, colors: colors.map(color) as CFArray, locations: locations)!
    context.drawLinearGradient(value, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
func metalGlyph(_ context: CGContext, dark: Bool) {
    // Cylindrical rod reflections run across the original stroke, not along it.
    for edge in design.edges {
        let a = point(design.nodes[edge[0]]), b = point(design.nodes[edge[1]])
        let dx = b.x - a.x, dy = b.y - a.y, length = hypot(dx, dy)
        let normal = CGPoint(x: -dy / length * design.lineWidth / 2, y: dx / length * design.lineWidth / 2)
        let middle = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        context.saveGState()
        context.setLineWidth(design.lineWidth); context.setLineCap(.round)
        context.move(to: a); context.addLine(to: b); context.replacePathWithStrokedPath(); context.clip()
        metalGradient(context, colors: dark ? ["#596575", "#F7F9FC", "#A2AEBC", "#414D5C", "#BBC6D2"]
            : ["#354150", "#DCE3EB", "#8391A2", "#253140", "#8291A1"],
            locations: [0, 0.25, 0.46, 0.73, 1],
            start: CGPoint(x: middle.x - normal.x, y: middle.y - normal.y),
            end: CGPoint(x: middle.x + normal.x, y: middle.y + normal.y))
        context.restoreGState()
    }
    // Reflected light/dark bands and a narrow bevel stay inside each silhouette.
    for (index, node) in design.nodes.enumerated() {
        let rect = CGRect(x: node[0] - node[2], y: node[1] - node[2], width: node[2] * 2, height: node[2] * 2)
        context.saveGState(); context.addEllipse(in: rect); context.clip()
        metalGradient(context, colors: dark ? darkMetal : lightMetal, locations: metalLocations,
            start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY))
        context.setLineWidth(0.8)
        context.setStrokeColor(color(dark ? "#DCE4EC" : "#4A5767"))
        context.strokeEllipse(in: rect.insetBy(dx: 0.4, dy: 0.4))
        context.restoreGState()
        if index == design.nodes.count - 1 {
            let radius = design.outputCoreRadius
            let core = CGRect(x: node[0] - radius, y: node[1] - radius, width: radius * 2, height: radius * 2)
            context.saveGState(); context.addEllipse(in: core); context.clip()
            gradient(context, colors: dark ? ["#F2F5F8", "#A7B2BF"] : ["#ACB7C4", "#536173"],
                start: CGPoint(x: core.minX, y: core.minY), end: CGPoint(x: core.maxX, y: core.maxY))
            context.setLineWidth(0.8); context.setStrokeColor(color(dark ? "#5F6C7A" : "#303C4B"))
            context.strokeEllipse(in: core.insetBy(dx: 0.4, dy: 0.4)); context.restoreGState()
        }
    }
}
func glyph(_ context: CGContext, monochrome: Bool = false, ink: String? = nil, accentColors: [String]? = nil) {
    if !monochrome && design.material == "polished-platinum" {
        metalGlyph(context, dark: ink == nil)
        return
    }
    let nodeInk = ink ?? design.ink
    context.saveGState()
    context.setLineWidth(design.lineWidth); context.setLineCap(.round); context.setLineJoin(.round)
    for edge in design.edges {
        context.move(to: point(design.nodes[edge[0]])); context.addLine(to: point(design.nodes[edge[1]]))
    }
    if monochrome { context.setStrokeColor(CGColor(gray: 0, alpha: 1)); context.strokePath() }
    else { context.replacePathWithStrokedPath(); context.clip(); accent(context, colors: accentColors) }
    context.restoreGState()
    for (index, node) in design.nodes.enumerated() {
        let circle = CGRect(x: node[0] - node[2], y: node[1] - node[2], width: node[2] * 2, height: node[2] * 2)
        if !monochrome && index == design.nodes.count - 1 {
            context.saveGState(); context.addEllipse(in: circle); context.clip(); accent(context, colors: accentColors); context.restoreGState()
            let radius = design.outputCoreRadius
            context.setFillColor(color(nodeInk))
            context.fillEllipse(in: CGRect(x: node[0] - radius, y: node[1] - radius, width: radius * 2, height: radius * 2))
        } else {
            context.setFillColor(monochrome ? CGColor(gray: 0, alpha: 1) : color(nodeInk)); context.fillEllipse(in: circle)
        }
    }
}
func cleanPNG(_ data: Data) -> Data {
    let allowed: Set<String> = ["IHDR", "sRGB", "IDAT", "IEND"]
    var output = Data(data.prefix(8)); var offset = 8
    while offset < data.count {
        let length = data[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
        let end = offset + length + 12
        precondition(end <= data.count)
        if allowed.contains(String(decoding: data[offset + 4..<offset + 8], as: UTF8.self)) { output.append(data[offset..<end]) }
        offset = end
    }
    return output
}
enum Variant { case ios, mac, windows, menu }
func headerMarkPNG(dark: Bool) -> Data {
    // Crop to the network's painted bounds; no tile and no outside alpha padding.
    let bounds = design.nodes.reduce(CGRect.null) { result, node in
        result.union(CGRect(x: node[0] - node[2], y: node[1] - node[2], width: node[2] * 2, height: node[2] * 2))
    }
    let scale: CGFloat = 2
    let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: scale, y: -scale)
    context.translateBy(x: -bounds.minX, y: -bounds.minY)
    if dark { glyph(context) }
    else { glyph(context, ink: "#465362", accentColors: ["#536173", "#ACB7C4"]) }
    return cleanPNG(NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!)
}
func png(size: Int, variant: Variant) -> Data {
    let opaque = variant == .ios
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
        space: colorSpace, bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x: 0, y: CGFloat(size)); context.scaleBy(x: 1, y: -1)
    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)
    if variant == .menu {
        // Give the small template more ink coverage than the app's padded tile.
        context.translateBy(x: 74, y: 135); context.scaleBy(x: 5.1, y: 5.1); context.translateBy(x: -44, y: -54)
        glyph(context, monochrome: true)
    } else {
        if variant == .mac { context.translateBy(x: 100, y: 100); context.scaleBy(x: 824 / 256, y: 824 / 256) }
        else { context.scaleBy(x: 4, y: 4) }
        let rect = CGRect(x: 0, y: 0, width: design.canvas, height: design.canvas)
        context.saveGState()
        if variant != .ios {
            context.addPath(CGPath(roundedRect: rect, cornerWidth: design.tileRadius, cornerHeight: design.tileRadius, transform: nil)); context.clip()
        }
        if let artworkImage {
            // The surrounding context uses top-left vector coordinates. Undo
            // that flip only for CGImage drawing so the approved bitmap is upright.
            context.translateBy(x: 0, y: design.canvas); context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .high
            context.draw(artworkImage, in: rect)
        } else {
            gradient(context, colors: design.background, start: .zero, end: CGPoint(x: design.canvas, y: design.canvas))
        }
        context.restoreGState()
        if artworkImage == nil { glyph(context) }
    }
    return cleanPNG(NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!)
}
func svg(background: Bool, monochrome: Bool = false) -> String {
    if background, !monochrome, let artworkData {
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 256 256\"><defs><clipPath id=\"tile\"><rect width=\"256\" height=\"256\" rx=\"\(design.tileRadius)\"/></clipPath></defs><image width=\"256\" height=\"256\" clip-path=\"url(#tile)\" href=\"data:image/png;base64,\(artworkData.base64EncodedString())\"/></svg>\n"
    }
    if !monochrome && design.material == "polished-platinum" { return metalSVG() }
    let stroke = monochrome ? "currentColor" : "url(#accent)"
    let fill = monochrome ? "currentColor" : design.ink
    var result = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 256 256\" color=\"#25314B\">\n"
    if !monochrome {
        result += "<defs><linearGradient id=\"tile\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\"><stop stop-color=\"\(design.background[0])\"/><stop offset=\"1\" stop-color=\"\(design.background[1])\"/></linearGradient><linearGradient id=\"accent\" gradientUnits=\"userSpaceOnUse\" x1=\"\(design.accentStart[0])\" y1=\"\(design.accentStart[1])\" x2=\"\(design.accentEnd[0])\" y2=\"\(design.accentEnd[1])\"><stop stop-color=\"\(design.accent[0])\"/><stop offset=\"1\" stop-color=\"\(design.accent[1])\"/></linearGradient></defs>\n"
    }
    if background { result += "<rect width=\"256\" height=\"256\" rx=\"\(design.tileRadius)\" fill=\"url(#tile)\"/>\n" }
    let lines = design.edges.map { "M\(design.nodes[$0[0]][0]) \(design.nodes[$0[0]][1])L\(design.nodes[$0[1]][0]) \(design.nodes[$0[1]][1])" }.joined()
    result += "<path d=\"\(lines)\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(design.lineWidth)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\n"
    for (index, node) in design.nodes.enumerated() {
        let output = index == design.nodes.count - 1
        result += "<circle cx=\"\(node[0])\" cy=\"\(node[1])\" r=\"\(node[2])\" fill=\"\(output ? stroke : fill)\"/>\n"
        if output && !monochrome { result += "<circle cx=\"\(node[0])\" cy=\"\(node[1])\" r=\"\(design.outputCoreRadius)\" fill=\"\(fill)\"/>\n" }
    }
    return result + "</svg>\n"
}
func metalSVG() -> String {
    func stops(_ colors: [String], _ locations: [CGFloat]) -> String {
        zip(colors, locations).map { "<stop offset=\"\($0.1)\" stop-color=\"\($0.0)\"/>" }.joined()
    }
    var defs = "<linearGradient id=\"node\" x1=\"0\" y1=\"0\" x2=\"0.5\" y2=\"1\">\(stops(darkMetal, metalLocations))</linearGradient>"
    defs += "<linearGradient id=\"core\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\"><stop stop-color=\"#F2F5F8\"/><stop offset=\"1\" stop-color=\"#A7B2BF\"/></linearGradient>"
    var body = ""
    for (index, edge) in design.edges.enumerated() {
        let a = point(design.nodes[edge[0]]), b = point(design.nodes[edge[1]])
        let dx = b.x - a.x, dy = b.y - a.y, length = hypot(dx, dy)
        let nx = -dy / length * design.lineWidth / 2, ny = dx / length * design.lineWidth / 2
        let mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2
        defs += "<linearGradient id=\"rod\(index)\" gradientUnits=\"userSpaceOnUse\" x1=\"\(mx - nx)\" y1=\"\(my - ny)\" x2=\"\(mx + nx)\" y2=\"\(my + ny)\">\(stops(["#596575", "#F7F9FC", "#A2AEBC", "#414D5C", "#BBC6D2"], [0, 0.25, 0.46, 0.73, 1]))</linearGradient>"
        body += "<path d=\"M\(a.x) \(a.y)L\(b.x) \(b.y)\" fill=\"none\" stroke=\"url(#rod\(index))\" stroke-width=\"\(design.lineWidth)\" stroke-linecap=\"round\"/>"
    }
    for (index, node) in design.nodes.enumerated() {
        body += "<circle cx=\"\(node[0])\" cy=\"\(node[1])\" r=\"\(node[2])\" fill=\"url(#node)\"/>"
        body += "<circle cx=\"\(node[0])\" cy=\"\(node[1])\" r=\"\(node[2] - 0.4)\" fill=\"none\" stroke=\"#DCE4EC\" stroke-width=\"0.8\"/>"
        if index == design.nodes.count - 1 {
            body += "<circle cx=\"\(node[0])\" cy=\"\(node[1])\" r=\"\(design.outputCoreRadius)\" fill=\"url(#core)\"/>"
            body += "<circle cx=\"\(node[0])\" cy=\"\(node[1])\" r=\"\(design.outputCoreRadius - 0.4)\" fill=\"none\" stroke=\"#5F6C7A\" stroke-width=\"0.8\"/>"
        }
    }
    return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 256 256\"><defs>\(defs)</defs>\(body)</svg>\n"
}
func little<T: FixedWidthInteger>(_ value: T) -> Data { var value = value.littleEndian; return withUnsafeBytes(of: &value) { Data($0) } }
func big(_ value: UInt32) -> Data { var value = value.bigEndian; return withUnsafeBytes(of: &value) { Data($0) } }
let windowsSizes = [16, 24, 32, 48, 64, 128, 256]
let windowsPNGs = windowsSizes.map { png(size: $0, variant: .windows) }
var ico = little(UInt16(0)) + little(UInt16(1)) + little(UInt16(windowsSizes.count))
var icoOffset = 6 + windowsSizes.count * 16
for (size, data) in zip(windowsSizes, windowsPNGs) {
    ico.append(contentsOf: [UInt8(size % 256), UInt8(size % 256), 0, 0])
    ico += little(UInt16(1)) + little(UInt16(32)) + little(UInt32(data.count)) + little(UInt32(icoOffset)); icoOffset += data.count
}
windowsPNGs.forEach { ico.append($0) }
var chunks = Data()
for (size, tag) in [(16, "icp4"), (32, "icp5"), (64, "icp6"), (128, "ic07"), (256, "ic08"), (512, "ic09"), (1024, "ic10")] {
    let data = png(size: size, variant: .mac)
    chunks += Data(tag.utf8) + big(UInt32(data.count + 8)) + data
}
let exports: [(String, Data)] = [
    ("app-icon.svg", Data(svg(background: true).utf8)), ("mark.svg", Data(svg(background: false).utf8)),
    ("menu-template.svg", Data(svg(background: false, monochrome: true).utf8)),
    ("app-icon-ios.png", png(size: 1024, variant: .ios)), ("app-icon-macos.png", png(size: 1024, variant: .mac)),
    ("app-icon-windows.png", png(size: 1024, variant: .windows)),
    ("header-logo.png", headerMarkPNG(dark: false)),
    ("header-logo-dark.png", headerMarkPNG(dark: true)),
    ("menu-template.png", png(size: 22, variant: .menu)), ("menu-template@2x.png", png(size: 44, variant: .menu)),
    ("menu-template@3x.png", png(size: 66, variant: .menu)),
    ("AI-BenchGauge.ico", ico), ("AI-BenchGauge.icns", Data("icns".utf8) + big(UInt32(chunks.count + 8)) + chunks)
]
for (name, data) in exports { try data.write(to: directory.appending(path: name)) }
let headerResources = root.appending(path: "Sources/LeaderboardKit/Resources/Brand")
try FileManager.default.createDirectory(at: headerResources, withIntermediateDirectories: true)
for name in ["header-logo.png", "header-logo-dark.png"] {
    try Data(contentsOf: directory.appending(path: name)).write(to: headerResources.appending(path: name))
}
print("Generated \(exports.count) brand assets from the selected neural-network geometry.")
