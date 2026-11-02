import XCTest
@testable import LumoCore

final class FinanceEngineTests: XCTestCase {
    private let income: [String: Any] = ["type": "income", "amount": 100000, "accountId": "acc_card", "categoryId": "cat_income_music", "date": "2026-11-02"]

    func testJavaScriptCoreLoadsAndDecodesNativeModels() throws {
        let engine = try FinanceEngine()
        let snapshot = try engine.snapshot(month: "2026-11")
        XCTAssertEqual(snapshot.state.settings.currency, "BYN")
        XCTAssertFalse(snapshot.state.settings.taxEnabled)
        XCTAssertEqual(snapshot.state.envelopes.compactMap(\.percent), [32, 32])
        XCTAssertEqual(snapshot.derived.total, 0)
    }

    func testRealJavaScriptCoreMoneyAndCryptoAreSeparate() throws {
        let e = try FinanceEngine()
        try e.perform("addTransaction", args: [income])
        try e.perform("saveAsset", args: ["acc_crypto", ["id": "usdt", "name": "Tether", "symbol": "USDT", "price": 330, "initialQty": 120]])
        let s = try e.snapshot(month: "2026-11")
        XCTAssertEqual(s.derived.fiatTotal, 100000)
        XCTAssertEqual(s.derived.total, 139600)
        XCTAssertEqual(s.derived.envelopeTotal, 100000)
        XCTAssertEqual(s.summary.income, 100000)
        XCTAssertEqual(s.derived.envelopes.map { $0.balance ?? 0 }, [32000, 32000, 36000])
    }

    func testRoundtripUnicodeAndExactAmounts() throws {
        let e = try FinanceEngine()
        var draft = income; draft["amount"] = 1; draft["comment"] = "Привет 😀 \" цитата"
        try e.perform("addTransaction", args: [draft])
        let text = try e.exportJSON()
        let restored = try FinanceEngine(); try restored.importJSON(text)
        let s = try restored.snapshot()
        XCTAssertEqual(s.derived.fiatTotal, 1)
        XCTAssertEqual(s.state.transactions.first?.comment, "Привет 😀 \" цитата")
        XCTAssertEqual(try restored.cents("1 234,56"), 123456)
        XCTAssertThrowsError(try restored.cents("1.999"))
    }

    func testDiskBackupRecoveryAndFailedWritePreservePreviousLedger() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try LedgerFiles(directory: directory)
        let e = try FinanceEngine()
        XCTAssertFalse(try files.load(into: e))
        try e.perform("addTransaction", args: [income])
        let knownGood = try e.exportJSON()
        try files.save(knownGood, previous: knownGood)
        try Data("broken".utf8).write(to: files.primary)
        let restored = try FinanceEngine()
        XCTAssertTrue(try files.load(into: restored))
        XCTAssertEqual(try restored.snapshot().derived.fiatTotal, 100000)
        let failing = try LedgerFiles(directory: directory) { data, url in
            if url.lastPathComponent == "ledger.json" { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        }
        try restored.perform("addTransaction", args: [income])
        XCTAssertThrowsError(try failing.save(restored.exportJSON(), previous: knownGood))
        let again = try FinanceEngine()
        XCTAssertTrue(try files.load(into: again))
        XCTAssertEqual(try again.snapshot().derived.fiatTotal, 100000)
    }

    func testDamagedContainerNeverSilentlyResets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try LedgerFiles(directory: directory)
        let data = Data("bad ledger".utf8)
        try data.write(to: files.primary); try data.write(to: files.backup)
        XCTAssertThrowsError(try files.load(into: FinanceEngine()))
        XCTAssertEqual(try Data(contentsOf: files.primary), data)
        XCTAssertEqual(try Data(contentsOf: files.backup), data)
        try files.preserveForRecovery()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("Recovery-") }.count, 1)
    }

    func testPreviewFingerprintProtectsRebalance() throws {
        let e = try FinanceEngine()
        try e.perform("saveAccount", args: [["id": "acc_card", "opening": 21500]])
        let p = try e.preview()
        XCTAssertEqual(p.rows.reduce(0) { $0 + $1.after }, 21500)
        try e.perform("rebalanceEnvelopes", args: [p.fingerprint])
        XCTAssertEqual(try e.snapshot().derived.unallocated, 0)
        XCTAssertThrowsError(try e.perform("rebalanceEnvelopes", args: [p.fingerprint]))
    }
}
