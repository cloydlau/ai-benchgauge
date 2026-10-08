import CSQLite
import Darwin
import Foundation
import LeaderboardCore
import Testing
@testable import leaderboard_menu

private actor TaskCountRecorder {
    var values: [CodexTaskCounts?] = []
    func record(_ value: CodexTaskCounts?) { values.append(value) }
}

private final class StoreReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    func read(_ root: URL) throws -> [String: CodexStoredTask] {
        lock.withLock { reads += 1 }
        return try CodexTaskStore.read(root: root)
    }
    var count: Int { lock.withLock { reads } }
}

/// A real local stream and real SQLite/read-state files. It has no access to
/// the user's Codex home and only implements initialize/follow notifications.
private final class TaskIPCFixture: @unchecked Sendable {
    let root: URL
    private let lock = NSLock()
    private var listener: Int32 = -1
    private var client: Int32 = -1
    private var stopped = false
    private var following = Set<String>()
    private var revision = 0
    private var states: [String: (runtime: String, status: String)] = [:]

    init() throws {
        // Darwin's socket paths are limited to 104 bytes; macOS's default
        // /var/folders temporary directory can already use most of that budget.
        root = URL(fileURLWithPath: "/tmp").appendingPathComponent("bg-events-\(UUID().uuidString)")
        let ipc = root.appendingPathComponent("ipc")
        try FileManager.default.createDirectory(at: ipc, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try sql("state_5.sqlite", """
        CREATE TABLE threads(id TEXT, creator_account_id TEXT, creator_user_id TEXT, archived INT, source TEXT, originator TEXT, thread_source TEXT);
        INSERT INTO threads VALUES ('task',NULL,NULL,0,'vscode','Codex Desktop','user');
        """)
        try sql("thread_history_1.sqlite", """
        CREATE TABLE thread_turns(thread_id TEXT, rollout_ordinal INT, status TEXT);
        INSERT INTO thread_turns VALUES ('task',1,'completed');
        """)
        try markUnread(false)
        listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(root.appendingPathComponent("ipc/ipc.sock").path.utf8) + [0]
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw FixtureError.socket }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path) }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard listener >= 0, bound == 0, Darwin.listen(listener, 1) == 0 else { throw FixtureError.socket }
        let serverFD = listener
        DispatchQueue(label: "benchgauge.fixture-ipc").async { [weak self] in
            let fd = Darwin.accept(serverFD, nil, nil)
            guard fd >= 0, let self else { return }
            var suppress: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &suppress, socklen_t(MemoryLayout<Int32>.size))
            let accepted = self.lock.withLock {
                if self.stopped { return false }
                self.client = fd
                return true
            }
            guard accepted else { Darwin.close(fd); return }
            self.serve(fd)
        }
    }

    enum FixtureError: Error { case socket, database }
    func sql(_ name: String, _ text: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(root.appendingPathComponent(name).path, &db) == SQLITE_OK else { throw FixtureError.database }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, text, nil, nil, nil) == SQLITE_OK else { throw FixtureError.database }
    }
    func markUnread(_ unread: Bool) throws {
        let object: [String: Any] = ["electron-thread-read-state-v1": ["version": 1,
            "unreadByIdentity": ["legacy": ["local:fixture": unread ? ["task"] : []]]]]
        try JSONSerialization.data(withJSONObject: object).write(to: root.appendingPathComponent(".codex-global-state.json"), options: .atomic)
    }
    func addThread() throws {
        try sql("state_5.sqlite", "INSERT INTO threads VALUES ('new',NULL,NULL,0,'vscode','Codex Desktop','user');")
        try sql("thread_history_1.sqlite", "INSERT INTO thread_turns VALUES ('new',1,'inProgress');")
    }
    func snapshot(_ id: String = "task", runtime: String, status: String) {
        lock.withLock {
            states[id] = (runtime, status)
            snapshotLocked(id, runtime: runtime, status: status)
        }
    }
    func ownerChanged() {
        lock.withLock {
            sendLocked(["type": "broadcast", "method": "client-status-changed", "version": 0,
                "params": ["status": "disconnected", "clientId": "fixture-owner"]])
            sendLocked(["type": "broadcast", "method": "thread-stream-following-status-requested", "version": 1,
                "sourceClientId": "replacement-owner", "params": ["hostId": "local", "conversationId": "task"]])
        }
    }
    private func snapshotLocked(_ id: String, runtime: String, status: String) {
        revision += 1
        sendLocked(["type": "broadcast", "method": "thread-stream-state-changed", "version": 11, "sourceClientId": "fixture-owner",
            "params": ["conversationId": id, "hostId": "local", "change": ["type": "snapshot", "revision": revision,
                "conversationState": ["threadRuntimeStatus": ["type": runtime, "activeFlags": []], "turns": [["status": status]]]]]])
    }
    private func serve(_ fd: Int32) {
        defer { Darwin.close(fd) }
        func read(_ count: Int) -> Data? {
            var result = Data()
            while result.count < count {
                var buffer = [UInt8](repeating: 0, count: count - result.count)
                let bytes = Darwin.read(fd, &buffer, buffer.count)
                guard bytes > 0 else { return nil }
                result.append(contentsOf: buffer.prefix(bytes))
            }
            return result
        }
        while let header = read(4) {
            let length = header.enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
            guard length < 1_048_576, let data = read(length), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { break }
            let params = object["params"] as? [String: Any] ?? [:]
            lock.withLock {
                if object["method"] as? String == "initialize" {
                    sendLocked(["type": "response", "method": "initialize", "resultType": "success", "requestId": object["requestId"]!, "result": ["clientId": "fixture-reader"]])
                } else if object["method"] as? String == "thread-stream-following-changed", let id = params["conversationId"] as? String, params["following"] as? Bool == true {
                    following.insert(id)
                    snapshotLocked(id, runtime: states[id]?.runtime ?? (id == "new" ? "active" : "idle"),
                        status: states[id]?.status ?? (id == "new" ? "inProgress" : "completed"))
                }
            }
        }
    }
    private func sendLocked(_ object: [String: Any]) {
        guard client >= 0, let payload = try? JSONSerialization.data(withJSONObject: object) else { return }
        var length = UInt32(payload.count).littleEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(payload)
        frame.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let n = Darwin.write(client, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if n <= 0 { break }
                offset += n
            }
        }
    }
    func closeConnection() {
        lock.withLock {
            if client >= 0 { Darwin.shutdown(client, SHUT_RDWR); client = -1 }
        }
    }
    func stop() {
        closeConnection()
        lock.withLock {
            stopped = true
            if listener >= 0 { Darwin.shutdown(listener, SHUT_RDWR); Darwin.close(listener); listener = -1 }
        }
    }
    deinit { stop(); try? FileManager.default.removeItem(at: root) }
}

@Suite(.serialized)
struct CodexTaskMonitorTests {
    private func waitFor(_ expected: CodexTaskCounts?, recorder: TaskCountRecorder, after: Int = 0, timeout: TimeInterval = 1) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let values = await recorder.values
            if values.dropFirst(after).contains(where: { $0 == expected }) { return true }
            try await Task.sleep(for: .milliseconds(10))
        } while Date() < deadline
        return false
    }

    @Test func idlePushImmediatelyUpdatesWithoutAnotherDatabaseReadAndCloseInvalidates() async throws {
        let fixture = try TaskIPCFixture()
        defer { fixture.stop() }
        let reads = StoreReadCounter()
        let monitor = CodexTaskMonitor(root: fixture.root, readStore: { try reads.read($0) })
        let updates = await monitor.updates(desktopRunning: true)
        let recorder = TaskCountRecorder()
        let listener = Task { for await count in updates { await recorder.record(count) } }
        let ready = try await waitFor(.init(running: 0, unread: 0, failed: 0), recorder: recorder, timeout: 4)
        #expect(ready)
        let before = reads.count
        fixture.snapshot(runtime: "active", status: "inProgress")
        let active = try await waitFor(.init(running: 1, unread: 0, failed: 0), recorder: recorder, timeout: 0.5)
        #expect(active)
        #expect(reads.count == before)
        fixture.snapshot(runtime: "idle", status: "failed")
        let failed = try await waitFor(.init(running: 0, unread: 0, failed: 1), recorder: recorder, timeout: 0.5)
        #expect(failed)
        let afterOwner = await recorder.values.count
        fixture.ownerChanged()
        let restored = try await waitFor(.init(running: 0, unread: 0, failed: 1), recorder: recorder, after: afterOwner, timeout: 0.5)
        #expect(restored)
        #expect(reads.count == before)
        let after = await recorder.values.count
        fixture.closeConnection()
        let unavailable = try await waitFor(nil, recorder: recorder, after: after, timeout: 0.5)
        #expect(unavailable)
        await monitor.stop()
        listener.cancel()
    }

    @Test func atomicUnreadReplacementNewTaskAndDesktopLifecycleWakeFromIdle() async throws {
        let fixture = try TaskIPCFixture()
        defer { fixture.stop() }
        let monitor = CodexTaskMonitor(root: fixture.root)
        let updates = await monitor.updates(desktopRunning: false)
        let recorder = TaskCountRecorder()
        let listener = Task { for await count in updates { await recorder.record(count) } }
        await monitor.setDesktopRunning(true)
        let ready = try await waitFor(.init(running: 0, unread: 0, failed: 0), recorder: recorder, timeout: 4)
        #expect(ready)
        try fixture.markUnread(true)
        let unread = try await waitFor(.init(running: 0, unread: 1, failed: 0), recorder: recorder)
        #expect(unread)
        let afterRead = await recorder.values.count
        try fixture.markUnread(false)
        let read = try await waitFor(.init(running: 0, unread: 0, failed: 0), recorder: recorder, after: afterRead)
        #expect(read)
        try fixture.addThread()
        let new = try await waitFor(.init(running: 1, unread: 0, failed: 0), recorder: recorder)
        #expect(new)
        let afterClose = await recorder.values.count
        await monitor.setDesktopRunning(false)
        let closed = try await waitFor(nil, recorder: recorder, after: afterClose)
        #expect(closed)
        await monitor.stop()
        await listener.value
    }

    @Test func fallbackCadenceAndRetryAreBounded() {
        #expect(CodexTaskMonitor.reconciliationDelay(running: 1) == 5)
        #expect(CodexTaskMonitor.reconciliationDelay(running: 0) == 30)
        #expect((1...8).map(CodexTaskMonitor.retryDelay) == [2, 4, 8, 16, 30, 30, 30, 30])
    }
}
