import Foundation
@testable import LeaderboardCore
import Testing

struct OpenAIAppServerTests {
    @Test func renewalTransportFailuresDoNotInvalidateLogin() {
        for message in ["Failed to refresh token: connection timed out", "refresh_token request failed: TLS handshake failed",
                        "Could not sign in: service temporarily unavailable", "unexpected status 403 Forbidden"] {
            #expect(!OpenAIAppServer.requiresReauthentication(message))
        }
        for message in ["unauthorized", "unexpected status 401", "refresh_token_reused", "invalid_grant",
                        "Your refresh token has already been used. Please sign in again."] {
            #expect(OpenAIAppServer.requiresReauthentication(message))
        }
    }
    @Test func receivesAResponseLargerThanTheReadBufferWithoutLosingFragments() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let helper = folder.appendingPathComponent("helper")
        let script = #"""
        #!/usr/bin/env python3
        import sys,json
        for line in sys.stdin:
            message=json.loads(line)
            if 'id' not in message: continue
            result={} if message['method']=='initialize' else {'payload':'x'*80000}
            print(json.dumps({'id':message['id'],'result':result}),flush=True)
        """#
        try Data(script.utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let server = OpenAIAppServer(profileURL: folder.appendingPathComponent("profile"), executableURL: helper,
                                    // This checks fragmented data, using the production request deadline.
                                    requestTimeout: .seconds(30), loginTimeout: .seconds(2), findExecutable: { nil })
        let response = try await server.request("account/read", params: Data("{}".utf8))
        let object = try JSONSerialization.jsonObject(with: response) as? [String: String]
        #expect(object?["payload"] == String(repeating: "x", count: 80000))
        await server.stop()
    }
    @Test func validatesMethodsAndReportsAnUnlaunchableHelper() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = OpenAIAppServer(profileURL: folder, executableURL: folder.appendingPathComponent("missing"))
        await #expect(throws: OpenAIConnectionError.invalidResponse) { try await server.request("thread/start", params: Data("{}".utf8)) }
        await #expect(throws: OpenAIConnectionError.serviceFailed) { try await server.request("account/read", params: Data("{}".utf8)) }
        await server.stop()
        _ = OpenAIAppServer.installedExecutable(environment: [:])
        _ = OpenAIAppServer.installedExecutable(environment: ["PATH": "/fixture/missing:/also/missing"])
        _ = OpenAIAppServer(profileURL: folder)
    }

    @Test func timesOutAndCancelsRequestsWithoutRunningTheInstalledCodex() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let helper = folder.appendingPathComponent("helper")
        let script = #"""
        #!/usr/bin/env python3
        import sys,json,signal
        signal.signal(signal.SIGTERM, lambda *args: sys.exit(0))
        for line in sys.stdin:
            message=json.loads(line)
            if 'id' not in message: continue
            if message['method']=='initialize':
                print(json.dumps({'id':message['id'],'result':{}}),flush=True)
            elif message['method']=='account/logout':
                print(json.dumps({'id':message['id'],'error':{}}),flush=True)
        """#
        try Data(script.utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let server = OpenAIAppServer(profileURL: folder.appendingPathComponent("profile"), executableURL: nil,
                                    requestTimeout: .milliseconds(500), loginTimeout: .milliseconds(100), findExecutable: { helper })
        await #expect(throws: OpenAIConnectionError.timedOut) { try await server.request("account/read", params: Data("{}".utf8)) }
        await #expect(throws: OpenAIConnectionError.timedOut) { try await server.waitForLogin("never-completed") }
        await #expect(throws: OpenAIConnectionError.serviceFailed) { try await server.request("account/logout", params: Data("{}".utf8)) }
        let request = Task { try await server.request("account/read", params: Data("{}".utf8)) }
        try await Task.sleep(for: .milliseconds(20)); request.cancel()
        do { _ = try await request.value; Issue.record("Cancelled request returned a result") } catch is CancellationError {}
        await server.stop()
        let absent = OpenAIAppServer(profileURL: folder, executableURL: nil,
                                    requestTimeout: .milliseconds(100), loginTimeout: .milliseconds(100), findExecutable: { nil })
        await #expect(throws: OpenAIConnectionError.helperMissing) { try await absent.request("account/read", params: Data("{}".utf8)) }
        await absent.stop()
    }

    @Test func exchangesAccountMessagesWithARealPipeAndHandlesLoginCompletion() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let helper = folder.appendingPathComponent("helper")
        let script = #"""
        #!/usr/bin/env python3
        import sys,json
        for line in sys.stdin:
            message=json.loads(line)
            if 'id' not in message: continue
            method=message['method']
            if method=='account/logout':
                response={'id':message['id'],'error':{'message':'unauthorized'}}
            elif method=='account/rateLimits/read':
                response={'id':message['id'],'error':{'message':'service failure'}}
            elif method=='account/login/cancel':
                response={'id':message['id']}
            else:
                response={'id':message['id'],'result':{'ok':True}}
            print('invalid json',flush=True)
            print(json.dumps(response),flush=True)
            if method=='account/login/start':
                print(json.dumps({'method':'account/login/completed','params':{'loginId':'complete','success':True}}),flush=True)
                print(json.dumps({'method':'account/login/completed','params':{'loginId':'failed','success':False}}),flush=True)
        """#
        try Data(script.utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let server = OpenAIAppServer(profileURL: folder.appendingPathComponent("profile"), executableURL: helper)
        let result = try await server.request("account/read", params: Data("{}".utf8))
        #expect((try JSONSerialization.jsonObject(with: result) as? [String: Bool]) == ["ok": true])
        await #expect(throws: OpenAIConnectionError.reauthRequired) { try await server.request("account/logout", params: Data("{}".utf8)) }
        await #expect(throws: OpenAIConnectionError.serviceFailed) { try await server.request("account/rateLimits/read", params: Data("{}".utf8)) }
        await #expect(throws: OpenAIConnectionError.invalidResponse) { try await server.request("account/login/cancel", params: Data("{}".utf8)) }
        _ = try await server.request("account/login/start", params: Data("{}".utf8))
        try await Task.sleep(for: .milliseconds(100))
        try await server.waitForLogin("complete")
        await #expect(throws: OpenAIConnectionError.signInFailed) { try await server.waitForLogin("failed") }
        let waiting = Task { try await server.waitForLogin("cancelled") }
        try await Task.sleep(for: .milliseconds(10)); waiting.cancel()
        do { try await waiting.value; Issue.record("cancelled login succeeded") } catch is CancellationError {} 
        let abandoned = Task { try await server.waitForLogin("abandoned") }
        try await Task.sleep(for: .milliseconds(10)); await server.stop()
        await #expect(throws: OpenAIConnectionError.cancelled) { try await abandoned.value }
    }
    @Test func malformedPipesAndUnresponsiveHelpersReleaseEveryPendingWaiter() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let helper = folder.appendingPathComponent("helper")
        let script = #"""
        #!/usr/bin/env python3
        import sys,json,signal,time
        signal.signal(signal.SIGTERM,signal.SIG_IGN)
        for line in sys.stdin:
            message=json.loads(line)
            if 'id' not in message: continue
            if message['method']=='initialize':
                print(json.dumps({'id':message['id'],'result':{}}),flush=True)
            elif message['method']=='account/login/start':
                print(json.dumps({'id':message['id'],'result':{}}),flush=True)
                time.sleep(.05)
                for identifier,success in [('wait-success',True),('wait-failure',False)]:
                    print(json.dumps({'method':'account/login/completed','params':{'loginId':identifier,'success':success}}),flush=True)
            elif message['method']=='account/logout':
                sys.stdout.write('x'*1100000);sys.stdout.flush()
            else:
                print(json.dumps({'id':message['id'],'result':{}}),flush=True)
        time.sleep(5)
        """#
        try Data(script.utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        var io = OpenAIAppServer.PipeOperations()
        #if canImport(Darwin)
        let interrupted = InterruptedPipeRead()
        io.readBytes = { descriptor, bytes, count in
            if interrupted.takeFirst() { errno = EINTR; return -1 }
            return Darwin.read(descriptor, bytes, count)
        }
        #endif
        let server = OpenAIAppServer(profileURL: folder.appendingPathComponent("profile"), executableURL: helper, requestTimeout: .seconds(2), loginTimeout: .seconds(2), findExecutable: { nil }, pipeOperations: io)
        await #expect(throws: OpenAIConnectionError.serviceFailed) { try await server.send([:]) }
        let generation = await server.connectionGeneration
        await server.receive(Data("{}".utf8), generation: UUID())
        await server.disconnected(generation: UUID())
        await server.receive(Data(repeating: 32, count: 1_048_577), generation: generation)
        _ = try await server.request("account/read", params: Data("{}".utf8))
        let success = Task { try await server.waitForLogin("wait-success") }
        let failure = Task { try await server.waitForLogin("wait-failure") }
        _ = try await server.request("account/login/start", params: Data("{}".utf8))
        try await success.value
        await #expect(throws: OpenAIConnectionError.signInFailed) { try await failure.value }
        await #expect(throws: OpenAIConnectionError.serviceFailed) { try await server.request("account/logout", params: Data("{}".utf8)) }
        await server.stop()
        var broken = OpenAIAppServer.PipeOperations()
        broken.writeBytes = { _, _ in throw CocoaError(.fileWriteUnknown) }
        let writer = OpenAIAppServer(profileURL: folder.appendingPathComponent("broken"), executableURL: helper, requestTimeout: .seconds(2), loginTimeout: .seconds(2), findExecutable: { nil }, pipeOperations: broken)
        await #expect(throws: OpenAIConnectionError.serviceFailed) { try await writer.request("account/read", params: Data("{}".utf8)) }
        await writer.stop()
        let idle = OpenAIAppServer(profileURL: folder)
        let cancelled = Task { try await idle.waitForLogin("unused") }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        await idle.stop()
    }

}

#if canImport(Darwin)
import Darwin
private final class InterruptedPipeRead: @unchecked Sendable {
    private let lock = NSLock()
    private var first = true
    func takeFirst() -> Bool { lock.withLock { defer { first = false }; return first } }
}
#endif

extension OpenAIAppServerTests {
    @Test func concurrentRequestsShareInitializationAndAnUnresponsiveHelperIsKilled() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("helper")
        let script = #"""
        #!/usr/bin/env python3
        import sys,json,signal,time
        signal.signal(signal.SIGTERM,signal.SIG_IGN)
        for line in sys.stdin:
            message=json.loads(line)
            if 'id' not in message: continue
            if message['method']=='initialize': time.sleep(0.05)
            print(json.dumps({'id':message['id'],'result':{'ok':True}}),flush=True)
        while True: time.sleep(0.05)
        """#
        try Data(script.utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let server = OpenAIAppServer(profileURL: root.appendingPathComponent("profile"), executableURL: helper)
        async let first = server.request("account/read", params: Data("{}".utf8))
        async let second = server.request("account/rateLimits/read", params: Data("{}".utf8))
        let results = try await [first, second]
        #expect(results.count == 2)
        await server.stop()
    }
}

private final class AppServerBoundaryReference: @unchecked Sendable {
    private let lock = NSLock()
    private var value: OpenAIAppServer?
    func set(_ server: OpenAIAppServer) { lock.withLock { value = server } }
    func get() -> OpenAIAppServer? { lock.withLock { value } }
}

extension OpenAIAppServerTests {
    @Test func stoppingAfterTheInitializationHandshakeCannotPublishTheOldGeneration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("helper")
        try Data(#"""
        #!/usr/bin/env python3
        import sys,json
        for line in sys.stdin:
            message=json.loads(line)
            if message.get('method')=='initialize': print(json.dumps({'id':message['id'],'result':{}}),flush=True)
        """#.utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        for index in 0..<5 {
            let reference = AppServerBoundaryReference()
            var pipes = OpenAIAppServer.PipeOperations()
            pipes.writeBytes = { handle, data in
                try handle.write(contentsOf: data)
                if String(decoding: data, as: UTF8.self).contains("\"initialized\""), let server = reference.get() {
                    Task { await server.stop() }
                }
            }
            // This tests cancellation after a completed handshake, not helper
            // startup speed under the full suite's process/rendering load.
            let server = OpenAIAppServer(profileURL: root.appendingPathComponent("profile-\(index)"), executableURL: helper, requestTimeout: .seconds(30), loginTimeout: .seconds(2), findExecutable: { nil }, pipeOperations: pipes)
            reference.set(server)
            await #expect(throws: OpenAIConnectionError.cancelled) { try await server.request("account/read", params: Data("{}".utf8)) }
            await server.stop()
        }
    }
}
