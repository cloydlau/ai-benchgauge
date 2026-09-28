// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AI-BenchGauge",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(
            name: "LeaderboardCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "leaderboard-menu",
            dependencies: ["LeaderboardCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/LeaderboardMenu",
            exclude: ["Resources/Info.plist", "Resources/logos"],
            resources: [.copy("Resources/Licenses")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "LeaderboardCoreTests",
            dependencies: ["LeaderboardCore"]
        ),
    ]
)
