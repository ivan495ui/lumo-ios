import Foundation
import Combine
import LumoCore

enum BackupServiceError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

@MainActor
final class AutomaticBackup: ObservableObject {
    @Published private(set) var configured: Bool
    @Published private(set) var isWorking = false
    @Published private(set) var status = "Автоматическая копия не настроена"
    @Published private(set) var lastWrite: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var folderName: String

    private let defaults: UserDefaults
    private let namespace: String
    private let pendingURL: URL
    private let setupError: String?
    private var worker: Task<Void, Never>?
    private var generation = UUID()
    private static let writer = BackupFolderWriter()

    init(defaults: UserDefaults = .standard, namespace: String = "lumo") {
        self.defaults = defaults
        self.namespace = namespace
        let prefix = "\(namespace).automaticBackup."
        configured = defaults.data(forKey: prefix + "bookmark") != nil
        folderName = defaults.string(forKey: prefix + "folderName") ?? "Выбранная папка"
        lastWrite = defaults.object(forKey: prefix + "lastWrite") as? Date
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent(namespace + "-automatic-backup", isDirectory: true)
        pendingURL = directory.appendingPathComponent("pending.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                  attributes: [.protectionKey: FileProtectionType.complete])
            var excluded = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try excluded.setResourceValues(values)
            setupError = nil
        } catch {
            setupError = "Не удалось создать защищённую локальную очередь копирования."
        }
        if configured { status = "Папка подключена. Проверяем копию при открытии приложения." }
    }

    /// Call only after the canonical local ledger has committed successfully.
    /// The queue is local file-protected JSON, like the canonical ledger; external files are encrypted.
    func record(_ exactJSON: String) {
        guard configured else { return }
        do {
            if let setupError { throw BackupServiceError.message(setupError) }
            try Data(exactJSON.utf8).write(to: pendingURL, options: [.atomic, .completeFileProtection])
            status = "Есть изменения для автоматической копии"
            retry()
        } catch {
            lastError = "Не удалось поставить копию в очередь. Журнал сохранён локально; повтори копирование."
            status = "Копия требует внимания"
        }
    }

    func configure(folder: URL, password: String, initialJSON: String) async throws {
        guard !isWorking else { throw BackupServiceError.message("Дождись текущего копирования.") }
        guard !configured else { throw BackupServiceError.message("Сначала отключи прежнюю папку. Её копии останутся на месте.") }
        guard password.count >= 10 else { throw BackupServiceError.message("Нужен пароль не короче 10 символов.") }
        if let setupError { throw BackupServiceError.message(setupError) }
        isWorking = true
        defer { if worker == nil { isWorking = false } }
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        let bookmark = try folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        // Authenticate an existing copy before accepting a new configuration.
        try await Self.writer.validateExisting(folder: folder, password: password, namespace: namespace)
        try SecureSettingsStore.savePassword(password, namespace: namespace)
        try Data(initialJSON.utf8).write(to: pendingURL, options: [.atomic, .completeFileProtection])
        defaults.set(bookmark, forKey: key("bookmark"))
        defaults.set(folder.lastPathComponent, forKey: key("folderName"))
        folderName = folder.lastPathComponent
        configured = true
        lastError = nil
        generation = UUID()
        retry()
    }

    /// Disconnecting never removes files from the chosen external folder.
    func disconnect() {
        generation = UUID(); worker?.cancel(); worker = nil
        configured = false; isWorking = false
        defaults.removeObject(forKey: key("bookmark"))
        defaults.removeObject(forKey: key("folderName"))
        defaults.removeObject(forKey: key("lastWrite"))
        SecureSettingsStore.removePassword(namespace: namespace)
        try? FileManager.default.removeItem(at: pendingURL)
        lastWrite = nil; lastError = nil
        status = "Автоматическая копия отключена. Файлы в папке сохранены."
    }

    func retry() {
        guard configured, worker == nil else { return }
        guard FileManager.default.fileExists(atPath: pendingURL.path) else { return }
        let token = generation
        isWorking = true
        worker = Task { [weak self] in
            guard let self else { return }
            await self.flush(generation: token)
            if token == self.generation { self.isWorking = false; self.worker = nil }
        }
    }

    private func flush(generation token: UUID) async {
        while configured, token == generation, !Task.isCancelled {
            do {
                let pending = try Data(contentsOf: pendingURL)
                guard let json = String(data: pending, encoding: .utf8) else {
                    throw BackupServiceError.message("Локальная очередь копии повреждена. Открой приложение заново для повторной постановки журнала.")
                }
                guard let bookmark = defaults.data(forKey: key("bookmark")) else { return }
                var stale = false
                let folder = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
                let accessed = folder.startAccessingSecurityScopedResource()
                defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
                if stale {
                    defaults.set(try folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), forKey: key("bookmark"))
                }
                let password = try SecureSettingsStore.password(namespace: namespace)
                status = "Создаём защищённую копию…"
                let encrypted = try await Task.detached(priority: .utility) {
                    try ProtectedBackup.encrypt(json, password: password)
                }.value
                guard token == generation, !Task.isCancelled else { return }
                let result = try await Self.writer.write(encrypted, exactJSON: json, folder: folder,
                                                         password: password, namespace: namespace)
                guard token == generation, !Task.isCancelled else { return }
                if let date = result.writtenAt { lastWrite = date; defaults.set(date, forKey: key("lastWrite")) }
                lastError = nil
                if result.uploaded { status = "iCloud сообщил о завершении загрузки копии" }
                else if result.unchanged { status = "Копия в папке актуальна. Загрузка в облако не подтверждена." }
                else { status = "Копия сохранена в папку. Загрузка в облако не подтверждена." }
                if try Data(contentsOf: pendingURL) == pending {
                    try FileManager.default.removeItem(at: pendingURL)
                    return
                }
            } catch {
                guard token == generation, !Task.isCancelled else { return }
                lastError = error.localizedDescription
                status = "Не удалось обновить внешнюю копию. Изменения остаются локально; повторим при открытии."
                return
            }
        }
    }

    private func key(_ suffix: String) -> String { "\(namespace).automaticBackup.\(suffix)" }
}

/// A single actor serializes provider writes, including a configuration changed mid-flight.
private struct BackupWriteResult {
    let uploaded: Bool
    let writtenAt: Date?
    let unchanged: Bool
}

private actor BackupFolderWriter {
    func validateExisting(folder: URL, password: String, namespace: String) throws {
        var coordinatorError: NSError?
        var validationError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: folder, options: [], error: &coordinatorError) { coordinatedFolder in
            do {
                try ProtectedBackupFiles(directory: coordinatedFolder, namespace: namespace).validateExisting(password: password)
            } catch { validationError = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let validationError { throw validationError }
    }

    func write(_ data: Data, exactJSON: String, folder: URL, password: String, namespace: String) throws -> BackupWriteResult {
        var coordinationError: NSError?
        var writeError: Error?
        var uploaded = false
        var writtenAt: Date?
        var unchanged = false
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: folder, options: [], error: &coordinationError) { coordinatedFolder in
            do {
                let files = ProtectedBackupFiles(directory: coordinatedFolder, namespace: namespace)
                unchanged = try files.save(data, exactJSON: exactJSON, password: password) == .unchanged
                let values = try? files.current.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .contentModificationDateKey])
                uploaded = values?.isUbiquitousItem == true && values?.ubiquitousItemIsUploaded == true
                writtenAt = values?.contentModificationDate
                if !unchanged && writtenAt == nil { writtenAt = Date() }
            } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
        return BackupWriteResult(uploaded: uploaded, writtenAt: writtenAt, unchanged: unchanged)
    }
}
