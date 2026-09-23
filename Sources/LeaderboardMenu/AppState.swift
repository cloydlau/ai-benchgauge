import Foundation
import LeaderboardCore

private struct CCSwitchQuotaLoad: Sendable {
    var result: CCSwitchProviderLoadResult
    var currentProviderID: String?
    var xaiAuthURL: URL
    var databaseURL: URL
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var snapshot = LeaderboardSnapshot()
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastErrors: [LeaderboardKind: String] = [:]
    @Published private(set) var schedule = UpdateSchedule.initial()
    @Published private(set) var lastAttemptAt: Date?
    @Published private(set) var selectedCategory = LeaderboardCategory.general
    @Published private(set) var selectedGrouping = LeaderboardGrouping.model
    @Published private(set) var isQuitting = false
    /// Provider quotas from the local CC Switch database. These are not
    /// leaderboard rows, so they stay off the table. Missing CC Switch or Codex
    /// installs are not errors.
    @Published private(set) var quotaChips: [AccountQuotaChip] = []
    @Published private(set) var quotaUpdatedAt: Date?
    @Published private(set) var quotaUnavailable = false

    private let fetcher = LeaderboardFetcher()
    private let cache: LeaderboardCache
    private let qwenWebsiteSource = QwenWebsiteQuotaSource()
    private var quotaClient: AccountQuotaClient!
    private let quotaNotifier = QuotaNotifier()
    private var updateTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var quotaTask: Task<Void, Never>?
    private var refreshPending = false
    private var lastQuotaAttemptAt: Date?
    private var lastQuotaAttemptAtByID: [String: Date] = [:]
    private var quotaGeneration = 0

    init(cache: LeaderboardCache) {
        self.cache = cache
        quotaClient = AccountQuotaClient(
            qwenQuotaSource: QwenPreferredQuotaSource(website: qwenWebsiteSource)
        )
        qwenWebsiteSource.onConnected = { [weak self] in
            self?.refreshQuotas(minimumInterval: 0)
        }
        if let cached = cache.load() {
            snapshot = cached
        }
        selectedCategory = CategoryPreference.load()
        selectedGrouping = GroupingPreference.load()
    }

    func start() {
        refreshNow()
        refreshQuotas(minimumInterval: 0)
        startTimer()
    }

    /// Leaderboard sources rate-limit, so menu clicks do not refetch them
    /// on every open. The selected provider's quota has no such interval.
    private static let minimumMenuRefreshInterval: TimeInterval = 10 * 60
    private static let inactiveQuotaRefreshInterval: TimeInterval = 60
    /// Matches CC Switch's default auto-query interval.
    private static let backgroundQuotaRefreshInterval: TimeInterval = 5 * 60

    func refreshFromMenuClick() {
        refreshQuotas(
            minimumInterval: 0,
            inactiveMinimumInterval: Self.inactiveQuotaRefreshInterval
        )
        if let lastAttemptAt,
           Date().timeIntervalSince(lastAttemptAt) < Self.minimumMenuRefreshInterval {
            return
        }
        refreshNow()
    }

    func connectQwenWebsite() {
        qwenWebsiteSource.connect()
    }

    /// Show the quitting state, then drop the timer and in-flight fetch so
    /// terminate is not held open by them. Returns false if quit already started.
    @discardableResult
    func beginQuitting() -> Bool {
        guard !isQuitting else { return false }
        isQuitting = true
        refreshPending = false
        updateTimer?.invalidate()
        updateTimer = nil
        refreshTask?.cancel()
        refreshTask = nil
        quotaTask?.cancel()
        quotaTask = nil
        quotaGeneration += 1
        return true
    }

    func selectCategory(_ category: LeaderboardCategory) {
        guard category != selectedCategory else { return }
        selectedCategory = category
        CategoryPreference.save(category)
        guard !isFresh(category) else { return }
        if isRefreshing {
            refreshPending = true
        } else {
            refreshNow()
        }
    }

    /// Grouping is a local view of the cached boards. Company rows are derived
    /// from models already on the board, so this must not refetch.
    func selectGrouping(_ grouping: LeaderboardGrouping) {
        guard grouping != selectedGrouping else { return }
        selectedGrouping = grouping
        GroupingPreference.save(grouping)
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
        guard !isQuitting else { return }
        refreshQuotas(minimumInterval: Self.backgroundQuotaRefreshInterval)
        if Date() >= schedule.giveUpAt {
            schedule = schedule.givingUp()
            return
        }

        guard !isRefreshing, schedule.isDue() else { return }
        refreshNow()
    }

    /// Loads providers from the local CC Switch database and refreshes their
    /// quotas. Credential material stays inside the client request. Does not
    /// read a Codex install.
    private func refreshQuotas(
        minimumInterval: TimeInterval,
        inactiveMinimumInterval: TimeInterval = 0
    ) {
        guard !isQuitting else { return }
        if let lastQuotaAttemptAt,
           Date().timeIntervalSince(lastQuotaAttemptAt) < minimumInterval {
            return
        }
        lastQuotaAttemptAt = Date()
        quotaGeneration += 1
        let generation = quotaGeneration
        quotaTask?.cancel()

        quotaTask = Task { [weak self] in
            guard let self else { return }
            let loaded = await Task.detached(priority: .utility) {
                let install = CCSwitchProviderStore.resolveInstall()
                let result = CCSwitchProviderStore.loadCodexProviders(databaseURL: install.databaseURL)
                let currentID: String?
                if case .records = result {
                    currentID = CCSwitchProviderStore.currentCodexProviderID(settingsURL: install.settingsURL)
                } else {
                    currentID = nil
                }
                return CCSwitchQuotaLoad(
                    result: result,
                    currentProviderID: currentID,
                    xaiAuthURL: install.xaiAuthURL,
                    databaseURL: install.databaseURL
                )
            }.value
            guard !Task.isCancelled, !self.isQuitting, generation == self.quotaGeneration else { return }

            switch loaded.result {
            case .absent:
                self.quotaUnavailable = false
                self.quotaChips = []
                self.quotaUpdatedAt = nil
                self.lastQuotaAttemptAtByID = [:]
            case .unavailable:
                // Keep the last chips. The strip only notes that this read failed.
                self.quotaUnavailable = true
            case let .records(records):
                self.quotaUnavailable = false
                let targets = CCSwitchQuotaCatalog.targets(
                    from: records,
                    currentProviderID: loaded.currentProviderID
                )
                guard !targets.isEmpty else {
                    self.quotaChips = []
                    self.quotaUpdatedAt = nil
                    self.lastQuotaAttemptAtByID = [:]
                    return
                }
                var previous = self.displayChips(for: targets)
                if let cachedQwen = self.qwenWebsiteSource.cachedQuota() {
                    previous = previous.map { chip in
                        guard chip.kind == .qwen, chip.status == .pending else { return chip }
                        return AccountQuotaChip(
                            id: chip.id,
                            shortName: chip.shortName,
                            websiteURL: chip.websiteURL,
                            kind: chip.kind,
                            isCurrent: chip.isCurrent,
                            status: .qwenWebsite(cachedQwen)
                        )
                    }
                }
                self.quotaChips = previous
                let now = Date()
                let targetsToRefresh = targets.filter { target in
                    if target.isCurrent { return true }
                    guard let lastAttempt = self.lastQuotaAttemptAtByID[target.id] else {
                        return true
                    }
                    return now.timeIntervalSince(lastAttempt) >= inactiveMinimumInterval
                }
                guard !targetsToRefresh.isEmpty else { return }
                for target in targetsToRefresh {
                    self.lastQuotaAttemptAtByID[target.id] = now
                }
                let client = self.quotaClient!
                do {
                    let chips = try await client.refresh(
                        targets: targetsToRefresh,
                        previous: previous,
                        authFileURL: loaded.xaiAuthURL,
                        databaseURL: loaded.databaseURL
                    )
                    guard !Task.isCancelled, !self.isQuitting, generation == self.quotaGeneration else { return }
                    let refreshedByID = Dictionary(uniqueKeysWithValues: chips.map { ($0.id, $0) })
                    let refreshedAt = Date()
                    self.quotaChips = previous.map { refreshedByID[$0.id] ?? $0 }
                    self.quotaUpdatedAt = refreshedAt
                    self.quotaNotifier.consider(chips: chips, now: refreshedAt)
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled, !self.isQuitting, generation == self.quotaGeneration else { return }
                    self.quotaChips = self.quotaChips.map { chip in
                        guard chip.status == .pending else { return chip }
                        return AccountQuotaChip(
                            id: chip.id,
                            shortName: chip.shortName,
                            websiteURL: chip.websiteURL,
                            kind: chip.kind,
                            isCurrent: chip.isCurrent,
                            status: .message(AccountQuotaMessage.queryFailed)
                        )
                    }
                }
            }
        }
    }

    /// Keeps the last shown value while a refresh is in flight so a failure
    /// color does not flash on every menu open.
    private func displayChips(for targets: [CCSwitchQuotaTarget]) -> [AccountQuotaChip] {
        targets.map { target in
            if let existing = quotaChips.first(where: { $0.id == target.id }),
               existing.status != .pending {
                return AccountQuotaChip(
                    id: target.id,
                    shortName: target.shortName,
                    websiteURL: target.websiteURL,
                    kind: target.kind,
                    isCurrent: target.isCurrent,
                    status: existing.status
                )
            }
            return .placeholder(for: target)
        }
    }

    private func refreshNow() {
        guard !isQuitting, !isRefreshing else { return }
        isRefreshing = true
        lastErrors = [:]
        lastAttemptAt = Date()

        let category = selectedCategory
        let kinds = category.boardKinds

        refreshTask = Task {
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
                    if Task.isCancelled { continue }
                    if let board {
                        snapshot.boards[kind] = board
                    } else {
                        lastErrors[kind] = errorMessage ?? "未知错误"
                    }
                }
            }

            guard !Task.isCancelled else { return }
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
