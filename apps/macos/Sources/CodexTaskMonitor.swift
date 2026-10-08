import Darwin
import Foundation
import LeaderboardCore

/// A passive follower of the local desktop's existing stream. It never starts
/// an app-server, resumes a thread, marks it read, or responds to an approval.
/// The private desktop protocol is versioned: incompatible data is unavailable.
actor CodexTaskMonitor {
    private let root: URL
    private var socketFD: Int32 = -1
    private var clientID: String?
    private var input = Data()
    private var projection = CodexTaskProjection()
    private var subscriptions = Set<String>()
    private var pendingSnapshots = Set<String>()
    private var connectedAt = Date.distantPast
    private var lastSnapshotRequest: [String: Date] = [:]

    init(root: URL? = nil) {
        self.root = root ?? ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    func poll(desktopRunning: Bool) -> CodexTaskCounts? {
        #if DEBUG
        let diagnostic = CommandLine.arguments.contains("--codex-task-status")
        if diagnostic && !desktopRunning { FileHandle.standardError.write(Data("Codex desktop is closed\n".utf8)) }
        #endif
        guard desktopRunning else { disconnect(); return nil }
        do {
            let stored = try CodexTaskStore.read(root: root)
            if socketFD < 0 { try connect() }
            try drain()
            if clientID != nil {
                for id in Set(stored.keys).subtracting(subscriptions) {
                    try follow(id, enabled: true)
                    subscriptions.insert(id)
                }
                for id in subscriptions.subtracting(stored.keys) {
                    try follow(id, enabled: false)
                    subscriptions.remove(id)
                    pendingSnapshots.remove(id)
                }
                for id in pendingSnapshots where Date().timeIntervalSince(lastSnapshotRequest[id] ?? .distantPast) >= 2 {
                    try follow(id, enabled: true)
                }
                try drain()
            }
            // Owners reply only for loaded conversations. A short warm-up lets
            // those snapshots arrive; unloaded threads cannot be executing.
            #if DEBUG
            if diagnostic { FileHandle.standardError.write(Data("Status stream: initialized=\(clientID != nil), warm=\(Date().timeIntervalSince(connectedAt) >= 2), resync=\(pendingSnapshots.count), partialBytes=\(input.count)\n".utf8)) }
            #endif
            guard clientID != nil, Date().timeIntervalSince(connectedAt) >= 2 else { return nil }
            guard pendingSnapshots.isEmpty, input.isEmpty else { return nil }
            return projection.counts(stored: stored)
        } catch {
            #if DEBUG
            if CommandLine.arguments.contains("--codex-task-status") {
                FileHandle.standardError.write(Data("Codex status read failed: \(type(of: error)) \(error)\n".utf8))
            }
            #endif
            disconnect()
            return nil
        }
    }

    func stop() { disconnect() }

    private enum StreamError: Error { case unavailable, invalid }
    private func connect() throws {
        let path = root.appendingPathComponent("ipc/ipc.sock").path
        var info = stat()
        guard lstat(path, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFSOCK else { throw StreamError.unavailable }
        var parent = stat()
        guard lstat(root.appendingPathComponent("ipc").path, &parent) == 0,
              parent.st_uid == getuid(), (parent.st_mode & S_IFMT) == S_IFDIR,
              parent.st_mode & 0o022 == 0 else { throw StreamError.unavailable }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw StreamError.invalid }
        withUnsafeMutableBytes(of: &address.sun_path) { target in target.copyBytes(from: bytes) }
        socketFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw StreamError.unavailable }
        var suppressSignal: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &suppressSignal, socklen_t(MemoryLayout<Int32>.size))
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0, fcntl(socketFD, F_SETFL, O_NONBLOCK) == 0 else { throw StreamError.unavailable }
        connectedAt = Date()
        try send(["type": "request", "requestId": UUID().uuidString, "sourceClientId": "initializing-client",
                  "version": 0, "method": "initialize", "params": ["clientType": "benchgauge"]])
    }

    private func follow(_ id: String, enabled: Bool) throws {
        guard let clientID else { throw StreamError.unavailable }
        if enabled { lastSnapshotRequest[id] = Date() }
        try send(["type": "broadcast", "method": "thread-stream-following-changed", "version": 1,
                  "sourceClientId": clientID, "params": ["conversationId": id, "hostId": "local", "following": enabled]])
    }

    private func send(_ object: [String: Any]) throws {
        let payload = try JSONSerialization.data(withJSONObject: object)
        var size = UInt32(payload.count).littleEndian
        var frame = withUnsafeBytes(of: &size) { Data($0) }
        frame.append(payload)
        try frame.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(socketFD, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard count > 0 else { throw StreamError.unavailable }
                offset += count
            }
        }
    }

    private func drain() throws {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        let deadline = Date().addingTimeInterval(0.25)
        // Bound work per poll, without ever dropping a partial frame.
        for _ in 0..<512 {
            let count = Darwin.read(socketFD, &buffer, buffer.count)
            if count == 0 { throw StreamError.unavailable }
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    // The router sends large initial snapshots in chunks under
                    // socket backpressure. Keep draining an unfinished frame so
                    // one menu refresh does not consume just one 16 KB chunk.
                    var descriptor = pollfd(fd: socketFD, events: Int16(POLLIN), revents: 0)
                    if Date() < deadline, Darwin.poll(&descriptor, 1, 10) > 0 { continue }
                    break
                }
                if errno == EINTR { continue }
                throw StreamError.unavailable
            }
            input.append(contentsOf: buffer.prefix(count))
            while input.count >= 4 {
                let length = input.prefix(4).enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
                guard length > 0, length <= 32 * 1_024 * 1_024 else { throw StreamError.invalid }
                guard input.count >= length + 4 else { break }
                let data = Data(input.dropFirst(4).prefix(length))
                input.removeFirst(length + 4)
                guard let message = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw StreamError.invalid }
                try handle(message)
            }
        }
    }

    private func handle(_ message: [String: Any]) throws {
        if message["type"] as? String == "response", message["method"] as? String == "initialize" {
            guard message["resultType"] as? String == "success",
                  let result = message["result"] as? [String: Any], let id = result["clientId"] as? String else { throw StreamError.invalid }
            clientID = id
        } else if message["type"] as? String == "client-discovery-request", let id = message["requestId"] as? String {
            try send(["type": "client-discovery-response", "requestId": id, "response": ["canHandle": false]])
        } else if message["type"] as? String == "broadcast" {
            let params = message["params"] as? [String: Any] ?? [:]
            if message["method"] as? String == "client-status-changed", params["status"] as? String == "disconnected",
               let owner = params["clientId"] as? String { projection.removeOwner(owner) }
            if message["method"] as? String == "thread-stream-state-changed", params["hostId"] as? String == "local",
               let id = params["conversationId"] as? String, subscriptions.contains(id) {
                guard message["version"] as? Int == 11 else { throw StreamError.invalid }
                if projection.receive(message) {
                    pendingSnapshots.remove(id)
                } else {
                    pendingSnapshots.insert(id)
                    // Revisions can change across reconnects or history edits.
                    // Ask the owner for a fresh snapshot; never resume a thread.
                    if Date().timeIntervalSince(lastSnapshotRequest[id] ?? .distantPast) >= 2 { try follow(id, enabled: true) }
                }
            }
        }
    }

    private func disconnect() {
        if socketFD >= 0 { Darwin.close(socketFD) }
        socketFD = -1
        clientID = nil
        input.removeAll()
        subscriptions.removeAll()
        pendingSnapshots.removeAll()
        lastSnapshotRequest.removeAll()
        projection = CodexTaskProjection()
    }
}
