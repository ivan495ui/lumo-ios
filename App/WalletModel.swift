import SwiftUI
import LumoCore
import UniformTypeIdentifiers

@MainActor
final class WalletModel: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    @Published var error: String?
    @Published private(set) var recoveryRequired = false
    @Published private(set) var restoredBackup = false
    private var engine: FinanceEngine?
    private var files: LedgerFiles?
    private var selectedMonth: String?

    init() {
        do {
            let engine = try FinanceEngine()
            self.engine = engine
            #if targetEnvironment(simulator)
            let demo = ProcessInfo.processInfo.environment["LUMO_DEMO"] == "1"
            #else
            let demo = false
            #endif
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent(demo ? "lumo-preview" : "lumo", isDirectory: true)
            let files = try LedgerFiles(directory: folder)
            self.files = files
            do { restoredBackup = try files.load(into: engine) }
            catch { recoveryRequired = true; self.error = error.localizedDescription; return }
            #if targetEnvironment(simulator)
            if demo {
                if try engine.snapshot().state.transactions.isEmpty { try seedDemo(engine, files) }
            }
            #endif
            snapshot = try engine.snapshot()
        } catch { recoveryRequired = true; self.error = error.localizedDescription }
    }

    var currency: String { snapshot?.state.settings.currency ?? "BYN" }
    var transactions: [LedgerTransaction] {
        (snapshot?.state.transactions ?? []).sorted {
            $0.date == $1.date ? ($0.createdAt ?? "") > ($1.createdAt ?? "") : $0.date > $1.date
        }
    }
    var visibleAccounts: [Account] {
        (snapshot?.derived.accounts ?? []).filter { !$0.archived && !($0.kind == "crypto" && snapshot?.state.settings.hideCrypto == true) }
    }

    @discardableResult
    func mutate(_ operation: String, _ args: [Any] = [], failure: ((String) -> Void)? = nil) -> Bool {
        guard !recoveryRequired, let engine, let files else { return false }
        do {
            let previous = try engine.exportJSON()
            do {
                try engine.perform(operation, args: args)
                let next = try engine.snapshot(month: selectedMonth)
                try files.save(engine.exportJSON(), previous: previous)
                snapshot = next
                return true
            } catch {
                try? engine.importJSON(previous)
                throw error
            }
        } catch {
            if let failure { failure(error.localizedDescription) }
            else { self.error = error.localizedDescription }
            return false
        }
    }

    func changeMonth(_ delta: Int) {
        guard let snapshot, let engine else { return }
        let parts = snapshot.month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2,
              let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: 1)),
              let shifted = Calendar.current.date(byAdding: .month, value: delta, to: date) else { return }
        selectedMonth = Self.monthKey(shifted)
        do { self.snapshot = try engine.snapshot(month: selectedMonth) }
        catch { self.error = error.localizedDescription }
    }

    func cents(_ text: String) throws -> Int {
        guard let engine else { throw FinanceError.message("Ядро не загружено") }
        return try engine.cents(text)
    }
    func prepared(_ draft: [String: Any], existingID: String? = nil) -> PreparedTransaction? {
        guard let engine else { return nil }
        var payload: [String: Any] = ["draft": draft]
        if let existingID { payload["id"] = existingID }
        return try? engine.value("prepare", payload)
    }
    func preview() throws -> RebalancePreview {
        guard let engine else { throw FinanceError.message("Ядро не загружено") }
        return try engine.preview()
    }
    func exportText() throws -> String {
        guard let engine else { throw FinanceError.message("Ядро не загружено") }
        return try engine.exportJSON()
    }
    func inspectImport(_ text: String) throws -> Snapshot {
        let candidate = try FinanceEngine()
        try candidate.importJSON(text)
        return try candidate.snapshot()
    }
    func importText(_ text: String) -> Bool {
        guard let engine, let files else { return false }
        do {
            _ = try inspectImport(text)
            let previous = try engine.exportJSON()
            do {
                try engine.importJSON(text)
                let next = try engine.snapshot(month: selectedMonth)
                if recoveryRequired { try files.preserveForRecovery() }
                try files.save(engine.exportJSON(), previous: previous)
                recoveryRequired = false
                snapshot = next
                return true
            } catch { try? engine.importJSON(previous); throw error }
        } catch { self.error = error.localizedDescription; return false }
    }
    func categoryName(_ id: String?) -> String? { snapshot?.state.categories.first { $0.id == id }?.name }
    func accountName(_ id: String?) -> String? { snapshot?.state.accounts.first { $0.id == id }?.name }
    func envelopeName(_ id: String?) -> String? { snapshot?.state.envelopes.first { $0.id == id }?.name }

    static func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func monthKey(_ date: Date) -> String { String(dateKey(date).prefix(7)) }

    #if targetEnvironment(simulator)
    private func seedDemo(_ engine: FinanceEngine, _ files: LedgerFiles) throws {
        let previous = try engine.exportJSON()
        let date = Self.dateKey(Date())
        try engine.perform("addTransaction", args: [["type": "income", "amount": 100000, "accountId": "acc_card", "categoryId": "cat_income_music", "date": date, "comment": "Продажа бита"]])
        try engine.perform("addTransaction", args: [["type": "expense", "amount": 8500, "accountId": "acc_card", "envelopeId": "env_personal", "categoryId": "cat_food", "date": date, "comment": "Кофе и продукты"]])
        try engine.perform("addTransaction", args: [["type": "transfer", "amount": 12000, "accountId": "acc_card", "toAccountId": "acc_cash", "date": date]])
        try engine.perform("saveAsset", args: ["acc_crypto", ["id": "demo_usdt", "symbol": "USDT", "name": "Tether", "initialQty": 120, "price": 330]])
        try files.save(engine.exportJSON(), previous: previous)
    }
    #endif
}

struct LedgerDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else {
            throw FinanceError.message("Не удалось прочитать JSON")
        }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
