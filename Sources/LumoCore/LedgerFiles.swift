import Foundation

/// Stores the canonical exported JSON, without re-encoding its financial fields.
public final class LedgerFiles {
    public let primary: URL
    public let backup: URL
    private let write: (Data, URL) throws -> Void

    public init(directory: URL, writer: @escaping (Data, URL) throws -> Void = { data, url in
        try data.write(to: url, options: .atomic)
    }) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        primary = directory.appendingPathComponent("ledger.json")
        backup = directory.appendingPathComponent("ledger.backup.json")
        write = writer
    }

    /// A damaged existing container never silently becomes a fresh empty ledger.
    public func load(into engine: FinanceEngine) throws -> Bool {
        let exists = [primary, backup].filter { FileManager.default.fileExists(atPath: $0.path) }
        if exists.isEmpty {
            let text = try engine.exportJSON()
            try save(text, previous: text)
            return false
        }
        for url in exists {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let candidate = try FinanceEngine()
                try candidate.importJSON(text)
                _ = try candidate.snapshot()
                try engine.importJSON(text)
                return url == backup
            } catch { continue }
        }
        throw FinanceError.message("Не удалось прочитать данные и резервную копию. Файлы сохранены. Импортируйте исправную JSON-копию, чтобы восстановить доступ.")
    }

    public func save(_ next: String, previous: String) throws {
        // Preserve the last known good state before replacing the primary file.
        try write(Data(previous.utf8), backup)
        try write(Data(next.utf8), primary)
    }

    public func preserveForRecovery() throws {
        let folder = primary.deletingLastPathComponent().appendingPathComponent("Recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for url in [primary, backup] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
        }
    }
}
