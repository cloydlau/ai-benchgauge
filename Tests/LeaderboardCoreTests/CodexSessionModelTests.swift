import Foundation
import CSQLite
import LeaderboardCore
import Testing

struct CodexSessionModelTests {
    private func fixture(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("session-model-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("model = \"gpt-5.6-sol\"".utf8).write(to: root.appendingPathComponent("config.toml"))
        try execute(root, """
        CREATE TABLE threads(id TEXT, model TEXT, model_provider TEXT, archived INT DEFAULT 0,
          source TEXT DEFAULT 'vscode', originator TEXT DEFAULT 'Codex Desktop', thread_source TEXT DEFAULT 'user',
          recency_at_ms INT, recency_at INT, updated_at_ms INT, updated_at INT);
        """)
        try body(root)
    }

    private func execute(_ root: URL, _ sql: String) throws {
        var database: OpaquePointer?
        try #require(sqlite3_open(root.appendingPathComponent("state_5.sqlite").path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        try #require(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
    }

    private func read(_ root: URL) -> CodexModelConfiguration? {
        CCSwitchProviderStore.currentCodexModelConfiguration(environment: ["CODEX_HOME": root.path])
    }

    @Test func actualSessionOverridesDefaultAndRereadsModelSwitch() throws {
        try fixture { root in
            try execute(root, "INSERT INTO threads(id,model,model_provider,recency_at_ms) VALUES ('chat','gpt-6.1-sol','openai',100);")
            #expect(read(root) == CodexModelConfiguration(model: "gpt-6.1-sol", provider: "openai"))
            let target = CCSwitchQuotaTarget(id: "openai", shortName: "OpenAI", modelName: "gpt-5.6-sol",
                websiteURL: nil, kind: .officialNote, isCurrent: true, apiKey: nil, baseURL: nil)
            let chip = AccountQuotaChip(id: target.id, shortName: target.shortName, modelName: target.modelName,
                websiteURL: nil, kind: .officialNote, isCurrent: true,
                status: .windows([ParsedQuotaWindow(name: "five_hour", utilization: 25, resetsAt: nil)]))
            #expect(read(root)?.menuBarText(for: [chip], targets: [target]) ==
                AccountQuotaMenuBarText(name: "gpt-6.1-sol", fullName: "gpt-6.1-sol", quota: "5h 75%"))
            try execute(root, "UPDATE threads SET model='gpt-6-astra' WHERE id='chat';")
            #expect(read(root)?.model == "gpt-6-astra")
            try FileManager.default.removeItem(at: root.appendingPathComponent("config.toml"))
            #expect(read(root)?.model == "gpt-6-astra")
        }
    }

    @Test func userRecencyWinsOverBackgroundUpdatesAndNonDesktopThreads() throws {
        try fixture { root in
            try execute(root, """
            INSERT INTO threads(id,model,model_provider,recency_at_ms,updated_at_ms) VALUES
              ('current','gpt-6.1-sol','openai',200,200), ('background','gpt-5.6-sol','openai',100,999);
            INSERT INTO threads(id,model,model_provider,recency_at_ms,thread_source) VALUES ('agent','wrong','openai',999,'subagent');
            INSERT INTO threads(id,model,model_provider,recency_at_ms,archived) VALUES ('archived','wrong','openai',999,1);
            INSERT INTO threads(id,model,model_provider,recency_at_ms,source) VALUES ('cli','wrong','openai',999,'cli');
            INSERT INTO threads(id,model,model_provider,recency_at_ms,originator) VALUES ('vscode','wrong','openai',999,'VS Code');
            """)
            #expect(read(root)?.model == "gpt-6.1-sol")
            try execute(root, "UPDATE threads SET recency_at_ms=300 WHERE id='background';")
            #expect(read(root)?.model == "gpt-5.6-sol")
        }
    }

    @Test func olderSchemaFallsBackToSecondsWithoutCreatingMissingStore() throws {
        try fixture { root in
            try execute(root, """
            ALTER TABLE threads DROP COLUMN recency_at_ms;
            ALTER TABLE threads DROP COLUMN updated_at_ms;
            INSERT INTO threads(id,model,model_provider,recency_at,updated_at,thread_source) VALUES ('old','gpt-6.1-sol','openai',20,10,NULL);
            """)
            #expect(read(root)?.model == "gpt-6.1-sol")
            try FileManager.default.removeItem(at: root.appendingPathComponent("state_5.sqlite"))
            #expect(read(root)?.model == "gpt-5.6-sol")
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("state_5.sqlite").path))
        }
    }

    @Test func emptyUnsupportedAndInvalidLatestSessionFallBackSafely() throws {
        try fixture { root in
            #expect(read(root)?.model == "gpt-5.6-sol")
            try execute(root, """
            INSERT INTO threads(id,model,model_provider,recency_at_ms) VALUES ('older','gpt-6.1-sol','openai',100),('newer',' ','openai',200);
            """)
            #expect(read(root)?.model == "gpt-5.6-sol")
            try execute(root, "ALTER TABLE threads DROP COLUMN model;")
            #expect(read(root)?.model == "gpt-5.6-sol")
        }
    }

    @Test func sessionProviderNeverBorrowsDefaultsRouteOrCredentials() throws {
        try fixture { root in
            try Data("""
            model = "kimi-k3"
            model_provider = "custom"
            [model_providers.custom]
            base_url = "https://api.kimi.com/coding/v1"
            [model_providers.other]
            base_url = "https://other.example/v1"
            """.utf8).write(to: root.appendingPathComponent("config.toml"))
            try execute(root, "INSERT INTO threads(id,model,model_provider,recency_at_ms) VALUES ('chat','gpt-6.1-sol','openai',100);")
            #expect(read(root) == CodexModelConfiguration(model: "gpt-6.1-sol", provider: "openai"))
            try execute(root, "UPDATE threads SET model='other-model',model_provider='other';")
            #expect(read(root) == CodexModelConfiguration(model: "other-model", provider: "other", baseURL: "https://other.example/v1"))
            try execute(root, "UPDATE threads SET model_provider='unknown';")
            #expect(read(root)?.baseURL == nil)
            #expect(read(root)?.provider == "unknown")
        }
    }

    @Test func lockedDatabaseFallsBackInsteadOfBlockingDisplay() throws {
        try fixture { root in
            try execute(root, "INSERT INTO threads(id,model,model_provider,recency_at_ms) VALUES ('chat','gpt-6.1-sol','openai',100);")
            var database: OpaquePointer?
            try #require(sqlite3_open(root.appendingPathComponent("state_5.sqlite").path, &database) == SQLITE_OK)
            defer { sqlite3_close(database) }
            try #require(sqlite3_exec(database, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK)
            #expect(read(root)?.model == "gpt-5.6-sol")
            try #require(sqlite3_exec(database, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
            #expect(read(root)?.model == "gpt-6.1-sol")
        }
    }
}
