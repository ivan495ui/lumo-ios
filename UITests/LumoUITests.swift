import XCTest

final class LumoUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["LUMO_DEMO"] = "1"
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()
    }
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testNativeTabsAndScreens() {
        XCTAssertTrue(app.staticTexts["overview.balance"].waitForExistence(timeout: 15))
        screenshot("01-overview")
        let savings = app.buttons["overview.envelope.env_savings"]
        XCTAssertTrue(savings.waitForExistence(timeout: 5))
        let crypto = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Криптовалюта")).firstMatch
        XCTAssertTrue(crypto.exists)
        XCTAssertLessThanOrEqual(crypto.frame.maxY, app.tabBars.firstMatch.frame.minY + 1,
            "All three accounts should be visible above the system tab bar")
        for (tab, filename) in [("Счета", "02-accounts"), ("Конверты", "03-envelopes"), ("Аналитика", "04-analytics"), ("История", "05-history")] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.exists); button.tap()
            screenshot(filename)
        }
        app.tabBars.buttons["Обзор"].tap()
        app.buttons["Расход"].tap()
        XCTAssertTrue(app.textFields["transaction.amount"].waitForExistence(timeout: 3))
        screenshot("06-transaction-form")
    }
    func testAddExpenseAndFindInHistory() {
        XCTAssertTrue(app.buttons["Расход"].waitForExistence(timeout: 15))
        app.buttons["Расход"].tap()
        let amount = app.textFields["transaction.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        amount.tap(); amount.typeText("12.34")
        let comment = app.textViews.firstMatch
        if comment.exists { comment.tap(); comment.typeText("Native UI test") }
        app.navigationBars.buttons["Готово"].tap()
        XCTAssertTrue(app.staticTexts["overview.balance"].waitForExistence(timeout: 5))
        app.tabBars.buttons["История"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "12,34")).firstMatch.waitForExistence(timeout: 5))
    }
    func testLargeTextKeepsAccountsReachable() {
        app.terminate()
        app.launchEnvironment["LUMO_PREVIEW_LARGE_TEXT"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["overview.balance"].waitForExistence(timeout: 15))
        screenshot("07-large-text-top")
        let crypto = app.buttons["overview.account.acc_crypto"]
        for _ in 0..<6 {
            if crypto.exists && crypto.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(crypto.exists && crypto.isHittable, "Large text must keep accounts reachable by scrolling")
        screenshot("08-large-text-accounts")
        crypto.tap()
        XCTAssertTrue(app.navigationBars["Криптовалюта"].waitForExistence(timeout: 5))
    }
}
