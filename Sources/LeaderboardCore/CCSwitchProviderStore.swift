import Foundation
import SQLite3

public enum CCSwitchProviderLoadResult: Equatable, Sendable {
    case records([CCSwitchProviderRecord])
    case unavailable
}

/// Read-only view of the local CC Switch database.
///
/// `settings_config` is returned so the catalog can extract a key for one
/// request. Callers must not log the records.
public enum CCSwitchProviderStore {
    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".cc-switch/cc-switch.db", directoryHint: .notDirectory)
    }

    public static func loadCodexProviders(
        databaseURL: URL = defaultDatabaseURL
    ) -> CCSwitchProviderLoadResult {
        let path = databaseURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return .records([])
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            sqlite3_close(database)
            return .unavailable
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)

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

    public static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".cc-switch/settings.json", directoryHint: .notDirectory)
    }

    /// Reads only `currentProviderCodex`. Other settings, including anything
    /// credential-shaped, are discarded.
    public static func currentCodexProviderID(
        settingsURL: URL = defaultSettingsURL
    ) -> String? {
        guard let data = try? Data(contentsOf: settingsURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["currentProviderCodex"] as? String else { return nil }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let bytes = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: bytes)
    }
}
