import Foundation

// Copy the canonical opaque artwork; deployments must never regenerate an old logo.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appending(path: "assets/brand/app-icon-ios.png")
let data = try Data(contentsOf: source)
precondition(Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
precondition(data[25] == 2, "The iOS icon must be opaque RGB")
let output = CommandLine.arguments.dropFirst().first ?? "apps/ios/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
try data.write(to: URL(fileURLWithPath: output))
