import Foundation

/// macOS keys per-app storage (WebKit website data, UserDefaults) by bundle
/// identifier. The identifier moved from `com.cloyd.*` to `com.cloydlau.*`,
/// which would otherwise present as a signed-out, reset app. Carry the previous
/// identifier's state over once, and drop the identifier orphaned earlier.
enum BundleIdentifierMigration {
    /// The identifier in use immediately before the move to `com.cloydlau.*`.
    private static let previousIdentifier = "com.cloyd.ai-benchgauge"
    /// Orphaned by the rename to AI BenchGauge; nothing reads it anymore.
    private static let orphanedIdentifier = "com.cloyd.ai-leaderboards"
    private static let doneKey = "bundleIdentifierMigrationDone"

    static func runOnce(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        guard defaults.object(forKey: doneKey) == nil else { return }
        adopt(previousIdentifier, defaults: defaults, fileManager: fileManager)
        remove(orphanedIdentifier, fileManager: fileManager)
        defaults.set(true, forKey: doneKey)
    }

    private static func adopt(
        _ identifier: String,
        defaults: UserDefaults,
        fileManager: FileManager
    ) {
        moveWebKitStore(from: identifier, fileManager: fileManager)
        if let previous = UserDefaults(suiteName: identifier) {
            for (key, value) in previous.dictionaryRepresentation()
            where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        removePreferencesFile(for: identifier, fileManager: fileManager)
    }

    private static func remove(_ identifier: String, fileManager: FileManager) {
        let root = fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library/WebKit", directoryHint: .isDirectory)
        try? fileManager.removeItem(at: root.appending(path: identifier, directoryHint: .isDirectory))
        removePreferencesFile(for: identifier, fileManager: fileManager)
    }

    private static func moveWebKitStore(from identifier: String, fileManager: FileManager) {
        let root = fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library/WebKit", directoryHint: .isDirectory)
        let source = root.appending(path: identifier, directoryHint: .isDirectory)
        guard let current = Bundle.main.bundleIdentifier else { return }
        let destination = root.appending(path: current, directoryHint: .isDirectory)
        guard hasWebsiteData(source, fileManager: fileManager) else { return }
        if fileManager.fileExists(atPath: destination.path) {
            // A launch before the move finished can leave an empty store behind.
            guard !hasWebsiteData(destination, fileManager: fileManager) else { return }
            try? fileManager.removeItem(at: destination)
        }
        try? fileManager.moveItem(at: source, to: destination)
    }

    private static func hasWebsiteData(_ store: URL, fileManager: FileManager) -> Bool {
        let defaultDirectory = store
            .appending(path: "WebsiteData/Default", directoryHint: .isDirectory)
        guard let contents = try? fileManager.contentsOfDirectory(atPath: defaultDirectory.path) else {
            return false
        }
        return contents.contains { $0 != "salt" }
    }

    private static func removePreferencesFile(for identifier: String, fileManager: FileManager) {
        let preferences = fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library/Preferences", directoryHint: .isDirectory)
        try? fileManager.removeItem(
            at: preferences.appending(path: "\(identifier).plist", directoryHint: .isFile)
        )
    }
}
