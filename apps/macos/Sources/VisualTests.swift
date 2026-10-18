#if DEBUG
import AppKit
import Foundation
import CryptoKit
import LeaderboardCore
import SwiftUI

@MainActor
enum NativeVisualCapture {
    enum CaptureError: Error { case blankFrame(String) }
    struct Entry: Decodable { let rank: Int; let name: String; let score: Double; let modelID: String?; let organization: String; let logo: String; let openness: ModelOpenness?; let brand: OrganizationBrand?; let organizationBrand: OrganizationBrand?; let developerCountry: OrganizationCountryMetadata? }
    struct Board: Decodable { let kind: String; let title: String; let entries: [Entry]; let sourceUpdatedAt: String?; let sourceTimeUnavailable: Bool?; let fetchedAt: String? }
    struct Quota: Decodable {
        struct Run: Decodable { let text: String }
        struct Balance: Decodable { let currency: String; let amount: Double }
        struct Window: Decodable { let name: String; let utilization: Double; let resetsAt: String?; let dateSource: ParsedQuotaDateSource? }
        let id: String; let name: String; let isCurrent: Bool; let runs: [Run]; let status: String?; let modelName: String?; let failureReason: String?; let baseURL: String?
        let windows: [Window]?
        let balances: [Balance]?
    }
    struct State: Decodable { let boards: [Board]; let quotas: [Quota]; let quotaUpdatedAt: String? }
    struct Case: Decodable { let id: String; let language: String; let width: Int; let height: Int; let scenario: String; let quotaAgeSeconds: Int?; let versionText: String?; let codexModel: String?; let codexProvider: String?; let codexBaseURL: String?; let taskCounts: CodexTaskCounts?; let refreshedTaskCounts: CodexTaskCounts?; let codexDesktopRunning: Bool?; let refreshedCodexDesktopRunning: Bool?; let showsCodexTaskStatus: Bool?; let refreshedShowsCodexTaskStatus: Bool?; let officialAccountChecking: Bool?; let sources: [String: LeaderboardOpennessFilter]?; let countries: [String: String]?; let grouping: LeaderboardGrouping?; let category: LeaderboardCategory?; let comparisonKind: LeaderboardKind?; let rowCount: Int? }
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
                    logoURL: root.appending(path: "assets/logos/\(entry.logo).png"), openness: entry.openness, brand: entry.brand, organizationBrand: entry.organizationBrand, developerCountry: entry.developerCountry)
            }
            return (kind, Leaderboard(kind: kind, title: board.title, sourceUpdatedAt: board.sourceTimeUnavailable == true ? nil : board.sourceUpdatedAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? fixedDate, fetchedAt: board.fetchedAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? fixedDate, entries: entries))
        })
        let kinds: [String: CCSwitchQuotaKind] = ["OpenAI": .officialNote, "Kimi": .kimi, "Qwen": .qwen, "DeepSeek": .deepseek, "GLM": .zhipu, "xAI": .xaiOAuth]
        func chip(_ quota: Quota) -> AccountQuotaChip {
            let status: AccountQuotaChip.Status
            switch quota.status {
            case "network": status = .message(AccountQuotaMessage.network)
            case "reauth": status = .message(AccountQuotaMessage.reauthRequired)
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
                    let entries = test.rowCount.map { count in
                        (1...count).map { rank in LeaderboardEntry(rank: rank, name: "Fixture model \(rank)", score: Double(count - rank + 1),
                            organization: "Fixture maker \(rank)", logoURL: root.appending(path: "assets/logos/openai.png")) }
                    } ?? board.entries
                    return Leaderboard(kind: board.kind, title: board.title, sourceUpdatedAt: board.sourceUpdatedAt,
                                fetchedAt: test.scenario == "sourceTimes" ? board.fetchedAt : quotaDate ?? fixedDate, entries: entries)
                }
                let stale = test.scenario == "freshnessStale"
                let shownChips = stale ? visibleChips.map { chip in
                    AccountQuotaChip(id: chip.id, shortName: chip.shortName, websiteURL: chip.websiteURL,
                                     kind: chip.kind, isCurrent: chip.isCurrent, status: chip.status, isStale: true)
                } : visibleChips
                func apply(refreshed: Bool = false) {
                    state.generalComparison = test.comparisonKind ?? .arenaText
                    state.setShowsCodexTaskStatus(refreshed
                        ? (test.refreshedShowsCodexTaskStatus ?? test.showsCodexTaskStatus ?? false)
                        : (test.showsCodexTaskStatus ?? false))
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
                        codexDesktopRunning: refreshed ? (test.refreshedCodexDesktopRunning ?? test.codexDesktopRunning ?? true) : (test.codexDesktopRunning ?? true),
                        category: test.category ?? .general)
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
                let view = test.scenario == "addModelDialog"
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
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
                window.contentView = host
                window.center(); window.orderFront(nil)
                if isClaudeConsentAlert {
                    let alert = ClaudeKeychainConsentAlert.make(language: AppLanguage(rawValue: test.language)!)
                    alert.beginSheetModal(for: window) { _ in }
                }
                if isQuotaHelpAlert {
                    QuotaTrackingHelpAlert.make(language: AppLanguage(rawValue: test.language)!).beginSheetModal(for: window) { _ in }
                }
                defer {
                    if let sheet = window.attachedSheet { window.endSheet(sheet) }
                    window.close(); defaults.removePersistentDomain(forName: defaultsName)
                }
                for frame in 0..<3 {
                    if frame == 1 { apply() }
                    try await Task.sleep(for: .milliseconds(300))
                    host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
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
                    let captureView = (isClaudeConsentAlert || isQuotaHelpAlert) ? window.attachedSheet?.contentView : host
                    let png = (test.scenario == "addModelDialog" || test.scenario.hasPrefix("xaiSubscriptionDialog") || test.scenario.hasPrefix("xaiDeviceDialog") || isClaudeConsentAlert || isQuotaHelpAlert)
                        ? captureView.flatMap { PanelScreenshot.captureForm(view: $0, minimumVariety: 1) }
                        : PanelScreenshot.capture(view: host)?.png
                    guard let png else { throw CaptureError.blankFrame(test.id) }
                    try png.write(to: output.appending(path: "\(test.id)-\(theme)-frame-\(frame).png"))
                }
                if test.scenario == "virtualRanking" {
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
                }
                if test.scenario == "completeRanking" {
                    func descendants(_ view: NSView) -> [NSView] {
                        [view] + view.subviews.flatMap(descendants)
                    }
                    guard let table = descendants(host).compactMap({ $0 as? NSTableView }).first,
                          table.numberOfRows == 31,
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
