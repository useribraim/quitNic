import XCTest

final class QuitNicUITests: XCTestCase {
    func testOnboardingIsAccessibleOnFreshInstall() throws {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing-reset"]
        app.launch()
        XCTAssertTrue(app.navigationBars["QuitNic"].waitForExistence(timeout: 3))
        let startButton = app.buttons["Start my plan"]
        XCTAssertTrue(startButton.exists)
        XCTAssertFalse(startButton.isEnabled)

        let motivation = app.descendants(matching: .any)["motivationField"]
        XCTAssertTrue(motivation.exists)
        motivation.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        app.typeText("More energy and freedom")
        XCTAssertTrue(startButton.isEnabled)
        try app.performAccessibilityAudit(for: .all.subtracting(.dynamicType))
    }

    func testOnboardingSupportsAccessibilityXXXLText() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-reset",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["QuitNic"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Nicotine type"].exists)
        XCTAssertTrue(app.staticTexts["Hour"].exists)
        XCTAssertTrue(app.buttons["Start my plan"].exists)
    }

    func testCompleteQuitJourney() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset"]
        addUIInterruptionMonitor(withDescription: "Notifications") { alert in
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
            return false
        }
        app.launch()

        XCTAssertTrue(app.navigationBars["QuitNic"].waitForExistence(timeout: 5))
        let motivation = app.descendants(matching: .any)["motivationField"]
        XCTAssertTrue(motivation.exists)
        motivation.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        app.typeText("More energy and freedom")
        app.buttons["Start my plan"].tap()
        app.tap()

        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 8))
        takeScreenshot(named: "01-dashboard")

        app.tabBars.buttons["Check In"].tap()
        app.textFields["What triggered it?"].tap()
        app.textFields["What triggered it?"].typeText("After coffee")
        app.textFields["What did you try?"].tap()
        app.textFields["What did you try?"].typeText("A short walk")
        app.buttons["Save check-in"].tap()
        XCTAssertTrue(app.alerts["Check-in saved"].waitForExistence(timeout: 3))
        app.alerts["Check-in saved"].buttons["OK"].tap()
        takeScreenshot(named: "02-check-in")

        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["After coffee"].exists)
        takeScreenshot(named: "03-progress")

        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 3))
        let coachInput = app.descendants(matching: .any)["coachInput"]
        coachInput.tap()
        coachInput.typeText("I have a strong craving")
        app.buttons["Send"].tap()
        let coachingReply = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Try a two-minute reset")
        ).firstMatch
        XCTAssertTrue(coachingReply.waitForExistence(timeout: 5))
        takeScreenshot(named: "04-coaching-reply")

        coachInput.tap()
        coachInput.typeText("I might kill myself")
        app.buttons["Send"].tap()
        let safetyReply = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "contact local emergency services")
        ).firstMatch
        XCTAssertTrue(safetyReply.waitForExistence(timeout: 5))
        takeScreenshot(named: "05-safety-reply")
    }

    private func takeScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
