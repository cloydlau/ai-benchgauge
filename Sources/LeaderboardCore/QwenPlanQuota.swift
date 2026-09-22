import Foundation

public struct QwenPlanQuota: Equatable, Sendable {
    public let usedPercent: Double
    public let remainingCredits: Double
    public let totalCredits: Double
    public let resetsAt: Date?

    public init(usedPercent: Double, remainingCredits: Double, totalCredits: Double, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.remainingCredits = remainingCredits
        self.totalCredits = totalCredits
        self.resetsAt = resetsAt
    }
}

public enum QwenPlanQuotaParser {
    public static func parse(_ data: Data) -> QwenPlanQuota? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plan = root["token_plan"] as? [String: Any],
              plan["subscribed"] as? Bool == true,
              let remaining = number(plan["remainingCredits"]),
              let total = number(plan["totalCredits"]),
              remaining.isFinite, total.isFinite, total > 0 else {
            return nil
        }
        let used = number(plan["usedPct"]) ?? (1 - remaining / total) * 100
        guard used.isFinite else { return nil }
        let reset = (plan["resetDate"] as? String).flatMap { value in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        }
        return QwenPlanQuota(
            usedPercent: min(max(used, 0), 100),
            remainingCredits: max(remaining, 0),
            totalCredits: total,
            resetsAt: reset
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}

public protocol QwenQuotaSource: Sendable {
    func loadSummary() async -> Data?
}

/// Uses the user's own 千问 AI 平台 login. The CLI keeps its credentials in
/// Keychain; the app receives only the JSON usage summary.
public struct QwenCLIQuotaSource: QwenQuotaSource {
    public init() {}

    public func loadSummary() async -> Data? {
        let state = QwenCLIProcessState()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: Self.run(state: state))
                }
            }
        } onCancel: {
            state.cancel()
        }
    }

    private static func run(state: QwenCLIProcessState) -> Data? {
        guard !state.isCancelled else { return nil }
        guard let executable = executableURL() else { return nil }
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["usage", "summary", "--format", "json"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [
            executable.deletingLastPathComponent().path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            environment["PATH"] ?? "/usr/bin:/bin",
        ].joined(separator: ":")
        process.environment = environment
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        state.track(process)
        let deadline = Date().addingTimeInterval(20)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            return nil
        }
        guard !state.isCancelled, process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return data.count <= 1_048_576 ? data : nil
    }

    private static func executableURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        directories += [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/Library/pnpm/bin",
            "\(home)/.local/bin",
            "\(home)/.volta/bin",
        ]
        let nvmVersions = URL(fileURLWithPath: home).appending(path: ".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(
            at: nvmVersions,
            includingPropertiesForKeys: nil
        ) {
            directories += versions.sorted { $0.lastPathComponent > $1.lastPathComponent }
                .map { $0.appending(path: "bin").path }
        }
        if let configured = environment["QIANWEN_CLI_PATH"], configured.hasPrefix("/") {
            let url = URL(fileURLWithPath: configured)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        for directory in directories where directory.hasPrefix("/") {
            let url = URL(fileURLWithPath: directory).appending(path: "qianwen")
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }
}

private final class QwenCLIProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func track(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldStop = cancelled
        lock.unlock()
        if shouldStop && process.isRunning { process.terminate() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let running = process
        lock.unlock()
        if let running, running.isRunning { running.terminate() }
    }
}
