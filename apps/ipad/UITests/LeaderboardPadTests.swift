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
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
