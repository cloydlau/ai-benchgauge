import Foundation

/// macOS scopes per-app state (WebKit website data, the cookie jar,
/// `UserDefaults`) to the bundle identifier. This app shipped as
/// `com.cloyd.ai-leaderboards`, then `com.cloyd.ai-benchgauge`, and now
/// `com.cloydlau.ai-benchgauge`. Every rename would otherwise look like a
/// signed-out, reset app, so carry the newest legacy state across and drop
/// whatever the retired identifiers left behind.
///
/// Every step is guarded and idempotent, so this runs on each launch: an
/// interrupted first pass retries instead of stranding the legacy state, and
/// the empty plist `cfprefsd` writes back for a removed domain only lets go on
/// a later pass.
enum BundleIdentifierMigration {
    /// Retired identifiers, newest first, so the freshest state wins a conflict.
    private static let legacyIdentifiers = [
        "com.cloyd.ai-benchgauge",
        "com.cloyd.ai-leaderboards",
    ]
    /// The cookie jar sits beside the identifier, outside the website data.
    private static let cookieSuffix = ".binarycookies"
    /// Written by the first, one-shot cut of this migration. Retiring it keeps
    /// the retry honest, and the key itself is now dead weight in preferences.
    private static let retiredDoneKey = "bundleIdentifierMigrationDone"

    /// Must run before any web view or `URLSession` is created, or the current
    /// identifier claims empty stores first and there is nothing to adopt into.
    static func run(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        guard let current = Bundle.main.bundleIdentifier,
              !legacyIdentifiers.contains(current) else { return }
        defaults.removeObject(forKey: retiredDoneKey)
        adoptWebsiteData(into: current, fileManager: fileManager)
        adoptCookies(into: current, fileManager: fileManager)
        adoptPreferences(into: defaults)
        discardLegacyState(into: current, defaults: defaults, fileManager: fileManager)
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
        let preferences = library.appending(path: "Preferences", directoryHint: .isDirectory)
        // A move can fail on a locked or foreign volume; never delete the only
        // copy of a signed-in session, so the next launch can retry.
        let hasMigratedStore = hasWebsiteData(
            webKit.appending(path: current, directoryHint: .isDirectory),
            fileManager: fileManager
        )
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
            if defaults.persistentDomain(forName: identifier)?.isEmpty ?? true {
                try? fileManager.removeItem(
                    at: preferences.appending(
                        path: "\(identifier).plist",
                        directoryHint: .notDirectory
                    )
                )
            }
        }
    }
}
