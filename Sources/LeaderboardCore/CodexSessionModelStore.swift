import Foundation
import CSQLite

/// Read-only display metadata for the most recently used local desktop chat.
/// Recency is user interaction order, unlike updated_at which background turns
/// can change. This does not infer which window/tab is currently focused.
enum CodexSessionModelStore {
    static func read(root: URL) -> CodexModelConfiguration? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(root.appendingPathComponent("state_5.sqlite").path,
                              &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 50)

        var schema: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(threads)", -1, &schema, nil) == SQLITE_OK else { return nil }
        var columns = Set<String>()
        while sqlite3_step(schema) == SQLITE_ROW {
            if let name = string(schema, column: 1) { columns.insert(name) }
        }
        sqlite3_finalize(schema)
        guard Set(["model", "model_provider", "archived", "source", "originator", "thread_source", "id"])
            .isSubset(of: columns) else { return nil }
        let timestamps = ["recency_at_ms", "recency_at", "updated_at_ms", "updated_at"].filter(columns.contains)
        guard !timestamps.isEmpty else { return nil }
        let values = timestamps.map { $0.hasSuffix("_ms") ? $0 : "\($0) * 1000" }
        let order = values.count == 1 ? values[0] : "COALESCE(\(values.joined(separator: ", ")))"
        let sql = """
        SELECT model, model_provider FROM threads
        WHERE archived = 0 AND source = 'vscode' AND originator = 'Codex Desktop'
          AND (thread_source IS NULL OR thread_source = 'user')
        ORDER BY \(order) DESC, id DESC LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let model = string(statement, column: 0)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !model.isEmpty, model.count <= 128,
              let provider = string(statement, column: 1)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !provider.isEmpty, provider.count <= 128 else { return nil }
        return CodexModelConfiguration(model: model, provider: provider)
    }

    private static func string(_ statement: OpaquePointer?, column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }
}
