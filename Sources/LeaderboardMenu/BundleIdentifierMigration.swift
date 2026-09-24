import Foundation

/// macOS scopes per-app state (WebKit website data, the cookie jar,
/// `UserDefaults`) to the bundle identifier. This app shipped as
/// `com.cloyd.ai-leaderboards`, then `com.cloyd.ai-benchgauge`, and now
/// `com.cloydlau.ai-benchgauge`. Every rename would otherwise look like a
/// signed-out, reset app, so carry the newest legacy state across once and
/// drop whatever the retired identifiers left behind.
enum BundleIdentifierMigration {
    /// Retired identifiers, newest first, so the freshest state wins a conflict.
    private static let legacyIdentifiers = [
        "com.cloyd.ai-benchgauge",
        "com.cloyd.ai-leaderboards",
    ]
    private static let doneKey = "bundleIdentifierMigrationDone"
    /// The cookie jar sits beside the identifier, outside the website data.
    private static let cookieSuffix = ".binarycookies"

    /// Must run before any web view or `URLSession` is created, or the current
    /// identifier claims empty stores first and there is nothing to adopt into.
    static func runOnce(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        guard defaults.object(forKey: doneKey) == nil,
              let current = Bundle.main.bundleIdentifier,
              !legacyIdentifiers.contains(current) else { return }
        adoptWebsiteData(into: current, fileManager: fileManager)
        adoptCookies(into: current, fileManager: fileManager)
        adoptPreferences(into: defaults)
        discardLegacyState(into: current, defaults: defaults, fileManager: fileManager)
        defaults.set(true, forKey: doneKey)
    }

    private static func libraryDirectory(_ fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library", directoryHint: .isDirectory)
    }

    /// Keeps the signed-in Qwen session: the web view reads its local storage
    /// from here, so a fresh store would render the quota page logged out.
    private static func adoptWebsiteData(into current: String, fileManager: FileManager) {
        let root = libraryDirectory(fileManager)
            .appending(path: "WebKit", directoryHint: .isDirectory)
        let destination = root.appending(path: current, directoryHint: .isDirectory)
        guard !hasWebsiteData(destination, fileManager: fileManager) else { return }
        guard let source = legacyURLs(in: root)
            .first(where: { hasWebsiteData($0, fileManager: fileManager) }) else { return }
        if fileManager.fileExists(atPath: destination.path) {
            // A launch that quit before migrating can leave an empty store behind.
            try? fileManager.removeItem(at: destination)
        }
        try? fileManager.moveItem(at: source, to: destination)
    }

    /// Cookies live beside the identifier rather than inside the website data,
    /// so moving that store alone would still read as signed out.
    private static func adoptCookies(into current: String, fileManager: FileManager) {
        let root = libraryDirectory(fileManager)
            .appending(path: "HTTPStorages", directoryHint: .isDirectory)
        let destination = root.appending(
            path: current + cookieSuffix,
            directoryHint: .notDirectory
        )
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        guard let source = legacyURLs(in: root, suffix: cookieSuffix)
            .first(where: { fileManager.fileExists(atPath: $0.path) }) else { return }
        try? fileManager.moveItem(at: source, to: destination)
    }

    private static func legacyURLs(in root: URL, suffix: String = "") -> [URL] {
        legacyIdentifiers.map {
            root.appending(path: $0 + suffix, directoryHint: .isDirectory)
        }
    }

    private static func hasWebsiteData(_ store: URL, fileManager: FileManager) -> Bool {
        let defaultDirectory = store
            .appending(path: "WebsiteData/Default", directoryHint: .isDirectory)
        guard let contents = try? fileManager
            .contentsOfDirectory(atPath: defaultDirectory.path) else { return false }
        return contents.contains { $0 != "salt" }
    }

    /// Only the identifiers' own keys: `dictionaryRepresentation()` would drag
    /// the global domain in and bloat the migrated preferences.
    private static func adoptPreferences(into defaults: UserDefaults) {
        for identifier in legacyIdentifiers {
            guard let stored = defaults.persistentDomain(forName: identifier) else { continue }
            for (key, value) in stored where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
    }

    private static func discardLegacyState(
        into current: String,
        defaults: UserDefaults,
        fileManager: FileManager
    ) {
        let library = libraryDirectory(fileManager)
        let webKit = library.appending(path: "WebKit", directoryHint: .isDirectory)
        let storages = library.appending(path: "HTTPStorages", directoryHint: .isDirectory)
        // A move can still fail on a locked or foreign volume; never delete the
        // only copy of a signed-in session.
        let migratedStore = webKit.appending(path: current, directoryHint: .isDirectory)
        let hasMigratedStore = hasWebsiteData(migratedStore, fileManager: fileManager)
        let hasMigratedCookies = fileManager.fileExists(
            atPath: storages.appending(
                path: current + cookieSuffix,
                directoryHint: .notDirectory
            ).path
        )
        for identifier in legacyIdentifiers {
            let legacyStore = webKit.appending(path: identifier, directoryHint: .isDirectory)
            if hasMigratedStore || !hasWebsiteData(legacyStore, fileManager: fileManager) {
                try? fileManager.removeItem(at: legacyStore)
            }
            try? fileManager.removeItem(
                at: library
                    .appending(path: "Caches", directoryHint: .isDirectory)
                    .appending(path: identifier, directoryHint: .isDirectory)
            )
            let legacyCookies = storages.appending(
                path: identifier + cookieSuffix,
                directoryHint: .notDirectory
            )
            if hasMigratedCookies || !fileManager.fileExists(atPath: legacyCookies.path) {
                try? fileManager.removeItem(at: legacyCookies)
            }
            for suffix in ["", ".snapshot", ".snapshot" + cookieSuffix] {
                try? fileManager.removeItem(
                    at: storages.appending(
                        path: identifier + suffix,
                        directoryHint: .isDirectory
                    )
                )
            }
            // Goes through cfprefsd; deleting the plist directly lets it write
            // the cached domain straight back out.
            defaults.removePersistentDomain(forName: identifier)
        }
    }
}
