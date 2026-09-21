import Foundation
import LeaderboardCore

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var snapshot = LeaderboardSnapshot()
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastErrors: [LeaderboardKind: String] = [:]
    @Published private(set) var schedule = UpdateSchedule.initial()
    @Published private(set) var lastAttemptAt: Date?
    @Published private(set) var selectedCategory = LeaderboardCategory.general

    private let fetcher = LeaderboardFetcher()
    private let cache: LeaderboardCache
    private var updateTimer: Timer?
    private var refreshPending = false

    init(cache: LeaderboardCache) {
        self.cache = cache
        if let cached = cache.load() {
            snapshot = cached
        }
    }

    func start() {
        refreshNow()
        startTimer()
    }

    /// Menu-bar clicks are throttled: the sources rate-limit, so rapid
    /// clicking must not turn into a burst of requests.
    private static let minimumMenuRefreshInterval: TimeInterval = 10 * 60

    func refreshFromMenuClick() {
        if let lastAttemptAt,
           Date().timeIntervalSince(lastAttemptAt) < Self.minimumMenuRefreshInterval {
            return
        }
        refreshNow()
    }

    func selectCategory(_ category: LeaderboardCategory) {
        guard category != selectedCategory else { return }
        selectedCategory = category
        guard !isFresh(category) else { return }
        if isRefreshing {
            refreshPending = true
        } else {
            refreshNow()
        }
    }

    private func startTimer() {
        updateTimer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    private func tick() {
        if Date() >= schedule.giveUpAt {
            schedule = schedule.givingUp()
            return
        }

        guard !isRefreshing, schedule.isDue() else { return }
        refreshNow()
    }

    private func refreshNow() {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastErrors = [:]
        lastAttemptAt = Date()

        let category = selectedCategory
        let kinds = category.boardKinds

        Task {
            await withTaskGroup(of: (LeaderboardKind, Leaderboard?, String?).self) { group in
                for kind in kinds {
                    let fetcher = fetcher
                    group.addTask {
                        do {
                            return (kind, try await fetcher.fetch(kind), nil)
                        } catch {
                            return (kind, nil, error.localizedDescription)
                        }
                    }
                }

                for await (kind, board, errorMessage) in group {
                    if let board {
                        snapshot.boards[kind] = board
                    } else {
                        lastErrors[kind] = errorMessage ?? "未知错误"
                    }
                }
            }

            finishRefresh()
        }
    }

    private func isFresh(_ category: LeaderboardCategory) -> Bool {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return category.boardKinds.allSatisfy { kind in
            (snapshot.boards[kind]?.fetchedAt ?? .distantPast) >= startOfDay
        }
    }

    private func finishRefresh() {
        cache.save(snapshot)
        isRefreshing = false

        if lastErrors.isEmpty {
            schedule = .afterSuccess()
        } else if Date() >= schedule.giveUpAt {
            schedule = schedule.givingUp()
        } else {
            schedule = schedule.schedulingRetry()
        }

        if refreshPending {
            refreshPending = false
            refreshNow()
        }
    }
}
