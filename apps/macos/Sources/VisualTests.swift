#if DEBUG
import AppKit
import Foundation
import CryptoKit
import LeaderboardCore
import SwiftUI

@MainActor
private final class SearchVisualWindow: NSWindow { override var canBecomeKey: Bool { true } }

@MainActor
enum NativeVisualCapture {
    enum CaptureError: Error { case blankFrame(String) }
    struct Entry: Decodable { let rank: Int; let name: String; let score: Double; let modelID: String?; let organization: String; let logo: String; let openness: ModelOpenness?; let brand: OrganizationBrand?; let organizationBrand: OrganizationBrand?; let developerCountry: OrganizationCountryMetadata?; let modelMetadata: ModelMetadata?; let totalTokens: String?; let rankChange: LeaderboardRankChange?; let companyRankChange: LeaderboardRankChange? }
    struct Board: Decodable { let kind: String; let title: String; let entries: [Entry]; let sourceUpdatedAt: String?; let sourceTimeUnavailable: Bool?; let fetchedAt: String?; let contentUpdatedAt: String?; let sourceNote: String? }
    struct Quota: Decodable {
        struct Run: Decodable { let text: String }
        struct Balance: Decodable { let currency: String; let amount: Double }
        struct Window: Decodable { let name: String; let utilization: Double; let resetsAt: String?; let dateSource: ParsedQuotaDateSource?; let subscriptionState: ParsedSubscriptionState? }
        let id: String; let name: String; let isCurrent: Bool; let runs: [Run]; let status: String?; let modelName: String?; let failureReason: String?; let baseURL: String?
        let windows: [Window]?
        let balances: [Balance]?
        let credits: OpenAICredits?
    }
    struct State: Decodable { let boards: [Board]; let quotas: [Quota]; let quotaUpdatedAt: String? }
    struct Case: Decodable { let id: String; let language: String; let width: Int; let height: Int; let scenario: String; let quotaAgeSeconds: Int?; let versionText: String?; let codexModel: String?; let codexProvider: String?; let codexBaseURL: String?; let taskCounts: CodexTaskCounts?; let refreshedTaskCounts: CodexTaskCounts?; let codexDesktopRunning: Bool?; let refreshedCodexDesktopRunning: Bool?; let showsCodexTaskStatus: Bool?; let refreshedShowsCodexTaskStatus: Bool?; let officialAccountChecking: Bool?; let sources: [String: LeaderboardOpennessFilter]?; let countries: [String: String]?; let grouping: LeaderboardGrouping?; let category: LeaderboardCategory?; let comparisonKind: LeaderboardKind?; let selectedBoards: [LeaderboardKind]?; let refreshedSelectedBoards: [LeaderboardKind]?; let rowCount: Int?; let searchQuery: String?; let contentUpdatedAt: String? }
    struct Fixture: Decodable { let state: State; let cases: [Case]; let quotaScenarios: [String: [Quota]]? }

    static func run() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let captureRoot = ProcessInfo.processInfo.environment["BENCHGAUGE_VISUAL_ROOT"]
            .map { URL(fileURLWithPath: $0) } ?? root.appending(path: "work/visual-parity")
        let output = captureRoot.appending(path: "macos")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixtureURL = ProcessInfo.processInfo.environment["BENCHGAUGE_VISUAL_FIXTURE"]
            .map { URL(fileURLWithPath: $0) } ?? root.appending(path: "Tests/fixtures/visual-state.json")
        let fixtureBytes = try Data(contentsOf: fixtureURL)
        let normalizedFixture = Data(String(decoding: fixtureBytes, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n").utf8)
        let fixtureHash = SHA256.hash(data: normalizedFixture).map { String(format: "%02x", $0) }.joined()
        let fixture = try JSONDecoder().decode(Fixture.self, from: fixtureBytes)
        let fixedDate = ISO8601DateFormatter().date(from: "2026-09-29T00:00:00Z")!
        let boards = Dictionary(uniqueKeysWithValues: fixture.state.boards.map { board in
            let kind = LeaderboardKind(rawValue: board.kind)!
            let entries = board.entries.map { entry in
                LeaderboardEntry(rank: entry.rank, name: entry.name, score: entry.score, modelID: entry.modelID, organization: entry.organization,
                    openness: entry.openness, brand: entry.brand, organizationBrand: entry.organizationBrand, developerCountry: entry.developerCountry, modelMetadata: entry.modelMetadata, totalTokens: entry.totalTokens, rankChange: entry.rankChange, companyRankChange: entry.companyRankChange)
            }
            return (kind, Leaderboard(kind: kind, title: board.title, sourceUpdatedAt: board.sourceTimeUnavailable == true ? nil : board.sourceUpdatedAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? fixedDate, sourceNote: board.sourceNote, fetchedAt: board.fetchedAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? fixedDate, contentUpdatedAt: board.contentUpdatedAt.flatMap { ISO8601DateFormatter().date(from: $0) }, entries: entries))
        })
        let kinds: [String: CCSwitchQuotaKind] = ["OpenAI": .officialNote, "Kimi": .kimi, "Qwen": .qwen, "DeepSeek": .deepseek, "GLM": .zhipu, "xAI": .xaiOAuth]
        // Exercise the same ownership deferral as production, with no real login
        // or network access. This fixture also runs against the pre-fix source.
        var deferredStatus: AccountQuotaChip.Status = .pending
        if (fixture.state.quotas + (fixture.quotaScenarios?.values.flatMap { $0 } ?? []))
            .contains(where: { $0.status == "refreshDeferred" }) {
            let authURL = output.appending(path: "synthetic-auth.json")
            defer { try? FileManager.default.removeItem(at: authURL) }
            try Data(#"{"default_account_id":"fixture","accounts":{"fixture":{"account_id":"fixture","refresh_token":"visual-fixture","requires_reauth":false}}}"#.utf8).write(to: authURL)
            let client = AccountQuotaClient(authFileURL: authURL, xaiRefreshAllowed: { false })
            let target = CCSwitchQuotaTarget(id: "fixture", shortName: "xAI", websiteURL: nil,
                kind: .xaiOAuth, isCurrent: false, apiKey: nil, baseURL: nil)
            deferredStatus = try await client.refresh(targets: [target], previous: []).first!.status
        }
        func chip(_ quota: Quota) -> AccountQuotaChip {
            let status: AccountQuotaChip.Status
            switch quota.status {
            case "network": status = .message(AccountQuotaMessage.network)
            case "reauth": status = .message(AccountQuotaMessage.reauthRequired)
            case "refreshDeferred": status = deferredStatus
            case "pending": status = .pending
            case "unconnected": status = .note(text: AccountQuotaMessage.connectOfficial, help: AccountQuotaMessage.connectOfficialHelp)
            case "qwenWebsite": status = .qwenWebsite(QwenWebsiteQuota(periodLabel: "1mo", remainingPercent: 42, resetsAt: nil))
            case "notSubscribed": status = .note(text: AccountQuotaMessage.kimiNoCodingPlan, help: AccountQuotaMessage.kimiNoCodingPlanHelp)
            case "queryFailed":
                status = quota.name == "Qwen" && quota.failureReason == "noPlan"
                    ? .note(text: AccountQuotaMessage.qwenNoPlan, help: AccountQuotaMessage.qwenNoPlanHelp)
                    : quota.name == "GLM" && quota.failureReason == "noCodingPlan"
                    ? .note(text: AccountQuotaMessage.glmNoCodingPlan, help: AccountQuotaMessage.glmNoCodingPlanHelp)
                    : .message(AccountQuotaMessage.queryFailed)
            case "notConfigured": status = .note(text: AccountQuotaMessage.notConfigured, help: AccountQuotaMessage.notConfiguredHelp)
            default:
                if let balances = quota.balances {
                    status = .balances(balances.map { ParsedBalance(currency: $0.currency, amount: $0.amount) })
                } else if let windows = quota.windows {
                    status = .windows(windows.map { ParsedQuotaWindow(name: $0.name, utilization: $0.utilization,
                        resetsAt: $0.resetsAt.flatMap { ISO8601DateFormatter().date(from: $0) }, dateSource: $0.dateSource,
                        subscriptionState: $0.subscriptionState) })
                } else {
                    let percent = Double(quota.runs.last!.text.replacingOccurrences(of: "%", with: ""))!
                    status = .windows([ParsedQuotaWindow(name: "seven_day", utilization: 100 - percent, resetsAt: nil)])
                }
            }
            return AccountQuotaChip(id: quota.id, shortName: quota.name, modelName: quota.modelName, websiteURL: nil,
                kind: kinds[quota.name] ?? .kimi, isCurrent: quota.isCurrent, status: status, credits: quota.credits)
        }
        let chips = fixture.state.quotas.map(chip)
        var metadata: [[String: String]] = []
        for test in fixture.cases {
            for theme in ["light", "dark"] {
                NSApplication.shared.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
                let defaultsName = "ai-benchgauge.visual.\(UUID().uuidString)"
                let defaults = UserDefaults(suiteName: defaultsName)!
                let state = AppState(cache: LeaderboardCache(fileURL: output.appending(path: "nonexistent-cache.json")), defaults: defaults)
                let visibleChips = (fixture.quotaScenarios?[test.scenario]).map { $0.map(chip) }
                    ?? (test.scenario == "manyQuotas" ? chips : (["empty", "installedEmpty", "error"].contains(test.scenario) ? [] : Array(chips.prefix(2))))
                let errors: [LeaderboardKind: String] = test.scenario == "error" ? [.artificialAnalysis: "Refresh failed / 刷新失败（测试）", .arenaText: "Refresh failed / 刷新失败（测试）"] : [:]
                let quotaDate: Date?
                if let age = test.quotaAgeSeconds {
                    quotaDate = age < 0 ? nil : Date().addingTimeInterval(-Double(age))
                } else {
                    quotaDate = fixture.state.quotaUpdatedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
                }
                var fetchedBoards = boards.mapValues { board in
                    var entries = test.rowCount.map { count in
                        (1...count).map { rank in
                            if test.scenario == "scrollPerformance", !board.entries.isEmpty {
                                let original = board.entries[(rank - 1) % board.entries.count]
                                return LeaderboardEntry(rank: rank, name: original.name + " \(rank)",
                                    score: Double(count - rank + 1), organization: original.organization,
                                    logoURL: original.logoURL, brand: original.brand)
                            }
                            return LeaderboardEntry(rank: rank, name: "Fixture model \(rank)", score: Double(count - rank + 1),
                                organization: "Fixture maker \(rank)")
                        }
                    } ?? board.entries
                    if test.scenario == "rankChanges" {
                        entries = entries.enumerated().map { index, entry in
                            let offset = board.kind == .epochECI ? 1 : board.kind == .arenaText ? 2 : 0
                            let change: LeaderboardRankChange? = switch (index + offset) % 4 {
                            case 0: .init(delta: 12)
                            case 1: .init(delta: -3)
                            case 2: .init(isNew: true)
                            default: nil
                            }
                            return LeaderboardEntry(rank: entry.rank, name: entry.name, score: entry.score,
                                modelID: entry.modelID, organization: entry.organization, logoURL: entry.logoURL,
                                openness: entry.openness, brand: entry.brand, organizationBrand: entry.organizationBrand,
                                developerCountry: entry.developerCountry, modelMetadata: entry.modelMetadata,
                                totalTokens: entry.totalTokens, rankChange: change, companyRankChange: change)
                        }
                    }
                    let singleTime = test.scenario == "sourceTimes"
                    let sourceDate = singleTime && board.kind == .artificialAnalysis ? nil : board.sourceUpdatedAt
                    let fetchDate = singleTime ? fixedDate.addingTimeInterval(23 * 86400)
                        : (test.scenario == "boardSelectionConfirm" || test.scenario.hasPrefix("desktopSearch") || test.scenario == "distributionCharts") ? Date() : quotaDate ?? fixedDate
                    return Leaderboard(kind: board.kind, title: board.title, sourceUpdatedAt: sourceDate, sourceNote: board.sourceNote,
                                fetchedAt: fetchDate, contentUpdatedAt: test.contentUpdatedAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? board.contentUpdatedAt, entries: entries)
                }
                if test.scenario == "usagePending" { fetchedBoards[.openRouterUsage] = nil }
                let stale = test.scenario == "freshnessStale"
                let shownChips = stale ? visibleChips.map { chip in
                    AccountQuotaChip(id: chip.id, shortName: chip.shortName, websiteURL: chip.websiteURL,
                                     kind: chip.kind, isCurrent: chip.isCurrent, status: chip.status, isStale: true, credits: chip.credits)
                } : visibleChips
                func apply(refreshed: Bool = false, phase: Int = 0) {
                    let loadingScenario = test.scenario.hasPrefix("usageLoading")
                    var displayedBoards = fetchedBoards
                    var displayedErrors = errors
                    if loadingScenario, test.scenario != "usageLoadingCached", !(phase == 2 && test.scenario == "usageLoadingSuccess") {
                        for kind in LeaderboardCategory.usage.boardKinds { displayedBoards[kind] = nil }
                    }
                    if test.scenario == "usageLoadingFailure", phase == 2 {
                        for kind in LeaderboardCategory.usage.boardKinds { displayedErrors[kind] = "Refresh failed / 加载失败（测试）" }
                    }
                    state.setShowsCodexTaskStatus(refreshed
                        ? (test.refreshedShowsCodexTaskStatus ?? test.showsCodexTaskStatus ?? false)
                        : (test.showsCodexTaskStatus ?? false))
                    state.applyVisualFixture(snapshot: LeaderboardSnapshot(boards: displayedBoards), chips: shownChips,
                        language: AppLanguage(rawValue: test.language)!, errors: displayedErrors,
                        emptyState: test.scenario == "empty" ? .notInstalled : (test.scenario == "installedEmpty" ? .installedEmpty : nil),
                        panelMode: test.scenario == "window" ? .window : .clickToClose, quotaUpdatedAt: quotaDate, quotaUnavailable: stale,
                        modelConfiguration: test.codexModel.map { CodexModelConfiguration(model: $0, provider: test.codexProvider, baseURL: test.codexBaseURL) },
                        targets: visibleChips.map { value in
                            CCSwitchQuotaTarget(id: value.id, shortName: value.shortName, modelName: value.modelName,
                                websiteURL: nil, kind: value.kind, isCurrent: value.isCurrent, apiKey: nil,
                                baseURL: (fixture.quotaScenarios?[test.scenario] ?? fixture.state.quotas).first { $0.id == value.id }?.baseURL)
                        }, taskCounts: refreshed ? (test.refreshedTaskCounts ?? test.taskCounts) : test.taskCounts,
                        codexDesktopRunning: refreshed ? (test.refreshedCodexDesktopRunning ?? test.codexDesktopRunning ?? true) : (test.codexDesktopRunning ?? true),
                        category: test.category ?? .general, boardKinds: refreshed ? (test.refreshedSelectedBoards ?? test.selectedBoards ?? (test.category ?? .general).boardKinds) : (test.selectedBoards ?? test.comparisonKind.map { [.artificialAnalysis, $0] } ?? (test.category ?? .general).boardKinds),
                        boardRefreshing: loadingScenario && phase < 2)
                    for (raw, filter) in test.sources ?? [:] {
                        if let kind = LeaderboardKind(rawValue: raw) { state.selectOpennessFilter(filter, for: kind) }
                    }
                    for (raw, value) in test.countries ?? [:] {
                        if let kind = LeaderboardKind(rawValue: raw), let country = OrganizationCountry(rawValue: value) {
                            state.selectCountryFilter(.country(country), for: kind)
                        }
                    }
                    if let grouping = test.grouping { state.selectGrouping(grouping) }
                }
                apply()
                if test.scenario == "popoverBoardResize" {
                    let controller = StatusBarController(state: state)
                    defer {
                        controller.finishVisualStatusCapture()
                        defaults.removePersistentDomain(forName: defaultsName)
                    }
                    var geometry: [[String: Any]] = []
                    for frame in 0..<4 {
                        if test.scenario.hasPrefix("usageLoading") { apply(refreshed: frame > 0, phase: frame) }
                    else if frame == 1 { apply(refreshed: true) }
                        if frame == 2 {
                            _ = controller.visualPopoverWindow(show: false)
                            try await Task.sleep(for: .milliseconds(100))
                        }
                        _ = controller.visualPopoverWindow(show: true)
                        try await Task.sleep(for: .milliseconds(frame == 3 ? 800 : 300))
                        guard let window = controller.visualPopoverWindow(show: true),
                              let chrome = window.contentView?.superview,
                              let anchor = controller.visualPopoverAnchor,
                              let png = PanelScreenshot.captureForm(view: chrome, minimumVariety: 1) else {
                            throw CaptureError.blankFrame("popover resize chrome missing")
                        }
                        try png.write(to: output.appending(path: "\(test.id)-\(theme)-frame-\(frame).png"))
                        geometry.append(["frame": frame, "window": NSStringFromRect(window.frame),
                            "anchor": NSStringFromRect(anchor), "chromeBounds": NSStringFromRect(chrome.bounds),
                            "anchorX": anchor.midX - window.frame.minX,
                            "boardCount": state.visibleBoardKinds.count])
                    }
                    let resizedAnchor = geometry[1]["anchorX"] as! CGFloat
                    let reopenedAnchor = geometry[2]["anchorX"] as! CGFloat
                    let settledAnchor = geometry[3]["anchorX"] as! CGFloat
                    guard abs(resizedAnchor - reopenedAnchor) <= 1,
                          abs(reopenedAnchor - settledAnchor) <= 1 else {
                        throw CaptureError.blankFrame("resized popover anchor differs from reopened/settled anchor")
                    }
                    try JSONSerialization.data(withJSONObject: geometry, options: [.prettyPrinted, .sortedKeys])
                        .write(to: output.appending(path: "\(test.id)-\(theme)-geometry.json"))
                    metadata.append(["id": test.id, "theme": theme, "width": "native-popover", "height": "native-popover",
                        "fixtureHash": fixtureHash, "timezone": TimeZone.current.identifier,
                        "sourceCommit": ProcessInfo.processInfo.environment["GITHUB_SHA"] ?? "local-uncommitted",
                        "backingScale": String(describing: NSScreen.main?.backingScaleFactor ?? 1),
                        "capture": "native-popover-chrome", "os": ProcessInfo.processInfo.operatingSystemVersionString])
                    continue
                }
                if test.scenario.hasPrefix("menuBar") {
                    let controller = StatusBarController(state: state)
                    defer {
                        controller.finishVisualStatusCapture()
                        defaults.removePersistentDomain(forName: defaultsName)
                    }
                    guard let button = controller.visualStatusButton(width: CGFloat(test.width)) else {
                        throw CaptureError.blankFrame(test.id)
                    }
                    button.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
                    button.highlight(test.scenario == "menuBarIconHighlighted")
                    var statusLabels = [String]()
                    var statusHelp = [String]()
                    var taskHighlights = [String]()
                    var statusAppearances = [String]()
                    for frame in 0..<3 {
                        if frame == 1, test.scenario != "menuBarIconAppearance" { apply(refreshed: true) }
                        if frame == 1, test.scenario == "menuBarIconAppearance" {
                            // Keep the existing attachment when the menu bar changes
                            // appearance; do not rely on an account/task refresh.
                            button.appearance = NSAppearance(named: theme == "dark" ? .aqua : .darkAqua)
                        }
                        try await Task.sleep(for: .milliseconds(300))
                        if test.scenario != "menuBarIconAppearance" {
                            _ = controller.visualStatusButton(width: CGFloat(test.width))
                        }
                        statusAppearances.append(button.effectiveAppearance.name.rawValue)
                        let label = button.attributedTitle.string
                        let help = button.toolTip ?? ""
                        guard label.contains("▶") == state.isCodexTaskStatusVisible,
                              state.isCodexTaskStatusVisible || !help.contains("Codex") else {
                            throw CaptureError.blankFrame("\(test.id): incorrect task-block visibility")
                        }
                        statusLabels.append(label)
                        statusHelp.append(help)
                        if ["menuBarTaskColors", "menuBarTaskToggle"].contains(test.scenario) {
                            taskHighlights.append(try taskHighlightMetadata(button: button, state: state))
                        }
                        var captured: Data?
                        // Resolve dynamic background colors inside the same
                        // appearance context as the native status-button text.
                        button.effectiveAppearance.performAsCurrentDrawingAppearance {
                            captured = PanelScreenshot.captureForm(view: button, minimumVariety: 1)
                        }
                        guard let png = captured else {
                            throw CaptureError.blankFrame(test.id)
                        }
                        try png.write(to: output.appending(path: "\(test.id)-\(theme)-frame-\(frame).png"))
                    }
                    metadata.append(["id": test.id, "theme": theme, "width": String(test.width),
                        "height": String(describing: button.bounds.height), "fixtureHash": fixtureHash,
                        "timezone": TimeZone.current.identifier,
                        "sourceCommit": ProcessInfo.processInfo.environment["GITHUB_SHA"] ?? "local-uncommitted",
                        "backingScale": String(describing: button.window?.backingScaleFactor ?? 1),
                        "shownStatusLabel": statusLabels[0], "refreshedStatusLabel": statusLabels[1], "settledStatusLabel": statusLabels[2],
                        "shownStatusHelp": statusHelp[0], "refreshedStatusHelp": statusHelp[1], "settledStatusHelp": statusHelp[2],
                        "statusAppearances": statusAppearances.joined(separator: "\n"),
                        "taskHighlights": taskHighlights.joined(separator: "\n"),
                        "capture": "native-status-button", "os": ProcessInfo.processInfo.operatingSystemVersionString])
                    continue
                }
                let size = NSSize(width: test.width, height: test.height)
                let isClaudeConsentAlert = test.scenario == "claudeKeychainConsentAlert"
                let isQuotaHelpAlert = test.scenario == "quotaTrackingHelp"
                let isSourceDetailsAlert = test.scenario == "sourceDetails"
                func captureSourceDetails(_ view: NSView) -> Data? {
                    var png: Data?
                    view.effectiveAppearance.performAsCurrentDrawingAppearance {
                        png = PanelScreenshot.captureForm(view: view, minimumVariety: 1)
                    }
                    return png
                }
                let detailEntry = boards[.artificialAnalysis]!.entries[0]
                let selectedDetail = test.scenario == "modelDetailsMissing"
                    ? LeaderboardEntry(rank: 0, name: "Unmatched model / 暂无模型资料", score: 0)
                    : test.scenario == "modelDetailsLong"
                    ? LeaderboardEntry(rank: 0, name: "Research Model — Extended Reasoning / Very Long Provider Variant 长名称测试模型（高推理预算版本）", score: 0, modelMetadata: detailEntry.modelMetadata)
                    : detailEntry
                let view = test.scenario == "thirdPartyNotices"
                    ? AnyView(LicenseNoticesView(section: .thirdParty, language: AppLanguage(rawValue: test.language)!))
                    : test.scenario == "applicationLicense"
                    ? AnyView(LicenseNoticesView(section: .application, language: AppLanguage(rawValue: test.language)!))
                    : test.scenario.hasPrefix("modelDetails")
                    ? AnyView(ModelDetailsView(entry: selectedDetail, language: AppLanguage(rawValue: test.language)!, copyName: { _ in true }, close: {}))
                    : test.scenario == "addModelDialog"
                    ? AnyView(OfficialQuotaAccountsView(state: state, onClose: {}, usesVisualFixture: true,
                        visualVerificationPending: test.officialAccountChecking ?? false))
                    : AnyView(LeaderboardView(state: state, maximumWidth: CGFloat(test.width), viewportSize: size))
                let host: NSView = test.scenario.hasPrefix("xaiDeviceDialog")
                    ? XAIAccountConnection().makeContent(language: AppLanguage(rawValue: test.language)!, fixtureState: test.scenario.replacingOccurrences(of: "xaiDeviceDialog-", with: ""))
                    : test.scenario.hasPrefix("xaiSubscriptionDialog")
                    ? XAIWebsiteSubscriptionSource(defaults: defaults, usesVisualFixture: true).makeContent(language: AppLanguage(rawValue: test.language)!, fixture: true, fixtureState: test.scenario.replacingOccurrences(of: "xaiSubscriptionDialog-", with: ""))
                    : NSHostingView(rootView: view
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, theme == "dark" ? .dark : .light))
                let style: NSWindow.StyleMask = test.scenario == "window" ? [.titled, .closable, .miniaturizable, .resizable] : [.borderless]
                let window: NSWindow = test.scenario.hasPrefix("desktopSearch")
                    ? SearchVisualWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
                    : NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
                window.contentView = host
                window.center(); window.orderFront(nil)
                if test.scenario.hasPrefix("desktopSearch") { window.makeKeyAndOrderFront(nil) }
                if isClaudeConsentAlert {
                    let alert = ClaudeKeychainConsentAlert.make(language: AppLanguage(rawValue: test.language)!)
                    alert.beginSheetModal(for: window) { _ in }
                }
                if isQuotaHelpAlert {
                    QuotaTrackingHelpAlert.make(language: AppLanguage(rawValue: test.language)!).beginSheetModal(for: window) { _ in }
                }
                if isSourceDetailsAlert {
                    let language = AppLanguage(rawValue: test.language)!
                    let kind = test.comparisonKind ?? .epochECI
                    let content = LeaderboardPresentation.sourceHelp(kind, language: language,
                        board: boards[kind], includesAgreement: true) + "\n\n" + kind.sourceURL.absoluteString
                    SourceDetailsAlert.make(title: LeaderboardPresentation.columnTitle(kind, language: language),
                        content: content, language: language).beginSheetModal(for: window) { _ in }
                }
                defer {
                    if let sheet = window.attachedSheet { window.endSheet(sheet) }
                    window.close(); defaults.removePersistentDomain(forName: defaultsName)
                }
                for frame in 0..<3 {
                    if test.scenario.hasPrefix("usageLoading") { apply(refreshed: frame > 0, phase: frame) }
                    else if frame == 1 { apply(refreshed: true) }
                    try await Task.sleep(for: .milliseconds(300))
                    host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                    if test.scenario == "sourceMenu" {
                        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
                        func sourceButton() throws -> DataSourcesButton {
                            guard let button = descendants(host).compactMap({ $0 as? DataSourcesButton }).first(where: {
                                $0.window === window && !$0.isHiddenOrHasHiddenAncestor && !$0.visibleRect.isEmpty
                            }), host.bounds.contains(button.convert(button.bounds, to: host)) else {
                                throw CaptureError.blankFrame("data source menu missing or clipped")
                            }
                            return button
                        }
                        let button = try sourceButton()
                        if frame > 0 {
                            if button.sourcesPopover?.isShown == true { button.performClick(nil) }
                            button.performClick(nil)
                            try await Task.sleep(for: .milliseconds(250))
                            guard let list = button.sourcesPopover?.contentViewController?.view as? DataSourcesListView,
                                  list.linkButtons.map({ $0.identifier?.rawValue }) == DataSourcesListView.sources.map({ "data-source-\($0.rawValue)" }),
                                  list.linkButtons.map(\.toolTip) == DataSourcesListView.sources.map({ $0.sourceURL.absoluteString }) else {
                                throw CaptureError.blankFrame("source menu links missing, stale or disabled")
                            }
                            var menuPNG: Data?
                            list.effectiveAppearance.performAsCurrentDrawingAppearance {
                                menuPNG = PanelScreenshot.captureForm(view: list, minimumVariety: 1)
                            }
                            guard let menuPNG else { throw CaptureError.blankFrame("source menu capture is blank") }
                            try menuPNG.write(to: output.appending(path: "\(test.id)-\(theme)-menu-frame-\(frame).png"))
                            if frame == 2 {
                                var destinations: [URL] = []
                                let probe = DataSourcesListView(language: AppLanguage(rawValue: test.language)!) { destinations.append($0) }
                                probe.linkButtons.forEach { $0.performClick(nil) }
                                guard destinations == DataSourcesListView.sources.map(\.sourceURL) else {
                                    throw CaptureError.blankFrame("source menu opens the wrong destination")
                                }
                            }
                        }
                    }
                    if test.scenario == "distributionCharts", frame > 0 {
                        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
                        guard let table = descendants(host).compactMap({ $0 as? NSTableView }).first,
                              let charts = descendants(host).first(where: { $0.identifier?.rawValue == "desktop-distributions" }) else {
                            throw CaptureError.blankFrame("distribution footer missing")
                        }
                        table.scrollRowToVisible(table.numberOfRows - 1)
                        try await Task.sleep(for: .milliseconds(300))
                        host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                        guard !charts.visibleRect.isEmpty else { throw CaptureError.blankFrame("distribution footer not reachable") }
                        // Realizing the final rows can update AppKit's estimated heights.
                        // Give the queued SwiftUI/AppKit layout one turn to settle.
                        for _ in 0..<5 {
                            let actual = table.convert(charts.bounds, from: charts)
                            let expected = table.rect(ofRow: table.numberOfRows - LeaderboardView.distributionRowCount)
                            let end = table.rect(ofRow: table.numberOfRows - 1)
                            if abs(actual.minY - expected.minY) < 1, abs(actual.maxY - end.maxY) < 1 { break }
                            try await Task.sleep(for: .milliseconds(20))
                            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                        }
                        let chartFrame = table.convert(charts.bounds, from: charts)
                        let first = table.rect(ofRow: table.numberOfRows - LeaderboardView.distributionRowCount)
                        let last = table.rect(ofRow: table.numberOfRows - 1)
                        guard abs(chartFrame.minY - first.minY) < 1, abs(chartFrame.maxY - last.maxY) < 1 else {
                            throw CaptureError.blankFrame("distribution footer does not cover its reserved rows: actual=\(chartFrame), first=\(first), last=\(last), host=\(charts.frame), parent=\(String(describing: charts.superview?.bounds))")
                        }
                    }
                    if test.scenario.hasPrefix("desktopSearch") {
                        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
                        guard let search = descendants(host).compactMap({ $0 as? DesktopLeaderboardSearchView }).first(where: {
                            $0.window === window && !$0.isHiddenOrHasHiddenAncestor && !$0.visibleRect.isEmpty
                        }) else { throw CaptureError.blankFrame("search control missing") }
                        if frame == 0 {
                            guard !search.expanded, search.hitTest(search.convert(NSPoint(x: 1, y: 12), to: search.superview)) == nil else {
                                throw CaptureError.blankFrame("collapsed search blocks navigation")
                            }
                        }
                        if frame == 1 {
                            search.button.performClick(nil)
                            try await Task.sleep(for: .milliseconds(250))
                            guard window.firstResponder === search.field.currentEditor() else {
                                throw CaptureError.blankFrame("search did not acquire keyboard focus")
                            }
                            search.field.stringValue = test.searchQuery ?? ""
                            search.field.currentEditor()?.string = test.searchQuery ?? ""
                            search.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search.field))
                        }
                        if frame == 2 {
                            apply(refreshed: true)
                            if test.scenario == "desktopSearchOutside" {
                                let point = host.convert(NSPoint(x: 20, y: 20), to: nil)
                                let click = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                    context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
                                let release = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                    context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
                                NSApp.postEvent(release, atStart: true)
                                NSApp.sendEvent(click)
                            } else {
                                window.makeFirstResponder(nil)
                            }
                        }
                        try await Task.sleep(for: .milliseconds(300))
                        host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                        if frame > 0 {
                            let query = test.searchQuery ?? ""
                            if test.scenario == "desktopSearchOutside", frame == 2,
                               let png = PanelScreenshot.capture(view: host)?.png {
                                try png.write(to: output.appending(path: "\(test.id)-\(theme)-outside.png"))
                            }
                            guard search.expanded == (frame == 1 || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), search.field.stringValue == query else {
                                throw CaptureError.blankFrame("search query or blur state lost")
                            }
                            if !query.isEmpty {
                                let kinds = state.visibleBoardKinds
                                let expected = kinds.map { kind -> Int in
                                    let entries = LeaderboardPresentation.rows(state.snapshot.boards[kind], grouping: state.selectedGrouping,
                                        filter: state.countryFilters[kind] ?? .all, openness: state.opennessFilters[kind] ?? .all)
                                    return entries.filter { LeaderboardPresentation.modelNameMatches($0.name, query: query) }.count
                                }.max() ?? 0
                                guard let table = descendants(host).compactMap({ $0 as? NSTableView }).first,
                                      table.numberOfRows == max(4, expected) + LeaderboardView.distributionRowCount else {
                                    throw CaptureError.blankFrame("search did not filter all selected boards")
                                }
                            }
                        }
                    }
                    if test.scenario == "boardSelectionConfirm" {
                        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
                        func visibleButton() throws -> BoardVisibilityButton {
                            guard let button = descendants(host).compactMap({ $0 as? BoardVisibilityButton }).first(where: {
                                $0.window === window && !$0.isHiddenOrHasHiddenAncestor && !$0.visibleRect.isEmpty
                            }) else { throw CaptureError.blankFrame("board visibility control missing") }
                            return button
                        }
                        var button = try visibleButton()
                        if frame == 0 { button.performClick(nil) }
                        if frame == 1 {
                            guard let picker = button.selectionPopover?.contentViewController?.view as? BoardVisibilitySelectionView else {
                                throw CaptureError.blankFrame("board selection closed before confirmation")
                            }
                            picker.checkboxes[0].performClick(nil)
                            picker.checkboxes[1].performClick(nil)
                            guard defaults.dictionary(forKey: "desktopBoardSelections") == nil else {
                                throw CaptureError.blankFrame("board draft persisted before confirmation")
                            }
                        }
                        if frame == 2 {
                            guard let picker = button.selectionPopover?.contentViewController?.view as? BoardVisibilitySelectionView else {
                                throw CaptureError.blankFrame("board selection lost its draft")
                            }
                            picker.confirmButton.performClick(nil)
                            try await Task.sleep(for: .milliseconds(300))
                            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                            // ViewThatFits may replace the footer after columns change.
                            button = try visibleButton()
                            button.performClick(nil)
                        }
                        try await Task.sleep(for: .milliseconds(200))
                        let expected = frame < 2 ? LeaderboardCategory.general.boardKinds : [.epochECI]
                        guard state.visibleBoardKinds == expected,
                              let table = descendants(host).compactMap({ $0 as? NSTableView }).first,
                              table.tableColumns.filter({ !$0.isHidden }).count == 1 + expected.count * 4,
                              let picker = button.selectionPopover?.contentViewController?.view as? BoardVisibilitySelectionView else {
                            throw CaptureError.blankFrame("board selection did not wait for confirmation or popover is blank")
                        }
                        var pickerPNG: Data?
                        // Resolve dynamic AppKit colors while the popover's
                        // appearance is current, including its transparent background.
                        picker.effectiveAppearance.performAsCurrentDrawingAppearance {
                            pickerPNG = PanelScreenshot.captureForm(view: picker, minimumVariety: 1)
                        }
                        guard let png = pickerPNG else { throw CaptureError.blankFrame("board picker capture is blank") }
                        try png.write(to: output.appending(path: "\(test.id)-\(theme)-picker-frame-\(frame).png"))
                        if frame == 2 {
                            picker.checkboxes[0].performClick(nil)
                            picker.cancelButton.performClick(nil)
                            try await Task.sleep(for: .milliseconds(300))
                            button = try visibleButton()
                            button.performClick(nil)
                            try await Task.sleep(for: .milliseconds(200))
                            guard let reopened = button.selectionPopover?.contentViewController?.view as? BoardVisibilitySelectionView,
                                  reopened.checkboxes.map(\.state) == [.off, .off, .on], state.visibleBoardKinds == [.epochECI] else {
                                throw CaptureError.blankFrame("cancelled draft was applied")
                            }
                            reopened.checkboxes[0].performClick(nil)
                            let dismissedPopover = button.selectionPopover
                            dismissedPopover?.close()
                            try await Task.sleep(for: .milliseconds(300))
                            // AppKit owns the asynchronous close animation; the
                            // application selection must remain committed throughout it.
                            guard state.visibleBoardKinds == [.epochECI] else {
                                throw CaptureError.blankFrame("closing the picker committed a draft")
                            }
                        }
                        host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                    }
                    if test.scenario == "boardSelection" {
                        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
                        guard let table = descendants(host).compactMap({ $0 as? NSTableView }).first else { throw CaptureError.blankFrame("selection table missing") }
                        let visible = table.tableColumns.filter { !$0.isHidden }
                        guard visible.count == 1 + state.visibleBoardKinds.count * 4 else { throw CaptureError.blankFrame("hidden source columns still visible") }
                        let contentWidth = visible.reduce(CGFloat(0)) { $0 + $1.width } + CGFloat(visible.count - 1) * table.intercellSpacing.width
                        guard let scroll = table.enclosingScrollView else { throw CaptureError.blankFrame("selection scroll view missing") }
                        if contentWidth > scroll.contentSize.width + 4 {
                            guard scroll.hasHorizontalScroller else { throw CaptureError.blankFrame("selected columns overflow the viewport") }
                            if frame > 0 {
                                scroll.contentView.scroll(to: NSPoint(x: max(0, contentWidth - scroll.contentSize.width), y: scroll.contentView.bounds.minY))
                                scroll.reflectScrolledClipView(scroll.contentView)
                                host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                                guard scroll.contentView.bounds.minX > 0 else { throw CaptureError.blankFrame("selected sources cannot be reached by horizontal scrolling") }
                            }
                        }
                    }
                    if test.scenario == "stickyHeader" || test.scenario == "scrollPerformance" {
                        func descendants(_ view: NSView) -> [NSView] {
                            [view] + view.subviews.flatMap(descendants)
                        }
                        guard let table = descendants(host).compactMap({ $0 as? NSTableView }).first,
                              let scroll = table.enclosingScrollView, let header = table.headerView else {
                            throw CaptureError.blankFrame("sticky header table missing")
                        }
                        let offset: CGFloat = frame == 0 ? 0 : 175.5
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
                        scroll.reflectScrolledClipView(scroll.contentView)
                        header.needsDisplay = true
                        host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                        guard frame == 0 || scroll.contentView.bounds.minY > 0 else {
                            throw CaptureError.blankFrame("sticky header did not scroll")
                        }
                        print("[sticky-header] \(test.id) \(theme) frame=\(frame) offset=\(scroll.contentView.bounds.minY) vibrant=\(header.allowsVibrancy)")
                    }
                    if test.scenario == "taskStatusFooter", frame == 0 {
                        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
                        let original = state.showsCodexTaskStatus
                        for enabled in [!original, original] {
                            guard let toggle = descendants(host).compactMap({ $0 as? NSSwitch }).first(where: { !$0.isHidden }),
                                  host.bounds.contains(toggle.convert(toggle.bounds, to: host)) else {
                                throw CaptureError.blankFrame("\(test.id): footer switch missing or clipped")
                            }
                            toggle.performClick(nil)
                            try await Task.sleep(for: .milliseconds(100))
                            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                            guard state.showsCodexTaskStatus == enabled,
                                  CodexTaskStatusPreference.load(from: defaults) == enabled else {
                                throw CaptureError.blankFrame("\(test.id): footer switch did not update and persist")
                            }
                        }
                    }
                    let captureView = (isClaudeConsentAlert || isQuotaHelpAlert || isSourceDetailsAlert) ? window.attachedSheet?.contentView : host
                    let png = isSourceDetailsAlert ? captureView.flatMap(captureSourceDetails)
                        : (test.scenario == "usagePending" || test.scenario.hasPrefix("usageLoading")) ? PanelScreenshot.captureForm(view: host, minimumVariety: 3) : (test.scenario == "thirdPartyNotices" || test.scenario.hasPrefix("modelDetails") || test.scenario == "addModelDialog" || test.scenario.hasPrefix("xaiSubscriptionDialog") || test.scenario.hasPrefix("xaiDeviceDialog") || isClaudeConsentAlert || isQuotaHelpAlert)
                        ? captureView.flatMap { PanelScreenshot.captureForm(view: $0, minimumVariety: 1) }
                        : PanelScreenshot.capture(view: host)?.png
                    guard let png else { throw CaptureError.blankFrame(test.id) }
                    try png.write(to: output.appending(path: "\(test.id)-\(theme)-frame-\(frame).png"))
                }
                if isSourceDetailsAlert {
                    guard let sheet = window.attachedSheet,
                          let scroll = sheet.contentView?.subviews.flatMap({ [$0] + $0.subviews })
                            .compactMap({ $0 as? NSScrollView }).first,
                          let text = scroll.documentView as? NSTextView,
                          !scroll.hasHorizontalScroller,
                          text.frame.width <= scroll.contentView.bounds.width + 1 else {
                        throw CaptureError.blankFrame("source details overflow horizontally")
                    }
                    let metrics: [String: Any] = ["documentWidth": text.frame.width,
                        "viewportWidth": scroll.contentView.bounds.width, "documentHeight": text.frame.height,
                        "viewportHeight": scroll.contentView.bounds.height, "characters": text.string.count,
                        "originX": scroll.contentView.bounds.minX, "originY": scroll.contentView.bounds.minY,
                        "appearance": sheet.effectiveAppearance.name.rawValue,
                        "horizontalScroller": scroll.hasHorizontalScroller]
                    try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
                        .write(to: output.appending(path: "\(test.id)-\(theme)-layout.json"))
                    text.scrollToEndOfDocument(nil)
                    sheet.displayIfNeeded()
                    guard let bottom = sheet.contentView.flatMap(captureSourceDetails) else {
                        throw CaptureError.blankFrame("source details bottom is blank")
                    }
                    try bottom.write(to: output.appending(path: "\(test.id)-\(theme)-bottom.png"))
                }
                if test.scenario == "virtualRanking" || test.scenario == "scrollPerformance" {
                    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
                    guard let table = descendants(host).compactMap({ $0 as? NSTableView }).first,
                          table.numberOfRows >= 1000 else { throw CaptureError.blankFrame("long ranking missing") }
                    func realizedRows() -> Int {
                        var count = 0
                        table.enumerateAvailableRowViews { _, _ in count += 1 }
                        return count
                    }
                    let initial = realizedRows()
                    guard initial > 0, initial < 100 else { throw CaptureError.blankFrame("table eagerly created row views") }
                    table.scrollRowToVisible(table.numberOfRows - 1)
                    try await Task.sleep(for: .milliseconds(300))
                    host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                    guard table.rowView(atRow: table.numberOfRows - 1, makeIfNecessary: false) != nil,
                          realizedRows() < 100 else { throw CaptureError.blankFrame("long table tail or recycling failed") }
                    print("[virtual-ranking] rows=\(table.numberOfRows) initialViews=\(initial) tailViews=\(realizedRows())")
                    guard let button = descendants(host).compactMap({ $0 as? NSButton }).first(where: {
                        $0.identifier?.rawValue == "leaderboard-back-to-top"
                    }) else { throw CaptureError.blankFrame("return control missing") }
                    button.performClick(nil)
                    try await Task.sleep(for: .milliseconds(300))
                    guard table.rowView(atRow: 0, makeIfNecessary: false) != nil else {
                        throw CaptureError.blankFrame("virtual table did not return to first row")
                    }
                    if test.scenario == "scrollPerformance", let scroll = table.enclosingScrollView {
                        var samples: [Double] = []
                        for step in 0..<240 {
                            let offset = CGFloat(step < 120 ? step : 239 - step) * 24
                            let start = ProcessInfo.processInfo.systemUptime
                            scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
                            scroll.reflectScrolledClipView(scroll.contentView)
                            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                            // Include deferred chrome/cell updates, not just setting bounds.
                            await Task.yield()
                            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                            samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                        }
                        let sorted = samples.sorted()
                        let timing: [String: Double] = [
                            "steps": Double(samples.count), "medianMS": sorted[sorted.count / 2],
                            "p95MS": sorted[Int(Double(sorted.count - 1) * 0.95)],
                            "maximumMS": sorted.last!, "totalMS": samples.reduce(0, +),
                            "realizedRows": Double(realizedRows()), "totalRows": Double(table.numberOfRows),
                        ]
                        try JSONSerialization.data(withJSONObject: timing, options: [.prettyPrinted, .sortedKeys])
                            .write(to: output.appending(path: "\(test.id)-\(theme)-scroll-timing.json"))
                        print("[scroll-performance] \(test.id) \(theme) \(timing)")
                    }
                }
                if test.scenario == "completeRanking" {
                    func descendants(_ view: NSView) -> [NSView] {
                        [view] + view.subviews.flatMap(descendants)
                    }
                    guard let table = descendants(host).compactMap({ $0 as? NSTableView }).first,
                          table.numberOfRows == 31 + LeaderboardView.distributionRowCount,
                          let scroll = table.enclosingScrollView,
                          scroll.hasVerticalScroller,
                          let button = descendants(host).compactMap({ $0 as? NSButton }).first(where: {
                              $0.identifier?.rawValue == "leaderboard-back-to-top"
                          }) else { throw CaptureError.blankFrame("full ranking table or scroll control missing") }
                    let viewport = scroll.frame.size
                    table.scrollRowToVisible(table.numberOfRows - 1)
                    try await Task.sleep(for: .milliseconds(300))
                    host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                    let buttonFrame = scroll.convert(button.bounds, from: button)
                    let bottomDistance = scroll.isFlipped ? scroll.bounds.maxY - buttonFrame.maxY
                        : buttonFrame.minY - scroll.bounds.minY
                    print("[full-ranking] \(test.id) \(theme) offset=\(scroll.contentView.bounds.minY) hidden=\(button.isHidden) button=\(buttonFrame) viewport=\(scroll.bounds) flipped=\(scroll.isFlipped)")
                    if let diagnostic = PanelScreenshot.capture(view: host)?.png {
                        try diagnostic.write(to: output.appending(path: "\(test.id)-\(theme)-bottom.png"))
                    }
                    guard scroll.contentView.bounds.minY > 0, !button.isHidden,
                          buttonFrame.minX >= scroll.bounds.width - 60,
                          bottomDistance >= 0, bottomDistance <= 45,
                          scroll.frame.size == viewport,
                          let bottom = PanelScreenshot.capture(view: host)?.png else {
                        throw CaptureError.blankFrame("tail row or back-to-top button unreachable")
                    }
                    try bottom.write(to: output.appending(path: "\(test.id)-\(theme)-bottom.png"))
                    button.performClick(nil)
                    try await Task.sleep(for: .milliseconds(300))
                    host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                    guard scroll.contentView.bounds.minY <= 1, button.isHidden,
                          scroll.frame.size == viewport,
                          let returned = PanelScreenshot.capture(view: host)?.png else {
                        throw CaptureError.blankFrame("back-to-top did not restore the first row")
                    }
                    try returned.write(to: output.appending(path: "\(test.id)-\(theme)-returned.png"))
                }
                if test.scenario == "addModelDialog" {
                    // SwiftUI sheets require an actual app bundle. SwiftPM's
                    // standalone testing helper has no Launch Services proxy.
                    try await verifyAccountSheetDismissal(state: state,
                        checking: test.officialAccountChecking ?? false)
                }
                metadata.append(["id": test.id, "theme": theme, "width": String(test.width), "height": String(test.height),
                    "fixtureHash": fixtureHash, "timezone": TimeZone.current.identifier,
                    "sourceCommit": ProcessInfo.processInfo.environment["GITHUB_SHA"] ?? "local-uncommitted",
                    "backingScale": String(describing: window.backingScaleFactor), "capture": "native-view-without-redaction",
                    "os": ProcessInfo.processInfo.operatingSystemVersionString])
            }
        }
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]).write(to: output.appending(path: "metadata.json"))
    }

    private static func taskHighlightMetadata(button: NSStatusBarButton, state: AppState) throws -> String {
        let title = button.attributedTitle
        var segments = [[String: String]]()
        title.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: title.length)) { value, range, _ in
            guard let color = value as? NSColor else { return }
            var rgb = ""
            button.effectiveAppearance.performAsCurrentDrawingAppearance {
                if let resolved = color.usingColorSpace(.sRGB) {
                    rgb = String(format: "#%02X%02X%02X", Int((resolved.redComponent * 255).rounded()),
                        Int((resolved.greenComponent * 255).rounded()), Int((resolved.blueComponent * 255).rounded()))
                }
            }
            segments.append(["text": (title.string as NSString).substring(with: range), "color": rgb])
        }
        let expected = state.isCodexTaskStatusVisible ? state.codexTaskCounts.map {
            [$0.running, $0.unread, $0.failed].filter { $0 > 0 }.map(String.init)
        } ?? [] : []
        guard segments.compactMap({ $0["text"] }) == expected else {
            throw CaptureError.blankFrame("incorrect nonzero task highlights")
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: segments, options: [.sortedKeys]), as: UTF8.self)
    }

    private static func verifyAccountSheetDismissal(state: AppState, checking: Bool) async throws {
        for escape in [false, true] {
            let presentation = AccountSheetPresentation()
            let host = NSHostingView(rootView: AccountSheetTestView(state: state,
                presentation: presentation, checking: checking))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 640),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            defer { if let sheet = window.attachedSheet { window.endSheet(sheet) }; window.close() }
            presentation.isPresented = true
            guard await waitFor({ window.attachedSheet != nil }), let sheet = window.attachedSheet else {
                throw CaptureError.blankFrame("add-model: sheet did not open")
            }
            try await Task.sleep(for: .milliseconds(200))
            sheet.contentView?.layoutSubtreeIfNeeded()
            sheet.displayIfNeeded()
            if escape {
                sheet.makeKey()
                guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
                    modifierFlags: [], timestamp: 0, windowNumber: sheet.windowNumber, context: nil,
                    characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53) else {
                    throw CaptureError.blankFrame("add-model: Escape event unavailable")
                }
                sheet.sendEvent(event)
            } else {
                guard let marker = findDoneButtonAnchor(sheet.contentView),
                      marker.bounds.width > 0, marker.bounds.height > 0 else {
                    throw CaptureError.blankFrame("add-model: Done geometry unavailable")
                }
                let point = marker.convert(NSPoint(x: marker.bounds.midX, y: marker.bounds.midY), to: nil)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let click = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                        timestamp: 0, windowNumber: sheet.windowNumber, context: nil,
                        eventNumber: 0, clickCount: 1, pressure: 1) else {
                        throw CaptureError.blankFrame("add-model: mouse event unavailable")
                    }
                    sheet.sendEvent(click)
                }
            }
            guard await waitFor({ !presentation.isPresented && window.attachedSheet == nil }) else {
                throw CaptureError.blankFrame("add-model: \(escape ? "Escape" : "Done") did not dismiss; checking=\(checking)")
            }
        }
    }

    private static func waitFor(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return predicate()
    }

    private static func findDoneButtonAnchor(_ view: NSView?) -> NSView? {
        guard let view else { return nil }
        if view.identifier == AccountDoneButtonAnchor.identifier { return view }
        for child in view.subviews {
            if let found = findDoneButtonAnchor(child) { return found }
        }
        return nil
    }
}

@MainActor
private final class AccountSheetPresentation: ObservableObject {
    @Published var isPresented = false
}

private struct AccountSheetTestView: View {
    let state: AppState
    @ObservedObject var presentation: AccountSheetPresentation
    let checking: Bool

    var body: some View {
        Text("Account sheet test")
            .sheet(isPresented: $presentation.isPresented) {
                OfficialQuotaAccountsView(state: state,
                    onClose: { presentation.isPresented = false },
                    usesVisualFixture: true, visualVerificationPending: checking)
            }
    }
}

#endif
