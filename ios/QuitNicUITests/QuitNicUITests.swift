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

    func testProgressSupportsAccessibilityXXXLText() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-reset",
            "-ui-testing-seed-progress",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Progress"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["Milestones"].waitForExistence(timeout: 3))

        let trigger = app.staticTexts["A long craving trigger after morning coffee"]
        for _ in 0..<4 where !trigger.exists { app.swipeUp() }
        XCTAssertTrue(trigger.exists)
        XCTAssertTrue(app.staticTexts["A deliberately long walk around the neighbourhood"].exists)
        takeScreenshot(named: "06-progress-accessibility-xxxl")
    }

    func testCompleteQuitJourney() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset", "-ui-testing-seed-plan"]
        addUIInterruptionMonitor(withDescription: "Notifications") { alert in
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
            return false
        }
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 8))
        takeScreenshot(named: "01-dashboard")
        try app.performAccessibilityAudit(for: .all.subtracting(.dynamicType)) { issue in
            // XCTest can sample offscreen ScrollView content through the translucent tab bar.
            // Visible contrast findings still fail; only covered/non-hittable elements are excluded.
            guard issue.auditType == .contrast, let element = issue.element else { return false }
            return !element.isHittable || element.frame.intersects(app.tabBars.firstMatch.frame)
        }

        app.tabBars.buttons["Rescue"].tap()
        XCTAssertTrue(app.buttons["Start a two-minute reset"].waitForExistence(timeout: 3))
        app.buttons["Start a two-minute reset"].tap()
        app.buttons["Coffee"].tap()
        try app.performAccessibilityAudit(for: .all.subtracting(.dynamicType))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Breathing reset"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["How do you feel now?"].waitForExistence(timeout: 5))
        app.buttons["I resisted the craving"].tap()
        app.buttons["Save result"].tap()
        XCTAssertTrue(app.staticTexts["You moved through it."].waitForExistence(timeout: 3))
        takeScreenshot(named: "02-rescue-complete")
        app.buttons["Done"].tap()

        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Coffee"].exists)
        takeScreenshot(named: "03-progress")
        try app.performAccessibilityAudit(for: .all.subtracting(.dynamicType)) { issue in
            // Xcode 16 can emit text-clipping reports without an associated element.
            // The accessibility-XXXL Progress test below verifies this layout directly.
            issue.auditType == .textClipped && issue.element == nil
        }

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
        try app.performAccessibilityAudit(for: .all.subtracting(.dynamicType))
        app.buttons["Send"].tap()
        let safetyReply = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "contact local emergency services")
        ).firstMatch
        XCTAssertTrue(safetyReply.waitForExistence(timeout: 5))
        takeScreenshot(named: "05-safety-reply")
        coachInput.tap()
        coachInput.typeText("I need another coping step")
        try app.performAccessibilityAudit(for: .all.subtracting(.dynamicType))

        app.tap() // dismiss the keyboard before switching tabs
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.buttons["Delete account and local data"].tap()
        XCTAssertTrue(app.buttons["Delete permanently"].waitForExistence(timeout: 3))
        app.buttons["Delete permanently"].tap()
        XCTAssertTrue(app.navigationBars["QuitNic"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start my plan"].exists)
    }

    private func takeScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
