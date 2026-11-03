import Foundation
import Combine
import LumoCore

@MainActor
final class ExchangeDisplay: ObservableObject {
    static let currencies = ["BYN", "USD", "RUB"]
    @Published private(set) var selection: String
    @Published private(set) var table: ExchangeRateTable?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    private let defaults: UserDefaults
    private let selectionKey = "display.currency.v1"
    private let ratesKey = "display.nbrb-rates.v1"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let saved = defaults.string(forKey: selectionKey) ?? ""
        selection = Self.currencies.contains(saved) ? saved : ""
        if let data = defaults.data(forKey: ratesKey) {
            table = try? JSONDecoder().decode(ExchangeRateTable.self, from: data)
        }
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["LUMO_FX_TEST"] == "1" {
            table = try? ExchangeRateTable(date: WalletModel.dateKey(Date()), fetchedAt: Date(), bynPerUnit: ["BYN": 1, "USD": 3, "RUB": Decimal(string: "0.04")!])
        }
        #endif
    }

    func selected(base: String) -> String { selection.isEmpty ? base : selection }
    func effective(base: String) -> String {
        let requested = selected(base: base)
        return requested == base || table?.bynPerUnit[requested] != nil && table?.bynPerUnit[base] != nil ? requested : base
    }
    func value(_ cents: Int, base: String, rounded: Bool = false) -> MoneyValue {
        let target = effective(base: base)
        if target != base, let units = try? table?.units(cents: cents, from: base, to: target) {
            return MoneyValue(units: units, currency: target, roundedToWhole: rounded, converted: true)
        }
        return MoneyValue(cents: cents, currency: base, roundedToWhole: rounded)
    }
    func select(_ code: String, base: String) {
        guard Self.currencies.contains(code) else { return }
        selection = code; defaults.set(code, forKey: selectionKey)
        Task { await refresh(base: base) }
    }
    func refresh(base: String, force: Bool = false) async {
        guard !isLoading else { return }
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["LUMO_FX_TEST"] == "1" { return }
        #endif
        if !force {
            if selected(base: base) == base { return }
            if let table, Date().timeIntervalSince(table.fetchedAt) < 4 * 60 * 60 { return }
        }
        isLoading = true; defer { isLoading = false }
        do {
            let url = URL(string: "https://api.nbrb.by/exrates/rates?periodicity=0")!
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000 else { throw DisplayMoneyError.invalidRates }
            let next = try ExchangeRateTable.fromNationalBank(data)
            table = next; lastError = nil
            defaults.set(try JSONEncoder().encode(next), forKey: ratesKey)
        } catch {
            lastError = table == nil ? "Курс недоступен. Пока показываем валюту учёта." : "Не удалось обновить курс. Используется сохранённый."
        }
    }
    func status(base: String) -> String? {
        guard selected(base: base) != base else { return nil }
        guard let table, effective(base: base) != base else { return lastError ?? "Загружаем курс. Пока показываем \(base)." }
        let day = String(table.date.suffix(2)), month = String(table.date.dropFirst(5).prefix(2))
        return "Курс НБРБ · \(day).\(month).\(table.date.prefix(4))\(lastError == nil ? "" : " · сохранённый")"
    }
}
