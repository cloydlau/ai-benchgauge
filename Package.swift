// swift-tools-version: 6.0
import PackageDescription

// Resolve AppKit/Sparkle only on macOS. The engine and business logic are shared.
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    .systemLibrary(name: "CSQLite"),
    .target(name: "CPlatformSupport", linkerSettings: [.linkedLibrary("bcrypt", .when(platforms: [.windows]))]),
    .target(name: "LeaderboardCore", dependencies: [
        "CSQLite", .target(name: "CPlatformSupport", condition: .when(platforms: [.windows])),
    ], linkerSettings: [
        .linkedLibrary("sqlite3", .when(platforms: [.macOS, .linux])),
        .linkedLibrary("winsqlite3", .when(platforms: [.windows])),
    ]),
    .executableTarget(name: "benchgauge-engine", dependencies: ["LeaderboardCore"], path: "Sources/LeaderboardBridge"),
    .testTarget(name: "LeaderboardCoreTests", dependencies: ["LeaderboardCore", "CSQLite"]),
]
#if os(macOS)
dependencies.append(.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"))
targets.append(.executableTarget(
    name: "leaderboard-menu", dependencies: ["LeaderboardCore", .product(name: "Sparkle", package: "Sparkle")],
    path: "apps/macos/Sources", exclude: ["Resources/Info.plist"], resources: [.copy("Resources/Licenses")],
    linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
))
#endif
let package = Package(name: "AI-BenchGauge", platforms: [.macOS(.v14)], dependencies: dependencies, targets: targets)
