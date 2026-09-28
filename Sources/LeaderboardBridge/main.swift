import Foundation
import LeaderboardCore

// One persistent child process, JSON-lines over inherited pipes. Credentials
// remain inside LeaderboardCore; the desktop receives only display projections.
struct Request: Decodable, Sendable {
    var id: Int
    var command: String
    var category: String?
    var grouping: String?
    var language: String?
    var providerID: String?
    var loginID: String?
    var authorizationURL: String?
    var pageText: String?
}
struct Response: Encodable {
    var id: Int
    var result: State?
    var authorizationURL: String?
    var loginID: String?
    var error: String?
}
struct State: Encodable {
    var boards: [Board]
    var quotas: [Quota]
    var quotaNeedsCCSwitch: Bool
    var quotaUnavailable: Bool
    var trayText: String?
    var alerts: [Alert]
}
struct Board: Encodable {
    var kind: String; var title: String; var url: String
    var updatedAt: String?; var error: String?; var entries: [Entry]
}
struct Entry: Encodable {
    var rank: Int; var name: String; var score: Double
    var organization: String?; var country: String?; var logo: String?
    var codingURL: String?; var apiURL: String?; var help: String?
}
struct Quota: Encodable {
    var id: String; var name: String; var isCurrent: Bool; var isStale: Bool
    var help: String; var url: String?; var canConnect: Bool; var connection: String?; var runs: [Run]
}
struct Run: Encodable { var text: String; var light: String; var dark: String }
struct Alert: Encodable { var title: String; var body: String }

actor Engine {
    private var snapshot = LeaderboardSnapshot()
    private var errors: [LeaderboardKind: String] = [:]
    private var chips: [AccountQuotaChip] = []
    private var targets: [String: CCSwitchQuotaTarget] = [:]
    private var needsCCSwitch = false
    private var unavailable = false
    private var delivered = Set<String>()
    private let fetcher = LeaderboardFetcher()
    private let cache: LeaderboardCache
    private let official = OpenAIManagedQuotaSource()
    private var client: AccountQuotaClient?
    private var lastBoardRefresh: [LeaderboardCategory: Date] = [:]
    private var lastQuotaRefresh: Date?
    private var lastInactiveRefresh: Date?
    private var activeBoardRefreshes = Set<LeaderboardCategory>()
    private var refreshingQuotas = false
    private var qwenWebsite: QwenWebsiteQuota?
    private var qwenCapturedAt: Date?
    private let qwenCacheFile = PlatformPaths.applicationSupport.appending(path: "qwen-website-quota.json")

    init(cacheFile: URL? = nil) throws {
        cache = LeaderboardCache(fileURL: try cacheFile ?? LeaderboardCache.defaultFileURL())
        snapshot = cache.load() ?? LeaderboardSnapshot()
        if let saved = try? Data(contentsOf: qwenCacheFile), let quota = QwenWebsiteQuotaParser.parse(saved),
           let captured = quota.capturedAt, Date().timeIntervalSince(captured) < 86400 {
            qwenWebsite = quota; qwenCapturedAt = captured
        }
    }
    func handle(_ request: Request) async -> Response {
        let category = LeaderboardCategory(rawValue: request.category ?? "general") ?? .general
        let language = AppLanguage(rawValue: request.language ?? "en") ?? .english
        do {
            switch request.command {
            case "state": break
            case "captureQwen":
                guard let text = request.pageText, text.utf8.count <= 50000,
                      let quota = QwenWebsiteQuotaParser.parse(Data(text.utf8)) else {
                    return Response(id: request.id, error: "No quota found")
                }
                qwenWebsite = quota; qwenCapturedAt = Date()
                if let stored = QwenWebsiteQuotaParser.persistedData(for: quota) {
                    try FileManager.default.createDirectory(at: qwenCacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try stored.write(to: qwenCacheFile, options: .atomic)
                    #if !os(Windows)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: qwenCacheFile.path)
                    #endif
                }
            case "refreshBoards": await refreshBoards(category)
            case "refreshQuotas", "refreshCurrentQuota":
                try await refreshQuotas(onlyCurrent: request.command == "refreshCurrentQuota")
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
            return Response(id: request.id, result: project(category: category, grouping: request.grouping, language: language))
        } catch {
            // Never serialize upstream messages, tokens, paths or account IDs.
            return Response(id: request.id, error: language.text("Could not complete this request. Check the connection and try again.", "请求未完成，请检查连接后重试。"))
        }
    }
    private func refreshBoards(_ category: LeaderboardCategory) async {
        if activeBoardRefreshes.contains(category) { return }
        if let previous = lastBoardRefresh[category], Date().timeIntervalSince(previous) < 1800 { return }
        activeBoardRefreshes.insert(category)
        defer { activeBoardRefreshes.remove(category) }
        lastBoardRefresh[category] = Date()
        let fetcher = self.fetcher
        let results = await withTaskGroup(of: (LeaderboardKind, Leaderboard?).self) { group in
            for kind in category.boardKinds { group.addTask { (kind, try? await fetcher.fetch(kind)) } }
            var results: [(LeaderboardKind, Leaderboard?)] = []
            for await result in group { results.append(result) }
            return results
        }
        for (kind, board) in results {
            if let board { snapshot.boards[kind] = board; errors.removeValue(forKey: kind) }
            else { errors[kind] = "Refresh failed" }
        }
        cache.save(snapshot)
    }
    private func refreshQuotas(onlyCurrent: Bool) async throws {
        guard !refreshingQuotas else { return }
        let now = Date()
        if let previous = lastQuotaRefresh, now.timeIntervalSince(previous) < (onlyCurrent ? 1800 : 10) { return }
        refreshingQuotas = true
        defer { refreshingQuotas = false }
        lastQuotaRefresh = now
        let install = CCSwitchProviderStore.resolveInstall()
        switch CCSwitchProviderStore.loadCodexProviders(databaseURL: install.databaseURL) {
        case .absent:
            chips = []; targets = [:]; unavailable = false
            needsCCSwitch = !FileManager.default.fileExists(atPath: install.databaseURL.path)
        case .unavailable: unavailable = true
        case .records(let records):
            unavailable = false; needsCCSwitch = false
            let list = CCSwitchQuotaCatalog.targets(from: records, currentProviderID: CCSwitchProviderStore.currentCodexProviderID(settingsURL: install.settingsURL))
            targets = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
            let prior = Dictionary(uniqueKeysWithValues: chips.map { ($0.id, $0) })
            chips = list.map { target in
                AccountQuotaChip(id: target.id, shortName: target.shortName, websiteURL: target.websiteURL,
                                 kind: target.kind, isCurrent: target.isCurrent,
                                 status: prior[target.id]?.status ?? .pending, isStale: prior[target.id]?.isStale ?? false)
            }
            if client == nil { client = AccountQuotaClient(officialQuotaSource: official) }
            let includeInactive = !onlyCurrent && (lastInactiveRefresh.map { now.timeIntervalSince($0) >= 60 } ?? true)
            let refreshing = list.filter { $0.isCurrent || includeInactive }
            if includeInactive { lastInactiveRefresh = now }
            guard let client, !refreshing.isEmpty else { return }
            let refreshed = try await client.refresh(targets: refreshing, previous: chips, authFileURL: install.xaiAuthURL)
            let result = Dictionary(uniqueKeysWithValues: refreshed.map { ($0.id, $0) })
            chips = chips.map { result[$0.id] ?? $0 }
        }
    }
    private func project(category: LeaderboardCategory, grouping: String?, language: AppLanguage) -> State {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        let boards = category.boardKinds.map { kind -> Board in
            let board = snapshot.boards[kind]
            let standings = grouping == "company" ? CompanyLeaderboard.rank(board?.entries ?? []) : []
            let entries = grouping == "company" ? standings.map(\.entry) : (board?.entries ?? [])
            return Board(kind: kind.rawValue, title: kind.sourcePrefix, url: kind.sourceURL.absoluteString,
                         updatedAt: board.map { formatter.string(from: $0.sourceUpdatedAt ?? $0.fetchedAt) },
                         error: errors[kind].map { _ in language.text("Refresh failed; showing saved data", "刷新失败，显示已保存的数据") },
                         entries: entries.map { entry in
                let links = PurchaseLinkCatalog.links(forOrganization: entry.organization, modelName: entry.name)
                return Entry(rank: entry.rank, name: entry.name, score: entry.score, organization: entry.organization,
                             country: OrganizationRegion.country(entry.organization, modelName: entry.name)?.rawValue,
                             logo: OrganizationLogoCatalog.resolvedKey(organization: entry.organization, modelName: entry.name),
                             codingURL: PurchaseLinkCatalog.preferredLink(from: links.codingPlan, language: language)?.url.absoluteString,
                             apiURL: PurchaseLinkCatalog.preferredLink(from: links.payAsYouGo, language: language)?.url.absoluteString,
                             help: standings.first { $0.entry.rank == entry.rank }.map { CompanyLeaderboard.scoreHelp(for: $0, language: language) })
            })
        }
        let displayChips = chips.map { chip -> AccountQuotaChip in
            guard chip.kind == .qwen, let website = qwenWebsite, let captured = qwenCapturedAt,
                  now.timeIntervalSince(captured) < 86400 else { return chip }
            let quota = QwenWebsiteQuota(periodLabel: website.periodLabel, remainingPercent: website.remainingPercent,
                                         resetsAt: website.resetsAt, expiresAt: website.expiresAt,
                                         isCached: now.timeIntervalSince(captured) > 60, capturedAt: captured)
            return AccountQuotaChip(id: chip.id, shortName: chip.shortName, websiteURL: chip.websiteURL,
                                    kind: chip.kind, isCurrent: chip.isCurrent, status: .qwenWebsite(quota))
        }
        let quotas = AccountQuotaFormatting.sortedChips(displayChips).map { chip in
            Quota(id: chip.id, name: chip.shortName, isCurrent: chip.isCurrent, isStale: chip.isStale,
                  help: language.quotaText(AccountQuotaFormatting.help(for: chip, now: now)),
                  url: chip.websiteURL?.absoluteString, canConnect: chip.kind == .officialNote || chip.kind == .qwen,
                  connection: chip.kind == .officialNote ? "openai" : (chip.kind == .qwen ? "qwen" : nil),
                  runs: AccountQuotaFormatting.runs(for: chip, now: now).map { run in
                Run(text: language.quotaText(run.text), light: color(run.tone, dark: false), dark: color(run.tone, dark: true))
            })
        }
        let alerts = displayChips.flatMap { QuotaAlerts.alerts(for: $0, now: now) }
        let activeKeys = Set(alerts.flatMap(\.componentKeys))
        delivered = QuotaAlerts.retainedKeys(delivered, evaluatedChips: displayChips, activeKeys: activeKeys)
        let pending = QuotaAlerts.pendingAlerts(alerts, delivered: delivered)
        for alert in pending { delivered.formUnion(alert.componentKeys) }
        return State(boards: boards, quotas: quotas, quotaNeedsCCSwitch: needsCCSwitch, quotaUnavailable: unavailable,
                     trayText: AccountQuotaFormatting.menuBarText(forChips: displayChips).map { "\($0.name) · \(language.quotaText($0.quota))" },
                     alerts: pending.map { Alert(title: language.quotaText($0.subtitle), body: language.quotaText($0.body)) })
    }
    private func color(_ tone: QuotaTone, dark: Bool) -> String {
        let rgb: QuotaRGB
        switch tone {
        case .remaining(let value): rgb = QuotaColorScale.color(remainingPercent: value, dark: dark)
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
