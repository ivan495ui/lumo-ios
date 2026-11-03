import XCTest
@testable import LumoCore

final class DisplayMoneyTests: XCTestCase {
    private func rates() throws -> ExchangeRateTable {
        let json = #"[{"Date":"2026-11-03T00:00:00","Cur_Abbreviation":"USD","Cur_Scale":1,"Cur_OfficialRate":3},{"Date":"2026-11-03T00:00:00","Cur_Abbreviation":"RUB","Cur_Scale":100,"Cur_OfficialRate":4}]"#
        return try .fromNationalBank(Data(json.utf8))
    }
    func testConversionUsesScaleAndSupportsBothDirectionsWithoutMutatingCents() throws {
        let table = try rates(), cents = 30000
        XCTAssertEqual(try table.units(cents: cents, from: "BYN", to: "USD"), 100)
        XCTAssertEqual(try table.units(cents: cents, from: "BYN", to: "RUB"), 7500)
        XCTAssertEqual(try table.units(cents: 10000, from: "USD", to: "BYN"), 300)
        XCTAssertEqual(cents, 30000)
        XCTAssertEqual(try table.units(cents: -100, from: "BYN", to: "BYN"), -1)
        XCTAssertThrowsError(try table.units(cents: 100, from: "EUR", to: "USD"))
    }
    func testRoundTripDecimalRatesCacheIsExact() throws {
        let table = try ExchangeRateTable(date: "2026-11-03", fetchedAt: Date(timeIntervalSince1970: 1234),
            bynPerUnit: ["BYN": 1, "USD": Decimal(string: "2.9549")!, "RUB": Decimal(string: "0.033787")!])
        XCTAssertEqual(try JSONDecoder().decode(ExchangeRateTable.self, from: JSONEncoder().encode(table)), table)
    }
    func testRejectsMissingZeroOrInconsistentDailyRates() throws {
        for json in ["[]", #"[{"Date":"2026-11-03","Cur_Abbreviation":"USD","Cur_Scale":0,"Cur_OfficialRate":3}]"#,
                     #"[{"Date":"2026-11-03","Cur_Abbreviation":"USD","Cur_Scale":1,"Cur_OfficialRate":3},{"Date":"2026-11-02","Cur_Abbreviation":"RUB","Cur_Scale":100,"Cur_OfficialRate":4}]"#] {
            XCTAssertThrowsError(try ExchangeRateTable.fromNationalBank(Data(json.utf8)))
        }
    }
    func testInvalidCachedRatesCannotBypassValidation() throws {
        let encoded = try JSONEncoder().encode(rates())
        var cache = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        cache["bynPerUnit"] = ["BYN": 1, "USD": 0, "RUB": 0.04]
        XCTAssertThrowsError(try JSONDecoder().decode(ExchangeRateTable.self, from: JSONSerialization.data(withJSONObject: cache)))
        cache["bynPerUnit"] = ["BYN": 1, "USD": 3, "RUB": 0.04]
        cache["date"] = "broken"
        XCTAssertThrowsError(try JSONDecoder().decode(ExchangeRateTable.self, from: JSONSerialization.data(withJSONObject: cache)))
    }
    func testEnvelopeRoundingIsPresentationOnlyAndPreservesCents() {
        let value = MoneyValue(cents: 22266, currency: "BYN", roundedToWhole: true)
        XCTAssertEqual(value.number, "223")
        XCTAssertEqual(value.units, Decimal(string: "222.66"))
        XCTAssertTrue(value.approximate)
        XCTAssertEqual(MoneyValue(cents: 22266, currency: "BYN").number, "222,66")
        XCTAssertEqual(MoneyValue(cents: -150, currency: "BYN", roundedToWhole: true).number, "-2")
    }
    func testSymbolsAndApproximationAreHonest() {
        XCTAssertEqual(MoneyValue(cents: 10000, currency: "USD").text(), "$100")
        XCTAssertEqual(MoneyValue(units: 10, currency: "USD", converted: true).text(sign: "+"), "≈ +$10")
        XCTAssertEqual(MoneyValue(cents: 10000, currency: "RUB").text(), "100 ₽")
        XCTAssertFalse(MoneyValue(cents: 10000, currency: "BYN", roundedToWhole: true).approximate)
    }
}
