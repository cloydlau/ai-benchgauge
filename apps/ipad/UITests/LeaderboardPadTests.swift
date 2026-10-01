import XCTest

final class LeaderboardPadTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
    }
    override func tearDownWithError() throws {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }
    func testCategoriesGroupingAndCountryFilter() {
        app.launch()
        XCTAssertTrue(app.otherElements["board-artificialAnalysis"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["UPDATED"].exists)
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
        XCTAssertTrue(app.staticTexts["Open-source notices"].firstMatch.waitForExistence(timeout: 5))
        capture("notices")
        app.buttons["Done"].tap()
        app.buttons["share"].tap()
        XCTAssertTrue(app.staticTexts["Copied to clipboard"].waitForExistence(timeout: 10))
        capture("screenshot-feedback")
    }
    func testChineseInterfacePreviews() {
        app.launchArguments.append("--preview-zh")
        app.launch()
        XCTAssertTrue(app.otherElements["board-artificialAnalysis"].waitForExistence(timeout: 10))
        waitForLayout(landscape: false)
        XCTAssertTrue(app.staticTexts["更新时间"].exists)
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
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
