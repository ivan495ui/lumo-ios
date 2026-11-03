import SwiftUI
import LumoCore
import UniformTypeIdentifiers
import Combine

@MainActor
final class WalletModel: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    @Published var error: String?
    @Published private(set) var recoveryRequired = false
    @Published private(set) var restoredBackup = false
    private var engine: FinanceEngine?
    private var files: LedgerFiles?
    private var selectedMonth: String?
    let preferences: UserDefaults
    let exchange: ExchangeDisplay
    let automaticBackup: AutomaticBackup
    let appLock: AppLock
    @Published private(set) var needsCurrencyConfirmation = false
    private var subscriptions = Set<AnyCancellable>()

    init() {
        #if targetEnvironment(simulator)
        let demo = ProcessInfo.processInfo.environment["LUMO_DEMO"] == "1"
        #else
        let demo = false
        #endif
        let namespace = demo ? "lumo-demo" : "lumo"
        let preferences = UserDefaults(suiteName: "\(namespace).native") ?? .standard
        self.preferences = preferences
        exchange = ExchangeDisplay(defaults: preferences)
        automaticBackup = AutomaticBackup(defaults: preferences, namespace: namespace)
        appLock = AppLock(defaults: preferences, namespace: namespace)
        exchange.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        do {
            let engine = try FinanceEngine()
            self.engine = engine
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
            needsCurrencyConfirmation = currency != "BYN" && preferences.string(forKey: "ledger.confirmed-units.v1") != currency
            if !needsCurrencyConfirmation { automaticBackup.record(try engine.exportJSON()) }
            Task { await exchange.refresh(base: currency) }
        } catch { recoveryRequired = true; self.error = error.localizedDescription }
    }

    var currency: String { snapshot?.state.settings.currency ?? "BYN" }
    var effectiveDisplayCurrency: String { exchange.effective(base: currency) }
    func displayValue(_ cents: Int, rounded: Bool = false) -> MoneyValue { exchange.value(cents, base: currency, rounded: rounded) }
    func displayMoney(_ cents: Int, rounded: Bool = false, sign: String = "") -> String { displayValue(cents, rounded: rounded).text(sign: sign) }
    func estimatedMoney(_ cents: Int) -> String {
        let value = displayValue(cents)
        return value.approximate ? value.text() : "≈ " + value.text()
    }
    func displayAmount(_ cents: Int) -> Decimal { displayValue(cents).units }
    func confirmCurrency(_ actualCurrency: String) -> Bool {
        guard ExchangeDisplay.currencies.contains(actualCurrency), mutate("updateSettings", [["currency": actualCurrency]]) else { return false }
        preferences.set(actualCurrency, forKey: "ledger.confirmed-units.v1")
        needsCurrencyConfirmation = false
        if let text = try? exportText() { automaticBackup.record(text) }
        Task { await exchange.refresh(base: currency) }
        return true
    }
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
                let exported = try engine.exportJSON()
                try files.save(exported, previous: previous)
                snapshot = next
                if !needsCurrencyConfirmation { automaticBackup.record(exported) }
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
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "−", with: "-")
        if normalized.hasPrefix("+") { normalized.removeFirst() }
        return try engine.cents(normalized)
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
    func importText(_ text: String, actualCurrency: String? = nil) -> Bool {
        guard let engine, let files else { return false }
        do {
            let candidate = try FinanceEngine()
            try candidate.importJSON(text)
            let incoming = try candidate.snapshot()
            guard incoming.state.settings.currency == "BYN" || actualCurrency != nil else { throw FinanceError.message("Уточни, в какой валюте вводились суммы в этой копии.") }
            if let actualCurrency {
                guard ExchangeDisplay.currencies.contains(actualCurrency) else { throw FinanceError.message("Неизвестная валюта") }
                try candidate.perform("updateSettings", args: [["currency": actualCurrency]])
            }
            let normalized = try candidate.exportJSON()
            let previous = try engine.exportJSON()
            do {
                try engine.importJSON(normalized)
                let next = try engine.snapshot(month: selectedMonth)
                if recoveryRequired { try files.preserveForRecovery() }
                try files.save(engine.exportJSON(), previous: previous)
                recoveryRequired = false
                snapshot = next
                needsCurrencyConfirmation = false
                preferences.set(currency, forKey: "ledger.confirmed-units.v1")
                automaticBackup.record(try engine.exportJSON())
                Task { await exchange.refresh(base: currency) }
                return true
            } catch { try? engine.importJSON(previous); throw error }
        } catch { self.error = error.localizedDescription; return false }
    }
    func categoryName(_ id: String?) -> String? { snapshot?.state.categories.first { $0.id == id }?.name }
    func accountName(_ id: String?) -> String? { snapshot?.state.accounts.first { $0.id == id }?.name }
    func envelopeName(_ id: String?) -> String? { snapshot?.state.envelopes.first { $0.id == id }?.name }
    func cryptoQuantity(_ transaction: LedgerTransaction) -> String {
        guard let qty = transaction.qty else { return "" }
        let ticker = snapshot?.derived.cryptoAssets.first { $0.id == transaction.assetId }?.symbol ?? ""
        let sign = transaction.type == "crypto_buy" ? "+" : "−"
        return "\(sign)\(qty.formatted(.number.precision(.fractionLength(0...8)))) \(ticker)"
    }

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
