// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AI-Leaderboards",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "LeaderboardCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "leaderboard-menu",
            dependencies: ["LeaderboardCore"],
            path: "Sources/LeaderboardMenu",
            exclude: ["Resources/Info.plist", "Resources/logos"]
        ),
        .testTarget(
            name: "LeaderboardCoreTests",
            dependencies: ["LeaderboardCore"]
        ),
    ]
)
