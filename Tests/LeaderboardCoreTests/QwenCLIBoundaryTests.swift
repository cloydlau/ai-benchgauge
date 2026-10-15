import Foundation
@testable import LeaderboardCore
import Testing

struct QwenCLIBoundaryTests {
    private func helper(_ body: String, root: URL) throws -> URL {
        let file = root.appendingPathComponent("qianwen-\(UUID().uuidString)")
        try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return file
    }
    @Test func runsOnlyAnIsolatedHelperAndRejectsBadOutputOrExitStatus() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (body, expected) in [("printf '{\"token_plan\":{\"subscribed\":true}}'", true), ("exit 1", false), ("/usr/bin/python3 -c 'print(\"x\"*1048577)'", false), ("/bin/sleep 5", false)] {
            let script = try helper(body, root: root)
            let source = QwenCLIQuotaSource(environment: ["QIANWEN_CLI_PATH": script.path, "PATH": "/usr/bin:/bin"], homeURL: root, timeout: body.contains("sleep") ? 0.2 : 2)
            let result = await source.loadSummary()
            #expect((result != nil) == expected)
        }
        let standalone = try helper("printf '{}'", root: root)
        #expect(await QwenCLIQuotaSource(environment: ["QIANWEN_CLI_PATH": standalone.path], homeURL: root, timeout: 1).loadSummary() == Data("{}".utf8))
        let invalid = try helper("exit 0", root: root)
        try Data("#!/missing/interpreter\n".utf8).write(to: invalid)
        let source = QwenCLIQuotaSource(environment: ["QIANWEN_CLI_PATH": invalid.path, "PATH": "relative"], homeURL: root, timeout: 0.2)
        #expect(await source.loadSummary() == nil)
        #expect(await source.unavailableStatus() == .note(text: AccountQuotaMessage.connectOfficial, help: AccountQuotaMessage.connectOfficialHelp))
        _ = QwenCLIQuotaSource()
    }

    @Test func cancelsAHelperAndNeverFallsBackToARealAccount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = try helper("/bin/sleep 5", root: root)
        let source = QwenCLIQuotaSource(environment: ["QIANWEN_CLI_PATH": script.path], homeURL: root, timeout: 5)
        let task = Task { await source.loadSummary() }
        try await Task.sleep(for: .milliseconds(100)); task.cancel()
        #expect(await task.value == nil)
        let cancelled = Task { await source.loadSummary() }; cancelled.cancel()
        #expect(await cancelled.value == nil)
    }

    @Test func resolvesConfiguredPathsAndNewestNodeInstallations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(QwenCLIQuotaSource.executableURL(environment: [:], homeURL: root) == nil)
        for version in ["v22.0.0", "v24.0.0"] {
            let bin = root.appendingPathComponent(".nvm/versions/node/\(version)/bin")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let file = bin.appendingPathComponent("qianwen")
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
        #expect(QwenCLIQuotaSource.executableURL(environment: [:], homeURL: root)?.path.contains("v24.0.0") == true)
        let configured = try helper("exit 0", root: root)
        #expect(QwenCLIQuotaSource.executableURL(environment: ["QIANWEN_CLI_PATH": configured.path], homeURL: root) == configured)
        #expect(QwenCLIQuotaSource.executableURL(environment: ["QIANWEN_CLI_PATH": root.appendingPathComponent("missing").path], homeURL: root)?.path.contains("v24.0.0") == true)
        #expect(QwenCLIQuotaSource.executableURL(environment: ["QIANWEN_CLI_PATH": "relative", "PATH": root.appendingPathComponent(".nvm/versions/node/v22.0.0/bin").path], homeURL: root)?.path.contains("v22.0.0") == true)
    }
    @Test func cancellationBeforeTrackingAndMissingOutputDoNotBlock() throws {
        let output = QwenCLIOutput()
        #expect(output.waitForData(timeout: 0) == nil)
        let state = QwenCLIProcessState()
        state.cancel()
        #expect(QwenCLIQuotaSource.run(state: state, environment: [:], homeURL: FileManager.default.temporaryDirectory, timeout: 1) == nil)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["1"]
        try process.run()
        state.track(process)
        process.waitUntilExit()
        #expect(state.isCancelled)
        let running = Process()
        running.executableURL = URL(fileURLWithPath: "/bin/sleep"); running.arguments = ["1"]
        try running.run()
        let tracked = QwenCLIProcessState(); tracked.track(running); tracked.cancel(); running.waitUntilExit()
        #expect(QwenCLIQuotaSource.run(state: QwenCLIProcessState(), environment: [:], homeURL: FileManager.default.temporaryDirectory, timeout: 1, resolveExecutable: { _, _ in nil }) == nil)
        let idle = QwenCLIProcessState()
        idle.track(Process()); idle.cancel()
        let invalid = Data(#"{"token_plan":{"subscribed":true,"remainingCredits":"1e308","totalCredits":"1e-308"}}"#.utf8)
        #expect(QwenPlanQuotaParser.parse(invalid) == nil)
        #expect(QwenPlanQuotaParser.parse(Data(#"{"token_plan":{"subscribed":true,"remainingCredits":{},"totalCredits":100}}"#.utf8)) == nil)
    }

}
