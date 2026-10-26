import Foundation
import LeaderboardCore

// One persistent child process, JSON-lines over inherited pipes. Credentials
// remain inside LeaderboardCore; the desktop receives only display projections.
struct Request: Decodable, Sendable {
    var id: Int
    var command: String
    var category: String?
    var grouping: String?
    var boards: [String]?
    var sources: [String: String]?
    var countries: [String: String]?
    var language: String?
    var providerID: String?
    var modelID: String?
    var loginID: String?
    var authorizationURL: String?
    var pageText: String?
    var officialProvider: String?
    var accountLabel: String?
    var apiKey: String?
    var qwenWebsiteConnected: Bool?
}
struct Response: Encodable {
    var id: Int
    var result: State?
    var authorizationURL: String?
    var loginID: String?
    var error: String?
    var officialAccounts: [OfficialAccountSummary]?
    var officialProviders: [OfficialProviderSummary]?
    var qwenAuthenticated: Bool?
    var qwenQuotaCaptured: Bool?
    var userCode: String?
    var loginState: String?
    var pollInterval: Double?
    var expiresIn: Double?
    var qwenQuotaRefreshNeeded: Bool?
    var modelDetails: [ModelDetailSection]?
}
struct State: Encodable {
    var boards: [Board]
    var quotas: [Quota]
    var quotaNeedsCCSwitch: Bool
    var quotaUnavailable: Bool
    var trayText: String?
    var alerts: [Alert]
    var layoutEntries: [LayoutEntry]? = nil
    var quotaUpdatedAt: String? = nil
}
struct LayoutEntry: Encodable { var name: String; var planTitle: String?; var apiTitle: String? }
struct Board: Encodable {
    var modelMetadataSource: ModelMetadataSource? = nil
    var kind: String; var title: String; var url: String
    var updatedAt: String?; var error: String?; var entries: [Entry]
    var fetchedAt: String? = nil
    var sourceNote: String? = nil
    var countryOptions: [CountryOption]? = nil
    var distribution: LeaderboardDistribution? = nil
}
struct CountryOption: Encodable { var value: String; var label: String }
struct Entry: Encodable {
    var modelMetadata: ModelMetadata? = nil
    var detailID: String? = nil
    var voteCount: Int? = nil
    var rank: Int; var name: String; var score: Double
    var organization: String?; var country: String?; var logo: String?
    var codingURL: String?; var apiURL: String?; var help: String?
    var openness: String? = nil
    var brandColor: String? = nil; var logoPNG: String? = nil; var initials: String? = nil
}
struct Quota: Encodable {
    var id: String; var name: String; var isCurrent: Bool; var isStale: Bool
    var help: String; var url: String?; var canConnect: Bool; var connection: String?; var runs: [Run]
    var accentLight: String?
    var isDimmed: Bool
}
struct Run: Encodable { var text: String; var light: String; var dark: String }
struct Alert: Encodable { var title: String; var body: String }
struct OfficialAccountSummary: Encodable { var id: String; var providerID: String; var label: String }
struct OfficialProviderSummary: Encodable { var id: String; var name: String; var description: String }

actor Engine {
    private static let inactiveQuotaRefreshInterval: TimeInterval = 60

    private var snapshot = LeaderboardSnapshot()
    private var errors: [LeaderboardKind: String] = [:]
    private var chips: [AccountQuotaChip] = []
    private var targets: [String: CCSwitchQuotaTarget] = [:]
    private var needsCCSwitch = false
    private var unavailable = false
    private var delivered = Set<String>()
    private let recoveryStore: QuotaRecoveryStore?
    private var recovery: QuotaRecoveryTracker
    private var lastQuotaAttemptAtByID: [String: Date] = [:]
    private let fetcher: LeaderboardFetcher
    private let cache: LeaderboardCache
    private let official = OpenAIManagedQuotaSource()
    private let officialAccountStore = OfficialQuotaAccountStore()
    private var client: AccountQuotaClient?
    private var lastBoardRefresh: [LeaderboardKind: Date] = [:]
    private var lastQuotaRefresh: Date?
    private var lastCheckedModelConfiguration: CodexModelConfiguration?
    private var quotaUpdatedAt: Date?
    private var lastInactiveRefresh: Date?
    private var sharedXAILoginRevision: XAISharedLoginRevision?
    private let xaiLogin = XAIDeviceLogin()
    private let xaiKeepAliveScheduleStore = XAIOAuthKeepAliveScheduleStore()
    private var xaiKeepAliveAccountID: String?
    private var nextXAIKeepAliveAt: Date?
    private var isXAIKeepAliveRefreshing = false
    private var selectedBoards: [LeaderboardCategory: [LeaderboardKind]] = [:]
    private var boardTasks: [LeaderboardKind: Task<Void, Never>] = [:]
    private var boardTokens: [LeaderboardKind: UUID] = [:]
    private var cachedBoardTasks: [LeaderboardKind: Task<Leaderboard?, Never>] = [:]
    private var cachedBoardTokens: [LeaderboardKind: UUID] = [:]
    private var selectionRequestIDs: [LeaderboardCategory: Int] = [:]
    private var refreshingQuotas = false
    private var qwenWebsite: QwenWebsiteQuota?
    private var qwenWebsiteConnected = false
    private var qwenWebsiteFailure: AccountQuotaChip.Status?
    private let allowsAccountAccess: Bool
    private var qwenCapturedAt: Date?
    private let qwenCacheFile = PlatformPaths.applicationSupport.appending(path: "qwen-website-quota.json")

    init(cacheFile: URL? = nil, fetcher: LeaderboardFetcher = LeaderboardFetcher()) throws {
        self.fetcher = fetcher
        allowsAccountAccess = cacheFile == nil
        recoveryStore = cacheFile == nil ? QuotaRecoveryStore() : nil
        recovery = recoveryStore?.load() ?? QuotaRecoveryTracker()
        cache = LeaderboardCache(fileURL: try cacheFile ?? LeaderboardCache.defaultFileURL())
        snapshot = cache.load() ?? LeaderboardSnapshot()
        if cacheFile == nil, let saved = try? Data(contentsOf: qwenCacheFile), let quota = QwenWebsiteQuotaParser.parse(saved),
           let captured = quota.capturedAt, Date().timeIntervalSince(captured) < 86400 {
            qwenWebsite = quota; qwenCapturedAt = captured
        }
    }
    func handle(_ request: Request) async -> Response {
        let category = LeaderboardCategory(rawValue: request.category ?? "general") ?? .general
        let language = AppLanguage(rawValue: request.language ?? "en") ?? .english
        // JSON-line requests can enter the actor out of order. An older
        // response must never re-enable a source the user has just disabled.
        let kinds: [LeaderboardKind]
        if request.id >= selectionRequestIDs[category, default: Int.min] {
            kinds = DesktopBoardSelection.kinds(for: category, saved: request.boards)
            selectedBoards[category] = kinds
            selectionRequestIDs[category] = request.id
        } else {
            kinds = selectedBoards[category] ?? category.boardKinds
        }
        for kind in category.boardKinds where !kinds.contains(kind) {
            if let task = boardTasks.removeValue(forKey: kind) {
                task.cancel()
                lastBoardRefresh[kind] = nil
            }
            cachedBoardTasks.removeValue(forKey: kind)?.cancel()
            cachedBoardTokens[kind] = nil
            boardTokens[kind] = nil
        }
        do {
            guard allowsAccountAccess || ["state", "cachedBoards", "refreshBoards", "refreshBoardsIfStale", "modelDetails"].contains(request.command) else {
                return Response(id: request.id, error: "Account access disabled for offline fixtures")
            }
            if let connected = request.qwenWebsiteConnected { qwenWebsiteConnected = connected }
            switch request.command {
            case "modelDetails":
                if let id = request.modelID {
                    let model = snapshot.boards.values.lazy.flatMap(\.entries).compactMap(\.modelMetadata)
                        .filter { $0.id == id }.max { $0.fetchedAt < $1.fetchedAt }
                    let details = model.map { ModelDetails.sections(for: LeaderboardEntry(rank: 0, name: $0.name, score: 0, modelMetadata: $0), language: language) } ?? []
                    return Response(id: request.id, modelDetails: details)
                }
                guard let text = request.pageText, text.utf8.count <= 1_048_576,
                      let model = try? JSONDecoder().decode(ModelMetadata.self, from: Data(text.utf8)) else {
                    return Response(id: request.id, modelDetails: [])
                }
                let entry = LeaderboardEntry(rank: 0, name: model.name, score: 0, modelMetadata: model)
                return Response(id: request.id, modelDetails: ModelDetails.sections(for: entry, language: language))
            case "officialAccounts":
                return Response(id: request.id, officialAccounts: try officialAccountStore.load().map {
                    OfficialAccountSummary(id: $0.id, providerID: $0.providerID, label: $0.label)
                }, officialProviders: LeaderboardQuotaProviders.keyProviders.map {
                    OfficialProviderSummary(id: $0.id, name: $0.name, description: $0.quotaDescription)
                })
            case "addOfficialAccount":
                guard let provider = request.officialProvider, let key = request.apiKey, !key.isEmpty, key.utf8.count <= 16_384,
                      !key.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" }) else { throw OpenAIConnectionError.invalidResponse }
                let account = OfficialQuotaAccount(providerID: provider, label: String((request.accountLabel ?? "").prefix(80)), apiKey: key)
                guard let target = account.target else { throw OpenAIConnectionError.invalidResponse }
                if client == nil { client = AccountQuotaClient(officialQuotaSource: official) }
                let result = try await client!.refresh(targets: [target], previous: [])
                guard let chip = result.first else { throw OpenAIConnectionError.invalidResponse }
                switch chip.status {
                case let .windows(windows): guard !windows.isEmpty else { throw OpenAIConnectionError.invalidResponse }
                case let .balances(balances): guard !balances.isEmpty else { throw OpenAIConnectionError.invalidResponse }
                default: throw OpenAIConnectionError.invalidResponse
                }
                var accounts = try officialAccountStore.load(); accounts.append(account)
                try officialAccountStore.save(accounts)
                lastQuotaRefresh = nil
                lastInactiveRefresh = nil
                try await refreshQuotas(onlyCurrent: false)
            case "removeOfficialAccount":
                guard let id = request.providerID, id.hasPrefix("official:") else { throw OpenAIConnectionError.invalidResponse }
                try officialAccountStore.save(try officialAccountStore.load().filter { $0.id != id })
                lastQuotaRefresh = nil
                lastInactiveRefresh = nil
                try await refreshQuotas(onlyCurrent: false)
            case "state":
                if allowsAccountAccess, CCSwitchProviderStore.currentCodexModelConfiguration() != lastCheckedModelConfiguration {
                    lastQuotaRefresh = nil
                    lastInactiveRefresh = nil
                    try await refreshQuotas(onlyCurrent: false)
                }
            case "captureQwen":
                guard let text = request.pageText, text.utf8.count <= 50000 else {
                    return Response(id: request.id, error: "No quota found")
                }
                let data = Data(text.utf8)
                guard let quota = QwenWebsiteQuotaParser.parse(data) else {
                    guard let failure = QwenWebsiteQuotaParser.failureStatus(in: data) else {
                        return Response(id: request.id, error: "No quota found")
                    }
                    qwenWebsiteFailure = failure
                    if failure != .message(AccountQuotaMessage.queryFailed) {
                        qwenWebsite = nil; qwenCapturedAt = nil
                        if FileManager.default.fileExists(atPath: qwenCacheFile.path) {
                            try FileManager.default.removeItem(at: qwenCacheFile)
                        }
                    }
                    if case .note = failure { qwenWebsiteConnected = true }
                    return Response(id: request.id, result: project(category: category, grouping: request.grouping, language: language, sources: request.sources, countries: request.countries, kinds: kinds),
                        qwenAuthenticated: { if case .note = failure { return true }; return nil }(), qwenQuotaCaptured: false)
                }
                qwenWebsiteFailure = nil; qwenWebsiteConnected = true
                qwenWebsite = quota; qwenCapturedAt = Date(); quotaUpdatedAt = qwenCapturedAt
                if let stored = QwenWebsiteQuotaParser.persistedData(for: quota) {
                    try FileManager.default.createDirectory(at: qwenCacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try stored.write(to: qwenCacheFile, options: .atomic)
                    #if !os(Windows)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: qwenCacheFile.path)
                    #endif
                }
                return Response(id: request.id, result: project(category: category, grouping: request.grouping, language: language, sources: request.sources, countries: request.countries, kinds: kinds),
                    qwenAuthenticated: true, qwenQuotaCaptured: true)
            case "captureXAI":
                guard let text = request.pageText, text.utf8.count <= 1_048_576 else { return Response(id: request.id, error: "No matching plan date") }
                if client == nil { client = AccountQuotaClient(officialQuotaSource: official) }
                let authURL = XaiAuthFile.defaultURL
                guard try await client!.captureXAIWebsiteSubscription(Data(text.utf8), authFileURL: authURL) else {
                    return Response(id: request.id, error: "No matching plan date")
                }
                let xaiTargets = targets.values.filter { $0.kind == .xaiOAuth }
                let refreshed = try await client!.refresh(targets: xaiTargets, previous: chips, authFileURL: authURL)
                let byID = Dictionary(uniqueKeysWithValues: refreshed.map { ($0.id, $0) })
                chips = chips.map { byID[$0.id] ?? $0 }
                quotaUpdatedAt = QuotaFreshness.updatedAt(afterRefreshing: refreshed, previous: quotaUpdatedAt, now: Date())
            case "keepAliveXAI":
                let authURL = XaiAuthFile.defaultURL
                if Self.selectedXAIAuthAccountID(at: authURL) != nil {
                    if client == nil { client = AccountQuotaClient(officialQuotaSource: official) }
                    await refreshXAIKeepAliveIfDue(authFileURL: authURL)
                }
                return Response(id: request.id)
            case "cachedBoards": await readCachedBoards(kinds)
            case "refreshBoards", "refreshBoardsIfStale": await refreshBoards(kinds, force: request.command == "refreshBoards")
            case "refreshQuotas", "refreshCurrentQuota":
                try await refreshQuotas(onlyCurrent: request.command == "refreshCurrentQuota")
            case "refreshQuotaRecoveries":
                guard !refreshingQuotas else { return Response(id: request.id) }
                let now = Date()
                let due = recovery.refreshDueChipIDs(now: now, lastAttempts: lastQuotaAttemptAtByID)
                    .intersection(targets.keys)
                let websiteIDs = Set(due.filter { targets[$0]?.kind == .qwen && qwenWebsiteConnected })
                for id in websiteIDs { lastQuotaAttemptAtByID[id] = now }
                let apiIDs = due.subtracting(websiteIDs)
                if !apiIDs.isEmpty {
                    try await refreshQuotas(onlyCurrent: false, requestedProviderIDs: apiIDs)
                }
                return Response(id: request.id, result: project(category: category, grouping: request.grouping, language: language, sources: request.sources, countries: request.countries, kinds: kinds),
                    qwenQuotaRefreshNeeded: !websiteIDs.isEmpty)
            case "retryQuota":
                guard let id = request.providerID, targets[id]?.kind == .zhipu else {
                    throw OpenAIConnectionError.invalidResponse
                }
                try await refreshQuotas(onlyCurrent: false, requestedProviderID: id)
            case "watchXAILogin":
                guard allowsAccountAccess else { throw XAIDeviceLoginError.cancelled }
                let url = XaiAuthFile.defaultURL
                let revision = XAISharedLoginRevision(url: url)
                guard sharedXAILoginRevision != revision else { return Response(id: request.id) }
                sharedXAILoginRevision = revision
                if let target = targets.values.first(where: { $0.kind == .xaiOAuth }) {
                    try await refreshQuotas(onlyCurrent: false, requestedProviderID: target.id)
                }
            case "connectXAI":
                guard allowsAccountAccess else { throw XAIDeviceLoginError.cancelled }
                let attempt = try await xaiLogin.startForBenchGauge()
                return Response(id: request.id, authorizationURL: attempt.authorizationURL.absoluteString,
                    loginID: attempt.id, userCode: attempt.userCode, loginState: "waiting",
                    pollInterval: attempt.interval, expiresIn: max(0, attempt.expiresAt.timeIntervalSinceNow))
            case "pollXAI":
                guard let id = request.loginID else { throw XAIDeviceLoginError.cancelled }
                switch try await xaiLogin.poll(id: id) {
                case let .waiting(interval): return Response(id: request.id, loginState: "waiting", pollInterval: interval)
                case .connected:
                    lastQuotaRefresh = nil
                    try? await refreshQuotas(onlyCurrent: false)
                    return Response(id: request.id, result: project(category: category, grouping: request.grouping, language: language, sources: request.sources, countries: request.countries, kinds: kinds), loginState: "saved")
                }
            case "cancelXAI": await xaiLogin.cancel()
            case "connectOpenAI":
                guard let id = request.providerID, let target = targets[id] else { throw OpenAIConnectionError.invalidResponse }
                let attempt = try await official.startLogin(for: target)
                return Response(id: request.id, authorizationURL: attempt.authorizationURL.absoluteString, loginID: attempt.id)
            case "finishOpenAI":
                guard let id = request.providerID, let target = targets[id], let loginID = request.loginID,
                      let rawURL = request.authorizationURL, let url = URL(string: rawURL),
                      OpenAIManagedQuotaSource.isTrustedAuthorizationURL(url) else { throw OpenAIConnectionError.invalidResponse }
                try await official.finishLogin(OpenAILoginAttempt(id: loginID, authorizationURL: url), for: target)
                lastQuotaRefresh = nil
                try await refreshQuotas(onlyCurrent: false)
            case "cancelOpenAI":
                if let id = request.providerID { await official.cancelLogin(for: id) }
            default: return Response(id: request.id, error: "Unknown command")
            }
            return Response(id: request.id, result: project(category: category, grouping: request.grouping, language: language, sources: request.sources, countries: request.countries, kinds: kinds))
        } catch let error as XAIDeviceLoginError {
            return Response(id: request.id, loginState: error.state)
        } catch {
            // Never serialize upstream messages, tokens, paths or account IDs.
            return Response(id: request.id, error: language.text("Could not complete this request. Check the connection and try again.", "请求未完成，请检查连接后重试。"))
        }
    }
    private func refreshBoards(_ kinds: [LeaderboardKind], force: Bool) async {
        let now = Date()
        for kind in kinds {
            guard boardTasks[kind] == nil else { continue }
            if !force, LeaderboardFreshness.dueKinds([kind], snapshot: snapshot, lastAttempts: lastBoardRefresh, now: now).isEmpty { continue }
            lastBoardRefresh[kind] = now
            let token = UUID()
            boardTokens[kind] = token
            let fetcher = self.fetcher
            boardTasks[kind] = Task {
                do {
                    let board = try await fetcher.fetch(kind, onCachedBoard: { board in
                        await self.acceptRefreshingBoard(board, token: token)
                    })
                    self.finishBoard(kind, board: board, token: token)
                } catch {
                    self.finishBoard(kind, board: nil, token: token, configurationRequired: error is LeaderboardConfigurationRequired)
                }
            }
        }
        let tasks = kinds.compactMap { boardTasks[$0] }
        for task in tasks { await task.value }
    }
    private func acceptRefreshingBoard(_ board: Leaderboard, token: UUID) {
        guard boardTokens[board.kind] == token else { return }
        acceptSharedBoard(board)
    }
    private func finishBoard(_ kind: LeaderboardKind, board: Leaderboard?, token: UUID, configurationRequired: Bool = false) {
        guard boardTokens[kind] == token else { return }
        if let board { acceptSharedBoard(board); errors[kind] = nil }
        else { errors[kind] = configurationRequired ? "configurationRequired" : "Refresh failed" }
        boardTokens[kind] = nil
        boardTasks[kind] = nil
        cache.save(snapshot)
    }
    private func acceptSharedBoard(_ board: Leaderboard) {
        guard board != snapshot.boards[board.kind], board.canReplace(snapshot.boards[board.kind]) else { return }
        snapshot.boards[board.kind] = board
        errors[board.kind] = nil
        cache.save(snapshot)
    }
    private func readCachedBoards(_ kinds: [LeaderboardKind]) async {
        let fetcher = self.fetcher
        for kind in kinds where cachedBoardTasks[kind] == nil {
            cachedBoardTokens[kind] = UUID()
            cachedBoardTasks[kind] = Task { try? await fetcher.fetchCached(kind) }
        }
        let tasks = kinds.compactMap { kind in cachedBoardTasks[kind].map { (kind, $0, cachedBoardTokens[kind]) } }
        for (kind, task, token) in tasks {
            let board = await task.value
            guard !task.isCancelled, cachedBoardTokens[kind] == token else { continue }
            cachedBoardTasks[kind] = nil
            cachedBoardTokens[kind] = nil
            if let board, selectedBoards.values.contains(where: { $0.contains(kind) }) { acceptSharedBoard(board) }
        }
    }
    private func refreshQuotas(onlyCurrent: Bool, requestedProviderID: String? = nil, requestedProviderIDs: Set<String>? = nil) async throws {
        guard !refreshingQuotas else { return }
        let now = Date()
        if requestedProviderID == nil, requestedProviderIDs == nil, let previous = lastQuotaRefresh, now.timeIntervalSince(previous) < (onlyCurrent ? 1800 : 10) { return }
        refreshingQuotas = true
        defer { refreshingQuotas = false }
        if (requestedProviderID == nil && requestedProviderIDs == nil) || requestedProviderID.flatMap({ targets[$0] })?.isCurrent == true { lastQuotaRefresh = now }
        let install = CCSwitchProviderStore.resolveInstall()
        var loaded = CCSwitchProviderStore.loadQuotaProviders(databaseURL: install.databaseURL)
        let officialTargets = OfficialQuotaDiscovery.merge(ccSwitch: [], official:
            ((try? officialAccountStore.load()) ?? []).compactMap(\.target)
            + OfficialQuotaDiscovery.targets(includeKeychain: false))
        if case .absent = loaded, !officialTargets.isEmpty { loaded = .records([]) }
        switch loaded {
        case .absent:
            chips = []; targets = [:]; unavailable = false; quotaUpdatedAt = nil
            needsCCSwitch = !FileManager.default.fileExists(atPath: install.databaseURL.path)
            xaiKeepAliveAccountID = nil
            nextXAIKeepAliveAt = nil
        case .unavailable: unavailable = true
            chips = chips.map {
                AccountQuotaChip(
                    id: $0.id,
                    shortName: $0.shortName,
                    modelName: $0.modelName,
                    websiteURL: $0.websiteURL,
                    kind: $0.kind,
                    isCurrent: $0.isCurrent,
                    status: $0.status,
                    isStale: true,
                    credits: $0.credits
                )
            }
        case .records(let records):
            unavailable = false; needsCCSwitch = false
            let discovered = OfficialQuotaDiscovery.merge(ccSwitch: CCSwitchQuotaCatalog.targets(from: records,
                currentProviderID: CCSwitchProviderStore.currentCodexProviderID(settingsURL: install.settingsURL)), official: officialTargets)
            lastCheckedModelConfiguration = CCSwitchProviderStore.currentCodexModelConfiguration()
            let list = lastCheckedModelConfiguration?.selectingCurrentTarget(in: discovered) ?? discovered
            targets = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
            let prior = Dictionary(uniqueKeysWithValues: chips.map { ($0.id, $0) })
            if !list.contains(where: { prior[$0.id] != nil }) { quotaUpdatedAt = nil }
            chips = list.map { target in
                AccountQuotaChip(id: target.id, shortName: target.shortName, modelName: target.modelName,
                                 websiteURL: target.websiteURL,
                                 kind: target.kind, isCurrent: target.isCurrent,
                                 status: prior[target.id]?.status ?? .pending, isStale: prior[target.id]?.isStale ?? false,
                                 credits: prior[target.id]?.credits)
            }
            if client == nil { client = AccountQuotaClient(officialQuotaSource: official) }
            if list.contains(where: { $0.kind == .xaiOAuth }) {
                await refreshXAIKeepAliveIfDue(authFileURL: XAILoginStore.authURL(sharedAuthURL: install.xaiAuthURL))
            } else {
                xaiKeepAliveAccountID = nil
                nextXAIKeepAliveAt = nil
            }
            let includeInactive = requestedProviderID == nil && requestedProviderIDs == nil && !onlyCurrent && (
                lastInactiveRefresh.map {
                    now.timeIntervalSince($0) >= Self.inactiveQuotaRefreshInterval
                } ?? true
            )
            let refreshing = list.filter { target in
                if let requestedProviderIDs { return requestedProviderIDs.contains(target.id) }
                if let requestedProviderID { return target.id == requestedProviderID }
                if target.isCurrent { return true }
                return includeInactive
            }
            if includeInactive {
                lastInactiveRefresh = now
            }
            guard let client, !refreshing.isEmpty else { return }
            for target in refreshing { lastQuotaAttemptAtByID[target.id] = now }
            let refreshed = try await client.refresh(targets: refreshing, previous: chips, authFileURL: XAILoginStore.authURL(sharedAuthURL: install.xaiAuthURL))
            let result = Dictionary(uniqueKeysWithValues: refreshed.map { ($0.id, $0) })
            chips = chips.map { result[$0.id] ?? $0 }
            quotaUpdatedAt = QuotaFreshness.updatedAt(afterRefreshing: refreshed, previous: quotaUpdatedAt, now: Date())
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
        guard let client else { return }
        let outcome: XAIOAuthKeepAliveOutcome
        do {
            outcome = try await client.keepAliveXAI(authFileURL: authFileURL)
        } catch is CancellationError {
            return
        } catch {
            outcome = .retry
        }
        if Task.isCancelled { return }
        let next = Date().addingTimeInterval(XAIOAuthKeepAlivePolicy.retryInterval(after: outcome))
        nextXAIKeepAliveAt = next
        xaiKeepAliveScheduleStore.save(accountID: accountID, nextAt: next)
    }

    private static func selectedXAIAuthAccountID(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let snapshot = XaiAuthFile.parse(data) else { return nil }
        return XaiAuthFile.selectedAccount(snapshot)?.id
    }

    private func project(category: LeaderboardCategory, grouping: String?, language: AppLanguage, sources: [String: String]? = nil, countries: [String: String]? = nil, kinds: [LeaderboardKind]) -> State {
        let now = Date()
        let boards = kinds.map { kind -> Board in
            let formatter = ISO8601DateFormatter()
            let board = snapshot.boards[kind]
            let sourceFilter = LeaderboardOpennessFilter(rawValue: sources?[kind.rawValue] ?? "all") ?? .all
            let countryValue = countries?[kind.rawValue] ?? ""
            let countryFilter: LeaderboardCountryFilter = countryValue == "unknown" ? .unknown
                : OrganizationCountry(rawValue: countryValue).map(LeaderboardCountryFilter.country) ?? .all
            let models = (board?.entries ?? []).filter { sourceFilter.matches($0) && countryFilter.matches($0) }
            let standings = grouping == "company" ? CompanyLeaderboard.rank(models, summingUsage: kind.isUsage) : []
            let entries = grouping == "company" ? standings.map(\.entry) : models
            return Board(modelMetadataSource: board?.modelMetadataSource, kind: kind.rawValue, title: kind.sourcePrefix, url: kind.sourceURL.absoluteString,
                         updatedAt: board?.sourceUpdatedAt.map { formatter.string(from: $0) },
                         error: errors[kind].map { $0 == "configurationRequired" ? LeaderboardFailure.configurationRequired.message(language: language, hasCachedBoard: board != nil) : language.text("Refresh failed; showing saved data", "刷新失败，显示已保存的数据") },
                         entries: entries.map { entry in
                let links = PurchaseLinkCatalog.links(forOrganization: entry.organization, modelName: entry.name)
                return Entry(detailID: grouping == "company" ? nil : entry.modelMetadata?.id, voteCount: entry.voteCount,
                             rank: entry.rank, name: entry.name, score: entry.score, organization: entry.organization,
                             country: OrganizationRegion.country(for: entry)?.rawValue,
                             logo: OrganizationLogoCatalog.resolvedKey(organization: entry.organization, modelName: entry.name),
                             codingURL: PurchaseLinkCatalog.preferredLink(from: links.codingPlan, language: language)?.url.absoluteString,
                             apiURL: PurchaseLinkCatalog.preferredLink(from: links.payAsYouGo, language: language)?.url.absoluteString,
                             help: standings.first { $0.entry.rank == entry.rank }.map { CompanyLeaderboard.scoreHelp(for: $0, language: language, kind: kind) },
                             openness: entry.resolvedOpenness?.rawValue,
                             brandColor: OrganizationLogoCatalog.rowBrandColorHex(for: entry),
                             logoPNG: OrganizationLogoCatalog.rowLogoPNGData(for: entry, isCompany: grouping == "company")?.base64EncodedString(),
                             initials: OrganizationLogoCatalog.initial(organization: entry.organization, modelName: entry.name))
            }, fetchedAt: board.map { formatter.string(from: $0.fetchedAt) }, sourceNote: board?.sourceNote,
                         countryOptions: LeaderboardPresentation.countryFilters(board).compactMap { filter in
                switch filter {
                case .all: return nil
                case .country(let country): return CountryOption(value: country.rawValue, label: country.localizedName(language: language))
                case .unknown: return CountryOption(value: "unknown", label: language.text("Unknown", "未知"))
                }
            }, distribution: LeaderboardDistribution(entries: board?.entries ?? []))
        }
        // Mirror Mac: size against every cached category and grouping, even
        // when the currently selected board happens to have short titles.
        var layoutEntries: [LayoutEntry] = []
        for category in LeaderboardCategory.allCases {
            for kind in category.boardKinds {
                let models = snapshot.boards[kind]?.entries ?? []
                for grouping in LeaderboardGrouping.allCases {
                    let entries = grouping == .company ? CompanyLeaderboard.rank(models, summingUsage: kind.isUsage).map(\.entry) : models
                    for entry in entries {
                        let links = PurchaseLinkCatalog.links(forOrganization: entry.organization, modelName: entry.name)
                        layoutEntries.append(LayoutEntry(name: entry.name,
                            planTitle: grouping == .company && !links.codingPlan.isEmpty ? language.text("Plan", "套餐") : nil,
                            apiTitle: grouping == .company && !links.payAsYouGo.isEmpty ? language.text("Pay as you go", "按量") : nil))
                    }
                }
            }
        }
        let displayChips = chips.map { chip -> AccountQuotaChip in
            guard chip.kind == .qwen else { return chip }
            guard let website = qwenWebsite, let captured = qwenCapturedAt,
                  (0..<86400).contains(now.timeIntervalSince(captured)),
                  website.resetsAt.map({ $0 > now }) ?? true else {
                let fallback: AccountQuotaChip.Status?
                if let failure = qwenWebsiteFailure { fallback = failure }
                else if qwenWebsiteConnected,
                        case .note(let text, _) = chip.status, text == AccountQuotaMessage.connectOfficial {
                    fallback = .message(AccountQuotaMessage.queryFailed)
                } else { fallback = nil }
                guard let fallback else { return chip }
                return AccountQuotaChip(id: chip.id, shortName: chip.shortName, modelName: chip.modelName,
                    websiteURL: chip.websiteURL, kind: chip.kind, isCurrent: chip.isCurrent, status: fallback, isStale: chip.isStale)
            }
            let quota = QwenWebsiteQuota(periodLabel: website.periodLabel, remainingPercent: website.remainingPercent,
                                         resetsAt: website.resetsAt, expiresAt: website.expiresAt,
                                         isCached: now.timeIntervalSince(captured) > 60, capturedAt: captured)
            return AccountQuotaChip(id: chip.id, shortName: chip.shortName, modelName: chip.modelName,
                                    websiteURL: chip.websiteURL,
                                    kind: chip.kind, isCurrent: chip.isCurrent, status: .qwenWebsite(quota))
        }
        let quotas = AccountQuotaFormatting.sortedChips(displayChips).map { chip in
            // Login-required Grok cards launch device authorization, not the product page.
            let xaiSignIn = AccountQuotaFormatting.requiresXAISignIn(chip)
            let xaiSubscription = AccountQuotaFormatting.requiresXAISubscriptionConnection(chip)
            let glmAction = AccountQuotaFormatting.glmRecoveryAction(for: chip)
            return Quota(id: chip.id, name: chip.shortName, isCurrent: chip.isCurrent, isStale: chip.isStale,
                    // Help is one fixed phrase or one composed value per line,
                    // and `quotaText` exact-matches a whole line only. Translating
                    // the joined block would leave every fixed phrase in Chinese.
                    help: AccountQuotaFormatting.help(for: chip, now: now)
                        .components(separatedBy: "\n")
                        .map(language.quotaText)
                        .joined(separator: "\n"),
                    url: xaiSignIn || glmAction != nil ? nil : chip.websiteURL?.absoluteString,
                    canConnect: glmAction != nil || chip.kind == .officialNote || chip.kind == .qwen || xaiSignIn || xaiSubscription,
                    connection: glmAction.map { $0 == .configure ? "glmConfiguration" : "glmRetry" } ?? (chip.kind == .officialNote ? "openai" : (chip.kind == .qwen ? "qwen" : (xaiSignIn ? "xai" : (xaiSubscription ? "xaiSubscription" : nil)))),
                    runs: AccountQuotaFormatting.runs(for: chip, now: now).map { run in
                Run(text: language.quotaText(run.text), light: color(run.tone, dark: false), dark: color(run.tone, dark: true))
            }, accentLight: AccountQuotaFormatting.cardColorLevel(for: chip, now: now).map { color(.remaining($0), dark: false) },
                isDimmed: AccountQuotaFormatting.isDimmed(chip))
        }
        let previousRecovery = recovery
        let recovered = recovery.consider(chips: displayChips)
        if previousRecovery != recovery { try? recoveryStore?.save(recovery) }
        let alerts = displayChips.flatMap { QuotaAlerts.alerts(for: $0, now: now) } + recovered
        let activeKeys = Set(alerts.flatMap(\.componentKeys))
        delivered = QuotaAlerts.retainedKeys(delivered, evaluatedChips: displayChips, activeKeys: activeKeys)
        let pending = QuotaAlerts.pendingAlerts(alerts, delivered: delivered)
        for alert in pending where alert.reason != .recovered { delivered.formUnion(alert.componentKeys) }
        if !recovered.isEmpty {
            recovery.acknowledge(Set(recovered.flatMap(\.componentKeys)))
            try? recoveryStore?.save(recovery)
        }
        let liveModel = allowsAccountAccess ? CCSwitchProviderStore.currentCodexModelConfiguration() : nil
        let menuText = liveModel?.menuBarText(for: displayChips, targets: Array(targets.values))
            ?? AccountQuotaFormatting.menuBarText(forChips: displayChips)
        return State(boards: boards, quotas: quotas, quotaNeedsCCSwitch: needsCCSwitch, quotaUnavailable: unavailable,
                     trayText: menuText.map { "\($0.name) · \(language.quotaText($0.quota))" },
                     alerts: pending.map { Alert(title: "\($0.title) · \(language.quotaText($0.subtitle))", body: language.quotaText($0.body)) },
                     layoutEntries: layoutEntries, quotaUpdatedAt: quotaUpdatedAt.map { ISO8601DateFormatter().string(from: $0) })
    }
    private func color(_ tone: QuotaTone, dark: Bool) -> String {
        let rgb: QuotaRGB
        switch tone {
        case .remaining(let value): rgb = QuotaColorScale.color(remainingPercent: value, dark: dark)
        case .deadline(let level): rgb = QuotaColorScale.color(remainingPercent: level, dark: dark)
        case .balance(let amount, let currency):
            guard let level = QuotaColorScale.balanceLevel(amount: amount, currency: currency) else { return dark ? "#AAAAAA" : "#666666" }
            rgb = QuotaColorScale.color(remainingPercent: level, dark: dark)
        case .green: rgb = QuotaColorScale.color(remainingPercent: 100, dark: dark)
        case .red: rgb = QuotaColorScale.color(remainingPercent: 0, dark: dark)
        case .orange: rgb = QuotaColorScale.color(remainingPercent: 25, dark: dark)
        case .secondary: return dark ? "#AAAAAA" : "#666666"
        }
        return String(format: "#%02X%02X%02X", Int(rgb.red * 255), Int(rgb.green * 255), Int(rgb.blue * 255))
    }
}

@main struct Bridge {
    static func main() async {
        do {
            let arguments = CommandLine.arguments
            let cacheFile = arguments.count == 3 && arguments[1] == "--cache-file" ? URL(fileURLWithPath: arguments[2]) : nil
            let engine = try Engine(cacheFile: cacheFile)
            let writer = Writer()
            await withTaskGroup(of: Void.self) { group in
            while let line = readLine(strippingNewline: true) {
                guard line.utf8.count <= 65_536, let data = line.data(using: .utf8),
                      let request = try? JSONDecoder().decode(Request.self, from: data) else { continue }
                group.addTask { await writer.write(await engine.handle(request)) }
            }
            }
        } catch { /* Startup errors never expose local account paths. */ }
    }
}
actor Writer {
    func write(_ response: Response) {
        guard var data = try? JSONEncoder().encode(response) else { return }
        data.append(10)
        try? FileHandle.standardOutput.write(contentsOf: data)
    }
}
