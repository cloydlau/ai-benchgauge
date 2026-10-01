import XCTest
import UIKit

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
        XCTAssertTrue(app.descendants(matching: .any)["source-error-artificialAnalysis"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["name-artificialAnalysis-1"].exists)
        capture("offline")
        app.buttons["source-error-artificialAnalysis"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "No internet connection")).firstMatch.waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.staticTexts["AI BenchGauge"].exists)
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
        XCTAssertTrue(app.staticTexts["AI BenchGauge"].exists)
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
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
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
    func testOfflineLicenseScreenshotAndLanguages() {
        app.launchArguments.append("--offline")
        app.launch()
        XCTAssertTrue(app.buttons["source-error-artificialAnalysis"].waitForExistence(timeout: 10))
        waitForButton("attribution")
        capture("iphone-offline")
        app.buttons["source-error-artificialAnalysis"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "No internet connection")).firstMatch.waitForExistence(timeout: 5))
        capture("iphone-offline-details")
        app.buttons["Done"].tap()
        waitForButton("attribution")
        app.buttons["attribution"].tap()
        app.buttons["MIT License"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Permission is hereby granted")).firstMatch.waitForExistence(timeout: 5))
        capture("iphone-license")
        app.buttons["Done"].tap()
        waitForButton("attribution")
        app.buttons["attribution"].tap()
        app.buttons["Open-source notices"].tap()
        XCTAssertTrue(app.segmentedControls["license-section"].waitForExistence(timeout: 5))
        capture("iphone-notices")
        app.buttons["Done"].tap()
        app.buttons["share"].tap()
        XCTAssertTrue(app.staticTexts["Copied to clipboard"].waitForExistence(timeout: 10))
        assertCategorySegments()
        capture("iphone-screenshot-feedback")
        waitForButton("language-menu")
        app.buttons["language-menu"].tap()
        app.buttons["简中"].tap()
        XCTAssertTrue(app.staticTexts["AI BenchGauge"].exists)
        XCTAssertFalse(app.staticTexts["获取于"].exists)
        app.segmentedControls["category"].buttons["图片"].tap()
        waitForFace("artificialAnalysisTextToImage")
        capture("iphone-zh-image")
        app.buttons["face-1"].tap()
        waitForFace("arenaTextToImage")
        capture("iphone-zh-image-second-face")
        waitForButton("language-menu")
        app.buttons["language-menu"].tap()
        app.buttons["繁中"].tap()
        app.segmentedControls["category"].buttons["視頻"].tap()
        waitForFace("arenaTextToVideo")
        capture("iphone-traditional-video")
    }
    func testLongBoardComparisonRankAndLandscape() {
        app.launchArguments += ["--full-board", "--dark", "--preview-zh"]
        app.launch()
        waitForFace("artificialAnalysis")
        waitForButton("attribution")
        waitForButton("share")
        waitForButton("language-menu")
        capture("iphone-long-dark", checkingDarkFooter: true)
        app.buttons["refresh"].tap()
        waitForFace("artificialAnalysis")
        capture("iphone-long-dark-refreshed", checkingDarkFooter: true)
        let viewport = app.otherElements["cube-viewport"]
        viewport.swipeUp()
        viewport.swipeUp()
        let visible = (2...19).first { rank in
            let row = app.buttons["name-artificialAnalysis-\(rank)"]
            return row.isHittable && row.frame.minY >= viewport.frame.minY && row.frame.minY < viewport.frame.midY
        }
        XCTAssertNotNil(visible)
        let firstY = visible.map { app.buttons["name-artificialAnalysis-\($0)"].frame.minY }
        capture("iphone-scrolled-first-face", checkingDarkFooter: true)
        app.buttons["face-1"].tap()
        waitForFace("arenaText")
        if let rank = visible, let firstY {
            let row = app.buttons["name-arenaText-\(rank)"]
            XCTAssertTrue(row.isHittable, "Keep the same rank visible for comparison")
            XCTAssertEqual(row.frame.minY, firstY, accuracy: 48, "The compared rank must stay near the same vertical position, not return to rank 1")
        }
        capture("iphone-scrolled-second-face", checkingDarkFooter: true)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.windows.firstMatch.frame.width > self.app.windows.firstMatch.frame.height
        }, object: app.windows.firstMatch)], timeout: 10), .completed)
        capture("iphone-landscape-dark", checkingDarkFooter: true)
        XCTAssertTrue(app.buttons["face-0"].isHittable)
        XCTAssertTrue(app.buttons["share"].isHittable)
        assertCategorySegments()
        app.buttons["face-0"].tap()
        waitForFace("artificialAnalysis")
        app.segmentedControls["grouping"].buttons["公司"].tap()
        XCTAssertTrue(app.buttons["country-artificialAnalysis"].isHittable, "Grouping changes must return to the top")
        XCTAssertTrue(app.buttons["name-artificialAnalysis-1"].isHittable)
        capture("iphone-reset-companies-landscape", checkingDarkFooter: true)
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
        capture("iphone-reduced-motion", checkingDarkFooter: true)
        app.buttons["face-0"].tap()
        waitForFace("artificialAnalysis")
    }
    private func waitForButton(_ identifier: String) {
        let button = app.buttons[identifier]
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in button.isHittable }, object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, "\(identifier) must be reachable")
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
    private func capture(_ name: String, checkingDarkFooter: Bool = false) {
        Thread.sleep(forTimeInterval: 0.75)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if checkingDarkFooter { assertDarkFooterVisible(in: screenshot) }
    }
    private func assertDarkFooterVisible(in screenshot: XCUIScreenshot) {
        guard let image = screenshot.image.cgImage else { return XCTFail("Native screenshot has no pixels") }
        let window = app.windows.firstMatch.frame
        let scale = CGFloat(image.width) / window.width
        // Accessibility can report a tappable control whose glyphs were never
        // painted. Inspect the very same native capture retained above.
        for identifier in ["attribution", "share", "language-menu"] {
            let frame = app.buttons[identifier].frame
            let rect = CGRect(x: (frame.minX - window.minX) * scale, y: (frame.minY - window.minY) * scale,
                              width: frame.width * scale, height: frame.height * scale).integral
            guard let crop = image.cropping(to: rect) else { return XCTFail("Missing screenshot region for \(identifier)") }
            var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
            let visible = bytes.withUnsafeMutableBytes { buffer -> Int in
                guard let context = CGContext(data: buffer.baseAddress, width: crop.width, height: crop.height,
                    bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return 0 }
                context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
                let pixels = buffer.bindMemory(to: UInt8.self)
                return stride(from: 0, to: pixels.count, by: 4).filter { max(pixels[$0], pixels[$0 + 1], pixels[$0 + 2]) > 128 }.count
            }
            XCTAssertGreaterThan(visible, 16, "\(identifier) must paint visible glyphs on the dark footer")
        }
    }
}
