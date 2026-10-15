import Foundation
import Testing
import CSQLite
@testable import LeaderboardCore

struct SQLiteReadBoundaryTests {
    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func execute(_ url: URL, _ sql: String) throws {
        var database: OpaquePointer?
        try #require(sqlite3_open(url.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        try #require(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
    }
    @Test func providerReadSeparatesUnreadableMetadataAndSQLiteFailures() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("providers.sqlite")
        try execute(file, "CREATE TABLE providers(id TEXT, app_type TEXT, name TEXT, settings_config TEXT, website_url TEXT, created_at INT, sort_index INT, meta TEXT, is_current INT); INSERT INTO providers VALUES('id',NULL,'Fixture',NULL,NULL,NULL,NULL,NULL,0),('missing','codex',NULL,NULL,NULL,NULL,NULL,NULL,0);")
        let good = CCSwitchProviderStore.loadProviders(databaseURL: file, allApps: true)
        if case .records(let records) = good {
            #expect(records.count == 1)
            #expect(records.first?.metaJSON == "{}")
            #expect(records.first?.settingsConfigJSON == "{}")
        } else { Issue.record("The isolated SQLite fixture could not be read") }
        var ops = CCSwitchProviderStore.ReadOperations()
        ops.fileKind = { _ in nil }
        #expect(CCSwitchProviderStore.loadProviders(databaseURL: file, allApps: true, operations: ops) == .unavailable)
        ops = .init(); ops.prefix = { _, _ in nil }
        #expect(CCSwitchProviderStore.loadProviders(databaseURL: file, allApps: true, operations: ops) == .unavailable)
        for hasHandle in [true, false] {
            ops = .init(); ops.open = { path, handle, flags, vfs in
                if hasHandle { _ = sqlite3_open_v2(path, handle, flags, vfs) }
                return SQLITE_CANTOPEN
            }
            #expect(CCSwitchProviderStore.loadProviders(databaseURL: file, allApps: true, operations: ops) == .unavailable)
        }
        for marker in ["sqlite_master", "PRAGMA", "SELECT id"] {
            ops = .init(); ops.prepare = { db, sql, count, output, tail in
                if sql.map({ String(cString: $0).contains(marker) }) == true { return SQLITE_IOERR }
                return sqlite3_prepare_v2(db, sql, count, output, tail)
            }
            #expect(CCSwitchProviderStore.loadProviders(databaseURL: file, allApps: true, operations: ops) == .unavailable)
        }
        for marker in ["sqlite_master", "PRAGMA", "SELECT id"] {
            ops = .init(); ops.step = { statement in
                if let sql = sqlite3_sql(statement), String(cString: sql).contains(marker) { return SQLITE_IOERR }
                return sqlite3_step(statement)
            }
            #expect(CCSwitchProviderStore.loadProviders(databaseURL: file, allApps: true, operations: ops) == .unavailable)
        }
        ops = .init(); ops.prepare = { _, _, _, _, _ in SQLITE_NOTADB }; ops.extendedError = { _ in SQLITE_NOTADB }
        #expect(CCSwitchProviderStore.loadProviders(databaseURL: file, allApps: true, operations: ops) == .absent)
        #expect(CCSwitchProviderStore.fileKind(at: root.appendingPathComponent("missing").path) == nil)
        #expect(CCSwitchProviderStore.readPrefix(file.path, count: 0) == nil)
        #expect(CCSwitchProviderStore.readPrefix(root.appendingPathComponent("missing").path, count: 16) == nil)
    }
    @Test func sessionSupportsOneTimestampAndRejectsQueryPreparationFailures() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("state_5.sqlite")
        try execute(file, "CREATE TABLE threads(id TEXT, model TEXT, model_provider TEXT, archived INT, source TEXT, originator TEXT, thread_source TEXT, updated_at INT); INSERT INTO threads VALUES('fixture','model','provider',0,'vscode','Codex Desktop','user',1);")
        #expect(CodexSessionModelStore.read(root: root)?.model == "model")
        #expect(CodexSessionModelStore.read(root: root, prepare: { _, _, _, _, _ in SQLITE_IOERR }) == nil)
        #expect(CodexSessionModelStore.read(root: root, prepare: { db, sql, count, output, tail in
            if sql.map({ String(cString: $0).contains("SELECT model") }) == true { return SQLITE_IOERR }
            return sqlite3_prepare_v2(db, sql, count, output, tail)
        }) == nil)
        try execute(file, "ALTER TABLE threads DROP COLUMN updated_at;")
        #expect(CodexSessionModelStore.read(root: root) == nil)
    }
    @Test func taskReadPropagatesBindAndStepFailuresWithoutPartialCounts() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        try execute(root.appendingPathComponent("state_5.sqlite"), "CREATE TABLE threads(id TEXT, creator_account_id TEXT, creator_user_id TEXT, archived INT, source TEXT, originator TEXT, thread_source TEXT); INSERT INTO threads VALUES('fixture',NULL,NULL,0,'vscode','Codex Desktop','user');")
        try execute(root.appendingPathComponent("thread_history_1.sqlite"), "CREATE TABLE thread_turns(thread_id TEXT, status TEXT, rollout_ordinal INT);")
        try Data("{}".utf8).write(to: root.appendingPathComponent(".codex-global-state.json"))
        var ops = CodexTaskStore.ReadOperations()
        ops.bind = { _, _, _, _, _ in SQLITE_TOOBIG }
        #expect(throws: (any Error).self) { try CodexTaskStore.read(root: root, operations: ops) }
        for marker in ["threads", "thread_turns"] {
            ops = .init(); ops.step = { statement in
                if let sql = sqlite3_sql(statement), String(cString: sql).contains(marker) { return SQLITE_IOERR }
                return sqlite3_step(statement)
            }
            #expect(throws: (any Error).self) { try CodexTaskStore.read(root: root, operations: ops) }
        }
        #expect(try CodexTaskStore.read(root: root)["fixture"]?.status == nil)
        let global = root.appendingPathComponent(".codex-global-state.json")
        try Data("invalid".utf8).write(to: global)
        #expect(throws: (any Error).self) { try CodexTaskStore.read(root: root) }
        try FileManager.default.removeItem(at: global)
        #expect(throws: (any Error).self) { try CodexTaskStore.read(root: root) }
        try Data("{}".utf8).write(to: global)
        try execute(root.appendingPathComponent("state_5.sqlite"), "DROP TABLE threads;")
        #expect(throws: (any Error).self) { try CodexTaskStore.read(root: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("thread_history_1.sqlite"))
        #expect(throws: (any Error).self) { try CodexTaskStore.read(root: root) }
        #expect(String(describing: CodexTaskStore.ReadError.read) == "read")
        #expect(String(describing: CodexTaskStore.ReadError.database(stage: "fixture", code: 10)) == "database:fixture:10")
        #expect(String(describing: CodexTaskStore.ReadError.schema(stage: "fixture")) == "schema:fixture")
    }
}
