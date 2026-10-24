#if DEBUG
import AppKit
import LeaderboardCore

/// Exercises production AppKit layout against frozen public leaderboard data.
/// Does not start account clients, timers, network refreshes or authorization.
@MainActor
enum NativePopoverPerformance {
    static func run() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let input = env["BENCHGAUGE_PERF_CACHE"], let destination = env["BENCHGAUGE_PERF_OUTPUT"] else {
            throw CocoaError(.fileNoSuchFile)
        }
        let output = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let clock = ContinuousClock()
        func elapsed(_ start: ContinuousClock.Instant) -> Double {
            let c = start.duration(to: clock.now).components
            return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
        }
        let loadStart = clock.now
        guard let snapshot = LeaderboardCache(fileURL: URL(fileURLWithPath: input)).load() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var result: [String: Any] = ["loadMs": elapsed(loadStart), "boardCounts": snapshot.boards.mapValues { $0.entries.count },
            "os": ProcessInfo.processInfo.operatingSystemVersionString, "backingScale": NSScreen.main?.backingScaleFactor ?? 1]
        // JSON dictionary keys must be strings.
        result["boardCounts"] = Dictionary(uniqueKeysWithValues: snapshot.boards.map { ($0.key.rawValue, $0.value.entries.count) })
        let suite = "popover-performance.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(PanelMode.clickToClose.rawValue, forKey: "panelMode")
        let temp = FileManager.default.temporaryDirectory.appending(path: "popover-perf-save-\(UUID()).json")
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: temp) }
        let state = AppState(cache: LeaderboardCache(fileURL: temp), defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_792_800_000)
        func chips(_ value: Double) -> [AccountQuotaChip] {
            (0..<8).map { index in
                .init(id: "fixture-\(index)", shortName: "Provider \(index)", websiteURL: nil,
                    kind: .claude, isCurrent: index == 0,
                    status: .windows([.init(name: "five_hour", utilization: value, resetsAt: date.addingTimeInterval(86_400))]))
            }
        }
        state.applyVisualFixture(snapshot: snapshot, chips: chips(25), language: .chinese, errors: [:], emptyState: nil, quotaUpdatedAt: date)
        let maxWidth: CGFloat = 1100
        var sizing: [Double] = []
        var sizes: [String] = []
        for _ in 0..<4 {
            let start = clock.now
            sizes.append(NSStringFromSize(LeaderboardView.preferredSize(for: state, maximumWidth: maxWidth)))
            sizing.append(elapsed(start))
        }
        result["sizeMs"] = sizing
        result["sizes"] = sizes
        let construction = clock.now
        let controller = StatusBarController(state: state)
        result["controllerMs"] = elapsed(construction)
        defer { controller.finishVisualStatusCapture(); state.beginQuitting() }
        var opens: [Double] = []
        for frame in 0..<3 {
            _ = controller.visualPopoverWindow(show: false)
            let start = clock.now
            _ = controller.visualPopoverWindow(show: true)
            for _ in 0..<500 {
                if let w = controller.visualPopoverWindow(show: true), w.isVisible, w.alphaValue > 0 { break }
                try await Task.sleep(for: .milliseconds(1))
            }
            opens.append(elapsed(start))
            try await Task.sleep(for: .milliseconds(150))
            if let window = controller.visualPopoverWindow(show: true), let chrome = window.contentView?.superview,
               let png = PanelScreenshot.captureForm(view: chrome, minimumVariety: 1) {
                try png.write(to: output.appending(path: "popover-frame-\(frame).png"))
            }
        }
        result["openToVisibleMs"] = opens
        let burst = clock.now
        for value in 26..<38 { state.applyVisualQuotaUpdate(chips(Double(value))) }
        // A next-turn marker runs after the controller's queued updates.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        result["quotaBurstMainQueueMs"] = elapsed(burst)
        let save = clock.now
        LeaderboardCache(fileURL: temp).save(snapshot)
        result["synchronousCacheSaveMs"] = elapsed(save)
        let persistence = SnapshotPersistence(cache: LeaderboardCache(fileURL: temp))
        let enqueue = clock.now
        persistence.save(snapshot)
        result["backgroundCacheEnqueueMs"] = elapsed(enqueue)
        await persistence.flush()
        result["backgroundCacheFlushMs"] = elapsed(enqueue)
        result["widthMeasurementCount"] = state.panelLayoutCache.widthMeasurementCount
        result["heightMeasurementCount"] = state.panelLayoutCache.heightMeasurementCount
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appending(path: "performance.json"))
        print("[popover-performance] \(destination)")
    }
}
#endif
