// swift-tools-version: 6.0
import PackageDescription

// Resolve AppKit/Sparkle only on macOS. The engine and business logic are shared.
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    .target(name: "LeaderboardKit"),
    .testTarget(name: "LeaderboardKitTests", dependencies: ["LeaderboardKit"]),
    .systemLibrary(name: "CSQLite"),
    .target(name: "CPlatformSupport", linkerSettings: [.linkedLibrary("bcrypt", .when(platforms: [.windows]))]),
    .target(name: "LeaderboardCore", dependencies: [
        "LeaderboardKit", "CSQLite", .target(name: "CPlatformSupport", condition: .when(platforms: [.windows])),
    ], linkerSettings: [
        .linkedLibrary("sqlite3", .when(platforms: [.macOS, .linux])),
        .linkedLibrary("winsqlite3", .when(platforms: [.windows])),
    ]),
    .executableTarget(name: "benchgauge-engine", dependencies: ["LeaderboardCore"], path: "Sources/LeaderboardBridge"),
    .testTarget(name: "LeaderboardCoreTests", dependencies: ["LeaderboardCore", "CSQLite", .target(name: "CPlatformSupport", condition: .when(platforms: [.windows]))]),
]
#if os(macOS)
// SwiftUI is shared across Apple targets; macOS tests also type-check the iPad interface.
targets.append(.target(name: "LeaderboardPadUI", dependencies: ["LeaderboardKit"],
                       path: "apps/ipad/UI", resources: [.copy("Resources/AI-BenchGauge.txt")]))
targets.append(.testTarget(name: "LeaderboardPadUITests", dependencies: ["LeaderboardPadUI", "LeaderboardKit"],
                           path: "Tests/LeaderboardPadUITests"))
dependencies.append(.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"))
targets.append(.executableTarget(
    name: "leaderboard-menu", dependencies: ["LeaderboardCore", .product(name: "Sparkle", package: "Sparkle")],
    path: "apps/macos/Sources", exclude: ["Resources/Info.plist"],
    resources: [.copy("Resources/Licenses")],
    linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
))
targets.append(.testTarget(name: "MacUpdaterTests", dependencies: ["leaderboard-menu", "LeaderboardCore"],
                           path: "Tests/MacUpdaterTests"))
#endif
var products: [Product] = [.library(name: "LeaderboardKit", targets: ["LeaderboardKit"])]
#if os(macOS)
products.append(.library(name: "LeaderboardPadUI", targets: ["LeaderboardPadUI"]))
#endif
let package = Package(name: "AI-BenchGauge", platforms: [.macOS(.v14), .iOS(.v17)],
                      products: products,
                      dependencies: dependencies, targets: targets)
