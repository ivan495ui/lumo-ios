import Foundation
import XCTest

final class LumoUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["LUMO_DEMO"] = "1"
        app.launchEnvironment["LUMO_FX_TEST"] = "1"
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
        XCTAssertTrue(app.buttons["Добавить операцию"].exists)
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
        app.buttons["Добавить операцию"].tap()
        XCTAssertTrue(app.textFields["transaction.amount"].waitForExistence(timeout: 3))
        screenshot("06-transaction-form")
    }
    func testAddExpenseAndFindInHistory() throws {
        selectDisplayCurrency("BYN")
        showFiatOverview()
        let balance = app.staticTexts["overview.balance"]
        let initialFiat = try XCTUnwrap(number(in: balance.label))
        XCTAssertTrue(app.buttons["Расход"].waitForExistence(timeout: 15))
        app.buttons["Расход"].tap()
        let amount = app.textFields["transaction.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        amount.tap(); amount.typeText("12.34")
        tapPicker("transaction.envelope", choice: "Личные расходы")
        let comment = app.textViews.firstMatch
        if comment.exists { comment.tap(); comment.typeText("Native UI test") }
        app.navigationBars.buttons["Готово"].tap()
        waitForNumber(initialFiat - Decimal(1234) / 100, in: balance)
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

    func testDisplayCurrencyConvertsBalanceButEntryRemainsInBYN() throws {
        selectDisplayCurrency("BYN")
        showFiatOverview()
        let balance = app.staticTexts["overview.balance"]
        let original = try XCTUnwrap(number(in: balance.label))
        XCTAssertGreaterThan(original, 0)

        selectDisplayCurrency("USD")
        var converted = original / 3, expected = Decimal()
        NSDecimalRound(&expected, &converted, 2, .plain)
        waitForNumber(expected, in: balance)
        XCTAssertTrue(balance.label.contains("$"), "The readout must use USD as well as a converted number")
        XCTAssertTrue(balance.label.contains("≈"))
        XCTAssertNotEqual(number(in: balance.label), original, "Changing only the currency symbol is insufficient")

        app.buttons["Расход"].tap()
        let amount = app.textFields["transaction.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertEqual(amount.placeholderValue, "Сумма, BYN", "Display currency must not change the units accepted by the ledger")
        screenshot("09-usd-display-byn-entry")
        app.navigationBars.buttons["Отмена"].tap()

        selectDisplayCurrency("BYN")
        waitForNumber(original, in: balance)
        XCTAssertTrue(balance.label.contains("Br"), "Switching display currency must leave the original ledger amount intact")
    }

    func testReceiveAndWithdrawUSDTKeepFiatAndEnvelopesSeparate() throws {
        selectDisplayCurrency("BYN")
        showFiatOverview()
        let balance = app.staticTexts["overview.balance"]
        let initialFiat = try XCTUnwrap(number(in: balance.label))
        let initialEnvelopes = envelopeLabels()
        XCTAssertEqual(initialEnvelopes.count, 3, "All demo envelopes must participate in the conservation check")
        openCryptoAccount()
        let quantity = app.staticTexts["crypto.balance.quantity"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        XCTAssertTrue(quantity.label.contains("USDT"))
        let initialQuantity = try XCTUnwrap(number(in: quantity.label))

        app.buttons["crypto.received"].tap()
        replaceText(in: app.textFields["crypto.quantity"], with: "2")
        XCTAssertFalse(element("crypto.fiatAccount").exists, "A receipt of crypto must not ask for a fiat payment account")
        app.buttons["crypto.save"].tap()
        waitForNumber(initialQuantity + 2, in: quantity)
        leaveCryptoAccount()
        waitForNumber(initialFiat, in: balance)
        XCTAssertEqual(envelopeLabels(), initialEnvelopes, "Receiving USDT must not create fiat income or envelope allocations")

        openCryptoAccount()
        app.buttons["crypto.withdraw"].tap()
        tapPicker("crypto.fiatAccount", choice: "Карта")
        replaceText(in: app.textFields["crypto.quantity"], with: "1")
        replaceText(in: app.textFields["crypto.amount"], with: "3.21")
        app.buttons["crypto.save"].tap()
        waitForNumber(initialQuantity + 1, in: quantity)
        screenshot("10-usdt-received-and-withdrawn")
        leaveCryptoAccount()
        waitForNumber(initialFiat + Decimal(321) / 100, in: balance)
        XCTAssertEqual(envelopeLabels(), initialEnvelopes, "Converting USDT to money credits the account without distributing a second income")
    }

    func testOverviewRoundsEnvelopesWithoutLosingExactLedgerCents() throws {
        selectDisplayCurrency("BYN")
        let personal = app.buttons["overview.envelope.env_personal"]
        XCTAssertTrue(personal.waitForExistence(timeout: 5))
        let initial = try exactEnvelopeAmount(personal.label)
        XCTAssertGreaterThan(initial, 1, "The demo envelope must fund this one- or two-cent regression fixture")
        // Demo data persist between tests. Choose a tiny expense that leaves a
        // fractional balance regardless of previous expense tests or repeated runs.
        let initialCents = NSDecimalNumber(decimal: initial * 100).intValue
        let expenseCents = initialCents % 100 == 1 ? 2 : 1
        let expected = initial - Decimal(expenseCents) / 100
        app.buttons["Расход"].tap()
        replaceText(in: app.textFields["transaction.amount"], with: expenseCents == 1 ? "0.01" : "0.02")
        tapPicker("transaction.envelope", choice: "Личные расходы")
        app.navigationBars.buttons["Готово"].tap()
        XCTAssertTrue(app.staticTexts["overview.balance"].waitForExistence(timeout: 5))
        XCTAssertEqual(try exactEnvelopeAmount(personal.label), expected)

        // Reload from disk: the exact cents must survive saving, not merely the
        // in-memory view immediately after recording the expense.
        app.terminate()
        app.launch()
        XCTAssertTrue(personal.waitForExistence(timeout: 15))
        XCTAssertEqual(try exactEnvelopeAmount(personal.label), expected)
        let visible = try XCTUnwrap(personal.label.components(separatedBy: ", ").dropFirst().first)
        XCTAssertFalse(visible.contains(","), "The overview tile should display whole units")
        XCTAssertTrue(visible.contains("≈"), "A fractional ledger balance needs the approximation marker")
        var exact = expected, rounded = Decimal()
        NSDecimalRound(&rounded, &exact, 0, .plain)
        XCTAssertEqual(number(in: visible), rounded)
        screenshot("11-rounded-envelope-exact-ledger")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func tapPicker(_ identifier: String, choice: String) {
        let picker = element(identifier)
        for _ in 0..<4 {
            if picker.exists && picker.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.isHittable)
        picker.tap()
        // SwiftUI can present this Picker as either a menu or a navigation list.
        let option = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", choice)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Missing picker choice: \(choice)")
        option.tap()
    }

    private func selectDisplayCurrency(_ code: String) {
        XCTAssertTrue(app.buttons["Настройки"].waitForExistence(timeout: 15))
        app.buttons["Настройки"].tap()
        let currency = app.buttons["Валюта отображения"]
        XCTAssertTrue(currency.waitForExistence(timeout: 5))
        currency.tap()
        let choice = ["BYN": "Белорусский рубль · BYN", "USD": "Доллар · USD"][code]!
        tapPicker("currency.display", choice: choice)
        let done = app.navigationBars.buttons["Готово"].firstMatch
        if !done.exists {
            let back = app.navigationBars.buttons["Настройки"]
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
        }
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(app.staticTexts["overview.balance"].waitForExistence(timeout: 5))
    }

    private func showFiatOverview() {
        let mode = app.buttons["Режим баланса"]
        if mode.exists {
            mode.tap()
            let fiat = app.buttons["Карта и наличные"]
            XCTAssertTrue(fiat.waitForExistence(timeout: 5))
            fiat.tap()
        }
        XCTAssertTrue(app.staticTexts["overview.balance"].waitForExistence(timeout: 5))
    }

    private func openCryptoAccount() {
        let account = app.buttons["overview.account.acc_crypto"]
        for _ in 0..<3 {
            if account.exists && account.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(account.exists && account.isHittable)
        account.tap()
        XCTAssertTrue(app.buttons["crypto.received"].waitForExistence(timeout: 5))
    }

    private func leaveCryptoAccount() {
        let back = app.navigationBars.buttons["lumo"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.staticTexts["overview.balance"].waitForExistence(timeout: 5))
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let value = field.value as? String ?? ""
        let existing = value == field.placeholderValue ? "" : value
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + text)
    }

    private func envelopeLabels() -> [String: String] {
        ["env_savings", "env_personal", "env_music"].reduce(into: [:]) { labels, id in
            let envelope = app.buttons["overview.envelope.\(id)"]
            if envelope.exists { labels[id] = envelope.label }
        }
    }

    private func exactEnvelopeAmount(_ label: String) throws -> Decimal {
        XCTAssertTrue(label.contains("Точно в учёте:"))
        let exact = try XCTUnwrap(label.components(separatedBy: "Точно в учёте:").last)
        return try XCTUnwrap(number(in: exact))
    }

    private func number(in label: String) -> Decimal? {
        let normalized = label.replacingOccurrences(of: "−", with: "-")
            .filter { $0.isNumber || $0 == "," || $0 == "." || $0 == "-" }
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func waitForNumber(_ expected: Decimal, in element: XCUIElement,
                               file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { [self] object, _ in
            guard let value = object as? XCUIElement, value.exists else { return false }
            return number(in: value.label) == expected
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5)
        XCTAssertEqual(result, .completed, "Expected \(expected), found \(element.exists ? element.label : "missing element")", file: file, line: line)
    }
}
