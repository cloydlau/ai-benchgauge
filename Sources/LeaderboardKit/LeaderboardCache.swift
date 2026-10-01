import Foundation

public struct LeaderboardCache {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        // Preserve Date's full precision; ISO 8601 encoding drops subsecond values.
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let interval = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: interval)
            }
            // Caches written by older builds contain ISO 8601 strings.
            let value = try container.decode(String.self)
            guard let date = ISO8601DateFormatter().date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid cached date")
            }
            return date
        }
    }

    public static func defaultFileURL() throws -> URL {
        #if os(Windows)
        let root = ProcessInfo.processInfo.environment["LOCALAPPDATA"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "AppData/Local")
        let directory = root.appending(path: "AI-BenchGauge", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "leaderboards.json")
        #else
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appending(
            path: "AI BenchGauge",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "leaderboards.json", directoryHint: .inferFromPath)
        #endif
    }

    public func load() -> LeaderboardSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(LeaderboardSnapshot.self, from: data)
    }

    public func save(_ snapshot: LeaderboardSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(Windows)
        try? data.write(to: fileURL, options: .atomic)
        #else
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        #endif
    }
}
