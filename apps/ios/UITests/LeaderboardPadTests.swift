import XCTest
import UIKit

final class LeaderboardBottomSafeAreaTests: XCTestCase {
    func testLongBoardCreatesOnlyNearbyRows() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let entries = (1...1000).map { ["rank": $0,
            "name": "Fixture Model \($0) with extended reasoning",
            "score": 2000 - $0, "organization": "Fixture Maker \($0)"] as [String: Any] }
        app.launchEnvironment["BENCHGAUGE_UI_MODEL_ENTRIES"] = String(data: try! JSONSerialization.data(withJSONObject: entries), encoding: .utf8)
        for company in [false, true] {
            app.launchArguments = ["--ui-testing", "--full-board", "--reduce-motion", "--preview-zh"]
                + (company ? ["--preview-companies", "--dark"] : [])
            let started = Date()
            app.launch()
            let first = app.buttons["name-artificialAnalysis-1"]
            XCTAssertTrue(first.waitForExistence(timeout: 15))
            let names = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "name-artificialAnalysis-"))
            let initial = names.count
            print("[lazy-ranking] company=\(company) initialRows=\(initial) firstFrameSeconds=\(Date().timeIntervalSince(started))")
            XCTAssertLessThan(initial, 200, "A thousand-row board must not create a thousand row views")
            capture("lazy-\(company ? "company" : "model")-initial")
            let scroll = UIDevice.current.userInterfaceIdiom == .phone
                ? app.otherElements["cube-viewport"] : app.scrollViews.firstMatch
            for _ in 0..<3 { scroll.swipeUp() }
            XCTAssertFalse(first.isHittable)
            print("[lazy-ranking] company=\(company) scrolledRows=\(names.count)")
            XCTAssertLessThan(names.count, 200)
            capture("lazy-\(company ? "company" : "model")-scrolled")
            let back = app.buttons["leaderboard-back-to-top"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons.matching(identifier: "leaderboard-back-to-top").count, 1,
                           "Only the active source may expose its return-to-top control")
            back.tap()
            let restored = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: first)
            wait(for: [restored], timeout: 5)
            capture("lazy-\(company ? "company" : "model")-returned")
            app.terminate()
        }
    }

    func testCompleteRankingsAndReturnToTop() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let entries = (1...40).map { ["rank": $0, "name": "Fixture Model \($0)",
            "score": 100 - $0, "organization": "Fixture Maker \($0)"] as [String: Any] }
        app.launchEnvironment["BENCHGAUGE_UI_MODEL_ENTRIES"] = String(data: try! JSONSerialization.data(withJSONObject: entries), encoding: .utf8)
        for company in [false, true] {
            app.launchArguments = ["--ui-testing", "--full-board", "--reduce-motion"]
                + (company ? ["--preview-companies", "--preview-zh", "--dark"] : [])
            app.launch()
            let first = app.buttons["name-artificialAnalysis-1"]
            XCTAssertTrue(first.waitForExistence(timeout: 10))
            let scroll = UIDevice.current.userInterfaceIdiom == .phone
                ? app.otherElements["cube-viewport"] : app.scrollViews.firstMatch
            let tail = app.buttons["name-artificialAnalysis-40"]
            capture("complete-\(company ? "company" : "model")-top")
            for _ in 0..<16 {
                if tail.isHittable { break }
                scroll.swipeUp()
            }
            XCTAssertTrue(tail.isHittable, "The full list must reach rank 40")
            let back = app.buttons["leaderboard-back-to-top"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons.matching(identifier: "leaderboard-back-to-top").count, 1,
                           "Only the active source may expose its return-to-top control")
            XCTAssertTrue(back.isHittable)
            capture("complete-\(company ? "company" : "model")-bottom")
            back.tap()
            let restored = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: first)
            wait(for: [restored], timeout: 5)
            XCTAssertFalse(back.isHittable)
            capture("complete-\(company ? "company" : "model")-returned")
            app.terminate()
        }
    }

    func testLastRowAndFooterRemainReachable() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let entries = (1...20).map { ["rank": $0,
            "name": "Fixture Model \($0) — Extended Reasoning And Multilingual Capabilities With A Long Context Window",
            "score": 90, "organization": "Google"] as [String: Any] }
        app.launchEnvironment["BENCHGAUGE_UI_MODEL_ENTRIES"] = String(data: try! JSONSerialization.data(withJSONObject: entries), encoding: .utf8)
        for dark in [false, true] {
            app.launchArguments = ["--ui-testing", "--full-board", "--preview-zh"] + (dark ? ["--dark"] : [])
            app.launch()
            XCTAssertTrue(app.segmentedControls["category"].waitForExistence(timeout: 10))
            let scroll = UIDevice.current.userInterfaceIdiom == .phone
                ? app.otherElements["cube-viewport"] : app.scrollViews.firstMatch
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
            capture("scrolling-\(dark ? "dark" : "light")")
            for _ in 0..<12 {
                let footer = app.buttons["share"].firstMatch
                if footer.isHittable && footer.frame.maxY <= app.frame.maxY - 30 { break }
                scroll.swipeUp()
            }
            let footer = app.buttons["share"].firstMatch
            capture("bottom-\(dark ? "dark" : "light")")
            XCTAssertTrue(footer.isHittable, "Footer must be reachable above the Home indicator")
            XCTAssertLessThanOrEqual(footer.frame.maxY, app.frame.maxY - 30)
            XCTAssertTrue(app.buttons["name-artificialAnalysis-20"].isHittable)
            XCTAssertEqual(scroll.frame.maxY, app.frame.maxY, accuracy: 1,
                           "Ranking viewport must continue through the bottom safe area")
            app.terminate()
        }
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

final class LeaderboardSourceDescriptionTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        print("[native-source] OS=\(UIDevice.current.systemVersion) scale=\(UIScreen.main.scale) idiom=\(UIDevice.current.userInterfaceIdiom.rawValue)")
    }
    override func tearDownWithError() throws { app.terminate() }

    func testExportedLeaderboardImages() {
        for chinese in [false, true] {
            for dark in [false, true] {
                app.launchArguments = ["--ui-testing", "--export-preview"] + (chinese ? ["--preview-zh"] : []) + (dark ? ["--dark"] : [])
                app.launch()
                XCTAssertTrue(app.otherElements["board-artificialAnalysis"].waitForExistence(timeout: 10))
                app.buttons["share"].tap()
                app.buttons["copy-screenshot"].tap()
                XCTAssertTrue(app.staticTexts[chinese ? "已复制到剪贴板" : "Copied to clipboard"].waitForExistence(timeout: 10))
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = "export-\(chinese ? "zh" : "en")-\(dark ? "dark" : "light")"
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }
    }

    func testNativeSourceDescriptionFrames() {
        for dark in [false, true] {
            for state in ["normal", "offline", "pending-boards"] {
                app.launchArguments = ["--ui-testing", "--preview-zh"]
                    + (dark ? ["--dark"] : []) + (state == "normal" ? [] : ["--\(state)"])
                app.launch()
                for kind in ["artificialAnalysis", "arenaText"] {
                    show(kind)
                    XCTAssertFalse(app.buttons["source-error-\(kind)"].exists)
                    for frame in 0..<3 {
                        if frame == 1 { app.buttons["refresh"].firstMatch.tap() }
                        Thread.sleep(forTimeInterval: 0.75)
                        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                        attachment.name = "source-\(state)-\(kind)-\(dark ? "dark" : "light")-frame-\(frame)"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
                app.terminate()
            }
        }
    }

    func testAutomaticRefreshFailureKeepsCachedRowsAndSourceDetailsQuiet() {
        for pending in [false, true] {
            app.launchArguments = ["--ui-testing", "--preview-zh", pending ? "--pending-boards" : "--offline"]
            app.launch()
            for (kind, label) in [("artificialAnalysis", "Artificial Analysis"), ("arenaText", "Text Arena")] {
                show(kind)
                let source = app.buttons["source-help-\(kind)"]
                XCTAssertTrue(source.waitForExistence(timeout: 10))
                if !pending {
                    XCTAssertTrue(app.buttons["name-\(kind)-1"].exists, "An automatic refresh failure must retain cached rows")
                }
                XCTAssertTrue(app.staticTexts["source-heading-\(kind)"].label.contains(label))
                XCTAssertFalse(app.buttons["source-error-\(kind)"].exists)
                XCTAssertFalse(source.label.contains("刷新失败"))
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = "silent-refresh-\(pending ? "empty" : "cached")-\(kind)"
                attachment.lifetime = .keepAlways
                add(attachment)
                source.tap()
                XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
                for text in ["刷新失败", "网络未连接", "请联网后重新刷新", "暂时无法更新这个来源"] {
                    XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.exists)
                }
                app.buttons["完成"].tap()
                XCTAssertTrue(source.exists)
            }
            app.terminate()
        }
    }

    func testSourceMetadataLayoutAndMissingPublicationTime() {
        for chinese in [true, false] {
            app.launchArguments = ["--ui-testing", "--full-board", "--source-times"]
                + (chinese ? ["--preview-zh"] : ["--dark"])
            app.launch()
            XCTAssertTrue(app.segmentedControls["category"].waitForExistence(timeout: 10))
            for (category, kind, missing) in [(chinese ? "综合" : "General", "artificialAnalysis", true),
                                            (chinese ? "编程" : "Coding", "artificialAnalysisCodingAgent", false)] {
                app.segmentedControls["category"].buttons[category].tap()
                show(kind)
                let heading = app.staticTexts["source-heading-\(kind)"]
                XCTAssertTrue(heading.waitForExistence(timeout: 5))
                XCTAssertEqual(heading.label, kind == "artificialAnalysis" ? "Artificial Analysis" : "Artificial Analysis 编程")
                if UIDevice.current.userInterfaceIdiom == .phone {
                    XCTAssertEqual(app.buttons["face-0"].label, chinese ? "任务测评" : "Task benchmarks")
                    XCTAssertEqual(app.buttons["face-1"].label, chinese ? "用户盲测" : "User votes")
                }
                let summary = app.buttons["source-help-\(kind)"]
                XCTAssertTrue(summary.exists)
                XCTAssertFalse(summary.label.contains("Artificial Analysis"))
                XCTAssertFalse(summary.label.contains(heading.label))
                let badge = app.descendants(matching: .any)["openness-\(kind)-1"].firstMatch
                XCTAssertTrue(badge.exists)
                XCTAssertEqual(badge.label, chinese ? "闭源" : "Closed")
                let phone = UIDevice.current.userInterfaceIdiom == .phone
                let times: XCUIElement? = phone
                    ? app.staticTexts["source-times-\(kind)"]
                    : app.buttons.matching(identifier: "refresh").allElementsBoundByIndex.first { $0.isHittable && $0.label.contains(chinese ? "抓取" : "Fetched") }
                XCTAssertNotNil(times)
                if phone {
                    XCTAssertFalse(times?.label.contains("\n") ?? true)
                    XCTAssertFalse(times?.label.contains(chinese ? "抓取" : "Fetched") ?? true)
                    XCTAssertFalse(times?.label.contains("—") ?? true)
                } else { XCTAssertEqual(times?.label.contains(chinese ? "更新 —" : "Updated —"), missing) }
                if let times {
                    let top = min(summary.frame.minY, times.frame.minY)
                    let bottom = max(summary.frame.maxY, times.frame.maxY)
                    // AX reports the caption's ink bounds; the regular iPad
                    // header font adds a 2.5-point inset to the layout gap.
                    XCTAssertEqual(heading.frame.minY - bottom, 24, accuracy: 3)
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        XCTAssertEqual(top - app.buttons["face-0"].frame.maxY, 24, accuracy: 2)
                    }
                }
                for frame in 0..<3 {
                    if frame == 1 { times?.tap() }
                    Thread.sleep(forTimeInterval: 0.5)
                    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    attachment.name = "metadata-\(kind)-\(chinese ? "zh-light" : "en-dark")-frame-\(frame)"
                    attachment.lifetime = .keepAlways; add(attachment)
                }
            }
            app.terminate()
        }
    }

    func testPhoneHeaderScrollAndFooterControls() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        app.launchArguments = ["--ui-testing", "--full-board", "--preview-zh", "--reduce-motion"]
        app.launch()
        let grouping = app.segmentedControls["grouping"]
        let subtitle = app.buttons["quota-tracking-help"]
        XCTAssertTrue(grouping.waitForExistence(timeout: 10))
        XCTAssertTrue(subtitle.exists)
        XCTAssertLessThan(abs(grouping.frame.midY - subtitle.frame.midY), 20)
        XCTAssertTrue(app.buttons["face-0"].isHittable)
        for _ in 0..<6 { app.swipeUp() }
        XCTAssertTrue(app.buttons["appearance-menu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["language-menu"].exists)
        XCTAssertFalse(app.buttons["attribution"].exists)
        XCTAssertFalse(app.buttons["license"].exists)
        XCTAssertFalse(app.buttons["face-0"].isHittable)
        let footer = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); footer.name = "mobile-clean-footer"; footer.lifetime = .keepAlways; add(footer)
        app.buttons["appearance-menu"].tap()
        XCTAssertTrue(app.buttons["深色"].waitForExistence(timeout: 5))
        app.buttons["深色"].tap()
        let dark = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); dark.name = "mobile-dark-footer"; dark.lifetime = .keepAlways; add(dark)
    }

    private func show(_ kind: String) {
        if UIDevice.current.userInterfaceIdiom == .phone {
            app.buttons[kind == "arenaText" ? "face-1" : "face-0"].tap()
        }
        XCTAssertTrue(app.otherElements["board-\(kind)"].waitForExistence(timeout: 10))
    }
}

final class LeaderboardCategoryTabTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }
    override func tearDownWithError() throws {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }
    func testQuotaTrackingHelp() {
        for chinese in [true, false] {
            app.launchArguments = ["--ui-testing", "--offline"] + (chinese ? ["--preview-zh"] : ["--dark"])
            app.launch()
            let help = app.buttons["quota-tracking-help"].firstMatch
            XCTAssertTrue(help.waitForExistence(timeout: 10))
            XCTAssertEqual(help.label, chinese ? "双榜对照 & 余量追踪" : "Dual boards & quota tracking")
            let heading = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            heading.name = "quota-help-\(chinese ? "zh-system" : "en-dark")-heading"
            heading.lifetime = .keepAlways; add(heading)
            let alert = app.alerts.firstMatch
            // Outer layout padding is not part of the visible help label.
            help.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                .withOffset(CGVector(dx: 0, dy: -2)).tap()
            XCTAssertFalse(alert.exists, "Header padding must not open quota help")
            // ViewThatFits can omit the decorative title from the iPad accessibility tree.
            // Tap its real position immediately to the left of the subtitle on both devices.
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: help.frame.minX - 20, dy: help.frame.midY)).tap()
            XCTAssertFalse(alert.exists, "The app title must not open quota help")
            let boundary = UIDevice.current.userInterfaceIdiom == .phone
                ? app.segmentedControls["grouping"].frame.minX
                : app.buttons["refresh"].firstMatch.frame.minX
            let blankStart = help.frame.maxX + 12
            if blankStart + 8 < boundary {
                app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: (blankStart + boundary) / 2, dy: help.frame.midY)).tap()
                XCTAssertFalse(alert.exists, "Blank header space must not open quota help")
            }
            help.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            let message = chinese
                ? "余量追踪目前在 Mac 和 Windows 版提供，可集中查看模型的剩余额度与使用进度。请在电脑上打开 AI 天梯使用这项功能。"
                : "Quota tracking is available in AI BenchGauge for Mac and Windows. Open the desktop app to view your models’ remaining quotas and usage progress."
            XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label == %@", message)).firstMatch.exists)
            let info = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            info.name = "quota-help-\(chinese ? "zh-system" : "en-dark")-dialog"
            info.lifetime = .keepAlways; add(info)
            alert.buttons[chinese ? "知道了" : "Got it"].tap()
            XCTAssertFalse(alert.exists)
            XCTAssertTrue(help.exists)
            if chinese {
                // The single-line label keeps the question mark at its trailing edge.
                help.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
                XCTAssertTrue(alert.waitForExistence(timeout: 5), "The question mark must still open help")
                alert.buttons["知道了"].tap()
            }
            app.terminate()
        }
    }
    func testDynamicCountryFrames() {
        for chinese in [true, false] {
            app.launchArguments = ["--ui-testing", "--offline"] + (chinese ? ["--preview-zh"] : ["--dark"])
            app.launchEnvironment["BENCHGAUGE_UI_MODEL_ENTRIES"] = #"""
            [{"rank":1,"name":"Utopai Video","score":100,"organization":"Utopai Studios","developerCountry":{"key":"utopaistudios","countryCode":"US"}},
             {"rank":2,"name":"SkyReels","score":99,"organization":"Skywork AI","developerCountry":{"key":"skyworkai","countryCode":"SG"}},
             {"rank":3,"name":"Agnes Video","score":98,"organization":"Sapiens AI","developerCountry":{"key":"sapiensai","countryCode":"SG"}},
             {"rank":4,"name":"Future Video","score":97,"organization":"New Maker","developerCountry":{"key":"newmaker","countryCode":"JP"}},
             {"rank":5,"name":"Unknown Video","score":96,"organization":"Unknown Maker"}]
            """#
            app.launch()
            XCTAssertTrue(app.segmentedControls["category"].waitForExistence(timeout: 10))
            for company in [false, true] {
                if company { app.segmentedControls["grouping"].buttons[chinese ? "公司" : "Companies"].tap() }
                for frame in 0..<3 {
                    if frame == 1 { app.buttons["refresh"].firstMatch.tap() }
                    Thread.sleep(forTimeInterval: 0.75)
                    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    attachment.name = "country-\(chinese ? "zh-light" : "en-dark")-\(company ? "company" : "model")-frame-\(frame)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
            app.terminate()
        }
    }
    func testModelLogoAndCompanyLogoFrames() {
        for chinese in [true, false] {
            app.launchArguments = ["--ui-testing", "--offline"] + (chinese ? ["--preview-zh"] : ["--dark"])
            app.launchEnvironment["BENCHGAUGE_UI_MODEL_ENTRIES"] = modelLogoEntries
            app.launch()
            XCTAssertTrue(app.segmentedControls["category"].waitForExistence(timeout: 10))
            for company in [false, true] {
                if company { app.segmentedControls["grouping"].buttons[chinese ? "公司" : "Companies"].tap() }
                for frame in 0..<3 {
                    if frame == 1 { app.buttons["refresh"].firstMatch.tap() }
                    Thread.sleep(forTimeInterval: 0.75)
                    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    attachment.name = "model-logo-\(chinese ? "zh-light" : "en-dark")-\(company ? "company" : "model")-frame-\(frame)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
            app.terminate()
        }
    }
    func testMobileLogoCornerFrames() {
        for chinese in [true, false] {
            app.launchArguments = ["--ui-testing", "--offline"] + (chinese ? ["--preview-zh"] : ["--dark"])
            app.launchEnvironment["BENCHGAUGE_UI_MODEL_ENTRIES"] = mobileLogoCornerEntries
            app.launch()
            XCTAssertTrue(app.segmentedControls["category"].waitForExistence(timeout: 10))
            for company in [false, true] {
                if company { app.segmentedControls["grouping"].buttons[chinese ? "公司" : "Companies"].tap() }
                for frame in 0..<3 {
                    if frame == 1 { app.buttons["refresh"].firstMatch.tap() }
                    Thread.sleep(forTimeInterval: 0.75)
                    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    attachment.name = "mobile-logo-corners-\(chinese ? "zh-light" : "en-dark")-\(company ? "company" : "model")-frame-\(frame)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
            app.terminate()
        }
    }
    func testBrandDiscoveryFrames() {
        for chinese in [true, false] {
            app.launchArguments = ["--ui-testing", "--brand-discovery", "--offline"] + (chinese ? ["--preview-zh"] : ["--dark"])
            app.launch()
            XCTAssertTrue(app.segmentedControls["category"].waitForExistence(timeout: 10))
            for landscape in [false, true] {
                orient(landscape)
                for frame in 0..<3 {
                    if frame == 1 { app.buttons["refresh"].firstMatch.tap() }
                    Thread.sleep(forTimeInterval: 0.75)
                    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    attachment.name = "brands-\(chinese ? "zh-light" : "en-dark")-\(landscape ? "landscape" : "portrait")-frame-\(frame)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
    }
    func testCategoryTabLayoutFrames() {
        for chinese in [true, false] {
            app.launchArguments = ["--ui-testing"] + (chinese ? ["--preview-zh"] : ["--dark"])
            app.launch()
            XCTAssertTrue(app.segmentedControls["category"].waitForExistence(timeout: 10))
            for landscape in [false, true] {
                orient(landscape)
                for frame in 0..<3 {
                    if frame == 1 { app.buttons["refresh"].firstMatch.tap() }
                    Thread.sleep(forTimeInterval: 0.75)
                    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    attachment.name = "category-\(chinese ? "zh-light" : "en-dark")-\(landscape ? "landscape" : "portrait")-frame-\(frame)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
    }
    func testOpennessColumnAndCompanyAggregation() {
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let kind = "artificialAnalysis"
        XCTAssertTrue(app.buttons["openness-filter-" + kind].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["openness-filter-" + kind].label.contains("Source"))
        XCTAssertEqual(app.buttons["openness-filter-" + kind].value as? String, "All sources")
        XCTAssertEqual(app.staticTexts["openness-" + kind + "-1"].label, "Closed")
        XCTAssertEqual(app.staticTexts["openness-" + kind + "-2"].label, "Open")
        XCTAssertEqual(app.staticTexts["openness-" + kind + "-3"].label, "—")
        app.segmentedControls["grouping"].buttons.element(boundBy: 1).tap()
        XCTAssertEqual(app.staticTexts["openness-" + kind + "-1"].label, "—")
        app.segmentedControls["grouping"].buttons.element(boundBy: 0).tap()
        XCTAssertEqual(app.staticTexts["openness-" + kind + "-2"].label, "Open")
    }
    func testSourceFilterMenuAndIntersection() {
        app.launchArguments = ["--ui-testing", "--offline"]
        app.launch()
        let kind = "artificialAnalysis"
        let picker = app.buttons["openness-filter-" + kind]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let before = XCTAttachment(screenshot: app.screenshot()); before.name = "source-filter-all"; before.lifetime = .keepAlways; add(before)
        func choose(_ value: String) {
            picker.tap()
            let option = app.buttons["openness-option-" + kind + "-" + value]
            XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
        }
        choose("open")
        XCTAssertEqual(picker.value as? String, "Open")
        XCTAssertEqual(app.descendants(matching: .any)["openness-" + kind + "-2"].label, "Open")
        XCTAssertFalse(app.descendants(matching: .any)["openness-" + kind + "-1"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["openness-" + kind + "-3"].exists)
        app.buttons["country-" + kind].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "United States")).firstMatch.tap()
        XCTAssertFalse(app.descendants(matching: .any)["openness-" + kind + "-2"].exists)
        app.buttons["country-" + kind].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "All countries")).firstMatch.tap()
        app.segmentedControls["grouping"].buttons.element(boundBy: 1).tap()
        XCTAssertEqual(app.descendants(matching: .any)["openness-" + kind + "-1"].label, "—")
        app.segmentedControls["grouping"].buttons.element(boundBy: 0).tap()
        choose("closed")
        XCTAssertEqual(app.descendants(matching: .any)["openness-" + kind + "-1"].label, "Closed")
        choose("unknown")
        XCTAssertEqual(app.descendants(matching: .any)["openness-" + kind + "-3"].label, "—")
        XCTAssertFalse(app.descendants(matching: .any)["openness-" + kind + "-1"].exists)
        choose("all")
        XCTAssertEqual(app.descendants(matching: .any)["openness-" + kind + "-2"].label, "Open")
        let after = XCTAttachment(screenshot: app.screenshot()); after.name = "source-filter-reset"; after.lifetime = .keepAlways; add(after)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertEqual(app.buttons["openness-filter-arenaText"].value as? String, "All sources")
        }
    }
    func testCategoryTabsUseRequestedWidths() {
        app.launchArguments = ["--ui-testing", "--preview-zh"]
        app.launch()
        XCTAssertTrue(app.segmentedControls["category"].waitForExistence(timeout: 10))
        for landscape in [false, true] {
            orient(landscape)
            let category = app.segmentedControls["category"]
            let frame = category.frame
            if UIDevice.current.userInterfaceIdiom == .phone {
                let viewport = app.otherElements["cube-viewport"].frame
                XCTAssertEqual(frame.minX, viewport.minX, accuracy: 2)
                XCTAssertEqual(frame.maxX, viewport.maxX, accuracy: 2)
            } else {
                XCTAssertEqual(frame.width, 360, accuracy: 2)
                XCTAssertEqual(frame.midX, app.windows.firstMatch.frame.midX, accuracy: 2)
            }
            let segments = category.buttons.allElementsBoundByIndex
            XCTAssertEqual(segments.count, 4)
            for segment in segments { XCTAssertEqual(segment.frame.width, segments[0].frame.width, accuracy: 2) }
            segments[1].tap()
            XCTAssertTrue(segments[1].isSelected)
            segments[0].tap()
        }
    }
    private func orient(_ landscape: Bool) {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let category = app.segmentedControls["category"]
        let predicate = NSPredicate { _, _ in
            let frame = self.app.windows.firstMatch.frame
            return (frame.width > frame.height) == landscape && category.isHittable
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: category)], timeout: 10), .completed)
        Thread.sleep(forTimeInterval: 1)
    }
}

final class LeaderboardPadTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad layout suite")
        print("[native] iPad OS=\(UIDevice.current.systemVersion) scale=\(UIScreen.main.scale) model=\(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown")")
    }
    override func tearDownWithError() throws {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }
    func testCategoriesGroupingAndCountryFilter() {
        app.launch()
        XCTAssertTrue(app.otherElements["board-artificialAnalysis"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["UPDATED"].exists)
        XCTAssertTrue(app.staticTexts["AI BenchGauge"].exists)
        XCTAssertFalse(app.staticTexts["Fetched"].exists)
        app.segmentedControls["category"].buttons["Coding"].tap()
        XCTAssertTrue(app.otherElements["board-codeArenaWebDev"].waitForExistence(timeout: 5))
        app.segmentedControls["grouping"].buttons["Companies"].tap()
        XCTAssertTrue(app.buttons["name-artificialAnalysisCodingAgent-1"].exists)
        app.buttons["score-artificialAnalysisCodingAgent-1"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Score uses the strongest model")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["country-artificialAnalysisCodingAgent"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "China")).firstMatch.tap()
        XCTAssertTrue(app.buttons["name-artificialAnalysisCodingAgent-1"].label.contains("DeepSeek"))
        capture("portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForLayout(landscape: true)
        capture("landscape")
        assertCategorySegments()
        app.buttons["name-artificialAnalysisCodingAgent-1"].tap()
        XCTAssertTrue(app.staticTexts["Copied DeepSeek"].waitForExistence(timeout: 5))
    }
    func testOfflineResultsAndLicenseAndScreenshot() {
        app.launchArguments.append("--offline")
        app.launch()
        XCTAssertTrue(app.buttons["name-artificialAnalysis-1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["source-error-artificialAnalysis"].exists)
        capture("offline")
        app.buttons["source-help-artificialAnalysis"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "No internet connection")).firstMatch.exists)
        capture("offline-details")
        app.buttons["Done"].tap()
        app.buttons["license"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Permission is hereby granted")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["open-source-notices"].tap()
        XCTAssertTrue(app.segmentedControls["license-section"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["license-section"].buttons["Open-source notices"].isSelected)
        capture("notices")
        app.buttons["Done"].tap()
        app.buttons["share"].tap()
        XCTAssertTrue(app.buttons["Copy image"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save to Photos"].exists)
        capture("screenshot-options")
        app.buttons["Copy image"].tap()
        XCTAssertTrue(app.staticTexts["Copied to clipboard"].waitForExistence(timeout: 10))
        assertCategorySegments()
        capture("screenshot-feedback")
    }
    func testChineseInterfacePreviews() {
        app.launchArguments.append("--preview-zh")
        app.launch()
        XCTAssertTrue(app.otherElements["board-artificialAnalysis"].waitForExistence(timeout: 10))
        waitForLayout(landscape: false)
        XCTAssertTrue(app.staticTexts["更新时间"].exists)
        XCTAssertTrue(app.staticTexts["AI 天梯"].exists)
        XCTAssertFalse(app.staticTexts["获取于"].exists)
        capture("zh-models-portrait")
        app.segmentedControls["grouping"].buttons["公司"].tap()
        capture("zh-companies-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForLayout(landscape: true)
        capture("zh-companies-landscape")
        app.buttons["source-help-artificialAnalysis"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "两榜分数不直接互比")).firstMatch.waitForExistence(timeout: 5))
        capture("zh-source-details")
    }
    func testFullBoardLongNamesUnknownCountryAndLanguages() {
        app.launchArguments += ["--full-board", "--dark"]
        app.launch()
        XCTAssertTrue(app.buttons["name-artificialAnalysis-1"].waitForExistence(timeout: 10))
        capture("full-long-dark-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForLayout(landscape: true)
        capture("full-long-dark-landscape")
        app.buttons["country-artificialAnalysis"].tap()
        app.buttons["Unknown country"].tap()
        XCTAssertTrue(app.buttons["name-artificialAnalysis-20"].exists)
        capture("unknown-country")
        // Footer may be below the fold with twenty real rows.
        scrollToFooter()
        app.segmentedControls["language"].buttons["繁中"].tap()
        XCTAssertTrue(app.staticTexts["更新時間"].exists)
        XCTAssertTrue(app.staticTexts["AI 天梯"].exists)
        capture("traditional-footer-dark")
        scrollToHeader()
        waitForLayout(landscape: true)
        capture("traditional-dark")
        scrollToFooter()
        app.segmentedControls["language"].buttons["简中"].tap()
        XCTAssertTrue(app.staticTexts["更新时间"].exists)
        scrollToHeader()
        app.segmentedControls["category"].buttons["图片"].tap()
        XCTAssertTrue(app.otherElements["board-arenaTextToImage"].waitForExistence(timeout: 5))
        capture("image-dark")
        app.segmentedControls["category"].buttons["视频"].tap()
        XCTAssertTrue(app.otherElements["board-arenaTextToVideo"].waitForExistence(timeout: 5))
        capture("video-dark")
    }
    private func scrollToHeader() {
        for _ in 0..<8 {
            if app.segmentedControls["category"].isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(app.segmentedControls["category"].isHittable)
    }
    private func scrollToFooter() {
        for _ in 0..<8 {
            if app.segmentedControls["language"].isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(app.segmentedControls["language"].isHittable)
    }
    private func assertCategorySegments() {
        let segments = ["General", "Coding", "Image", "Video"].map { app.segmentedControls["category"].buttons[$0].frame }
        for (left, right) in zip(segments, segments.dropFirst()) {
            XCTAssertLessThan(left.maxX, right.maxX)
            XCTAssertEqual(left.width, right.width, accuracy: 2)
        }
    }
    private func waitForLayout(landscape: Bool) {
        let window = app.windows.firstMatch
        let predicate = NSPredicate { _, _ in
            let frame = window.frame
            return frame.width > 0 && frame.height > 0 && (frame.width > frame.height) == landscape
                && self.app.segmentedControls["category"].isHittable
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: window)], timeout: 10), .completed)
        var previous = app.segmentedControls["category"].frame
        var stableFrames = 0
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.3)
            let current = app.segmentedControls["category"].frame
            stableFrames = current == previous ? stableFrames + 1 : 0
            previous = current
            if stableFrames >= 3 { return }
        }
        XCTFail("iPad controls did not settle after rotation")
    }
    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 0.75)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

final class LeaderboardPhoneTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "iPhone cube suite")
        print("[native] iPhone OS=\(UIDevice.current.systemVersion) scale=\(UIScreen.main.scale) model=\(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown")")
        XCUIDevice.shared.orientation = .portrait
    }
    override func tearDownWithError() throws {
        // Avoid asking SpringBoard to idle for operations already completed by
        // a test; redundant orientation resets can stall simulator teardown.
        if app.state != .notRunning { app.terminate() }
        if XCUIDevice.shared.orientation != .portrait { XCUIDevice.shared.orientation = .portrait }
    }
    func testColumnHeadersStayPinnedAndFiltersRemainUsable() {
        let entries = (1...60).map { ["rank": $0, "name": "Fixture Model \($0)",
            "score": 100 - $0, "organization": "Fixture Maker \($0)"] as [String: Any] }
        app.launchEnvironment["BENCHGAUGE_UI_MODEL_ENTRIES"] = String(data: try! JSONSerialization.data(withJSONObject: entries), encoding: .utf8)
        for dark in [false, true] {
            app.launchArguments = ["--ui-testing", "--full-board", "--reduce-motion"]
                + (dark ? ["--dark", "--preview-zh", "--preview-companies"] : [])
            app.launch()
            waitForFace("artificialAnalysis")
            let viewport = app.otherElements["cube-viewport"]
            var comparisonRank: Int?
            for face in [0, 1] {
                if face == 1 {
                    swipe(left: true)
                    XCTAssertTrue(app.otherElements["board-arenaText"].waitForExistence(timeout: 10))
                    if let rank = comparisonRank {
                        let row = app.buttons["name-arenaText-\(rank)"]
                        XCTAssertTrue(row.waitForExistence(timeout: 5))
                        XCTAssertTrue(row.isHittable)
                        XCTAssertGreaterThanOrEqual(row.frame.minY,
                            app.buttons["country-arenaText"].frame.maxY,
                            "The compared rank must not disappear behind the pinned header")
                    }
                }
                let kind = face == 0 ? "artificialAnalysis" : "arenaText"
                let country = app.buttons["country-" + kind]
                // A first gesture can finish launch-time layout; scroll far enough
                // to pass the metadata before checking the pinned position.
                for _ in 0..<3 {
                    viewport.swipeUp()
                    if country.frame.maxY < viewport.frame.minY + 65 { break }
                }
                let openness = app.buttons["openness-filter-" + kind]
                XCTAssertTrue(country.isHittable, "The pinned country filter must remain tappable")
                XCTAssertTrue(openness.isHittable)
                XCTAssertGreaterThanOrEqual(country.frame.minY, viewport.frame.minY - 1)
                XCTAssertLessThan(country.frame.maxY, viewport.frame.minY + 65)
                let pinnedY = country.frame.minY
                viewport.swipeUp()
                XCTAssertEqual(country.frame.minY, pinnedY, accuracy: 2)
                if face == 0 {
                    let top = country.frame.maxY + 12
                    let bottom = viewport.frame.maxY
                    let names = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "name-artificialAnalysis-")).allElementsBoundByIndex
                    comparisonRank = names.first { row in
                        let frame = row.frame
                        return frame.minY >= top && frame.maxY <= bottom && row.isHittable
                    }.flatMap { Int($0.identifier.split(separator: "-").last ?? "") }
                    XCTAssertNotNil(comparisonRank)
                }
                capture("pinned-\(dark ? "dark-company" : "light-model")-\(kind)")
                if face == 1 {
                    openness.tap()
                    let all = app.buttons["openness-option-" + kind + "-all"]
                    XCTAssertTrue(all.waitForExistence(timeout: 5))
                    all.tap()
                    XCTAssertTrue(country.isHittable)
                }
            }
            // Selecting a filter intentionally resets the comparison to the top.
            let first = app.buttons["name-arenaText-1"]
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            XCTAssertTrue(first.isHittable)
            capture("pinned-\(dark ? "dark-company" : "light-model")-returned")
            app.terminate()
        }
    }
    func testSwipeAndTapBothFacesThenRefresh() {
        app.launch()
        waitForFace("artificialAnalysis")
        capture("iphone-shown")
        XCTAssertFalse(app.otherElements["board-arenaText"].exists)
        let before = app.otherElements["cube-viewport"].frame
        swipe(left: true)
        waitForFace("arenaText")
        capture("iphone-second-face-settled")
        XCTAssertEqual(app.otherElements["cube-viewport"].frame, before)
        swipe(left: false)
        waitForFace("artificialAnalysis")
        app.buttons["refresh"].tap()
        waitForFace("artificialAnalysis")
        capture("iphone-refreshed")
        app.buttons["face-1"].tap()
        waitForFace("arenaText")
        app.segmentedControls["category"].buttons["Coding"].tap()
        waitForFace("codeArenaWebDev")
        capture("iphone-coding-second-face")
        app.buttons["face-0"].tap()
        waitForFace("artificialAnalysisCodingAgent")
        app.segmentedControls["grouping"].buttons["Companies"].tap()
        app.buttons["score-artificialAnalysisCodingAgent-1"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Score uses the strongest model")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        capture("iphone-coding-companies")
        app.buttons["country-artificialAnalysisCodingAgent"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "China")).firstMatch.tap()
        XCTAssertTrue(app.buttons["name-artificialAnalysisCodingAgent-1"].label.contains("DeepSeek"))
        app.buttons["face-1"].tap()
        waitForFace("codeArenaWebDev")
        XCTAssertEqual(app.buttons["country-codeArenaWebDev"].value as? String, "All countries")
        capture("iphone-independent-filter")
    }
    func testDiagonalScrollingDoesNotSwitchSourcesAndNextHorizontalSwipeWorks() {
        app.launchArguments += ["--full-board"]
        app.launch()
        waitForFace("artificialAnalysis")
        let viewport = app.otherElements["cube-viewport"]
        for (startX, endX) in [(0.8, 0.2), (0.2, 0.8)] {
            let start = viewport.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.75))
            let end = viewport.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: 0.75))
                .withOffset(CGVector(dx: 0, dy: -viewport.frame.width * 0.4))
            start.press(forDuration: 0.08, thenDragTo: end)
            XCTAssertTrue(app.buttons["face-0"].isSelected)
            XCTAssertFalse(app.otherElements["board-arenaText"].exists)
        }
        XCTAssertFalse(app.buttons["name-artificialAnalysis-1"].isHittable,
                       "Diagonal drags must still scroll the native list")
        capture("iphone-diagonal-scroll-retains-source")
        swipe(left: true)
        XCTAssertTrue(app.otherElements["board-arenaText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["face-1"].isSelected)
        capture("iphone-horizontal-switch-after-scroll")
    }
    @MainActor
    func testLongPressTruncatedNameShowsBubbleWithoutCopying() {
        app.launchArguments += ["--full-board", "--wrapped-names", "--preview-zh", "--reduce-motion"]
        app.launch()
        waitForFace("artificialAnalysis")
        let name = app.buttons["name-artificialAnalysis-1"]
        let before = UIPasteboard.general.changeCount
        name.press(forDuration: 0.8)
        let fullName = app.staticTexts["full-name-name-artificialAnalysis-1"]
        XCTAssertTrue(fullName.waitForExistence(timeout: 5))
        capture("truncated-name-bubble")
        XCTAssertEqual(fullName.label, "GPT Fixture — Very Long Model Name With Extended Reasoning And Multilingual Capabilities")
        XCTAssertEqual(UIPasteboard.general.changeCount, before)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.1)).tap()
        XCTAssertFalse(fullName.exists)
        name.tap()
        XCTAssertTrue(app.staticTexts["已复制 GPT Fixture — Very Long Model Name With Extended Reasoning And Multilingual Capabilities"].waitForExistence(timeout: 3))
        XCTAssertGreaterThan(UIPasteboard.general.changeCount, before)
        app.buttons["name-artificialAnalysis-4"].press(forDuration: 0.8)
        XCTAssertFalse(app.staticTexts["full-name-name-artificialAnalysis-4"].exists)
    }
    @MainActor
    func testSwipingFromModelNameDoesNotCopyButTappingStillDoes() {
        app.launchArguments += ["--full-board", "--wrapped-names"]
        app.launch()
        waitForFace("artificialAnalysis")
        let beforeSwipe = UIPasteboard.general.changeCount
        let viewport = app.otherElements["cube-viewport"]
        let firstName = app.buttons["name-artificialAnalysis-1"]
        let leftStart = firstName.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        leftStart.press(forDuration: 0.08, thenDragTo: leftStart.withOffset(CGVector(dx: -viewport.frame.width * 0.6, dy: 0)))
        waitForFace("arenaText")
        XCTAssertEqual(UIPasteboard.general.changeCount, beforeSwipe,
                       "A swipe starting on a model name must not copy it")
        capture("name-swipe-arena")

        let secondName = app.buttons["name-arenaText-1"]
        let rightStart = secondName.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        rightStart.press(forDuration: 0.08, thenDragTo: rightStart.withOffset(CGVector(dx: viewport.frame.width * 0.6, dy: 0)))
        waitForFace("artificialAnalysis")
        XCTAssertEqual(UIPasteboard.general.changeCount, beforeSwipe,
                       "The reverse swipe must not copy either")
        capture("name-swipe-return")

        let shortStart = app.buttons["name-artificialAnalysis-1"].coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        shortStart.press(forDuration: 0.08, thenDragTo: shortStart.withOffset(CGVector(dx: -40, dy: 0)),
                         withVelocity: .slow, thenHoldForDuration: 0.3)
        waitForFace("artificialAnalysis")
        XCTAssertEqual(UIPasteboard.general.changeCount, beforeSwipe,
                       "A short drag that returns to the same board must not copy")

        let beforeTap = UIPasteboard.general.changeCount
        app.buttons["name-artificialAnalysis-1"].tap()
        XCTAssertTrue(app.staticTexts["Copied GPT Fixture — Very Long Model Name With Extended Reasoning And Multilingual Capabilities"].waitForExistence(timeout: 3))
        XCTAssertGreaterThan(UIPasteboard.general.changeCount, beforeTap,
                             "An ordinary tap must still write the name to the clipboard")
    }
    func testOfflineLicenseScreenshotAndLanguages() {
        app.launchArguments.append("--offline")
        app.launch()
        XCTAssertTrue(app.buttons["name-artificialAnalysis-1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["source-error-artificialAnalysis"].exists)
        capture("iphone-offline")
        app.buttons["source-help-artificialAnalysis"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "No internet connection")).firstMatch.exists)
        capture("iphone-offline-details")
        app.buttons["Done"].tap()
        scrollToFooter()
        XCTAssertFalse(app.buttons["attribution"].exists)
        XCTAssertFalse(app.buttons["license"].exists)
        XCTAssertFalse(app.staticTexts["Cloyd Lau"].exists)
        XCTAssertTrue(app.buttons["appearance-menu"].exists)
        XCTAssertTrue(app.buttons["language-menu"].exists)
        XCTAssertFalse(app.buttons["face-0"].isHittable)
        capture("iphone-clean-footer")
        app.buttons["share"].tap()
        XCTAssertTrue(app.buttons["Copy image"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save to Photos"].exists)
        capture("iphone-screenshot-options")
        app.buttons["Copy image"].tap()
        XCTAssertTrue(app.staticTexts["Copied to clipboard"].waitForExistence(timeout: 10))
        assertCategorySegments()
        capture("iphone-screenshot-feedback")
        waitForButton("language-menu")
        app.buttons["language-menu"].tap()
        app.buttons["简中"].tap()
        XCTAssertTrue(app.staticTexts["AI 天梯"].exists)
        XCTAssertFalse(app.staticTexts["获取于"].exists)
        app.segmentedControls["category"].buttons["图片"].tap()
        waitForFace("artificialAnalysisTextToImage")
        capture("iphone-zh-image")
        app.buttons["face-1"].tap()
        waitForFace("arenaTextToImage")
        capture("iphone-zh-image-second-face")
        scrollToFooter()
        waitForButton("language-menu")
        app.buttons["language-menu"].tap()
        app.buttons["繁中"].tap()
        app.segmentedControls["category"].buttons["視頻"].tap()
        waitForFace("arenaTextToVideo")
        capture("iphone-traditional-video")
    }
    func testScreenshotPhotoSaveFeedback() {
        app.launch()
        waitForFace("artificialAnalysis")
        scrollToFooter()
        app.buttons["share"].tap()
        XCTAssertTrue(app.buttons["Copy image"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save to Photos"].exists)
        XCTAssertFalse(app.staticTexts["Copied to clipboard"].exists)
        capture("iphone-photo-actions")
        app.buttons["Save to Photos"].tap()

        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.exists {
            let allow = permission.buttons.matching(NSPredicate(format:
                "NOT (label CONTAINS[c] %@ OR label CONTAINS %@)", "Don", "不允")).firstMatch
            XCTAssertTrue(allow.exists, "The system must offer add-only Photos access")
            allow.tap()
        }
        let denied = app.alerts["Cannot save to Photos"]
        let saved = app.staticTexts["Saved to Photos"]
        let feedback = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            saved.exists || denied.exists
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [feedback], timeout: 15), .completed)
        if saved.exists {
            capture("iphone-photo-saved")
        } else {
            XCTAssertTrue(denied.exists)
            XCTAssertTrue(app.buttons["Open Settings"].exists)
            capture("iphone-photo-denied")
            app.buttons["Cancel"].tap()
        }
        // Copy remains independent of the user's Photos permission.
        app.buttons["share"].tap()
        app.buttons["Copy image"].tap()
        XCTAssertTrue(app.staticTexts["Copied to clipboard"].waitForExistence(timeout: 10))
    }
    func testLongBoardComparisonRankAndLandscape() {
        app.launchArguments += ["--full-board", "--dark", "--preview-zh"]
        app.launch()
        waitForFace("artificialAnalysis")
        XCTAssertFalse(app.buttons["share"].isHittable, "The footer must stay below the full board")
        capture("iphone-long-dark")
        let viewport = app.otherElements["cube-viewport"]
        viewport.swipeUp()
        viewport.swipeUp()
        let visible = (2...19).first { rank in
            let row = app.buttons["name-artificialAnalysis-\(rank)"]
            return row.isHittable && row.frame.minY >= viewport.frame.minY && row.frame.minY < viewport.frame.midY
        }
        XCTAssertNotNil(visible)
        let firstY = visible.map { app.buttons["name-artificialAnalysis-\($0)"].frame.minY }
        capture("iphone-scrolled-first-face")
        app.buttons["face-1"].tap()
        waitForFace("arenaText")
        if let rank = visible, let firstY {
            let row = app.buttons["name-arenaText-\(rank)"]
            XCTAssertTrue(row.isHittable, "Keep the same rank visible for comparison")
            XCTAssertEqual(row.frame.minY, firstY, accuracy: 48, "The compared rank must stay near the same vertical position, not return to rank 1")
        }
        capture("iphone-scrolled-second-face")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.windows.firstMatch.frame.width > self.app.windows.firstMatch.frame.height
        }, object: app.windows.firstMatch)], timeout: 10), .completed)
        capture("iphone-landscape-dark")
        XCTAssertTrue(app.buttons["face-0"].isHittable)
        scrollToFooter()
        XCTAssertTrue(app.buttons["share"].isHittable)
        capture("iphone-landscape-scrolled-footer")
        assertCategorySegments()
        app.buttons["face-0"].tap()
        waitForFace("artificialAnalysis")
        app.segmentedControls["grouping"].buttons["公司"].tap()
        XCTAssertFalse(app.buttons["share"].isHittable, "Returning to the top must scroll the footer out of view")
        XCTAssertTrue(app.buttons["country-artificialAnalysis"].isHittable, "Grouping changes must return to the top")
        XCTAssertTrue(app.buttons["name-artificialAnalysis-1"].isHittable)
        capture("iphone-reset-companies-landscape")
    }
    func testSourceSwitchKeepsTopAndScrolledRowsVisible() {
        checkSourceSwitchVisibility(dark: false)
    }
    func testSourceSwitchKeepsTopAndScrolledRowsVisibleInDarkMode() {
        checkSourceSwitchVisibility(dark: true)
    }
    private func checkSourceSwitchVisibility(dark: Bool) {
        app.launchArguments.append("--full-board")
        if dark { app.launchArguments.append("--dark") }
        app.launch()
        waitForFace("artificialAnalysis")
        let appearance = dark ? "dark" : "light"
        capture("source-switch-\(appearance)-aa-top")
        app.buttons["face-1"].tap()
        waitForFace("arenaText")
        capture("source-switch-\(appearance)-arena-top")
        let arenaHeaderVisible = app.buttons["source-help-arenaText"].isHittable
            && app.buttons["country-arenaText"].isHittable
        app.buttons["face-0"].tap()
        waitForFace("artificialAnalysis")
        let viewport = app.otherElements["cube-viewport"]
        viewport.swipeUp()
        let rank = (2...19).first { rank in
            let row = app.buttons["name-artificialAnalysis-\(rank)"]
            return row.isHittable && row.frame.minY >= viewport.frame.minY
                && row.frame.minY < viewport.frame.midY
        }
        XCTAssertNotNil(rank)
        capture("source-switch-\(appearance)-aa-scrolled")
        app.buttons["face-1"].tap()
        waitForFace("arenaText")
        capture("source-switch-\(appearance)-arena-scrolled")
        if let rank {
            XCTAssertTrue(app.buttons["name-arenaText-\(rank)"].isHittable,
                          "Switching scrolled boards must retain the comparison rank")
        }
        XCTAssertTrue(arenaHeaderVisible, "Switching from the top must retain the source and column headers")
    }
    func testCubeMidTurnNativeCapture() {
        app.launchArguments += ["--cube-preview", "--preview-zh"]
        app.launch()
        XCTAssertTrue(app.buttons["face-0"].waitForExistence(timeout: 10))
        capture("iphone-cube-mid-turn")
        app.buttons["face-1"].tap()
        waitForFace("arenaText")
    }
    func testReducedMotionStillSupportsSwipeAndButtons() {
        app.launchArguments += ["--reduce-motion", "--dark"]
        app.launch()
        waitForFace("artificialAnalysis")
        swipe(left: true)
        waitForFace("arenaText")
        capture("iphone-reduced-motion")
        app.buttons["face-0"].tap()
        waitForFace("artificialAnalysis")
    }
    func testLaunchEntranceSettlesAndKeepsScrollAndSwitchingAvailable() {
        app.launchArguments += ["--cube-entrance", "--full-board", "--preview-zh"]
        app.launch()
        waitForFace("artificialAnalysis")
        let hint = app.descendants(matching: .any)["cube-launch-hint"].firstMatch
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !hint.exists }, object: hint)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 8), .completed)
        XCTAssertTrue(app.buttons["face-0"].isSelected)
        capture("iphone-launch-entrance-settled")
        let viewport = app.otherElements["cube-viewport"]
        let firstRowY = app.buttons["name-artificialAnalysis-1"].frame.minY
        viewport.swipeUp()
        XCTAssertLessThan(app.buttons["name-artificialAnalysis-1"].frame.minY, firstRowY - 20,
                          "The entrance must leave native vertical scrolling available")
        swipe(left: true)
        XCTAssertTrue(app.buttons["face-1"].isSelected)
        XCTAssertTrue(app.otherElements["board-arenaText"].waitForExistence(timeout: 5))
        capture("iphone-launch-entrance-scrolled-switch")
    }
    func testLaunchEntrancePreviewYieldsImmediatelyToScrolling() {
        app.launchArguments += ["--cube-entrance-preview", "--full-board", "--preview-zh"]
        app.launch()
        XCTAssertTrue(app.buttons["face-0"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["cube-launch-hint"].firstMatch.exists)
        capture("iphone-launch-entrance-reveal")
        app.otherElements["cube-viewport"].swipeUp()
        XCTAssertFalse(app.descendants(matching: .any)["cube-launch-hint"].firstMatch.exists)
        XCTAssertTrue(app.buttons["face-0"].isSelected)
        app.buttons["face-1"].tap()
        XCTAssertTrue(app.otherElements["board-arenaText"].waitForExistence(timeout: 5))
        capture("iphone-launch-entrance-interrupted")
    }
    func testReducedMotionLaunchEntranceDoesNotPreventFaceSelection() {
        app.launchArguments += ["--cube-entrance", "--reduce-motion", "--dark"]
        app.launch()
        waitForFace("artificialAnalysis")
        app.buttons["face-1"].tap()
        waitForFace("arenaText")
        XCTAssertFalse(app.descendants(matching: .any)["cube-launch-hint"].firstMatch.exists)
        capture("iphone-launch-entrance-reduced-motion")
    }
    private func waitForButton(_ identifier: String) {
        let button = app.buttons[identifier]
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in button.isHittable }, object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, "\(identifier) must be reachable")
    }
    private func scrollToFooter() {
        let viewport = app.otherElements["cube-viewport"]
        for _ in 0..<12 {
            if app.buttons["share"].isHittable { return }
            viewport.swipeUp()
        }
        XCTAssertTrue(app.buttons["share"].isHittable)
    }
    private func assertCategorySegments() {
        let segments = app.segmentedControls["category"].buttons.allElementsBoundByIndex.map(\.frame)
        XCTAssertEqual(segments.count, 4)
        for (left, right) in zip(segments, segments.dropFirst()) {
            XCTAssertEqual(left.width, right.width, accuracy: 2)
            XCTAssertLessThan(left.maxX, right.maxX)
        }
    }
    private func waitForFace(_ kind: String) {
        XCTAssertTrue(app.otherElements["board-\(kind)"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["name-\(kind)-1"].waitForExistence(timeout: 5))
    }
    private func swipe(left: Bool) {
        let viewport = app.otherElements["cube-viewport"]
        let start = viewport.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.85 : 0.15, dy: 0.5))
        let end = viewport.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.15 : 0.85, dy: 0.5))
        start.press(forDuration: 0.08, thenDragTo: end)
    }
    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 0.75)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// Official Wan icon and the previously served Alibaba icon, kept separate for native UI review.
private let modelLogoEntries = #"""
[{"rank":1,"name":"Wan 3.0","score":100,"organization":"Alibaba","brand":{"colorHex":"#634FD2","pngData":"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","key":"model-wan"},"organizationBrand":{"key":"qwen","colorHex":"#623AE7","pngData":"iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAMAAACdt4HsAAACQFBMVEVMaXH/WgD/WgD/VwD/VQD/WQD/WQD/WgD/WgD/WQD/ZgD/WAD/WAD/WgD/VQD/fwD/WgD/WgD/XAD/YgD/WgD/WgD/WgD/XAD/VQD/WgD/WgD/XAD/WgD/AAD/WgD/WgD/WgD/WgD/WQD/WgD/WQD/ZgD/WQD/WQD/WQD/WQD/WgD/WgD/XwD/WgD/WgD/WgD/WQD/WgD/WAD/WwD/VQD/WQD/WgD/WwD/WgD/WgD/WgD/WgD/WQD/WgD/WgD/WQD/WQD/WgD/WQD/WQD/WAD/VQD/WAD/WgD/WwD/WwD/WgD/WgD/SAD/WgD/WgD/XwD/WQD/VwD/WgD/XAD/WQD/WQD/WQD/WQD/WQD/VwD/WQD/VwD/VQD/WQD/WgD/VQD/WQD/WgD/WQD/WgD/WgD/WAD/WQD/WQD/WQD/WQD/WgD/WwD/WQD/XAD/WQD/WQD/WgD/WgD/WQD/WQD/WgD/WQD/WgD/WgD/WgD/WgD/WQD/WAD/WQD/WQD/WgD/WQD/WwD/WgD/WAD/WgD/VQD/WgD/WQD/WgD/WgD/WQD/WgD/WgD/WwD/WQD/WQD/WQD/WgD/WQD/WQD/WgD/WgD/WQD/WQD/WAD/WgD/WgD/WgD/WgD/XAD/WAD/WQD/WgD/WgD/WwD/WgD/WgD/WQD/WgD/WQD/WQD/WgD/WgD/WQD/WgD/WQD/WgD/WgD/WwD/WQD/WgD/WQD/XgD/WgD/VwD/WgD/PwD/WQD/WQD/WAD/WgD/WQD/WgD/WgD/WgB3OaaEAAAAv3RSTlMA7qomA/X6/vz3ClYXYwwCUtYLDcuCxhYYxdkkdgHr1KTde2uPBU0870qjHwiBZvb93CtRFZS9HKdPd3n0aPiwcnw53jQGGpA4GVfiB8zREJwpoSFpXoDbiR0/Og+zQQnyyGe0ikLNNih6mGLCL4Zhcbui5PO+55O3VVAx4MHqg1QwRXMSEdD535emRCrpjM+bWL/oycTTLsNM+38sN62ywHCeM6Dw1Z+I2pFd4+0tQLmEnRuSIJYE0sdLrMqVuNqwir8AAAAJcEhZcwAACxMAAAsTAQCanBgAAAMKSURBVFjDY2AYBaNg5ADXOZp6okuYmJiywpLUhUjULCHQJ8m5HwlwTBOVJlq3tEwi+35MwF4bRYxuE5k2FG0lIgYIzgSCPnHSskO11iCOwWS1hQaMO8Ufn25ZyzRMh6/VBMrocMeyQbjJsrj1a4rsx+bzldFgWfHZCWA+Ny7t1ZKYmg2LCqJi4CoixUBivti1c6XMQtXLIeLe4ImmSEgeJBOMTX+3IqrNnQKt2JSpgSS9MMX565Gi3UDSKgOXN3lAChwwhFsqECE2VZkHTzQxYzVgujNMe7+MNv5UYovNCy6MEN2TdQMJplJwPKNZkg5LZL1cBPXPBKkTxG4/ECwkmL2lQMoyUcR6NBDBX8wCF7bM48NigBJIlT5K4hB3Rop8ZKN1DTGDU5oVpEoFWYhlEpJ+UySJfH32QozEMgOkilUCWUwXSf9ufrhwrtn+fbz7zdEMaAYri0AWiuZA6C9jhiW27NL9JVb8fHpoCaoRXMB5I4eNjyAiAYLCMMeiiMlszf79CVvEMQNQGBwD+6uQxcIQ9hfs2rsHbAPHMi3ueGxR2AVWZ48sZM6KMGAjKERNmDMidXAkAT2wMjmUEAxCCsHlBJJQLqSEr0QWC0QKwf2F+PVDA0ABRVALuQARxG+AAliRYgyymD9ytdPBi1c/L1gRmweKYD5Cu42yKl79RpDQtkYVRQShLzN+96v6gZWZ8aMKy8P05/ARiAFHSAy6oQnDigF5Qvrd9MHqBNDFYTVgKqFSxBSsTAytFlFnqIHolyOkXxgSguXISTgpNtyYwR5iQJ0sAQOMoQkFmjfFLVPS2DlWCTMwhEK9IEDAACWoOkaLiBVZpWXg+tkInJfDoYmAlwU92haHLFqgDuOJote3YrBQa4LW9/u9VbiDwe2O7ZvTja02JXLuV1TmQq1KEGDDeoRNE9mQJNgYGWFcMW5kNzEj5bmlputQ3DrXD7NBsEOUGWs62r+fc34oRs3DojavHaGXdec23q3YWk3uTEwB1nE4ipp4j5C8AAUVpWw1I5bRlvUoGIkAAFRTWmBA7O1VAAAAAElFTkSuQmCC","status":"ready"}},{"rank":2,"name":"Wan2.7-260612","score":99,"organization":"Alibaba","brand":{"colorHex":"#634FD2","pngData":"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","key":"model-wan"},"organizationBrand":{"key":"qwen","colorHex":"#623AE7","pngData":"iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAMAAACdt4HsAAACQFBMVEVMaXH/WgD/WgD/VwD/VQD/WQD/WQD/WgD/WgD/WQD/ZgD/WAD/WAD/WgD/VQD/fwD/WgD/WgD/XAD/YgD/WgD/WgD/WgD/XAD/VQD/WgD/WgD/XAD/WgD/AAD/WgD/WgD/WgD/WgD/WQD/WgD/WQD/ZgD/WQD/WQD/WQD/WQD/WgD/WgD/XwD/WgD/WgD/WgD/WQD/WgD/WAD/WwD/VQD/WQD/WgD/WwD/WgD/WgD/WgD/WgD/WQD/WgD/WgD/WQD/WQD/WgD/WQD/WQD/WAD/VQD/WAD/WgD/WwD/WwD/WgD/WgD/SAD/WgD/WgD/XwD/WQD/VwD/WgD/XAD/WQD/WQD/WQD/WQD/WQD/VwD/WQD/VwD/VQD/WQD/WgD/VQD/WQD/WgD/WQD/WgD/WgD/WAD/WQD/WQD/WQD/WQD/WgD/WwD/WQD/XAD/WQD/WQD/WgD/WgD/WQD/WQD/WgD/WQD/WgD/WgD/WgD/WgD/WQD/WAD/WQD/WQD/WgD/WQD/WwD/WgD/WAD/WgD/VQD/WgD/WQD/WgD/WgD/WQD/WgD/WgD/WwD/WQD/WQD/WQD/WgD/WQD/WQD/WgD/WgD/WQD/WQD/WAD/WgD/WgD/WgD/WgD/XAD/WAD/WQD/WgD/WgD/WwD/WgD/WgD/WQD/WgD/WQD/WQD/WgD/WgD/WQD/WgD/WQD/WgD/WgD/WwD/WQD/WgD/WQD/XgD/WgD/VwD/WgD/PwD/WQD/WQD/WAD/WgD/WQD/WgD/WgD/WgB3OaaEAAAAv3RSTlMA7qomA/X6/vz3ClYXYwwCUtYLDcuCxhYYxdkkdgHr1KTde2uPBU0870qjHwiBZvb93CtRFZS9HKdPd3n0aPiwcnw53jQGGpA4GVfiB8zREJwpoSFpXoDbiR0/Og+zQQnyyGe0ikLNNih6mGLCL4Zhcbui5PO+55O3VVAx4MHqg1QwRXMSEdD535emRCrpjM+bWL/oycTTLsNM+38sN62ywHCeM6Dw1Z+I2pFd4+0tQLmEnRuSIJYE0sdLrMqVuNqwir8AAAAJcEhZcwAACxMAAAsTAQCanBgAAAMKSURBVFjDY2AYBaNg5ADXOZp6okuYmJiywpLUhUjULCHQJ8m5HwlwTBOVJlq3tEwi+35MwF4bRYxuE5k2FG0lIgYIzgSCPnHSskO11iCOwWS1hQaMO8Ufn25ZyzRMh6/VBMrocMeyQbjJsrj1a4rsx+bzldFgWfHZCWA+Ny7t1ZKYmg2LCqJi4CoixUBivti1c6XMQtXLIeLe4ImmSEgeJBOMTX+3IqrNnQKt2JSpgSS9MMX565Gi3UDSKgOXN3lAChwwhFsqECE2VZkHTzQxYzVgujNMe7+MNv5UYovNCy6MEN2TdQMJplJwPKNZkg5LZL1cBPXPBKkTxG4/ECwkmL2lQMoyUcR6NBDBX8wCF7bM48NigBJIlT5K4hB3Rop8ZKN1DTGDU5oVpEoFWYhlEpJ+UySJfH32QozEMgOkilUCWUwXSf9ufrhwrtn+fbz7zdEMaAYri0AWiuZA6C9jhiW27NL9JVb8fHpoCaoRXMB5I4eNjyAiAYLCMMeiiMlszf79CVvEMQNQGBwD+6uQxcIQ9hfs2rsHbAPHMi3ueGxR2AVWZ48sZM6KMGAjKERNmDMidXAkAT2wMjmUEAxCCsHlBJJQLqSEr0QWC0QKwf2F+PVDA0ABRVALuQARxG+AAliRYgyymD9ytdPBi1c/L1gRmweKYD5Cu42yKl79RpDQtkYVRQShLzN+96v6gZWZ8aMKy8P05/ARiAFHSAy6oQnDigF5Qvrd9MHqBNDFYTVgKqFSxBSsTAytFlFnqIHolyOkXxgSguXISTgpNtyYwR5iQJ0sAQOMoQkFmjfFLVPS2DlWCTMwhEK9IEDAACWoOkaLiBVZpWXg+tkInJfDoYmAlwU92haHLFqgDuOJote3YrBQa4LW9/u9VbiDwe2O7ZvTja02JXLuV1TmQq1KEGDDeoRNE9mQJNgYGWFcMW5kNzEj5bmlputQ3DrXD7NBsEOUGWs62r+fc34oRs3DojavHaGXdec23q3YWk3uTEwB1nE4ipp4j5C8AAUVpWw1I5bRlvUoGIkAAFRTWmBA7O1VAAAAAElFTkSuQmCC","status":"ready"}},{"rank":3,"name":"Unknown Video Model","score":98,"organization":"Unlisted Studio"}]
"""#

// Real shared-service marks plus bundled and text fallbacks cover tile padding and clipping.
private let mobileLogoCornerEntries = #"""
[{"brand":{"colorHex":"#FF6900","key":"xiaomi","pngData":"iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAMAAACdt4HsAAACClBMVEVMaXH/aAD/AAD/aQD/aQD/aQD/aQD/aQD/aQD/aAD/aAD/aAD/aAD/aAD/aAD/aAD/ZwD/YwD/aQD/aQD/aQD/agD/ZgD/aAD/aQD/ZwD/YwD/aAD/aAD/aAD/ZgD/aQD/aQD/ZgD/aQD/aQD/aQD/aAD/aAD/agD/agD/aQD/aAD/aAD/aQD/fwD/aQD/aQD/aAD/aAD/aQD/aQD/aAD/aAD/awD/aQD/aQD/aAD/aAD/aQD/aQD/aAD/aQD/bwD/aQD/agD/aQD/aAD/aQD/aQD/aQD/aAD/VQD/ZgD/aQD/ZgD/aQD/aQD/awD/aQD/ZwD/aAD/aAD/aAD/aQD/ZwD/YgD/aQD/ZwD/aAD/aAD/aQD/agD/aAD/ZgD/aQD/ZgD/aQD/aQD/ZwD/aQD/aAD/aQD/aAD/ZwD/aQD/aAD/aQD/aQD/agD/aAD/aAD/aQD/aAD/aQD/aAD/agD/aQD/bQD/////aQD/uYj/dRX/qm7/8+v/v5L/izn/1rn/3sf/fSL/jj//9e7/49D/gyz//v3/693/7N//zar/uIf/nFf/hS//+vf/agH/awT/zqz/4s7/cg//7+T/6dn/w5n/q3H/mlT/iDX/+/n/kEP/38n/giv/3cb//fv/bgn/o2L/tID/gSj/7+P/nlr/8OX/dBL/t4X/mFD/cQ7/mVL//Pr/8un/n1v66OMIAAAAd3RSTlMA0QH8/u7t3czU/aP71vP2QBLoROY8FOeHZxcW7M0e17gj4fD1t9sMMLaX4zMCu6CfqBHkoaYam6Q9nqpVi/kQPxiiXUFq0zgDD9wox+smxjvq7/TaSg3pG8rPuj7ZNM45s5lFrq1ha1bfnIxtQ97iil+IaVleFdt7C1sAAAAJcEhZcwAACxMAAAsTAQCanBgAAAKDSURBVFjDpdflX9tAGAfwp1SSVKCrUYEhw4cOGA7D5u7u7t6jbGXu7u4u/+OS60pTcmkud79XTy59vp+2SZt7ADQZCEbCTbWiJAhF9nyE8u1FgiCJtU3hSHAAjDJt/8EDKEeOdvTOytFev7MAGaa/x59Hbt+6GFFmWT2hvbrOiajjrKue2j9bRKZimZ7dXxNAJhOoUfevb0WmU6h6D2stiCHSgkmgGzGlI92/3cYGOOel+vOKEWM2pO4oP2LOHAzsYQdalP6omx3oD8nAMOLIaRkY4gG6ZaCVBzgGEENcCYGXD+iCfaqjD/EpeXf589sHz66mzz/6rSzeUAMR6FMdjcfJeZhMnU/go3NqIAwuCiD+8pUe0AybaID44/c6QCVsowLiv3QAETwa4ObFySR/3PqTAp7qABIIGuB81nVKXMeLT3SA1TDTAEC38eLde2SgHNYZAT+v4dUEGfDBDDLwZUzJJaX8ilc/kQE7FJCBCVyOKeUVXN4hAxVgNQRe4/IFGXBTABdwmSQDVoqPkBOo0PsSaYGVsIIP8OndSLRAud6tTAtUQQkfIMFGPqAYGvmASsJfmimgGQ7xASfhMB8wCkdUR28yv+HnuMR/53+V6vs3ubr/USnHs3cIg3xPprMAPp7+gPx0bucBhmRgLw8wrOySrez97qiySdrBDuzGu7Q17MAuDDRIrP2W/6NLF+NW1+ZNb5Zb2ABXZlbbwtK/MJQZGMqWmO93LFWPLEGH6f7l2UNTWYm5/qpFmpm13cS1sHWS5lfvXOrrv5k8ujb4eyi2/s7G3vn60/Pgic7CnLOe60zUcIKPjYz2tZWKHkFw2Fcp479DEDxiadvxUyMx7av/ASfcgat960cQAAAAAElFTkSuQmCC"},"developerCountry":{"countryCode":"CN","key":"xiaomi"},"logoURL":"https://artificialanalysis.ai/img/logos/xiaomi.svg","modelID":"mimo-v2-6-pro","name":"MiMo-V2.6-Pro","openness":"open","organization":"Xiaomi","rank":1,"score":100},{"brand":{"colorHex":"#505050","key":"stepfun","pngData":"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"},"developerCountry":{"countryCode":"CN","key":"stepfun"},"logoURL":"https://artificialanalysis.ai/img/logos/stepfun.svg","modelID":"step-5","name":"Step 5 Preview","openness":"closed","organization":"StepFun","rank":2,"score":99},{"rank":3,"name":"MiMo bundled fallback","score":98,"organization":"Xiaomi"},{"rank":4,"name":"Step bundled fallback","score":97,"organization":"StepFun"},{"rank":5,"name":"Unknown logo fallback","score":96,"organization":"Unlisted Studio"}]
"""#
