import Combine
import Testing
@testable import leaderboard_menu

@Suite(.serialized) @MainActor
struct DesktopLeaderboardSearchTests {
    @Test func rapidEditsPublishOnlyTheSettledQuery() async throws {
        let state = DesktopLeaderboardSearchState(delay: .milliseconds(30))
        var queries: [String] = []
        let subscription = state.$query.dropFirst().sink { queries.append($0) }
        defer { subscription.cancel() }
        for value in ["c", "cl", "cla", "claude"] { state.edit(value) }
        #expect(state.input == "claude")
        #expect(state.query.isEmpty)
        try await Task.sleep(for: .milliseconds(100))
        #expect(queries == ["claude"])
        state.edit("claude")
        try await Task.sleep(for: .milliseconds(100))
        #expect(queries == ["claude"])
    }

    @Test func clearingCancelsAnOlderPendingQuery() async throws {
        let state = DesktopLeaderboardSearchState(delay: .milliseconds(30))
        state.edit("gpt")
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.query == "gpt")
        state.edit("claude")
        state.edit("")
        #expect(state.query.isEmpty)
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.query.isEmpty)
    }

    @Test func compositionKeepsDraftTextWithoutFilteringUntilCommitted() async throws {
        let state = DesktopLeaderboardSearchState(delay: .milliseconds(30))
        state.edit("pending")
        state.edit("中", composing: true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.input == "中")
        #expect(state.query.isEmpty)
        state.edit("中文")
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.query == "中文")
    }
}
