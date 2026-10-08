import LeaderboardCore
import Testing
@testable import leaderboard_menu

@Suite(.serialized)
@MainActor
struct OfficialAccountsFormTests {
    private func wait(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return predicate()
    }

    @Test func closingCancelsVerificationAndIgnoresALateSuccess() async {
        let form = OfficialAccountsForm()
        form.apiKey = "fixture-key"
        var reply: CheckedContinuation<Bool, Never>?
        var cancelled = false
        var finished = false
        var reloads = 0
        form.startVerification(verify: { _, _ in
            let result = await withCheckedContinuation { reply = $0 }
            cancelled = Task.isCancelled
            finished = true
            return result
        }, loadAccounts: { reloads += 1; return [] })
        #expect(await wait { reply != nil })
        #expect(form.busy)
        form.cancelVerification()
        #expect(!form.busy)
        #expect(form.apiKey.isEmpty)
        reply?.resume(returning: true)
        #expect(await wait { finished })
        #expect(cancelled)
        #expect(reloads == 0)
        #expect(!form.failed)
    }

    @Test func cancelledRequestCannotChangeANewVerification() async {
        let form = OfficialAccountsForm()
        form.apiKey = "old-fixture-key"
        var oldReply: CheckedContinuation<Bool, Never>?
        var newReply: CheckedContinuation<Bool, Never>?
        var oldFinished = false
        form.startVerification(verify: { _, _ in
            let result = await withCheckedContinuation { oldReply = $0 }
            oldFinished = true
            return result
        }, loadAccounts: { Issue.record("Cancelled verification reloaded accounts"); return [] })
        #expect(await wait { oldReply != nil })
        form.cancelVerification()
        form.apiKey = "new-fixture-key"
        form.startVerification(verify: { _, _ in
            await withCheckedContinuation { newReply = $0 }
        }, loadAccounts: { [] })
        #expect(await wait { newReply != nil })
        oldReply?.resume(returning: true)
        #expect(await wait { oldFinished })
        #expect(form.busy)
        #expect(form.apiKey == "new-fixture-key")
        newReply?.resume(returning: false)
        #expect(await wait { !form.busy })
        #expect(form.failed)
    }

    @Test func successfulVerificationStillLoadsAccountsAndClearsTheKey() async {
        let form = OfficialAccountsForm()
        form.providerID = "kimi"
        form.apiKey = "fixture-key"
        let account = OfficialQuotaAccount(providerID: "kimi", label: "fixture", apiKey: "fixture-key")
        form.startVerification(verify: { provider, key in
            #expect(provider == "kimi")
            #expect(key == "fixture-key")
            return true
        }, loadAccounts: { [account] })
        #expect(await wait { !form.busy })
        #expect(form.apiKey.isEmpty)
        #expect(form.accounts.map(\.id) == [account.id])
        #expect(!form.failed)
    }

}
