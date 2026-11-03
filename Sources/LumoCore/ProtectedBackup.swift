import Foundation
import CryptoKit
import CommonCrypto
import Security

/// Encrypts the canonical ledger export without parsing or re-encoding its contents.
/// File placement, secret storage, and validation of a restored ledger belong to callers.
public enum ProtectedBackup {
    public static let maximumFileSizeBytes = 32 * 1_024 * 1_024
    public static let minimumPasswordLength = 10
    public static let maximumPasswordUTF8Bytes = 1_024

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case passwordTooShort
        case passwordTooLong
        case emptyPassword
        case fileTooLarge
        case invalidEnvelope
        case unsupportedVersion(Int)
        case randomGenerationFailed
        case keyDerivationFailed
        case authenticationFailed
        case invalidPayload

        public var errorDescription: String? {
            switch self {
            case .passwordTooShort: return "Пароль восстановления должен содержать минимум 10 символов."
            case .passwordTooLong: return "Пароль восстановления слишком длинный."
            case .emptyPassword: return "Введите пароль восстановления."
            case .fileTooLarge: return "Защищённая копия превышает допустимый размер 32 МБ."
            case .invalidEnvelope: return "Формат защищённой копии повреждён или не поддерживается."
            case .unsupportedVersion: return "Эта версия защищённой копии пока не поддерживается."
            case .randomGenerationFailed: return "Не удалось безопасно создать защищённую копию."
            case .keyDerivationFailed: return "Не удалось подготовить ключ защищённой копии."
            case .authenticationFailed: return "Неверный пароль или защищённая копия повреждена."
            case .invalidPayload: return "Содержимое защищённой копии не является текстом UTF-8."
            }
        }
    }

    private static let magic = "lumo.protected-backup"
    private static let version = 1
    private static let kdf = "PBKDF2-HMAC-SHA256"
    private static let iterations = 600_000
    private static let saltLength = 16
    private static let nonceLength = 12
    private static let tagLength = 16
    // Base64 expands the combined box by 4/3. Reserve ample fixed JSON/header space.
    private static let maximumPlaintextBytes = (maximumFileSizeBytes - 1_024) / 4 * 3 - nonceLength - tagLength

    private struct Envelope: Codable {
        let magic: String
        let version: Int
        let kdf: String
        let iterations: Int
        let salt: Data
        let combined: Data
    }

    public static func encrypt(_ json: String, password: String) throws -> Data {
        try validatePassword(password, encrypting: true)
        guard json.utf8.count <= maximumPlaintextBytes else { throw Error.fileTooLarge }
        let salt = try randomBytes(count: saltLength)
        let nonce = try AES.GCM.Nonce(data: randomBytes(count: nonceLength))
        let key = try deriveKey(password: password, salt: salt)
        let sealed = try AES.GCM.seal(Data(json.utf8), using: key, nonce: nonce,
                                      authenticating: authenticatedHeader(salt: salt))
        guard let combined = sealed.combined else { throw Error.invalidEnvelope }
        let envelope = Envelope(magic: magic, version: version, kdf: kdf,
                                iterations: iterations, salt: salt, combined: combined)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let result = try encoder.encode(envelope)
        guard result.count <= maximumFileSizeBytes else { throw Error.fileTooLarge }
        return result
    }

    public static func decrypt(_ data: Data, password: String) throws -> String {
        // Reject untrusted size, password, and work-factor fields before expensive PBKDF2.
        guard data.count <= maximumFileSizeBytes else { throw Error.fileTooLarge }
        try validatePassword(password, encrypting: false)
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw Error.invalidEnvelope
        }
        guard envelope.magic == magic else { throw Error.invalidEnvelope }
        guard envelope.version == version else { throw Error.unsupportedVersion(envelope.version) }
        guard envelope.kdf == kdf, envelope.iterations == iterations,
              envelope.salt.count == saltLength,
              envelope.combined.count >= nonceLength + tagLength,
              envelope.combined.count <= maximumPlaintextBytes + nonceLength + tagLength else {
            throw Error.invalidEnvelope
        }
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.SealedBox(combined: envelope.combined)
        } catch {
            throw Error.invalidEnvelope
        }
        let key = try deriveKey(password: password, salt: envelope.salt)
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(sealed, using: key,
                                         authenticating: authenticatedHeader(salt: envelope.salt))
        } catch {
            throw Error.authenticationFailed
        }
        guard let json = String(data: plaintext, encoding: .utf8) else { throw Error.invalidPayload }
        return json
    }

    private static func validatePassword(_ password: String, encrypting: Bool) throws {
        guard password.utf8.count <= maximumPasswordUTF8Bytes else { throw Error.passwordTooLong }
        guard !password.isEmpty else { throw Error.emptyPassword }
        if encrypting && password.count < minimumPasswordLength { throw Error.passwordTooShort }
    }

    private static func authenticatedHeader(salt: Data) -> Data {
        // A fixed, unambiguous representation independent of JSON field order/whitespace.
        var header = Data("\(magic)\n\(version)\n\(kdf)\n\(iterations)\n".utf8)
        header.append(salt)
        return header
    }

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw Error.randomGenerationFailed }
        return bytes
    }

    private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        // CommonCrypto is supplied by the Apple SDK; no external crypto dependency is needed.
        // Explicit byte lengths preserve embedded NULs and avoid Unicode normalization.
        var passwordBytes = Data(password.utf8)
        var keyBytes = Data(count: 32)
        defer {
            passwordBytes.resetBytes(in: 0..<passwordBytes.count)
            keyBytes.resetBytes(in: 0..<keyBytes.count)
        }
        let status = passwordBytes.withUnsafeBytes { passwordBuffer in
            salt.withUnsafeBytes { saltBuffer in
                keyBytes.withUnsafeMutableBytes { keyBuffer in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.baseAddress!.assumingMemoryBound(to: Int8.self), passwordBuffer.count,
                        saltBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), saltBuffer.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                        keyBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), keyBuffer.count)
                }
            }
        }
        guard status == kCCSuccess else { throw Error.keyDerivationFailed }
        return SymmetricKey(data: keyBytes)
    }
}
