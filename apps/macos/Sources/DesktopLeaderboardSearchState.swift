import Combine
import Foundation

/// Only a settled query invalidates the leaderboard. Draft edits and expansion
/// belong to the search control, not the expensive table/size calculation.
@MainActor
final class DesktopLeaderboardSearchState: ObservableObject {
    @Published private(set) var query = ""
    private(set) var input = ""
    private var pending: Task<Void, Never>?
    private let delay: Duration

    init(delay: Duration = .milliseconds(250)) { self.delay = delay }

    func edit(_ value: String, composing: Bool = false) {
        input = value
        pending?.cancel()
        pending = nil
        guard !composing else { return }
        // Clearing should restore the full list immediately.
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            apply(value)
            return
        }
        guard value != query else { return }
        let delay = delay
        pending = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, let self, self.input == value else { return }
            self.apply(value)
        }
    }

    private func apply(_ value: String) {
        if query != value { query = value }
    }

    deinit { pending?.cancel() }
}
