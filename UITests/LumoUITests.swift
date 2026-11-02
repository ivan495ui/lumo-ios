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
        let savings = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Накопления,")).firstMatch
        XCTAssertTrue(savings.waitForExistence(timeout: 5))
        let crypto = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Криптовалюта")).firstMatch
        XCTAssertTrue(crypto.exists)
        XCTAssertLessThanOrEqual(crypto.frame.maxY, app.tabBars.firstMatch.frame.minY + 1,
            "All three accounts should be visible above the system tab bar")
        screenshot("01-overview")
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
}
