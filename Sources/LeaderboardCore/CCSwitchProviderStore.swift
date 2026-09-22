import Foundation
import SQLite3

public enum CCSwitchProviderLoadResult: Equatable, Sendable {
    /// No install, or the file is not a CC Switch provider database we understand.
    case absent
    /// Schema matched. The Codex list may be empty.
    case records([CCSwitchProviderRecord])
    /// A regular database file is present, but this read failed.
    case unavailable
}

public struct CCSwitchInstall: Equatable, Sendable {
    public var root: URL
    public var databaseURL: URL
    public var settingsURL: URL
    public var xaiAuthURL: URL

    public init(root: URL, databaseURL: URL, settingsURL: URL, xaiAuthURL: URL) {
        self.root = root
        self.databaseURL = databaseURL
        self.settingsURL = settingsURL
        self.xaiAuthURL = xaiAuthURL
    }
}

/// Read-only view of the local CC Switch database.
///
/// `settings_config` is returned so the catalog can extract a key for one
/// request. Callers must not log the records, the override path, or auth files.
public enum CCSwitchProviderStore {
    private static let sqliteMagic = Data("SQLite format 3\0".utf8)
    private static let requiredColumns: Set<String> = [
        "id", "app_type", "name", "settings_config", "website_url",
        "created_at", "sort_index", "meta", "is_current",
    ]

    public static var defaultDatabaseURL: URL {
        resolveInstall().databaseURL
    }

    public static var defaultSettingsURL: URL {
        resolveInstall().settingsURL
    }

    public static var defaultXAIAuthURL: URL {
        resolveInstall().xaiAuthURL
    }

    /// CC Switch reads `app_config_dir_override` from its Tauri store before
    /// `~/.cc-switch`. An empty value, a non-string, or a path that does not
    /// exist falls back. A path that exists is used even when it has no database.
    public static func resolveInstall(
        appPathsURL: URL? = nil,
        homeDirectory: URL? = nil
    ) -> CCSwitchInstall {
        let home = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        let pathsURL = appPathsURL ?? defaultAppPathsURL(in: home)
        let root = overriddenConfigDirectory(appPathsURL: pathsURL, homeDirectory: home)
            ?? home.appending(path: ".cc-switch", directoryHint: .isDirectory)
        return CCSwitchInstall(
            root: root,
            databaseURL: root.appending(path: "cc-switch.db", directoryHint: .notDirectory),
            settingsURL: root.appending(path: "settings.json", directoryHint: .notDirectory),
            xaiAuthURL: root.appending(path: "xai_oauth_auth.json", directoryHint: .notDirectory)
        )
    }

    public static func loadCodexProviders(
        databaseURL: URL = defaultDatabaseURL
    ) -> CCSwitchProviderLoadResult {
        let path = databaseURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return .absent
        }
        guard let kind = fileKind(at: path) else {
            return .unavailable
        }
        guard kind == .typeRegular else {
            return .absent
        }
        guard let header = readPrefix(path, count: sqliteMagic.count) else {
            return .unavailable
        }
        guard header == sqliteMagic else {
            return .absent
        }

        var database: OpaquePointer?
        let opened = sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil)
        guard opened == SQLITE_OK, let database else {
            let code = database.map { sqlite3_extended_errcode($0) } ?? opened
            if let database {
                sqlite3_close(database)
            }
            return classify(code, schemaConfirmed: false)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)

        switch confirmSchema(database) {
        case .absent:
            return .absent
        case .unavailable:
            return .unavailable
        case .ok:
            break
        }

        let sql = """
        SELECT id, name, website_url, sort_index, created_at, is_current, meta, settings_config
        FROM providers
        WHERE app_type = 'codex'
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return .unavailable
        }
        defer { sqlite3_finalize(statement) }

        var records: [CCSwitchProviderRecord] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { return .unavailable }
            guard let id = columnText(statement, 0),
                  let name = columnText(statement, 1) else { continue }
            let createdAt = sqlite3_column_type(statement, 4) == SQLITE_NULL
                ? 0
                : sqlite3_column_int64(statement, 4)
            let sortIndex = sqlite3_column_type(statement, 3) == SQLITE_NULL
                ? nil
                : Int(sqlite3_column_int64(statement, 3))
            records.append(
                CCSwitchProviderRecord(
                    id: id,
                    name: name,
                    websiteURL: columnText(statement, 2),
                    sortIndex: sortIndex,
                    createdAt: createdAt,
                    isCurrent: sqlite3_column_int(statement, 5) != 0,
                    metaJSON: columnText(statement, 6) ?? "{}",
                    settingsConfigJSON: columnText(statement, 7) ?? "{}"
                )
            )
        }
        return .records(records)
    }

    /// Reads only `currentProviderCodex`. Other settings, including anything
    /// credential-shaped, are discarded. A missing or invalid file is not an error.
    public static func currentCodexProviderID(
        settingsURL: URL = defaultSettingsURL
    ) -> String? {
        guard let data = try? Data(contentsOf: settingsURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["currentProviderCodex"] as? String else { return nil }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Reads the usage totals that CC Switch has already recorded for a Codex
    /// provider. This is intentionally read-only and contains no credentials.
    public static func localUsage(
        providerID: String,
        databaseURL: URL = defaultDatabaseURL,
        now: Date = Date()
    ) -> [ParsedUsageWindow] {
        let path = databaseURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            if let database { sqlite3_close(database) }
            return []
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)

        let escapedID = providerID.replacingOccurrences(of: "'", with: "''")
        let windows: [(String, TimeInterval)] = [("24小时", 24 * 3600), ("7天", 7 * 24 * 3600)]
        return windows.compactMap { name, interval in
            let cutoff = Int64(now.timeIntervalSince1970 - interval)
            let sql = """
            SELECT COUNT(*),
                   COALESCE(SUM(input_tokens), 0),
                   COALESCE(SUM(output_tokens), 0),
                   COALESCE(SUM(total_cost_usd), 0)
            FROM proxy_request_logs
            WHERE app_type = 'codex' AND provider_id = '\(escapedID)' AND created_at >= \(cutoff)
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else { return nil }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            let requests = Int(sqlite3_column_int64(statement, 0))
            let inputTokens = sqlite3_column_int64(statement, 1)
            let outputTokens = sqlite3_column_int64(statement, 2)
            let costUSD = sqlite3_column_double(statement, 3)
            guard requests > 0 || inputTokens > 0 || outputTokens > 0 || costUSD > 0 else {
                return nil
            }
            return ParsedUsageWindow(
                name: name,
                requests: requests,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                costUSD: costUSD
            )
        }
    }

    private static func defaultAppPathsURL(in home: URL) -> URL {
        home.appending(
            path: "Library/Application Support/com.ccswitch.desktop/app_paths.json",
            directoryHint: .notDirectory
        )
    }

    /// `nil` means "fall back". A non-nil URL exists and must not be replaced
    /// with `~/.cc-switch`, even if that directory has no database.
    private static func overriddenConfigDirectory(appPathsURL: URL, homeDirectory: URL) -> URL? {
        guard let data = try? Data(contentsOf: appPathsURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["app_config_dir_override"] as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let resolved = expandHome(trimmed, homeDirectory: homeDirectory)
        guard FileManager.default.fileExists(atPath: resolved.path(percentEncoded: false)) else {
            return nil
        }
        return resolved
    }

    /// Matches CC Switch: `~`, `~/…`, and `~\…` expand. Other paths are used as given.
    private static func expandHome(_ raw: String, homeDirectory: URL) -> URL {
        if raw == "~" {
            return homeDirectory
        }
        if raw.hasPrefix("~/") {
            return homeDirectory.appending(path: String(raw.dropFirst(2)), directoryHint: .isDirectory)
        }
        if raw.hasPrefix("~\\") {
            return homeDirectory.appending(path: String(raw.dropFirst(2)), directoryHint: .isDirectory)
        }
        return URL(fileURLWithPath: raw, isDirectory: true)
    }

    private static func fileKind(at path: String) -> FileAttributeType? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let type = attributes[.type] as? FileAttributeType else { return nil }
        return type
    }

    /// `nil` means the regular file could not be read.
    private static func readPrefix(_ path: String, count: Int) -> Data? {
        guard count > 0, let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: count)
    }

    private enum SchemaProbe {
        case ok
        case absent
        case unavailable
    }

    private static func confirmSchema(_ database: OpaquePointer) -> SchemaProbe {
        var master: OpaquePointer?
        let masterSQL = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'providers' LIMIT 1"
        guard sqlite3_prepare_v2(database, masterSQL, -1, &master, nil) == SQLITE_OK,
              let master else {
            return probe(sqlite3_extended_errcode(database), schemaConfirmed: false)
        }
        defer { sqlite3_finalize(master) }
        switch sqlite3_step(master) {
        case SQLITE_ROW:
            break
        case SQLITE_DONE:
            return .absent
        default:
            return probe(sqlite3_extended_errcode(database), schemaConfirmed: false)
        }

        var info: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(providers)", -1, &info, nil) == SQLITE_OK,
              let info else {
            return .unavailable
        }
        defer { sqlite3_finalize(info) }

        var columns: Set<String> = []
        while true {
            let step = sqlite3_step(info)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { return .unavailable }
            if let name = columnText(info, 1) {
                columns.insert(name.lowercased())
            }
        }
        return requiredColumns.isSubset(of: columns) ? .ok : .absent
    }

    private static func probe(_ code: Int32, schemaConfirmed: Bool) -> SchemaProbe {
        switch classify(code, schemaConfirmed: schemaConfirmed) {
        case .absent: .absent
        case .unavailable: .unavailable
        case .records: .unavailable
        }
    }

    /// Before the schema is confirmed, "not a database" is absence. A present
    /// SQLite file that is busy, locked, unreadable, or corrupt is unavailable.
    /// After the schema matches, any failed read is unavailable.
    private static func classify(_ code: Int32, schemaConfirmed: Bool) -> CCSwitchProviderLoadResult {
        let primary = code & 0xFF
        if !schemaConfirmed, primary == SQLITE_NOTADB {
            return .absent
        }
        return .unavailable
    }

    private static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let bytes = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: bytes)
    }
}
