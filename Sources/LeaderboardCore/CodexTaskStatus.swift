import Foundation
import CSQLite
#if canImport(CryptoKit)
import CryptoKit
#elseif os(Windows)
import CPlatformSupport
#endif

public struct CodexTaskCounts: Equatable, Sendable, Codable {
    public var running: Int
    public var unread: Int
    public var failed: Int

    public init(running: Int, unread: Int, failed: Int) {
        self.running = running
        self.unread = unread
        self.failed = failed
    }

    public static func menuBarText(_ counts: Self?) -> String {
        guard let counts else { return "▶ —  ✓ —  ! —" }
        return "▶ \(counts.running)  ✓ \(counts.unread)  ! \(counts.failed)"
    }

    public static func help(_ counts: Self?, chinese: Bool) -> String {
        guard let counts else {
            return chinese ? "Codex 任务状态暂不可用" : "Codex task status unavailable"
        }
        return chinese
            ? "Codex · 执行中 \(counts.running) · 已完成待查看 \(counts.unread) · 报错 \(counts.failed)"
            : "Codex · Running \(counts.running) · Completed unread \(counts.unread) · Failed \(counts.failed)"
    }
}

public struct CodexStoredTask: Sendable {
    public var status: String?
    public var unread: Bool
    public init(status: String?, unread: Bool) {
        self.status = status
        self.unread = unread
    }
}

/// Only the visible desktop threads and their latest turn are read. Historical
/// inProgress rows never establish liveness; that comes from the desktop IPC.
public enum CodexTaskStore {
    public static func read(root: URL) throws -> [String: CodexStoredTask] {
        let state = try database(root.appendingPathComponent("state_5.sqlite"))
        defer { sqlite3_close(state) }
        let history = try database(root.appendingPathComponent("thread_history_1.sqlite"))
        defer { sqlite3_close(history) }
        let data = try Data(contentsOf: root.appendingPathComponent(".codex-global-state.json"))
        let global = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let readState = global?["electron-thread-read-state-v1"] as? [String: Any],
              readState["version"] as? Int == 1,
              let identities = readState["unreadByIdentity"] as? [String: [String: [String]]] else {
            throw ReadError.schema
        }
        let unreadByAccount = identities.mapValues { hosts in
            Set(hosts.filter { $0.key.hasPrefix("local:") }.values.flatMap { $0 })
        }
        let legacyUnread = Set(unreadByAccount.values.flatMap { $0 })
        var rows: OpaquePointer?
        guard sqlite3_prepare_v2(state, "SELECT id, creator_account_id, creator_user_id FROM threads WHERE archived = 0 AND source = 'vscode' AND originator = 'Codex Desktop' AND (thread_source IS NULL OR thread_source = 'user')", -1, &rows, nil) == SQLITE_OK else { throw ReadError.schema }
        defer { sqlite3_finalize(rows) }
        var latest: OpaquePointer?
        guard sqlite3_prepare_v2(history, "SELECT status FROM thread_turns WHERE thread_id = ? ORDER BY rollout_ordinal DESC LIMIT 1", -1, &latest, nil) == SQLITE_OK else { throw ReadError.schema }
        defer { sqlite3_finalize(latest) }
        var result: [String: CodexStoredTask] = [:]
        var step = sqlite3_step(rows)
        while step == SQLITE_ROW {
            let id = string(rows, 0)!
            let account = string(rows, 1)
            let user = string(rows, 2)
            sqlite3_reset(latest)
            sqlite3_clear_bindings(latest)
            let bound = id.withCString { sqlite3_bind_text(latest, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard bound == SQLITE_OK else { throw ReadError.read }
            let statusStep = sqlite3_step(latest)
            guard statusStep == SQLITE_ROW || statusStep == SQLITE_DONE else { throw ReadError.read }
            let identity = try account.flatMap { account in try user.map { try readIdentityKey(account: account, user: $0) } }
            let unread = identity.map { unreadByAccount[$0, default: []].contains(id) } ?? legacyUnread.contains(id)
            result[id] = CodexStoredTask(status: statusStep == SQLITE_ROW ? string(latest, 0) : nil, unread: unread)
            step = sqlite3_step(rows)
        }
        guard step == SQLITE_DONE else { throw ReadError.read }
        return result
    }

    private enum ReadError: Error { case schema, read }
    /// Desktop read-state identities are hashes of [kind, account, user], not
    /// raw account IDs. These metadata fields do not contain authentication.
    public static func readIdentityKey(account: String, user: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["chatgpt", account, user], options: [.withoutEscapingSlashes])
        #if os(Windows)
        var digest = [UInt8](repeating: 0, count: 32)
        let ok = data.withUnsafeBytes { bg_sha256($0.bindMemory(to: UInt8.self).baseAddress, Int32(data.count), &digest) }
        guard ok != 0 else { throw ReadError.read }
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #endif
    }
    private static func database(_ url: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw ReadError.read
        }
        sqlite3_busy_timeout(db, 250)
        return db
    }
    private static func string(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }
}

/// Keeps status metadata, never messages, tool arguments or transcript contents.
/// Versions/revisions are checked so a missed patch cannot leave a false count.
public struct CodexTaskProjection {
    private struct Live {
        var owner: String
        var revision: Int
        var runtime: String
        var flags: [String]
        var latestKey: String?
        var status: String?
    }
    private var live: [String: Live] = [:]
    public init() {}

    public mutating func removeOwner(_ owner: String) {
        live = live.filter { $0.value.owner != owner }
    }

    /// Returns false when this thread needs a fresh snapshot.
    public mutating func receive(_ message: [String: Any]) -> Bool {
        guard message["version"] as? Int == 11,
              let owner = message["sourceClientId"] as? String,
              let params = message["params"] as? [String: Any], params["hostId"] as? String == "local",
              let id = params["conversationId"] as? String,
              let change = params["change"] as? [String: Any], let revision = change["revision"] as? Int else { return false }
        if change["type"] as? String == "snapshot" {
            guard let state = change["conversationState"] as? [String: Any],
                  let runtime = state["threadRuntimeStatus"] as? [String: Any],
                  let type = runtime["type"] as? String,
                  ["active", "idle", "notLoaded", "systemError"].contains(type) else { return false }
            var key: String?
            var status: String?
            if let turnHistory = state["turnHistory"] as? [String: Any],
               let history = turnHistory["history"] as? [String: Any],
               let islands = history["islands"] as? [[String: Any]],
               let island = islands.last,
               let entries = island["entries"] as? [[String: Any]],
               let entities = history["entitiesByKey"] as? [String: [String: Any]] {
                key = entries.last?["value"] as? String
                status = key.flatMap { entities[$0]?["status"] as? String }
            } else {
                status = (state["turns"] as? [[String: Any]])?.last?["status"] as? String
            }
            live[id] = Live(owner: owner, revision: revision, runtime: type,
                            flags: runtime["activeFlags"] as? [String] ?? [], latestKey: key, status: status)
            return true
        }
        guard change["type"] as? String == "patches", var value = live[id], value.owner == owner,
              change["baseRevision"] as? Int == value.revision,
              let patches = change["patches"] as? [[String: Any]] else { return false }
        for patch in patches {
            guard let path = patch["path"] as? [Any], let first = path.first as? String else { return false }
            if first == "threadRuntimeStatus" {
                if path.count == 1, let runtime = patch["value"] as? [String: Any], let type = runtime["type"] as? String {
                    value.runtime = type
                    value.flags = runtime["activeFlags"] as? [String] ?? []
                } else if path.count == 2, path[1] as? String == "type", let type = patch["value"] as? String {
                    value.runtime = type
                } else if path.count == 2, path[1] as? String == "activeFlags", let flags = patch["value"] as? [String] {
                    value.flags = flags
                } else { return false }
                guard ["active", "idle", "notLoaded", "systemError"].contains(value.runtime) else { return false }
            }
            if first == "turns" { return false }
            if first == "turnHistory" {
                let names = path.compactMap { $0 as? String }
                if names.count == 5, names[2] == "entitiesByKey", names[3] == value.latestKey, names[4] == "status" {
                    value.status = patch["value"] as? String
                } else if names.count < 5 || names.contains("islands") { return false }
                // Item/tool/error patches inside a turn are deliberately ignored.
            }
        }
        value.revision = revision
        live[id] = value
        return true
    }

    public func counts(stored: [String: CodexStoredTask]) -> CodexTaskCounts {
        var result = CodexTaskCounts(running: 0, unread: 0, failed: 0)
        for (id, record) in stored {
            if let current = live[id], current.runtime == "active" {
                if !current.flags.contains("waitingOnApproval") && !current.flags.contains("waitingOnUserInput") { result.running += 1 }
                continue
            }
            if live[id]?.runtime == "systemError" || (live[id]?.status ?? record.status) == "failed" {
                result.failed += 1
            } else if (live[id]?.status ?? record.status) == "completed", record.unread {
                result.unread += 1
            }
        }
        return result
    }
}
