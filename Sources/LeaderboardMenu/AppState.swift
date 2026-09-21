import Foundation
import LeaderboardCore

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var snapshot = LeaderboardSnapshot()
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastErrors: [LeaderboardKind: String] = [:]
    @Published private(set) var schedule = UpdateSchedule.initial()
    @Published private(set) var lastAttemptAt: Date?

    private let fetcher = LeaderboardFetcher()
    private let cache: LeaderboardCache
    private var updateTimer: Timer?

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

    func refreshFromMenuClick() {
        refreshNow()
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

        Task {
            async let artificialAnalysis = fetcher.artificialAnalysis()
            async let arena = fetcher.arenaWebDev()

            do {
                let board = try await artificialAnalysis
                snapshot.boards[board.kind] = board
            } catch {
                lastErrors[.artificialAnalysis] = error.localizedDescription
            }

            do {
                let board = try await arena
                snapshot.boards[board.kind] = board
            } catch {
                lastErrors[.codeArenaWebDev] = error.localizedDescription
            }

            finishRefresh()
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
    }
}
