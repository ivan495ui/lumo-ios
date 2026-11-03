import Foundation

/// Rotation only. Callers own file-provider coordination, secret storage and serialization.
public final class ProtectedBackupFiles {
    public enum SaveResult: Equatable { case written, unchanged }
    public enum Error: Swift.Error, LocalizedError {
        case invalidJournal, payloadMismatch, writeVerificationFailed
        public var errorDescription: String? {
            switch self {
            case .invalidJournal: return "Копия не содержит журнал lumo. Прежние файлы сохранены."
            case .payloadMismatch: return "Проверка новой копии не пройдена. Прежние файлы сохранены."
            case .writeVerificationFailed: return "Не удалось проверить записанную копию. Используй предыдущую исправную копию."
            }
        }
    }

    public let current: URL
    public let previous: URL
    private let writer: (Data, URL) throws -> Void

    public init(directory: URL, namespace: String = "lumo",
                writer: @escaping (Data, URL) throws -> Void = { data, url in
                    try data.write(to: url, options: .atomic)
                }) {
        current = directory.appendingPathComponent("\(namespace)-current.lumobackup")
        previous = directory.appendingPathComponent("\(namespace)-previous.lumobackup")
        self.writer = writer
    }

    public func validateExisting(password: String) throws {
        if FileManager.default.fileExists(atPath: current.path) {
            let json = try ProtectedBackup.decrypt(read(current), password: password)
            _ = try statePayload(json)
        }
    }

    @discardableResult
    public func save(_ encrypted: Data, exactJSON: String, password: String) throws -> SaveResult {
        let restored = try ProtectedBackup.decrypt(encrypted, password: password)
        guard Data(restored.utf8) == Data(exactJSON.utf8) else { throw Error.payloadMismatch }
        let nextState = try statePayload(exactJSON)
        var old: Data?
        if FileManager.default.fileExists(atPath: current.path) {
            let bytes = try read(current)
            let json = try ProtectedBackup.decrypt(bytes, password: password)
            if try statePayload(json) == nextState { return .unchanged }
            old = bytes
            // The current known-good file remains untouched until its fallback is verified.
            try writer(bytes, previous)
            guard try read(previous) == bytes else { throw Error.writeVerificationFailed }
        }
        do {
            try writer(encrypted, current)
            let verified = try ProtectedBackup.decrypt(read(current), password: password)
            guard Data(verified.utf8) == Data(exactJSON.utf8) else { throw Error.writeVerificationFailed }
        } catch {
            // Best effort restores current too; the verified previous file remains available.
            if let old { try? writer(old, current) }
            throw error
        }
        return .written
    }

    private func read(_ url: URL) throws -> Data {
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > ProtectedBackup.maximumFileSizeBytes { throw ProtectedBackup.Error.fileTooLarge }
        let data = try Data(contentsOf: url)
        guard data.count <= ProtectedBackup.maximumFileSizeBytes else { throw ProtectedBackup.Error.fileTooLarge }
        return data
    }

    // Export metadata such as exportedAt must not erase the previous distinct journal on app launch.
    private func statePayload(_ json: String) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        guard let envelope = object as? [String: Any], let state = envelope["state"] as? [String: Any],
              state["accounts"] is [Any], state["transactions"] is [Any] else { throw Error.invalidJournal }
        return try JSONSerialization.data(withJSONObject: state, options: .sortedKeys)
    }
}
