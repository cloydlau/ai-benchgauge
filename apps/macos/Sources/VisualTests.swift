#if DEBUG
import AppKit
import Foundation
import CryptoKit
import LeaderboardCore
import SwiftUI

@MainActor
enum NativeVisualCapture {
    enum CaptureError: Error { case blankFrame(String) }
    struct Entry: Decodable { let rank: Int; let name: String; let score: Double; let organization: String; let logo: String }
    struct Board: Decodable { let kind: String; let title: String; let entries: [Entry] }
    struct Quota: Decodable {
        struct Run: Decodable { let text: String }
        struct Balance: Decodable { let currency: String; let amount: Double }
        struct Window: Decodable { let name: String; let utilization: Double; let resetsAt: String?; let dateSource: ParsedQuotaDateSource? }
        let id: String; let name: String; let isCurrent: Bool; let runs: [Run]; let status: String?; let modelName: String?; let failureReason: String?; let baseURL: String?
        let windows: [Window]?
        let balances: [Balance]?
    }
    struct State: Decodable { let boards: [Board]; let quotas: [Quota]; let quotaUpdatedAt: String? }
    struct Case: Decodable { let id: String; let language: String; let width: Int; let height: Int; let scenario: String; let quotaAgeSeconds: Int?; let versionText: String?; let codexModel: String?; let codexProvider: String?; let codexBaseURL: String?; let taskCounts: CodexTaskCounts?; let refreshedTaskCounts: CodexTaskCounts?; let codexDesktopRunning: Bool?; let refreshedCodexDesktopRunning: Bool? }
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
                LeaderboardEntry(rank: entry.rank, name: entry.name, score: entry.score, organization: entry.organization,
                    logoURL: root.appending(path: "assets/logos/\(entry.logo).png"))
            }
            return (kind, Leaderboard(kind: kind, title: board.title, sourceUpdatedAt: fixedDate, fetchedAt: fixedDate, entries: entries))
        })
        let kinds: [String: CCSwitchQuotaKind] = ["OpenAI": .officialNote, "Kimi": .kimi, "Qwen": .qwen, "DeepSeek": .deepseek, "GLM": .zhipu, "xAI": .xaiOAuth]
        func chip(_ quota: Quota) -> AccountQuotaChip {
            let status: AccountQuotaChip.Status
            switch quota.status {
            case "reauth": status = .message(AccountQuotaMessage.reauthRequired)
            case "pending": status = .pending
            case "unconnected": status = .note(text: AccountQuotaMessage.connectOfficial, help: AccountQuotaMessage.connectOfficialHelp)
            case "qwenWebsite": status = .qwenWebsite(QwenWebsiteQuota(periodLabel: "1mo", remainingPercent: 42, resetsAt: nil))
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
                        resetsAt: $0.resetsAt.flatMap { ISO8601DateFormatter().date(from: $0) }, dateSource: $0.dateSource) })
                } else {
                    let percent = Double(quota.runs.last!.text.replacingOccurrences(of: "%", with: ""))!
                    status = .windows([ParsedQuotaWindow(name: "seven_day", utilization: 100 - percent, resetsAt: nil)])
                }
            }
            return AccountQuotaChip(id: quota.id, shortName: quota.name, modelName: quota.modelName, websiteURL: nil,
                kind: kinds[quota.name] ?? .kimi, isCurrent: quota.isCurrent, status: status)
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
                let fetchedBoards = boards.mapValues { board in
                    Leaderboard(kind: board.kind, title: board.title, sourceUpdatedAt: board.sourceUpdatedAt,
                                fetchedAt: quotaDate ?? fixedDate, entries: board.entries)
                }
                let stale = test.scenario == "freshnessStale"
                let shownChips = stale ? visibleChips.map { chip in
                    AccountQuotaChip(id: chip.id, shortName: chip.shortName, websiteURL: chip.websiteURL,
                                     kind: chip.kind, isCurrent: chip.isCurrent, status: chip.status, isStale: true)
                } : visibleChips
                func apply(refreshed: Bool = false) {
                    state.applyVisualFixture(snapshot: LeaderboardSnapshot(boards: fetchedBoards), chips: shownChips,
                        language: AppLanguage(rawValue: test.language)!, errors: errors,
                        emptyState: test.scenario == "empty" ? .notInstalled : (test.scenario == "installedEmpty" ? .installedEmpty : nil),
                        panelMode: test.scenario == "window" ? .window : .clickToClose, quotaUpdatedAt: quotaDate, quotaUnavailable: stale,
                        modelConfiguration: test.codexModel.map { CodexModelConfiguration(model: $0, provider: test.codexProvider, baseURL: test.codexBaseURL) },
                        targets: visibleChips.map { value in
                            CCSwitchQuotaTarget(id: value.id, shortName: value.shortName, modelName: value.modelName,
                                websiteURL: nil, kind: value.kind, isCurrent: value.isCurrent, apiKey: nil,
                                baseURL: (fixture.quotaScenarios?[test.scenario] ?? fixture.state.quotas).first { $0.id == value.id }?.baseURL)
                        }, taskCounts: refreshed ? (test.refreshedTaskCounts ?? test.taskCounts) : test.taskCounts,
                        codexDesktopRunning: refreshed ? (test.refreshedCodexDesktopRunning ?? test.codexDesktopRunning ?? true) : (test.codexDesktopRunning ?? true))
                }
                apply()
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
                    var statusLabels = [String]()
                    var statusHelp = [String]()
                    for frame in 0..<3 {
                        if frame == 1 { apply(refreshed: true) }
                        try await Task.sleep(for: .milliseconds(300))
                        _ = controller.visualStatusButton(width: CGFloat(test.width))
                        let label = button.attributedTitle.string
                        let help = button.toolTip ?? ""
                        guard label.contains("▶") == state.codexDesktopRunning,
                              state.codexDesktopRunning || !help.contains("Codex") else {
                            throw CaptureError.blankFrame("\(test.id): incorrect task-block visibility")
                        }
                        statusLabels.append(label)
                        statusHelp.append(help)
                        guard let png = PanelScreenshot.captureForm(view: button, minimumVariety: 1) else {
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
                        "capture": "native-status-button", "os": ProcessInfo.processInfo.operatingSystemVersionString])
                    continue
                }
                let size = NSSize(width: test.width, height: test.height)
                let isClaudeConsentAlert = test.scenario == "claudeKeychainConsentAlert"
                let view = test.scenario == "addModelDialog"
                    ? AnyView(OfficialQuotaAccountsView(state: state, usesVisualFixture: true))
                    : AnyView(LeaderboardView(state: state, maximumWidth: CGFloat(test.width), viewportSize: size, visualVersionText: test.versionText))
                let host: NSView = test.scenario.hasPrefix("xaiSubscriptionDialog")
                    ? XAIWebsiteSubscriptionSource(defaults: defaults, usesVisualFixture: true).makeContent(language: AppLanguage(rawValue: test.language)!, fixture: true, fixtureState: test.scenario.replacingOccurrences(of: "xaiSubscriptionDialog-", with: ""))
                    : NSHostingView(rootView: view
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, theme == "dark" ? .dark : .light))
                let style: NSWindow.StyleMask = test.scenario == "window" ? [.titled, .closable, .miniaturizable, .resizable] : [.borderless]
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
                window.contentView = host
                window.center(); window.orderFront(nil)
                if isClaudeConsentAlert {
                    let alert = ClaudeKeychainConsentAlert.make(language: AppLanguage(rawValue: test.language)!)
                    alert.beginSheetModal(for: window) { _ in }
                }
                defer {
                    if let sheet = window.attachedSheet { window.endSheet(sheet) }
                    window.close(); defaults.removePersistentDomain(forName: defaultsName)
                }
                for frame in 0..<3 {
                    if frame == 1 { apply() }
                    try await Task.sleep(for: .milliseconds(300))
                    host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                    let captureView = isClaudeConsentAlert ? window.attachedSheet?.contentView : host
                    let png = (test.scenario == "addModelDialog" || test.scenario.hasPrefix("xaiSubscriptionDialog") || isClaudeConsentAlert)
                        ? captureView.flatMap { PanelScreenshot.captureForm(view: $0, minimumVariety: 1) }
                        : PanelScreenshot.capture(view: host)?.png
                    guard let png else { throw CaptureError.blankFrame(test.id) }
                    try png.write(to: output.appending(path: "\(test.id)-\(theme)-frame-\(frame).png"))
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
}

#endif
