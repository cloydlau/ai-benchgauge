import CSQLite
import Foundation
import LeaderboardCore
import Testing

struct CodexTaskStatusTests {
    private func snapshot(_ id: String = "task", runtime: String = "active", status: String = "inProgress", flags: [String] = [], revision: Int = 1) -> [String: Any] {
        ["version": 11, "sourceClientId": "desktop", "params": ["hostId": "local", "conversationId": id,
          "change": ["type": "snapshot", "revision": revision, "conversationState": [
            "threadRuntimeStatus": ["type": runtime, "activeFlags": flags],
            "turnHistory": ["kind": "canonical", "history": ["islands": [["entries": [["value": "latest"]]]],
                "entitiesByKey": ["latest": ["status": status]]]]]]]]
    }

    private func patch(base: Int = 1, revision: Int = 2, runtime: String = "idle", status: String = "completed") -> [String: Any] {
        ["version": 11, "sourceClientId": "desktop", "params": ["hostId": "local", "conversationId": "task",
          "change": ["type": "patches", "baseRevision": base, "revision": revision, "patches": [
            ["op": "replace", "path": ["threadRuntimeStatus"], "value": ["type": runtime, "activeFlags": []]],
            ["op": "replace", "path": ["turnHistory", "history", "entitiesByKey", "latest", "status"], "value": status]]]]]
    }

    @Test func realRuntimeOverridesStaleHistoryAndReadClearsCompletedCount() {
        var projection = CodexTaskProjection()
        var stored = ["task": CodexStoredTask(status: "interrupted", unread: true),
                      "stale": CodexStoredTask(status: "inProgress", unread: true)]
        let received1 = projection.receive(snapshot())
        #expect(received1)
        #expect(projection.counts(stored: stored) == CodexTaskCounts(running: 1, unread: 0, failed: 0))
        let received2 = projection.receive(patch())
        #expect(received2)
        #expect(projection.counts(stored: stored) == CodexTaskCounts(running: 0, unread: 1, failed: 0))
        stored["task"]?.unread = false
        #expect(projection.counts(stored: stored) == CodexTaskCounts(running: 0, unread: 0, failed: 0))
    }

    @Test func failureRetryArchiveAndOwnerDisconnect() {
        var projection = CodexTaskProjection()
        let stored = ["task": CodexStoredTask(status: "failed", unread: true)]
        #expect(projection.counts(stored: stored).failed == 1)
        let received3 = projection.receive(snapshot())
        #expect(received3)
        #expect(projection.counts(stored: stored) == CodexTaskCounts(running: 1, unread: 0, failed: 0))
        let received4 = projection.receive(patch(status: "failed"))
        #expect(received4)
        #expect(projection.counts(stored: stored) == CodexTaskCounts(running: 0, unread: 0, failed: 1))
        let received5 = projection.receive(snapshot(revision: 3))
        #expect(received5)
        let received6 = projection.receive(patch(base: 3, revision: 4))
        #expect(received6)
        #expect(projection.counts(stored: stored).failed == 0)
        #expect(projection.counts(stored: [:]) == CodexTaskCounts(running: 0, unread: 0, failed: 0))
        let received7 = projection.receive(snapshot(revision: 5))
        #expect(received7)
        projection.removeOwner("desktop")
        #expect(projection.counts(stored: stored).running == 0)
    }

    @Test func approvalWaitAndUserInputAreNotExecutingAndToolErrorsAreNotFailedTasks() {
        var projection = CodexTaskProjection()
        let stored = ["task": CodexStoredTask(status: "inProgress", unread: false)]
        for flag in ["waitingOnApproval", "waitingOnUserInput"] {
            let received8 = projection.receive(snapshot(flags: [flag]))
            #expect(received8)
            #expect(projection.counts(stored: stored).running == 0)
        }
        let received9 = projection.receive(snapshot())
        #expect(received9)
        let toolError: [String: Any] = ["version": 11, "sourceClientId": "desktop", "params": ["hostId": "local", "conversationId": "task",
            "change": ["type": "patches", "baseRevision": 1, "revision": 2, "patches": [["op": "add",
                "path": ["turnHistory", "history", "entitiesByKey", "latest", "items", 0], "value": ["error": "temporary tool failure"]]]]]]
        let received10 = projection.receive(toolError)
        #expect(received10)
        #expect(projection.counts(stored: stored) == CodexTaskCounts(running: 1, unread: 0, failed: 0))
    }

    @Test func missingRevisionUnknownSchemaAndRemoteStreamsRequireResync() {
        var projection = CodexTaskProjection()
        let received11 = projection.receive(snapshot())
        #expect(received11)
        let received12 = projection.receive(patch(base: 0))
        #expect(!received12)
        var other = snapshot()
        other["version"] = 12
        let received13 = projection.receive(other)
        #expect(!received13)
        let received14 = projection.receive(snapshot(runtime: "unknown"))
        #expect(!received14)
        other = snapshot()
        var params = other["params"] as! [String: Any]
        params["hostId"] = "remote"
        other["params"] = params
        let received15 = projection.receive(other)
        #expect(!received15)
        #expect(CodexTaskCounts.menuBarText(nil).contains("—"))
        #expect(CodexTaskCounts.menuBarText(.init(running: 123, unread: 45, failed: 6)) == "▶ 123  ✓ 45  ! 6")
    }

    @Test func storeUsesLatestTurnLocalUnreadAccountAndDesktopScopeReadOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func create(_ name: String, sql: String) throws {
            var db: OpaquePointer?
            #expect(sqlite3_open(root.appendingPathComponent(name).path, &db) == SQLITE_OK)
            defer { sqlite3_close(db) }
            #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        }
        try create("state_5.sqlite", sql: """
        CREATE TABLE threads(id TEXT, creator_account_id TEXT, archived INT, source TEXT, originator TEXT, thread_source TEXT, creator_user_id TEXT);
        INSERT INTO threads VALUES ('complete','a',0,'vscode','Codex Desktop','user','u'),('fail','a',0,'vscode','Codex Desktop','user','u'),
        ('stale','a',0,'vscode','Codex Desktop','user','u'),('wrong-account','a',0,'vscode','Codex Desktop','user','u'),
        ('archived','a',1,'vscode','Codex Desktop','user','u'),('child','a',0,'vscode','Codex Desktop','subAgent','u'),
        ('cli','a',0,'exec','Codex Desktop','user','u');
        """)
        try create("thread_history_1.sqlite", sql: """
        CREATE TABLE thread_turns(thread_id TEXT, rollout_ordinal INT, status TEXT);
        INSERT INTO thread_turns VALUES ('complete',1,'failed'),('complete',2,'completed'),('fail',1,'failed'),('stale',1,'inProgress'),('wrong-account',1,'completed');
        """)
        let identityA = try CodexTaskStore.readIdentityKey(account: "a", user: "u")
        // Fixed value from SHA256 of the desktop's JSON tuple, independently
        // guards against accidentally hashing just the account or a dictionary.
        #expect(identityA == "4dd3641ec3abbe56c6b0d030bc188364e0d3bfc6246cdf898b22ede4d7bf6768")
        let identityB = try CodexTaskStore.readIdentityKey(account: "b", user: "u")
        let global: [String: Any] = ["electron-thread-read-state-v1": ["version": 1, "unreadByIdentity": [
            identityA: ["local:host": ["complete", "fail", "stale"], "remote:host": ["wrong-account"]],
            identityB: ["local:host": ["wrong-account"]]]]]
        let file = root.appendingPathComponent(".codex-global-state.json")
        try JSONSerialization.data(withJSONObject: global).write(to: file)
        let before = try Data(contentsOf: file)
        let records = try CodexTaskStore.read(root: root)
        #expect(Set(records.keys) == Set(["complete", "fail", "stale", "wrong-account"]))
        #expect(records["complete"]?.status == "completed")
        #expect(records["wrong-account"]?.unread == false)
        #expect(CodexTaskProjection().counts(stored: records) == CodexTaskCounts(running: 0, unread: 1, failed: 1))
        #expect(try Data(contentsOf: file) == before)
        try Data("{}".utf8).write(to: file)
        let missingReadState = try CodexTaskStore.read(root: root)
        #expect(missingReadState.values.allSatisfy { !$0.unread })
        #expect(CodexTaskProjection().counts(stored: missingReadState) == CodexTaskCounts(running: 0, unread: 0, failed: 1))
        try Data("{\"electron-thread-read-state-v1\":{\"version\":1,\"unreadByIdentity\":{}}}".utf8).write(to: file)
        #expect(try CodexTaskStore.read(root: root).values.allSatisfy { !$0.unread })
        try Data("{\"electron-thread-read-state-v1\":{\"version\":2,\"unreadByIdentity\":{}}}".utf8).write(to: file)
        #expect(throws: (any Error).self) { try CodexTaskStore.read(root: root) }
        #expect(throws: (any Error).self) { try CodexTaskStore.read(root: root.appendingPathComponent("missing")) }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("missing/state_5.sqlite").path))
    }
}
