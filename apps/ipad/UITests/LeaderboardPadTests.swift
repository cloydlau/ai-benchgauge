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
        app.segmentedControls["category"].buttons["Coding"].tap()
        XCTAssertTrue(app.otherElements["board-codeArenaWebDev"].waitForExistence(timeout: 5))
        app.segmentedControls["grouping"].buttons["Companies"].tap()
        XCTAssertTrue(app.staticTexts["OpenAI"].firstMatch.exists)
        app.buttons["score-artificialAnalysisCodingAgent-1"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Score uses the strongest model")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["country-artificialAnalysisCodingAgent"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "China")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["DeepSeek"].firstMatch.exists)
        capture("portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.otherElements["board-artificialAnalysisCodingAgent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["board-codeArenaWebDev"].exists)
        waitForLayout(landscape: true)
        capture("landscape")
    }
    func testOfflineResultsAndSettings() {
        app.launchArguments.append("--offline")
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["source-error-artificialAnalysis"].firstMatch.waitForExistence(timeout: 10)
            || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "No internet connection")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["GPT Fixture"].firstMatch.exists)
        app.buttons["settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings-github"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["license"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Permission is hereby granted")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["share"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["share-image"].firstMatch.waitForExistence(timeout: 10))
        capture("share")
    }
    func testChineseInterfacePreviews() {
        app.launchArguments.append("--preview-zh")
        app.launch()
        XCTAssertTrue(app.otherElements["board-artificialAnalysis"].waitForExistence(timeout: 10))
        waitForLayout(landscape: false)
        capture("zh-models-portrait")
        app.segmentedControls["grouping"].buttons["公司"].tap()
        capture("zh-companies-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForLayout(landscape: true)
        capture("zh-companies-landscape")
        XCUIDevice.shared.orientation = .portrait
        waitForLayout(landscape: false)
        app.buttons["settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings-github"].firstMatch.waitForExistence(timeout: 5))
        capture("zh-settings")
    }

    private func waitForLayout(landscape: Bool) {
        let window = app.windows.firstMatch
        let predicate = NSPredicate { _, _ in
            let frame = window.frame
            return frame.width > 0 && frame.height > 0
                && (frame.width > frame.height) == landscape
                && self.app.buttons["settings"].isHittable
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: window)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
        // Existing board identifiers can remain present while rotation is still animating.
        // Wait for a stable window frame before taking the complete screen snapshot.
        var previous = window.frame
        var stableFrames = 0
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.3)
            let current = window.frame
            stableFrames = current == previous ? stableFrames + 1 : 0
            previous = current
            if stableFrames >= 3 { return }
        }
        XCTFail("iPad window did not settle after rotation")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
