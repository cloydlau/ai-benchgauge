import Foundation
import Darwin

public enum OpenAIConnectionError: Error, Equatable, Sendable {
    case helperMissing, serviceFailed, timedOut, cancelled, signInFailed, accountMismatch, invalidResponse, reauthRequired
}

/// Only account APIs are exposed. The helper owns OAuth, its callback server,
/// token storage and refresh; no agent threads or model requests are started.
public protocol OpenAIAccountRPC: Sendable {
    func request(_ method: String, params: Data) async throws -> Data
    func waitForLogin(_ id: String) async throws
    func stop() async
}

public actor OpenAIAppServer: OpenAIAccountRPC {
    private let profileURL: URL
    private let executableURL: URL?
    private var process: Process?
    private var input: FileHandle?
    private var reader: Task<Void, Never>?
    private var generation = UUID()
    private var nextID = 0
    private var initialized = false
    private var initialization: Task<Void, Error>?
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var loginWaiters: [String: CheckedContinuation<Void, Error>] = [:]
    private var completedLogins: [String: Bool] = [:]

    public init(profileURL: URL, executableURL: URL? = nil) {
        self.profileURL = profileURL
        self.executableURL = executableURL
    }

    public static func installedExecutable(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let bundledPaths = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex",
        ]
        let searchPaths = (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
            + ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        return (bundledPaths + searchPaths).first {
            FileManager.default.isExecutableFile(atPath: $0)
        }.map { URL(fileURLWithPath: $0) }
    }

    public func request(_ method: String, params: Data) async throws -> Data {
        guard ["account/read", "account/login/start", "account/login/cancel", "account/logout", "account/rateLimits/read"].contains(method) else {
            throw OpenAIConnectionError.invalidResponse
        }
        try Task.checkCancellation()
        if process == nil { try launch() }
        if !initialized {
            let currentGeneration = generation
            let task: Task<Void, Error>
            if let initialization { task = initialization }
            else {
                task = Task {
                    let info = Data(#"{"clientInfo":{"name":"ai_benchgauge","title":"AI BenchGauge","version":"1.0"}}"#.utf8)
                    _ = try await sendRequest("initialize", params: info)
                    try send(["method": "initialized", "params": [:]])
                }
                initialization = task
            }
            do {
                try await task.value
                guard generation == currentGeneration else { throw OpenAIConnectionError.cancelled }
                initialized = true
                initialization = nil
            } catch {
                if generation == currentGeneration { initialization = nil }
                throw error
            }
        }
        try Task.checkCancellation()
        return try await sendRequest(method, params: params)
    }

    private func launch() throws {
        guard let executable = executableURL ?? Self.installedExecutable() else {
            throw OpenAIConnectionError.helperMissing
        }
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: profileURL.path)
        let child = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        child.executableURL = executable
        child.arguments = ["app-server", "-c", "cli_auth_credentials_store=\"file\""]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = profileURL.path
        for key in ["OPENAI_API_KEY", "CODEX_API_KEY", "CODEX_ACCESS_TOKEN"] { environment.removeValue(forKey: key) }
        child.environment = environment
        child.currentDirectoryURL = profileURL
        child.standardInput = stdin
        child.standardOutput = stdout
        // Server errors may contain credential-shaped values. Never log them.
        child.standardError = FileHandle.nullDevice
        do { try child.run() } catch { throw OpenAIConnectionError.serviceFailed }
        process = child
        input = stdin.fileHandleForWriting
        initialized = false
        let currentGeneration = UUID()
        generation = currentGeneration
        let output = stdout.fileHandleForReading
        reader = Task.detached { [weak self] in
            var buffer = Data()
            var bytes = [UInt8](repeating: 0, count: 4096)
            while !Task.isCancelled {
                // read(upToCount:) may wait to fill the requested count on a
                // pipe. POSIX read returns the currently available response.
                let count = bytes.withUnsafeMutableBytes {
                    Darwin.read(output.fileDescriptor, $0.baseAddress, $0.count)
                }
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { break }
                buffer.append(contentsOf: bytes.prefix(count))
                while let newline = buffer.firstIndex(of: 10) {
                    let line = Data(buffer[..<newline])
                    buffer.removeSubrange(...newline)
                    await self?.receive(line, generation: currentGeneration)
                }
                if buffer.count > 1_048_576 { break }
            }
            try? output.close()
            await self?.disconnected(generation: currentGeneration)
        }
    }

    private func send(_ message: [String: Any]) throws {
        guard let input else { throw OpenAIConnectionError.serviceFailed }
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(10)
        do { try input.write(contentsOf: data) } catch { throw OpenAIConnectionError.serviceFailed }
    }

    private func sendRequest(_ method: String, params: Data) async throws -> Data {
        let object = try JSONSerialization.jsonObject(with: params)
        nextID += 1
        let id = nextID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                do { try send(["id": id, "method": method, "params": object]) }
                catch {
                    pending.removeValue(forKey: id)?.resume(throwing: error)
                    return
                }
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(30))
                    await self?.expireRequest(id)
                }
            }
        } onCancel: {
            Task { await self.cancelRequest(id) }
        }
    }

    private func receive(_ data: Data, generation: UUID) {
        guard generation == self.generation, data.count <= 1_048_576,
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let id = message["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
            if let error = message["error"] as? [String: Any] {
                let text = (error["message"] as? String ?? "").lowercased()
                let authFailure = ["unauthorized", "401", "not authenticated", "authentication required",
                                   "refresh token", "refresh_token", "sign in", "not logged in"].contains { text.contains($0) }
                continuation.resume(throwing: authFailure ? OpenAIConnectionError.reauthRequired : .serviceFailed)
            } else if let result = message["result"], let data = try? JSONSerialization.data(withJSONObject: result) {
                continuation.resume(returning: data)
            } else {
                continuation.resume(throwing: OpenAIConnectionError.invalidResponse)
            }
        } else if message["method"] as? String == "account/login/completed",
                  let params = message["params"] as? [String: Any],
                  let id = params["loginId"] as? String {
            let success = params["success"] as? Bool == true
            if let continuation = loginWaiters.removeValue(forKey: id) {
                if success { continuation.resume() }
                else { continuation.resume(throwing: OpenAIConnectionError.signInFailed) }
            } else {
                // Completion can precede registration of the waiter.
                completedLogins[id] = success
            }
        }
    }

    public func waitForLogin(_ id: String) async throws {
        try Task.checkCancellation()
        if let success = completedLogins.removeValue(forKey: id) {
            if success { return }
            throw OpenAIConnectionError.signInFailed
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                loginWaiters[id] = continuation
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(300))
                    await self?.expireLogin(id)
                }
            }
        } onCancel: {
            Task { await self.cancelLoginWaiter(id) }
        }
    }

    private func expireRequest(_ id: Int) { pending.removeValue(forKey: id)?.resume(throwing: OpenAIConnectionError.timedOut) }
    private func cancelRequest(_ id: Int) { pending.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
    private func expireLogin(_ id: String) { loginWaiters.removeValue(forKey: id)?.resume(throwing: OpenAIConnectionError.timedOut) }
    private func cancelLoginWaiter(_ id: String) { loginWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError()) }

    private func disconnected(generation: UUID) {
        guard generation == self.generation else { return }
        stop(with: .serviceFailed)
    }

    public func stop() async {
        let child = stop(with: .cancelled)
        // Release the loopback callback port before a retry starts a helper.
        for _ in 0..<40 {
            guard let child, child.isRunning else { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        if let child, child.isRunning { Darwin.kill(child.processIdentifier, SIGKILL) }
    }

    @discardableResult
    private func stop(with error: OpenAIConnectionError) -> Process? {
        let child = process
        generation = UUID()
        reader?.cancel()
        reader = nil
        try? input?.close()
        input = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        initialized = false
        initialization?.cancel()
        initialization = nil
        for continuation in pending.values { continuation.resume(throwing: error) }
        for continuation in loginWaiters.values { continuation.resume(throwing: error) }
        pending.removeAll()
        loginWaiters.removeAll()
        completedLogins.removeAll()
        return child
    }
}
