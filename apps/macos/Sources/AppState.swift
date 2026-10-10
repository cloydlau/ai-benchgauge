import AppKit
import CoreGraphics
import Foundation
import LeaderboardCore

private struct CCSwitchQuotaLoad: Sendable {
    var result: CCSwitchProviderLoadResult
    var isInstalled: Bool
    var currentProviderID: String?
    var xaiAuthURL: URL
    var officialTargets: [CCSwitchQuotaTarget]
    var ccSwitchTargets: [CCSwitchQuotaTarget]
    var shouldAskClaudeKeychainConsent: Bool
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
    @Published private(set) var claudeKeychainConsent = ClaudeKeychainConsent.notDetermined
    @Published private(set) var isClaudeKeychainConsentPending = false
    private let officialAccountStore = OfficialQuotaAccountStore()

    func officialAccounts() -> [OfficialQuotaAccount] {
        (try? officialAccountStore.load()) ?? []
    }

    func addOfficialAccount(providerID: String, label: String, apiKey: String) async -> Bool {
        guard !Task.isCancelled else { return false }
        let account = OfficialQuotaAccount(providerID: providerID, label: String(label.prefix(80)),
                                           apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let target = account.target, let client = quotaClient,
              let result = try? await client.refresh(targets: [target], previous: [], authFileURL: URL(fileURLWithPath: "/unused")),
              let chip = result.first, !Task.isCancelled else { return false }
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
    @Published private(set) var codexTaskCounts: CodexTaskCounts?
    @Published private(set) var codexDesktopRunning = false
    private let codexTaskMonitor = CodexTaskMonitor()
    private var codexTaskRefresh: Task<Void, Never>?
    private var codexTaskWorkspaceObservers: [NSObjectProtocol] = []
    var menuBarQuota: AccountQuotaMenuBarText? {
        if let currentCodexModelConfiguration {
            return currentCodexModelConfiguration.menuBarText(for: quotaChips, targets: Array(quotaTargetsByID.values))
        }
        return AccountQuotaFormatting.menuBarText(forChips: quotaChips)
    }

    private let fetcher = LeaderboardFetcher()
    private let cache: LeaderboardCache
    private let defaults: UserDefaults
    private let configuration: AppConfiguration
    private let qwenWebsiteSource = QwenWebsiteQuotaSource()
    private let xaiConnection = XAIAccountConnection()
    private let xaiWebsiteSource = XAIWebsiteSubscriptionSource()
    private let openAIConnection = OpenAIAccountConnection()
    private var quotaTargetsByID: [String: CCSwitchQuotaTarget] = [:]
    private var quotaClient: AccountQuotaClient!
    private let quotaNotifier = QuotaNotifier()
    private let xaiKeepAliveScheduleStore = XAIOAuthKeepAliveScheduleStore()
    private var updateTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var quotaTask: Task<Void, Never>?
    private var sharedXAILoginTimer: Timer?
    private var sharedXAILoginRevision: XAISharedLoginRevision?
    private var xaiKeepAliveTask: Task<Void, Never>?
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
    private var lastCheckedCodexModelConfiguration: CodexModelConfiguration?
    /// Set only for the refresh immediately following an explicit user action;
    /// background reads must never trigger macOS' Keychain authorization UI.
    private var allowsKeychainAuthenticationUI = false

    init(
        cache: LeaderboardCache,
        defaults: UserDefaults = .standard,
        configuration: AppConfiguration = .load(from: Bundle.main.url(forResource: "app", withExtension: "json"))
    ) {
        self.cache = cache
        self.defaults = defaults
        self.configuration = configuration
        claudeKeychainConsent = ClaudeKeychainConsentPreference.load(from: defaults)
        currentCodexModelConfiguration = CCSwitchProviderStore.currentCodexModelConfiguration()
        panelMode = PanelModePreference.load(from: defaults)
        quotaClient = AccountQuotaClient(
            qwenQuotaSource: QwenPreferredQuotaSource(website: qwenWebsiteSource),
            officialQuotaSource: openAIConnection.source
        )
        xaiWebsiteSource.onData = { [weak self] data in
            guard let self, let client = self.quotaClient, !self.isQuitting else { return false }
            let authURL = CCSwitchProviderStore.resolveInstall().xaiAuthURL
            return (try? await client.captureXAIWebsiteSubscription(data, authFileURL: authURL)) == true
        }
        xaiConnection.onConnected = { [weak self] in self?.refreshQuotas(minimumInterval: 0) }
        xaiWebsiteSource.onUpdated = { [weak self] in self?.refreshQuotas(minimumInterval: 0) }
        qwenWebsiteSource.onUpdated = { [weak self] status in
            guard let self, !self.isQuitting else { return }
            self.quotaChips = self.quotaChips.map { chip in
                guard chip.kind == .qwen else { return chip }
                return AccountQuotaChip(id: chip.id, shortName: chip.shortName, modelName: chip.modelName,
                    websiteURL: chip.websiteURL, kind: chip.kind, isCurrent: chip.isCurrent, status: status)
            }
            if case .qwenWebsite = status { self.quotaUpdatedAt = Date() }
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
        codexDesktopRunning = isCodexRunning
    }

    func start() {
        updateCodexDesktopPresence(isCodexRunning)
        let notifications = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            codexTaskWorkspaceObservers.append(notifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      QuotaAutoRefreshPolicy.isCodexBundleIdentifier(application.bundleIdentifier) else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let running = NSWorkspace.shared.runningApplications.contains {
                        !$0.isTerminated && QuotaAutoRefreshPolicy.isCodexBundleIdentifier($0.bundleIdentifier)
                    }
                    self.updateCodexDesktopPresence(running)
                    await self.codexTaskMonitor.setDesktopRunning(running)
                }
            })
        }
        codexTaskRefresh = Task { [weak self] in
            guard let monitor = self?.codexTaskMonitor else { return }
            let updates = await monitor.updates(desktopRunning: self?.isCodexRunning ?? false)
            for await counts in updates {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                let visibleCounts = self.codexDesktopRunning ? counts : nil
                if self.codexTaskCounts != visibleCounts { self.codexTaskCounts = visibleCounts }
            }
            await monitor.stop()
        }
        refreshNow()
        refreshQuotas(minimumInterval: 0)
        startXAIKeepAliveIfNeeded()
        lastCheckedQuotaProviderID = currentQuotaProviderSelection()
        lastCheckedCodexModelConfiguration = currentCodexModelConfiguration
        startTimer()
    }

    #if DEBUG
    /// The native visual suite supplies public fixture data and never starts
    /// timers, network requests, authentication or account refreshes.
    func applyVisualFixture(snapshot: LeaderboardSnapshot, chips: [AccountQuotaChip],
                            language: AppLanguage, errors: [LeaderboardKind: String],
                            emptyState: CCSwitchState?, panelMode: PanelMode = .clickToClose, quotaUpdatedAt: Date? = nil, quotaUnavailable: Bool = false,
                            modelConfiguration: CodexModelConfiguration? = nil, targets: [CCSwitchQuotaTarget] = [], taskCounts: CodexTaskCounts? = nil,
                            codexDesktopRunning: Bool = true) {
        self.snapshot = snapshot
        self.quotaUpdatedAt = quotaUpdatedAt
        self.quotaUnavailable = quotaUnavailable
        quotaChips = chips
        codexTaskCounts = taskCounts
        self.codexDesktopRunning = codexDesktopRunning
        currentCodexModelConfiguration = modelConfiguration
        quotaTargetsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
        selectedLanguage = language
        selectedCategory = .general
        selectedGrouping = .model
        self.panelMode = panelMode
        lastErrors = errors
        ccSwitchEmptyState = emptyState
    }
    #endif

    /// Applies to every leaderboard refresh path. Quota refreshes use their
    /// own intervals because they read different sources.
    private static let minimumLeaderboardRefreshInterval: TimeInterval = 30 * 60
    private static let inactiveQuotaRefreshInterval: TimeInterval = 60
    /// Automatic menu-bar quota refreshes run only while the Codex desktop
    /// app is open and the user is active. xAI token renewal runs independently.
    /// Explicit interactions and provider/model switches bypass this
    /// cadence; see the selection check in tick().
    private static let backgroundQuotaRefreshInterval = QuotaAutoRefreshPolicy.activeInterval

    func refreshFromMenuClick() {
        refreshCurrentModelName()
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

    /// Usage OAuth is shared with CC Switch; plan dates use a separate site session.
    func connectXAI(_ chip: AccountQuotaChip) {
        guard !isQuitting, chip.kind == .xaiOAuth else { return }
        if AccountQuotaFormatting.requiresXAISubscriptionConnection(chip) {
            connectXAISubscription()
        } else { xaiConnection.connect(language: selectedLanguage) }
    }

    func connectXAISubscription() {
        guard !isQuitting else { return }
        xaiWebsiteSource.connect(language: selectedLanguage)
    }

    func recoverGLMQuota(_ chip: AccountQuotaChip) {
        guard !isQuitting, let action = AccountQuotaFormatting.glmRecoveryAction(for: chip) else { return }
        if action == .configure {
            openCCSwitch()
        } else {
            refreshQuotas(minimumInterval: 0, requestedProviderID: chip.id)
        }
    }

    func openCCSwitch() {
        guard !isQuitting else { return }
        if let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: CCSwitchProviderStore.bundleID
        ) {
            // Reopen the existing instance so a window hidden in the tray
            // is restored too. Activation alone does not restore that window.
            let options = NSWorkspace.OpenConfiguration()
            options.activates = true
            options.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: appURL, configuration: options) { _, error in
                if let error {
                    Task { @MainActor in
                        NSAlert(error: error).runModal()
                    }
                }
            }
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
        codexTaskRefresh?.cancel()
        codexTaskRefresh = nil
        for observer in codexTaskWorkspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        codexTaskWorkspaceObservers.removeAll()
        openAIConnection.cancel()
        xaiConnection.cancel()
        xaiWebsiteSource.cancel()
        refreshPending = false
        updateTimer?.invalidate()
        updateTimer = nil
        sharedXAILoginTimer?.invalidate()
        sharedXAILoginTimer = nil
        refreshTask?.cancel()
        refreshTask = nil
        quotaTask?.cancel()
        quotaTask = nil
        quotaGeneration += 1
        xaiKeepAliveTask?.cancel()
        xaiKeepAliveTask = nil
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

    func allowClaudeKeychainAccess() {
        ClaudeKeychainConsentPreference.save(.allowed, to: defaults)
        claudeKeychainConsent = .allowed
        isClaudeKeychainConsentPending = false
        allowsKeychainAuthenticationUI = true
        refreshQuotas(minimumInterval: 0)
    }

    func declineClaudeKeychainAccess() {
        ClaudeKeychainConsentPreference.save(.denied, to: defaults)
        claudeKeychainConsent = .denied
        isClaudeKeychainConsentPending = false
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
        sharedXAILoginTimer?.invalidate()
        sharedXAILoginRevision = XAISharedLoginRevision(url: CCSwitchProviderStore.resolveInstall().xaiAuthURL)
        let sharedTimer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshSharedXAILoginIfChanged() }
        }
        RunLoop.main.add(sharedTimer, forMode: .common)
        sharedXAILoginTimer = sharedTimer
    }

    private func refreshSharedXAILoginIfChanged() {
        guard !isQuitting else { return }
        let revision = XAISharedLoginRevision(url: CCSwitchProviderStore.resolveInstall().xaiAuthURL)
        guard revision != sharedXAILoginRevision else { return }
        sharedXAILoginRevision = revision
        guard let target = quotaTargetsByID.values.first(where: { $0.kind == .xaiOAuth }) else { return }
        lastQuotaAttemptAtByID[target.id] = nil
        refreshQuotas(minimumInterval: 0, requestedProviderID: target.id)
    }

    private func tick() {
        guard !isQuitting else { return }
        // Workspace notifications can be missed during app startup. Recheck
        // cheap process metadata here; the monitor ignores unchanged values.
        let desktopRunning = isCodexRunning
        updateCodexDesktopPresence(desktopRunning)
        Task { [weak self] in await self?.codexTaskMonitor.setDesktopRunning(desktopRunning) }
        refreshCurrentModelName()
        refreshQuotaSelectionIfChanged()
        startXAIKeepAliveIfNeeded()
        if QuotaAutoRefreshPolicy.shouldRefreshAutomatically(
            now: Date(),
            lastAttemptAt: lastQuotaAttemptAt,
            isCodexRunning: isCodexRunning,
            secondsSinceLastUserInput: secondsSinceLastUserInput
        ) {
            refreshQuotas(
                minimumInterval: Self.backgroundQuotaRefreshInterval,
                inactiveMinimumInterval: 0,
                inactiveScope: .xaiOAuthOnly
            )
        }
        if Date() >= schedule.giveUpAt {
            schedule = schedule.givingUp()
            return
        }

        guard !isRefreshing, schedule.isDue() else { return }
        refreshNow()
    }

    /// Model selection can change inside Codex without switching CC Switch providers.
    /// Update only display metadata; keep the existing quota snapshot and cadence.
    private func refreshCurrentModelName() {
        let current = CCSwitchProviderStore.currentCodexModelConfiguration()
        if current != currentCodexModelConfiguration { currentCodexModelConfiguration = current }
    }

    /// CC Switch owns provider switching, while quota queries stay on the slow
    /// background cadence. Each tick reads only the tiny selection file; a
    /// changed selection forces one background-style refresh so the menu bar
    /// follows the switch within a minute instead of within half an hour.
    private func refreshQuotaSelectionIfChanged() {
        guard !isQuitting, connectingOpenAIProviderID == nil else { return }
        let selection = currentQuotaProviderSelection()
        guard selection != lastCheckedQuotaProviderID || currentCodexModelConfiguration != lastCheckedCodexModelConfiguration else { return }
        lastCheckedQuotaProviderID = selection
        lastCheckedCodexModelConfiguration = currentCodexModelConfiguration
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

    /// Only the desktop app bundle counts. BenchGauge can launch the bundled
    /// Codex CLI app-server helper, and that helper alone does not mean Codex
    /// is open for the user.
    private var isCodexRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            !$0.isTerminated && QuotaAutoRefreshPolicy.isCodexBundleIdentifier($0.bundleIdentifier)
        }
    }

    private func updateCodexDesktopPresence(_ running: Bool) {
        if codexDesktopRunning != running { codexDesktopRunning = running }
        if !running, codexTaskCounts != nil { codexTaskCounts = nil }
    }

    /// CGEventSource reports event timing without exposing event contents and
    /// does not require Accessibility or Input Monitoring permission.
    private var secondsSinceLastUserInput: TimeInterval? {
        let eventTypes: [CGEventType] = [
            .mouseMoved,
            .leftMouseDown,
            .leftMouseDragged,
            .rightMouseDown,
            .rightMouseDragged,
            .otherMouseDown,
            .otherMouseDragged,
            .scrollWheel,
            .keyDown,
            .flagsChanged,
        ]
        return eventTypes
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min()
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
        inactiveScope: InactiveQuotaRefreshScope = .all,
        requestedProviderID: String? = nil
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
        if requestedProviderID == nil || requestedProviderID.flatMap { quotaTargetsByID[$0] }?.isCurrent == true {
            lastQuotaAttemptAt = Date()
        }
        if let requestedProviderID {
            quotaChips = quotaChips.map { chip in
                guard chip.id == requestedProviderID else { return chip }
                return AccountQuotaChip(id: chip.id, shortName: chip.shortName, modelName: chip.modelName,
                    websiteURL: chip.websiteURL, kind: chip.kind, isCurrent: chip.isCurrent, status: .pending)
            }
        }
        quotaGeneration += 1
        let generation = quotaGeneration
        quotaTask?.cancel()
        let isInstalled = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: CCSwitchProviderStore.bundleID
        ) != nil
        let defaults = self.defaults
        let officialAccountStore = self.officialAccountStore
        let consent = ClaudeKeychainConsentPreference.load(from: defaults)
        let includesClaudeKeychain = consent == .allowed
        let allowsAuthenticationUI = self.allowsKeychainAuthenticationUI
        self.allowsKeychainAuthenticationUI = false

        quotaTask = Task { [weak self] in
            guard let self else { return }
            let loaded = await Task.detached(priority: .utility) {
                let install = CCSwitchProviderStore.resolveInstall()
                var result = CCSwitchProviderStore.loadQuotaProviders(databaseURL: install.databaseURL)
                var ccSwitchTargets: [CCSwitchQuotaTarget] = []
                let officialTargets = OfficialQuotaDiscovery.merge(ccSwitch: [], official:
                    ((try? officialAccountStore.load()) ?? []).compactMap(\.target)
                    + OfficialQuotaDiscovery.targets(
                        includeKeychain: includesClaudeKeychain,
                        allowKeychainAuthenticationUI: allowsAuthenticationUI,
                        includedKeychainKinds: [.claude]
                    ))
                if case .absent = result, !officialTargets.isEmpty { result = .records([]) }
                let currentID: String?
                if case .records = result {
                    currentID = CCSwitchProviderStore.currentCodexProviderID(settingsURL: install.settingsURL)
                } else {
                    currentID = nil
                }
                if case let .records(records) = result {
                    ccSwitchTargets = CCSwitchQuotaCatalog.targets(
                        from: records,
                        currentProviderID: currentID
                    )
                } else {
                    ccSwitchTargets = []
                }
                let shouldAsk = consent == .notDetermined
                    && ccSwitchTargets.contains { $0.kind == .claude && $0.accessToken == nil }
                    && !officialTargets.contains { $0.kind == .claude }
                return CCSwitchQuotaLoad(
                    result: result,
                    isInstalled: isInstalled,
                    currentProviderID: currentID,
                    xaiAuthURL: install.xaiAuthURL,
                    officialTargets: officialTargets,
                    ccSwitchTargets: ccSwitchTargets,
                    shouldAskClaudeKeychainConsent: shouldAsk
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
            case .records:
                self.quotaUnavailable = false
                self.ccSwitchEmptyState = nil
                if loaded.shouldAskClaudeKeychainConsent { self.isClaudeKeychainConsentPending = true }
                let discovered = OfficialQuotaDiscovery.merge(
                    ccSwitch: loaded.ccSwitchTargets,
                    official: loaded.officialTargets
                )
                let targets = self.currentCodexModelConfiguration?.selectingCurrentTarget(in: discovered) ?? discovered
                self.quotaTargetsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
                if targets.contains(where: { $0.kind == .xaiOAuth }) { self.xaiWebsiteSource.refreshIfConnected() }
                guard !targets.isEmpty else {
                    self.showCCSwitchEmptyState(self.configuration.ccSwitchState(
                        isInstalled: loaded.isInstalled, hasProviders: false
                    ))
                    return
                }
                if targets.contains(where: { $0.kind == .xaiOAuth }) {
                    self.startXAIKeepAliveIfNeeded()
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
                    if let requestedProviderID { return target.id == requestedProviderID }
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
                    self.quotaUpdatedAt = QuotaFreshness.updatedAt(afterRefreshing: chips, previous: self.quotaUpdatedAt, now: refreshedAt)
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
    /// Runs while the panel is hidden or Codex/user activity is idle. This task
    /// is separate from quotaTask so ordinary quota refresh cancellation cannot
    /// postpone renewal or interrupt saving a rotated token.
    private func startXAIKeepAliveIfNeeded() {
        guard !isQuitting, configuration.previewCCSwitchState == nil,
              xaiKeepAliveTask == nil else { return }
        let authURL = CCSwitchProviderStore.resolveInstall().xaiAuthURL
        guard Self.selectedXAIAuthAccountID(at: authURL) != nil else { return }
        xaiKeepAliveTask = Task { [weak self] in
            guard let self else { return }
            defer { self.xaiKeepAliveTask = nil }
            await self.refreshXAIKeepAliveIfDue(authFileURL: authURL)
        }
    }

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
