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
        let id: String; let name: String; let isCurrent: Bool; let runs: [Run]
    }
    struct State: Decodable { let boards: [Board]; let quotas: [Quota]; let quotaUpdatedAt: String? }
    struct Case: Decodable { let id: String; let language: String; let width: Int; let height: Int; let scenario: String; let quotaAgeSeconds: Int?; let versionText: String? }
    struct Fixture: Decodable { let state: State; let cases: [Case] }

    static func run() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = root.appending(path: "work/visual-parity/macos")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixtureBytes = try Data(contentsOf: root.appending(path: "Tests/fixtures/visual-state.json"))
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
        let chips = fixture.state.quotas.map { quota in
            let percent = Double(quota.runs.last!.text.replacingOccurrences(of: "%", with: ""))!
            return AccountQuotaChip(id: quota.id, shortName: quota.name, websiteURL: nil,
                kind: kinds[quota.name]!, isCurrent: quota.isCurrent,
                status: .windows([ParsedQuotaWindow(name: "seven_day", utilization: 100 - percent, resetsAt: nil)]))
        }
        var metadata: [[String: String]] = []
        for test in fixture.cases {
            for theme in ["light", "dark"] {
                let defaultsName = "ai-benchgauge.visual.\(UUID().uuidString)"
                let defaults = UserDefaults(suiteName: defaultsName)!
                let state = AppState(cache: LeaderboardCache(fileURL: output.appending(path: "nonexistent-cache.json")), defaults: defaults)
                let visibleChips = test.scenario == "manyQuotas" ? chips : (test.scenario == "empty" || test.scenario == "error" ? [] : Array(chips.prefix(2)))
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
                func apply() {
                    state.applyVisualFixture(snapshot: LeaderboardSnapshot(boards: fetchedBoards), chips: shownChips,
                        language: AppLanguage(rawValue: test.language)!, errors: errors,
                        emptyState: test.scenario == "empty" ? .notInstalled : nil,
                        panelMode: test.scenario == "window" ? .window : .clickToClose, quotaUpdatedAt: quotaDate, quotaUnavailable: stale)
                }
                apply()
                let size = NSSize(width: test.width, height: test.height)
                let host = NSHostingView(rootView: LeaderboardView(state: state, maximumWidth: CGFloat(test.width), viewportSize: size, visualVersionText: test.versionText)
                    .environment(\.colorScheme, theme == "dark" ? .dark : .light))
                let style: NSWindow.StyleMask = test.scenario == "window" ? [.titled, .closable, .miniaturizable, .resizable] : [.borderless]
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
                window.contentView = host
                window.center(); window.orderFront(nil)
                defer { window.close(); defaults.removePersistentDomain(forName: defaultsName) }
                for frame in 0..<3 {
                    if frame == 1 { apply() }
                    try await Task.sleep(for: .milliseconds(300))
                    host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                    guard let capture = PanelScreenshot.capture(view: host) else { throw CaptureError.blankFrame(test.id) }
                    try capture.png.write(to: output.appending(path: "\(test.id)-\(theme)-frame-\(frame).png"))
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
