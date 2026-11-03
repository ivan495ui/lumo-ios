import Foundation
import XCTest
@testable import LumoCore

final class ProtectedBackupFilesTests: XCTestCase {
    private var directory: URL!
    private let password = "Only fictional backup data 123"
    private enum Injected: Error { case unavailable }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lumo-backup-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
    }

    func testThreeRevisionsKeepCurrentAndPreviousExactExports() throws {
        let files = ProtectedBackupFiles(directory: directory)
        let first = ledger(1), second = ledger(2), third = ledger(3)
        XCTAssertEqual(try save(first, files), .written)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.previous.path))
        try save(second, files)
        try save(third, files)
        XCTAssertEqual(try plain(files.current), Data(third.utf8))
        XCTAssertEqual(try plain(files.previous), Data(second.utf8))
    }

    func testFreshExportTimestampDoesNotRotateAwayPreviousDistinctJournal() throws {
        let files = ProtectedBackupFiles(directory: directory)
        try save(ledger(1), files)
        try save(ledger(2), files)
        let current = try Data(contentsOf: files.current)
        let previous = try Data(contentsOf: files.previous)
        XCTAssertEqual(try save(ledger(2, stamp: "2099-12-31T23:59:59Z"), files), .unchanged)
        XCTAssertEqual(try Data(contentsOf: files.current), current)
        XCTAssertEqual(try Data(contentsOf: files.previous), previous)
        XCTAssertEqual(try plain(files.previous), Data(ledger(1).utf8))
    }

    func testMismatchingNewPayloadCannotTouchEitherFile() throws {
        let files = ProtectedBackupFiles(directory: directory)
        try save(ledger(1), files); try save(ledger(2), files)
        let current = try Data(contentsOf: files.current), previous = try Data(contentsOf: files.previous)
        let encrypted = try ProtectedBackup.encrypt(ledger(3), password: password)
        XCTAssertThrowsError(try files.save(encrypted, exactJSON: ledger(4), password: password))
        XCTAssertEqual(try Data(contentsOf: files.current), current)
        XCTAssertEqual(try Data(contentsOf: files.previous), previous)
    }

    func testDamagedCurrentCannotOverwriteKnownGoodPrevious() throws {
        let files = ProtectedBackupFiles(directory: directory)
        try save(ledger(1), files); try save(ledger(2), files)
        let previous = try Data(contentsOf: files.previous)
        let damaged = Data("damaged fixture".utf8)
        try damaged.write(to: files.current)
        XCTAssertThrowsError(try save(ledger(3), files))
        XCTAssertEqual(try Data(contentsOf: files.current), damaged)
        XCTAssertEqual(try Data(contentsOf: files.previous), previous)
        XCTAssertEqual(try plain(files.previous), Data(ledger(1).utf8))
    }

    func testDifferentPasswordCannotReplaceExistingCopy() throws {
        let files = ProtectedBackupFiles(directory: directory)
        try save(ledger(1), files)
        let current = try Data(contentsOf: files.current)
        let otherPassword = "A different recovery password 123"
        let encrypted = try ProtectedBackup.encrypt(ledger(2), password: otherPassword)
        XCTAssertThrowsError(try files.save(encrypted, exactJSON: ledger(2), password: otherPassword))
        XCTAssertEqual(try Data(contentsOf: files.current), current)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.previous.path))
    }

    func testFailureWritingPreviousLeavesCurrentUntouched() throws {
        let original = ProtectedBackupFiles(directory: directory)
        try save(ledger(1), original)
        let current = try Data(contentsOf: original.current)
        let files = ProtectedBackupFiles(directory: directory, writer: { data, url in
            if url.lastPathComponent.contains("-previous.") { throw Injected.unavailable }
            try data.write(to: url, options: .atomic)
        })
        XCTAssertThrowsError(try save(ledger(2), files))
        XCTAssertEqual(try Data(contentsOf: files.current), current)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.previous.path))
    }

    func testFailureWritingCurrentKeepsVerifiedFallback() throws {
        let original = ProtectedBackupFiles(directory: directory)
        try save(ledger(1), original)
        let files = ProtectedBackupFiles(directory: directory, writer: { data, url in
            if url.lastPathComponent.contains("-current.") { throw Injected.unavailable }
            try data.write(to: url, options: .atomic)
        })
        XCTAssertThrowsError(try save(ledger(2), files))
        XCTAssertEqual(try plain(files.current), Data(ledger(1).utf8))
        XCTAssertEqual(try plain(files.previous), Data(ledger(1).utf8))
    }

    func testSilentCurrentCorruptionIsDetectedAndCurrentRollsBack() throws {
        let original = ProtectedBackupFiles(directory: directory)
        try save(ledger(1), original)
        var corrupted = false
        let files = ProtectedBackupFiles(directory: directory, writer: { data, url in
            if url.lastPathComponent.contains("-current."), !corrupted {
                corrupted = true
                try Data("provider returned success but damaged bytes".utf8).write(to: url, options: .atomic)
            } else { try data.write(to: url, options: .atomic) }
        })
        XCTAssertThrowsError(try save(ledger(2), files))
        XCTAssertTrue(corrupted)
        XCTAssertEqual(try plain(files.current), Data(ledger(1).utf8))
        XCTAssertEqual(try plain(files.previous), Data(ledger(1).utf8))
    }

    func testSilentPreviousCorruptionPreventsReplacingCurrent() throws {
        let original = ProtectedBackupFiles(directory: directory)
        try save(ledger(1), original)
        let current = try Data(contentsOf: original.current)
        let files = ProtectedBackupFiles(directory: directory, writer: { data, url in
            if url.lastPathComponent.contains("-previous.") {
                try Data("bad fallback".utf8).write(to: url, options: .atomic)
            } else { try data.write(to: url, options: .atomic) }
        })
        XCTAssertThrowsError(try save(ledger(2), files))
        XCTAssertEqual(try Data(contentsOf: files.current), current)
        XCTAssertEqual(try plain(files.current), Data(ledger(1).utf8))
    }

    @discardableResult
    private func save(_ json: String, _ files: ProtectedBackupFiles) throws -> ProtectedBackupFiles.SaveResult {
        try files.save(ProtectedBackup.encrypt(json, password: password), exactJSON: json, password: password)
    }
    private func plain(_ url: URL) throws -> Data {
        Data(try ProtectedBackup.decrypt(Data(contentsOf: url), password: password).utf8)
    }
    private func ledger(_ cents: Int, stamp: String = "2026-11-03T00:00:00Z") -> String {
        """
        { "app": "lumo", "exportedAt": "\(stamp)", "state": {
          "accounts": [], "transactions": [{ "amount": \(cents), "comment": "Привет é 😀" }]
        } }

        """
    }
}
