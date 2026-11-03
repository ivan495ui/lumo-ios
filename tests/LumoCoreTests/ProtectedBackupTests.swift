import Foundation
import XCTest
@testable import LumoCore

final class ProtectedBackupTests: XCTestCase {
    private let password = "Сохранить мои данные 🔑"
    private let ledger = """
    { "amount": 9007199254740991, "minor": 1, "comment": "Привет 😀 é", "escaped": "\\u0430" }

    """

    func testRestorePreservesExactExportBytesAndUnicodePassword() throws {
        let encrypted = try ProtectedBackup.encrypt(ledger, password: password)
        let restored = try ProtectedBackup.decrypt(encrypted, password: password)
        XCTAssertEqual(Data(restored.utf8), Data(ledger.utf8))
        XCTAssertFalse(String(decoding: encrypted, as: UTF8.self).contains("9007199254740991"))
    }

    func testRestoreIndependentNodeCryptoFixture() throws {
        // Produced independently with Node crypto PBKDF2-SHA256 + AES-256-GCM,
        // fixed salt 00...0f and nonce 10...1b; exercises interoperability and AAD.
        let fixture = #"{"magic":"lumo.protected-backup","version":1,"kdf":"PBKDF2-HMAC-SHA256","iterations":600000,"salt":"AAECAwQFBgcICQoLDA0ODw==","combined":"EBESExQVFhcYGRobfe+Bsm1YSmXibvM+M1V6R9ra4ctoSl5eYB09HyhQUAMtthSJb4FB/8rwS/NUwaGLBWOa+KHLZk70PGvSBA=="}"#
        let restored = try ProtectedBackup.decrypt(Data(fixture.utf8), password: "reference-password-123")
        XCTAssertEqual(Data(restored.utf8), Data("{ \"amount\": 1, \"text\": \"Привет 😀\" }\n".utf8))
    }

    func testRepeatedBackupsHaveIndependentSaltAndNonceAndBothRestore() throws {
        let first = try ProtectedBackup.encrypt(ledger, password: password)
        let second = try ProtectedBackup.encrypt(ledger, password: password)
        let firstFields = try fields(first)
        let secondFields = try fields(second)
        XCTAssertNotEqual(firstFields["salt"] as? String, secondFields["salt"] as? String)
        let firstBox = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(firstFields["combined"] as? String)))
        let secondBox = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(secondFields["combined"] as? String)))
        XCTAssertNotEqual(firstBox.prefix(12), secondBox.prefix(12))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(Data(try ProtectedBackup.decrypt(first, password: password).utf8), Data(ledger.utf8))
        XCTAssertEqual(Data(try ProtectedBackup.decrypt(second, password: password).utf8), Data(ledger.utf8))
    }

    func testWrongPasswordAndDamagedCiphertextDoNotReturnPlaintext() throws {
        let encrypted = try ProtectedBackup.encrypt(ledger, password: password)
        assertError(.authenticationFailed) {
            _ = try ProtectedBackup.decrypt(encrypted, password: "Другой длинный пароль")
        }
        let damaged = try mutate(encrypted) { fields in
            var combined = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fields["combined"] as? String)))
            combined[combined.count / 2] ^= 1
            fields["combined"] = combined.base64EncodedString()
        }
        assertError(.authenticationFailed) { _ = try ProtectedBackup.decrypt(damaged, password: password) }
        let damagedSalt = try mutate(encrypted) { fields in
            var salt = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fields["salt"] as? String)))
            salt[0] ^= 1
            fields["salt"] = salt.base64EncodedString()
        }
        assertError(.authenticationFailed) { _ = try ProtectedBackup.decrypt(damagedSalt, password: password) }
    }

    func testUnsupportedVersionsAndUntrustedKDFParametersAreRejected() throws {
        let encrypted = try ProtectedBackup.encrypt(ledger, password: password)
        let future = try mutate(encrypted) { $0["version"] = 2 }
        assertError(.unsupportedVersion(2)) { _ = try ProtectedBackup.decrypt(future, password: password) }
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["magic"] = "other.backup" },
            { $0["kdf"] = "PBKDF2-HMAC-SHA1" },
            { $0["iterations"] = 1 },
            { $0["iterations"] = Int.max },
            { $0["salt"] = Data(repeating: 1, count: 15).base64EncodedString() },
            { $0["combined"] = Data(repeating: 1, count: 27).base64EncodedString() }
        ]
        for change in changes {
            let malformed = try mutate(encrypted, change)
            assertError(.invalidEnvelope) { _ = try ProtectedBackup.decrypt(malformed, password: password) }
        }
    }

    func testMalformedAndTruncatedFilesAreRejected() throws {
        for data in [Data(), Data("{}".utf8), Data("not a backup".utf8)] {
            assertError(.invalidEnvelope) { _ = try ProtectedBackup.decrypt(data, password: password) }
        }
        let encrypted = try ProtectedBackup.encrypt(ledger, password: password)
        assertError(.invalidEnvelope) {
            _ = try ProtectedBackup.decrypt(Data(encrypted.dropLast()), password: password)
        }
    }

    func testSizeAndPasswordLimitsAreRejectedBeforeEnvelopeProcessing() {
        let oversized = Data(repeating: 0, count: ProtectedBackup.maximumFileSizeBytes + 1)
        assertError(.fileTooLarge) { _ = try ProtectedBackup.decrypt(oversized, password: password) }
        let oversizedExport = String(repeating: "a", count: ProtectedBackup.maximumFileSizeBytes)
        assertError(.fileTooLarge) { _ = try ProtectedBackup.encrypt(oversizedExport, password: password) }
        assertError(.passwordTooShort) { _ = try ProtectedBackup.encrypt(ledger, password: "123456789") }
        assertError(.emptyPassword) { _ = try ProtectedBackup.decrypt(Data(), password: "") }
        let oversizedPassword = String(repeating: "я", count: 513)
        assertError(.passwordTooLong) { _ = try ProtectedBackup.encrypt(ledger, password: oversizedPassword) }
        assertError(.passwordTooLong) { _ = try ProtectedBackup.decrypt(Data(), password: oversizedPassword) }
    }

    func testPasswordUTF8IsNotTruncatedAtEmbeddedNUL() throws {
        let exactPassword = "long-password\0suffix"
        let encrypted = try ProtectedBackup.encrypt(ledger, password: exactPassword)
        XCTAssertEqual(Data(try ProtectedBackup.decrypt(encrypted, password: exactPassword).utf8), Data(ledger.utf8))
        assertError(.authenticationFailed) {
            _ = try ProtectedBackup.decrypt(encrypted, password: "long-password")
        }
    }

    private func fields(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func mutate(_ data: Data, _ edit: (inout [String: Any]) throws -> Void) throws -> Data {
        var value = try fields(data)
        try edit(&value)
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private func assertError(_ expected: ProtectedBackup.Error, file: StaticString = #filePath,
                             line: UInt = #line, _ operation: () throws -> Void) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ProtectedBackup.Error, expected, file: file, line: line)
        }
    }
}
