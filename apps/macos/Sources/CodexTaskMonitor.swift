import Darwin
import Foundation
import LeaderboardCore
import OSLog

/// A passive follower of the local desktop's existing stream. It never starts
/// an app-server, resumes a thread, marks it read, or responds to an approval.
/// The private desktop protocol is versioned: incompatible data is unavailable.
actor CodexTaskMonitor {
    private static let logger = Logger(subsystem: "com.cloydlau.ai-benchgauge", category: "CodexTaskMonitor")
    private let root: URL
    private let readStore: @Sendable (URL) throws -> [String: CodexStoredTask]
    private var socketFD: Int32 = -1
    private var clientID: String?
    private var input = Data()
    private var projection = CodexTaskProjection()
    private var subscriptions = Set<String>()
    private var pendingSnapshots = Set<String>()
    private var connectedAt = Date.distantPast
    private var lastSnapshotRequest: [String: Date] = [:]
    private var storedTasks: [String: CodexStoredTask] = [:]
    private var continuation: AsyncStream<CodexTaskCounts?>.Continuation?
    private var lastPublished: CodexTaskCounts?
    private var desktopRunning = false
    private var readSource: (any DispatchSourceRead)?
    private var socketGeneration = 0
    private let eventQueue = DispatchQueue(label: "benchgauge.codex-task-events", qos: .utility)
    private struct FileObserver {
        let inode: UInt64
        let source: any DispatchSourceFileSystemObject
    }
    private var fileObservers: [String: FileObserver] = [:]
    private var fileRefreshTask: Task<Void, Never>?
    private var fallbackTask: Task<Void, Never>?
    private var fallbackDelay: TimeInterval?
    private var warmupTask: Task<Void, Never>?
    private var lastStoreRefresh = Date.distantPast
    private var nextConnectAttempt = Date.distantPast
    private var connectionFailures = 0
    private var lifecycleGeneration = 0

    /// Stream events wake the reader even while there are no executing tasks.
    /// Files cover unread markers/new threads; timers only reconcile missed
    /// filesystem events and retry a broken connection.
    func updates(desktopRunning: Bool) -> AsyncStream<CodexTaskCounts?> {
        stop()
        let stream = AsyncStream<CodexTaskCounts?>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation = stream.continuation
        let generation = lifecycleGeneration
        continuation?.onTermination = { [weak self] _ in
            Task { await self?.streamTerminated(generation: generation) }
        }
        continuation?.yield(nil)
        self.desktopRunning = desktopRunning
        Self.logger.notice("Task monitor started: desktop running=\(desktopRunning, privacy: .public)")
        installFileObservers()
        refreshFromStore()
        return stream.stream
    }

    func setDesktopRunning(_ running: Bool) {
        guard continuation != nil, desktopRunning != running else { return }
        desktopRunning = running
        Self.logger.notice("Task monitor desktop presence changed: \(running, privacy: .public)")
        nextConnectAttempt = .distantPast
        connectionFailures = 0
        refreshFromStore()
    }

    init(root: URL? = nil, readStore: @escaping @Sendable (URL) throws -> [String: CodexStoredTask] = { try CodexTaskStore.read(root: $0) }) {
        self.readStore = readStore
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
            let stored = try readStore(root)
            storedTasks = stored
            if socketFD < 0 {
                guard Date() >= nextConnectAttempt else { return nil }
                try connect()
            }
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
            connectionFailures = 0
            return projection.counts(stored: stored)
        } catch {
            Self.logger.error("Task source read failed: \(String(describing: type(of: error)), privacy: .public), code=\((error as NSError).code, privacy: .public)")
            #if DEBUG
            if CommandLine.arguments.contains("--codex-task-status") {
                FileHandle.standardError.write(Data("Codex status read failed: \(type(of: error)) \(error)\n".utf8))
            }
            #endif
            disconnect()
            connectionFailures += 1
            nextConnectAttempt = Date().addingTimeInterval(Self.retryDelay(failures: connectionFailures))
            return nil
        }
    }

    static func reconciliationDelay(running: Int) -> TimeInterval { running > 0 ? 5 : 30 }
    static func retryDelay(failures: Int) -> TimeInterval { min(30, pow(2, Double(min(5, max(1, failures))))) }

    func stop() {
        lifecycleGeneration += 1
        fallbackTask?.cancel()
        fallbackTask = nil
        fallbackDelay = nil
        fileRefreshTask?.cancel()
        fileRefreshTask = nil
        for observer in fileObservers.values { observer.source.cancel() }
        fileObservers.removeAll()
        disconnect()
        continuation?.finish()
        continuation = nil
        lastPublished = nil
        desktopRunning = false
        nextConnectAttempt = .distantPast
        connectionFailures = 0
    }

    private func streamTerminated(generation: Int) {
        if lifecycleGeneration == generation { stop() }
    }

    private func refreshFromStore() {
        guard continuation != nil else { return }
        lastStoreRefresh = Date()
        _ = poll(desktopRunning: desktopRunning)
        installFileObservers()
        publishCurrent()
        scheduleFallback()
    }

    private func publishCurrent() {
        guard continuation != nil else { return }
        // A split frame is still being delivered; wait for its readable event
        // rather than briefly replacing a valid count with loading dashes.
        if !input.isEmpty && pendingSnapshots.isEmpty { return }
        let counts: CodexTaskCounts? = desktopRunning && clientID != nil
            && Date().timeIntervalSince(connectedAt) >= 2 && pendingSnapshots.isEmpty
            ? projection.counts(stored: storedTasks) : nil
        if counts != nil { connectionFailures = 0 }
        guard counts != lastPublished else { return }
        lastPublished = counts
        if let counts {
            Self.logger.notice("Task counts updated: running=\(counts.running, privacy: .public), unread=\(counts.unread, privacy: .public), failed=\(counts.failed, privacy: .public)")
        } else {
            Self.logger.notice("Task counts unavailable: desktop=\(self.desktopRunning, privacy: .public), initialized=\(self.clientID != nil, privacy: .public), resync=\(self.pendingSnapshots.count, privacy: .public), partialBytes=\(self.input.count, privacy: .public)")
        }
        continuation?.yield(counts)
        scheduleFallback()
    }

    private func scheduleFallback() {
        guard continuation != nil, desktopRunning else {
            fallbackTask?.cancel(); fallbackTask = nil; fallbackDelay = nil
            return
        }
        let delay = socketFD < 0
            ? max(0.1, nextConnectAttempt.timeIntervalSinceNow)
            : (!pendingSnapshots.isEmpty || clientID == nil ? 2 : Self.reconciliationDelay(running: lastPublished?.running ?? 0))
        guard fallbackTask == nil || fallbackDelay != delay else { return }
        fallbackTask?.cancel()
        fallbackDelay = delay
        fallbackTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.fallbackFired()
        }
    }

    private func fallbackFired() {
        guard !Task.isCancelled else { return }
        fallbackTask = nil
        fallbackDelay = nil
        refreshFromStore()
    }

    private func fileChanged() {
        guard continuation != nil, desktopRunning, fileRefreshTask == nil else { return }
        // Continuous WAL writes must not postpone refresh indefinitely, nor
        // cause a database read for every token. Coalesce at most four reads/s.
        let delay = max(0.05, 0.25 - Date().timeIntervalSince(lastStoreRefresh))
        fileRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.fileRefreshFired()
        }
    }

    private func fileRefreshFired() {
        guard !Task.isCancelled else { return }
        fileRefreshTask = nil
        refreshFromStore()
    }

    private func warmupFired(generation: Int) {
        guard socketGeneration == generation else { return }
        publishCurrent()
    }

    private func handshakeDeadline(generation: Int) {
        guard socketGeneration == generation, clientID == nil else { return }
        disconnect()
        connectionFailures += 1
        nextConnectAttempt = Date().addingTimeInterval(Self.retryDelay(failures: connectionFailures))
        publishCurrent()
        scheduleFallback()
    }

    private func installFileObservers() {
        guard continuation != nil else { return }
        let paths = [root.path, root.appendingPathComponent("ipc").path] + [
            "state_5.sqlite", "state_5.sqlite-wal", "thread_history_1.sqlite", "thread_history_1.sqlite-wal", ".codex-global-state.json",
        ].map { root.appendingPathComponent($0).path }
        for path in paths {
            var info = stat()
            guard lstat(path, &info) == 0 else {
                fileObservers.removeValue(forKey: path)?.source.cancel()
                continue
            }
            if fileObservers[path]?.inode == info.st_ino { continue }
            fileObservers.removeValue(forKey: path)?.source.cancel()
            let fd = Darwin.open(path, O_EVTONLY | O_CLOEXEC)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                eventMask: [.write, .extend, .rename, .delete, .revoke], queue: eventQueue)
            source.setEventHandler { [weak self] in Task { await self?.fileChanged() } }
            source.setCancelHandler { Darwin.close(fd) }
            fileObservers[path] = FileObserver(inode: info.st_ino, source: source)
            source.activate()
        }
    }

    private func socketReadable(generation: Int) {
        guard continuation != nil, socketGeneration == generation, socketFD >= 0 else { return }
        do {
            try drain(waitForChunks: false)
            // Initialization can arrive after the first database refresh.
            if clientID != nil {
                for id in Set(storedTasks.keys).subtracting(subscriptions) {
                    try follow(id, enabled: true)
                    subscriptions.insert(id)
                }
            }
            publishCurrent()
        } catch {
            Self.logger.error("Task socket delivery failed: \(String(describing: type(of: error)), privacy: .public), code=\((error as NSError).code, privacy: .public)")
            disconnect()
            connectionFailures += 1
            nextConnectAttempt = Date().addingTimeInterval(Self.retryDelay(failures: connectionFailures))
            publishCurrent()
            scheduleFallback()
        }
    }

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
        if continuation != nil {
            socketGeneration += 1
            let generation = socketGeneration
            let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: eventQueue)
            let observedFD = socketFD
            source.setCancelHandler { Darwin.close(observedFD) }
            // Suspend until this delivery is consumed, so one readable socket
            // cannot queue hundreds of actor tasks while a snapshot is parsed.
            source.setEventHandler { [weak self, weak source] in
                guard let source else { return }
                source.suspend()
                Task {
                    await self?.socketReadable(generation: generation)
                    source.resume()
                }
            }
            readSource = source
            source.activate()
            warmupTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard !Task.isCancelled else { return }
                await self?.warmupFired(generation: generation)
                // An open but unresponsive router must also enter retry backoff.
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard !Task.isCancelled else { return }
                await self?.handshakeDeadline(generation: generation)
            }
        }
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

    private func drain(waitForChunks: Bool = true) throws {
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
                    if waitForChunks, Date() < deadline, Darwin.poll(&descriptor, 1, 10) > 0 { continue }
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
            if params["hostId"] as? String == "local" {
                if message["method"] as? String == "thread-stream-following-status-requested",
                   let id = params["conversationId"] as? String, subscriptions.contains(id) {
                    // A replacement desktop owner discovers existing followers
                    // this way; reply immediately even during the idle cadence.
                    try follow(id, enabled: true)
                }
                if ["thread-read-state-changed", "thread-archived", "thread-unarchived"].contains(message["method"] as? String ?? "") {
                    fileChanged()
                }
            }
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
        socketGeneration += 1
        warmupTask?.cancel()
        warmupTask = nil
        if let source = readSource {
            source.setEventHandler(handler: nil)
            source.cancel()
            readSource = nil
            // The cancellation handler closes the descriptor after any queued
            // delivery. Closing now could let a new socket reuse its number.
        } else if socketFD >= 0 { Darwin.close(socketFD) }
        socketFD = -1
        clientID = nil
        input.removeAll()
        subscriptions.removeAll()
        pendingSnapshots.removeAll()
        lastSnapshotRequest.removeAll()
        projection = CodexTaskProjection()
    }
}
