import AppKit
import Foundation
import LeaderboardCore

private struct CCSwitchQuotaLoad: Sendable {
    var result: CCSwitchProviderLoadResult
    var isInstalled: Bool
    var currentProviderID: String?
    var xaiAuthURL: URL
    var officialTargets: [CCSwitchQuotaTarget]
}

private enum InactiveQuotaRefreshScope {
    case all
    case xaiOAuthOnly
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var snapshot = LeaderboardSnapshot()
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastErrors: [LeaderboardKind: String] = [:]
    @Published private(set) var schedule = UpdateSchedule.initial()
    @Published private(set) var selectedCategory = LeaderboardCategory.general
    @Published private(set) var selectedGrouping = LeaderboardGrouping.model
    @Published private(set) var selectedLanguage = AppLanguage.load()
    @Published private(set) var panelMode: PanelMode
    var closesOnFocusLoss: Bool { panelMode.closesOnFocusLoss }
    @Published private(set) var countryFilters: [LeaderboardKind: CountryFilter] = [:]
    @Published private(set) var isQuitting = false
    /// Provider quotas from the local CC Switch database. These are not
    /// leaderboard rows, so they stay off the table. Missing CC Switch data
    /// prompts installation; Codex itself does not need to be installed.
    @Published private(set) var quotaChips: [AccountQuotaChip] = []
    @Published private(set) var quotaUpdatedAt: Date?
    @Published private(set) var quotaUnavailable = false
    @Published private(set) var ccSwitchEmptyState: CCSwitchState?
    private let officialAccountStore = OfficialQuotaAccountStore()

    func officialAccounts() -> [OfficialQuotaAccount] {
        (try? officialAccountStore.load()) ?? []
    }

    func addOfficialAccount(providerID: String, label: String, apiKey: String) async -> Bool {
        let account = OfficialQuotaAccount(providerID: providerID, label: String(label.prefix(80)),
                                           apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let target = account.target, let client = quotaClient,
              let result = try? await client.refresh(targets: [target], previous: [], authFileURL: URL(fileURLWithPath: "/unused")),
              let chip = result.first else { return false }
        switch chip.status {
        case let .windows(windows): guard !windows.isEmpty else { return false }
        case let .balances(balances): guard !balances.isEmpty else { return false }
        default: return false
        }
        do {
            var accounts = try officialAccountStore.load()
            accounts.append(account)
            try officialAccountStore.save(accounts)
            refreshQuotas(minimumInterval: 0)
            return true
        } catch { return false }
    }

    func removeOfficialAccount(id: String) -> Bool {
        do {
            let accounts = try officialAccountStore.load().filter { $0.id != id }
            try officialAccountStore.save(accounts)
            refreshQuotas(minimumInterval: 0)
            return true
        } catch { return false }
    }
    @Published private(set) var connectingOpenAIProviderID: String?

    /// The status item is a projection of the same chips the panel renders, so
    /// a refresh triggered inside the panel moves the menu bar at the same
    /// moment instead of waiting for the slower background cadence.
    @Published private(set) var currentCodexModelConfiguration: CodexModelConfiguration?
    var menuBarQuota: AccountQuotaMenuBarText? {
        let target = quotaChips.first(where: \.isCurrent).flatMap { quotaTargetsByID[$0.id] }
        let model = target.flatMap { currentCodexModelConfiguration?.modelName(matching: $0) }
        return AccountQuotaFormatting.menuBarText(forChips: quotaChips, currentModelName: model)
    }

    private let fetcher = LeaderboardFetcher()
    private let cache: LeaderboardCache
    private let defaults: UserDefaults
    private let configuration: AppConfiguration
    private let qwenWebsiteSource = QwenWebsiteQuotaSource()
    private let xaiWebsiteSource = XAIWebsiteSubscriptionSource()
    private let openAIConnection = OpenAIAccountConnection()
    private var quotaTargetsByID: [String: CCSwitchQuotaTarget] = [:]
    private var quotaClient: AccountQuotaClient!
    private let quotaNotifier = QuotaNotifier()
    private let xaiKeepAliveScheduleStore = XAIOAuthKeepAliveScheduleStore()
    private var updateTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var quotaTask: Task<Void, Never>?
    private var refreshPending = false
    private var lastLeaderboardAttemptAtByCategory: [LeaderboardCategory: Date] = [:]
    private var lastQuotaAttemptAt: Date?
    private var lastQuotaAttemptAtByID: [String: Date] = [:]
    private var xaiKeepAliveAccountID: String?
    private var nextXAIKeepAliveAt: Date?
    private var isXAIKeepAliveRefreshing = false
    private var quotaGeneration = 0
    /// The current-provider selection this app last reacted to. CC Switch owns
    /// the value and rewrites its tiny settings file on every switch.
    private var lastCheckedQuotaProviderID: String?

    init(cache: LeaderboardCache, defaults: UserDefaults = .standard) {
        self.cache = cache
        self.defaults = defaults
        panelMode = PanelModePreference.load(from: defaults)
        quotaClient = AccountQuotaClient(
            qwenQuotaSource: QwenPreferredQuotaSource(website: qwenWebsiteSource),
            officialQuotaSource: openAIConnection.source
        )
        qwenWebsiteSource.onConnected = { [weak self] in
            self?.refreshQuotas(minimumInterval: 0)
        }
        openAIConnection.onConnected = { [weak self] in
            self?.refreshQuotas(minimumInterval: 0)
        }
        openAIConnection.onConnectingChanged = { [weak self] id in
            self?.connectingOpenAIProviderID = id
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
        lastCheckedQuotaProviderID = currentQuotaProviderSelection()
        startTimer()
    }

    /// Applies to every leaderboard refresh path. Quota refreshes use their
    /// own intervals because they read different sources.
    private static let minimumLeaderboardRefreshInterval: TimeInterval = 30 * 60
    private static let inactiveQuotaRefreshInterval: TimeInterval = 60
    /// Refresh the persistent menu bar quota every 30 minutes. Inactive xAI
    /// gets a separate token renewal near its observed seven-day login
    /// lifetime; other inactive chips are refreshed when the panel is opened.
    /// A provider switch does not wait for this cadence; see the selection
    /// check in tick().
    private static let backgroundQuotaRefreshInterval: TimeInterval = 30 * 60

    func refreshFromMenuClick() {
        refreshQuotas(
            minimumInterval: 0,
            inactiveMinimumInterval: Self.inactiveQuotaRefreshInterval
        )
        refreshNow()
    }

    func connectQwenWebsite() {
        qwenWebsiteSource.connect()
    }

    func connectOpenAI(_ chip: AccountQuotaChip) {
        guard !isQuitting, let target = quotaTargetsByID[chip.id], target.kind == .officialNote else { return }
        let previousTask = quotaTask
        previousTask?.cancel()
        quotaGeneration += 1
        openAIConnection.connect(target, language: selectedLanguage, after: previousTask)
    }

    /// A Grok sign-in can only happen inside CC Switch, which owns the auth
    /// file this quota reads. The provider's stored website is a product page
    /// with no sign-in entry, so the chip opens CC Switch instead. The chip
    /// recovers on the next refresh, which re-reads that file.
    func openCCSwitchSignIn(_ chip: AccountQuotaChip) {
        guard !isQuitting, chip.kind == .xaiOAuth else { return }
        openCCSwitch()
    }

    func openCCSwitch() {
        guard !isQuitting else { return }
        if let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: CCSwitchProviderStore.bundleID
        ).first {
            running.activate(options: [.activateAllWindows])
            return
        }
        if let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: CCSwitchProviderStore.bundleID
        ) {
            let options = NSWorkspace.OpenConfiguration()
            options.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: options) { _, _ in }
            return
        }
        NSWorkspace.shared.open(CCSwitchProviderStore.downloadURL)
    }

    /// Show the quitting state, then drop the timer and in-flight fetch so
    /// terminate is not held open by them. Returns false if quit already started.
    @discardableResult
    func beginQuitting() -> Bool {
        guard !isQuitting else { return false }
        isQuitting = true
        openAIConnection.cancel()
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

    func selectCountryFilter(_ filter: CountryFilter, for kind: LeaderboardKind) {
        countryFilters[kind] = filter == .all ? nil : filter
    }

    /// Grouping is a local view of the cached boards. Company rows are derived
    /// from models already on the board, so this must not refetch.
    func selectGrouping(_ grouping: LeaderboardGrouping) {
        guard grouping != selectedGrouping else { return }
        selectedGrouping = grouping
        GroupingPreference.save(grouping)
    }

    func selectLanguage(_ language: AppLanguage) {
        guard language != selectedLanguage else { return }
        selectedLanguage = language
        language.save()
    }

    func selectPanelMode(_ mode: PanelMode) {
        guard mode != panelMode else { return }
        panelMode = mode
        PanelModePreference.save(mode, to: defaults)
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
        refreshQuotaSelectionIfChanged()
        refreshQuotas(
            minimumInterval: Self.backgroundQuotaRefreshInterval,
            inactiveMinimumInterval: 0,
            inactiveScope: .xaiOAuthOnly
        )
        if Date() >= schedule.giveUpAt {
            schedule = schedule.givingUp()
            return
        }

        guard !isRefreshing, schedule.isDue() else { return }
        refreshNow()
    }

    /// CC Switch owns provider switching, while quota queries stay on the slow
    /// background cadence. Each tick reads only the tiny selection file; a
    /// changed selection forces one background-style refresh so the menu bar
    /// follows the switch within a minute instead of within half an hour.
    private func refreshQuotaSelectionIfChanged() {
        guard !isQuitting, connectingOpenAIProviderID == nil else { return }
        let selection = currentQuotaProviderSelection()
        guard selection != lastCheckedQuotaProviderID else { return }
        lastCheckedQuotaProviderID = selection
        refreshQuotas(
            minimumInterval: 0,
            inactiveMinimumInterval: Self.backgroundQuotaRefreshInterval,
            inactiveScope: .xaiOAuthOnly
        )
    }

    private func currentQuotaProviderSelection() -> String? {
        guard configuration.previewCCSwitchState != .notInstalled,
              configuration.previewCCSwitchState != .installedEmpty else { return nil }
        return CCSwitchProviderStore.currentCodexProviderID(
            settingsURL: CCSwitchProviderStore.resolveInstall().settingsURL
        )
    }

    /// Loads providers from the local CC Switch database and refreshes their
    /// quotas. `inactiveMinimumInterval` throttles the providers the status
    /// item does not show. `inactiveScope` can limit a background pass to xAI
    /// for OAuth keepalive while leaving other inactive providers untouched.
    /// Credential material stays inside the client request. Does not read a
    /// Codex install.
    private func refreshQuotas(
        minimumInterval: TimeInterval,
        inactiveMinimumInterval: TimeInterval = 0,
        inactiveScope: InactiveQuotaRefreshScope = .all
    ) {
        if let preview = configuration.previewCCSwitchState, preview != .configured {
            quotaTask?.cancel()
            quotaGeneration += 1
            showCCSwitchEmptyState(preview)
            return
        }
        guard !isQuitting, connectingOpenAIProviderID == nil else { return }
        if let lastQuotaAttemptAt,
           Date().timeIntervalSince(lastQuotaAttemptAt) < minimumInterval {
            return
        }
        lastQuotaAttemptAt = Date()
        quotaGeneration += 1
        let generation = quotaGeneration
        quotaTask?.cancel()
        let isInstalled = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: CCSwitchProviderStore.bundleID
        ) != nil

        quotaTask = Task { [weak self] in
            guard let self else { return }
            let loaded = await Task.detached(priority: .utility) {
                let install = CCSwitchProviderStore.resolveInstall()
                var result = CCSwitchProviderStore.loadQuotaProviders(databaseURL: install.databaseURL)
                let officialTargets = OfficialQuotaDiscovery.merge(ccSwitch: [], official:
                    ((try? self.officialAccountStore.load()) ?? []).compactMap(\.target) + OfficialQuotaDiscovery.targets())
                if case .absent = result, !officialTargets.isEmpty { result = .records([]) }
                let currentID: String?
                if case .records = result {
                    currentID = CCSwitchProviderStore.currentCodexProviderID(settingsURL: install.settingsURL)
                } else {
                    currentID = nil
                }
                return CCSwitchQuotaLoad(
                    result: result,
                    isInstalled: isInstalled,
                    currentProviderID: currentID,
                    xaiAuthURL: install.xaiAuthURL,
                    officialTargets: officialTargets
                )
            }.value
            guard !Task.isCancelled, !self.isQuitting, generation == self.quotaGeneration else { return }

            switch loaded.result {
            case .absent:
                self.showCCSwitchEmptyState(self.configuration.ccSwitchState(
                    isInstalled: loaded.isInstalled, hasProviders: false
                ))
            case .unavailable:
                if self.configuration.previewCCSwitchState == .configured {
                    self.showCCSwitchEmptyState(.configured)
                    return
                }
                // Keep the last chips. The strip only notes that this read failed.
                self.quotaUnavailable = true
                self.ccSwitchEmptyState = nil
            case let .records(records):
                self.quotaUnavailable = false
                self.ccSwitchEmptyState = nil
                let targets = OfficialQuotaDiscovery.merge(ccSwitch: CCSwitchQuotaCatalog.targets(
                    from: records,
                    currentProviderID: loaded.currentProviderID
                ), official: loaded.officialTargets)
                self.quotaTargetsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
                if targets.contains(where: { $0.kind == .xaiOAuth }) { self.xaiWebsiteSource.refreshIfConnected() }
                guard !targets.isEmpty else {
                    self.showCCSwitchEmptyState(self.configuration.ccSwitchState(
                        isInstalled: loaded.isInstalled, hasProviders: false
                    ))
                    return
                }
                if targets.contains(where: { $0.kind == .xaiOAuth }) {
                    await self.refreshXAIKeepAliveIfDue(authFileURL: loaded.xaiAuthURL)
                } else {
                    self.xaiKeepAliveAccountID = nil
                    self.nextXAIKeepAliveAt = nil
                }
                var previous = self.displayChips(for: targets)
                if let cachedQwen = self.qwenWebsiteSource.cachedQuota() {
                    previous = previous.map { chip in
                        guard chip.kind == .qwen, chip.status == .pending else { return chip }
                        return AccountQuotaChip(
                            id: chip.id,
                            shortName: chip.shortName,
                            modelName: chip.modelName,
                            websiteURL: chip.websiteURL,
                            kind: chip.kind,
                            isCurrent: chip.isCurrent,
                            status: .qwenWebsite(cachedQwen),
                            isStale: chip.isStale
                        )
                    }
                }
                self.quotaChips = previous
                let now = Date()
                let targetsToRefresh = targets.filter { target in
                    if target.isCurrent { return true }
                    if inactiveScope == .xaiOAuthOnly {
                        return false
                    }
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
                        authFileURL: loaded.xaiAuthURL
                    )
                    guard !Task.isCancelled, !self.isQuitting, generation == self.quotaGeneration else { return }
                    let refreshedByID = Dictionary(uniqueKeysWithValues: chips.map { ($0.id, $0) })
                    let refreshedAt = Date()
                    self.quotaChips = previous.map { refreshedByID[$0.id] ?? $0 }
                    self.quotaUpdatedAt = refreshedAt
                    self.quotaNotifier.consider(chips: chips, now: refreshedAt, language: self.selectedLanguage)
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled, !self.isQuitting, generation == self.quotaGeneration else { return }
                    self.quotaChips = self.quotaChips.map { chip in
                        guard chip.status == .pending else { return chip }
                        return AccountQuotaChip(
                            id: chip.id,
                            shortName: chip.shortName,
                            modelName: chip.modelName,
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

    /// Forces a refresh-token exchange rather than relying on a quota request.
    /// xAI does not publish the login lifetime, so this uses the observed
    /// seven-day boundary minus a safety margin.
    private func refreshXAIKeepAliveIfDue(authFileURL: URL) async {
        guard !isXAIKeepAliveRefreshing else { return }
        let accountID = Self.selectedXAIAuthAccountID(at: authFileURL)
        if let persisted = xaiKeepAliveScheduleStore.nextDate(accountID: accountID) {
            nextXAIKeepAliveAt = persisted
        } else if xaiKeepAliveAccountID != accountID {
            nextXAIKeepAliveAt = nil
        }
        xaiKeepAliveAccountID = accountID
        if let next = nextXAIKeepAliveAt, Date() < next { return }
        isXAIKeepAliveRefreshing = true
        defer { isXAIKeepAliveRefreshing = false }
        let outcome: XAIOAuthKeepAliveOutcome
        do {
            outcome = try await quotaClient.keepAliveXAI(authFileURL: authFileURL)
        } catch is CancellationError {
            return
        } catch {
            outcome = .retry
        }
        if Task.isCancelled { return }
        let next = Date().addingTimeInterval(
            outcome == .renewed
                ? XAIOAuthKeepAlivePolicy.successInterval
                : XAIOAuthKeepAlivePolicy.failureRetryInterval
        )
        nextXAIKeepAliveAt = next
        xaiKeepAliveScheduleStore.save(accountID: accountID, nextAt: next)
    }

    private static func selectedXAIAuthAccountID(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let snapshot = XaiAuthFile.parse(data) else { return nil }
        return XaiAuthFile.selectedAccount(snapshot)?.id
    }

    private func showCCSwitchEmptyState(_ state: CCSwitchState) {
        ccSwitchEmptyState = state == .configured ? nil : state
        quotaUnavailable = false
        quotaTargetsByID = [:]
        quotaChips = state == .configured ? [
            AccountQuotaChip(
                id: "preview-openai", shortName: "OpenAI · 示例", websiteURL: nil,
                kind: .officialNote, isCurrent: true,
                status: .windows([ParsedQuotaWindow(name: "five_hour", utilization: 23.4, resetsAt: nil)])
            ),
            AccountQuotaChip(
                id: "preview-kimi", shortName: "Kimi · 示例", websiteURL: nil,
                kind: .kimi, isCurrent: false,
                status: .windows([ParsedQuotaWindow(name: "weekly_limit", utilization: 46.2, resetsAt: nil)])
            ),
        ] : []
        quotaUpdatedAt = nil
        lastQuotaAttemptAtByID = [:]
        xaiKeepAliveAccountID = nil
        nextXAIKeepAliveAt = nil
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
                    modelName: target.modelName,
                    websiteURL: target.websiteURL,
                    kind: target.kind,
                    isCurrent: target.isCurrent,
                    status: existing.status,
                    isStale: existing.isStale
                )
            }
            return .placeholder(for: target)
        }
    }

    private func refreshNow() {
        guard !isQuitting, !isRefreshing else { return }
        let category = selectedCategory
        let now = Date()
        if let lastAttempt = lastLeaderboardAttemptAtByCategory[category],
           now.timeIntervalSince(lastAttempt) < Self.minimumLeaderboardRefreshInterval {
            return
        }
        // A recent successful fetch in the cache also limits refreshes after
        // an app restart. Missing boards still get their first fetch promptly.
        if category.boardKinds.allSatisfy({ kind in
            guard let fetchedAt = snapshot.boards[kind]?.fetchedAt else { return false }
            return now.timeIntervalSince(fetchedAt) < Self.minimumLeaderboardRefreshInterval
        }) {
            return
        }

        isRefreshing = true
        lastErrors = [:]
        lastLeaderboardAttemptAtByCategory[category] = now

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
