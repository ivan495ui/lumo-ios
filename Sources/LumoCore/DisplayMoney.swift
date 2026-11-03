import Foundation

public enum DisplayMoneyError: LocalizedError {
    case invalidRates, missingRate
    public var errorDescription: String? {
        switch self {
        case .invalidRates: "Не удалось проверить валютные курсы"
        case .missingRate: "Для выбранной валюты пока нет курса"
        }
    }
}

/// Official daily BYN valuations per one currency unit, never ledger amounts.
public struct ExchangeRateTable: Codable, Equatable {
    public let date: String
    public let fetchedAt: Date
    public let bynPerUnit: [String: Decimal]

    public init(date: String, fetchedAt: Date, bynPerUnit: [String: Decimal]) throws {
        guard date.count == 10, date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              bynPerUnit["BYN"] == 1,
              ["USD", "RUB"].allSatisfy({ code in
                  guard let value = bynPerUnit[code] else { return false }
                  return !value.isNaN && value > 0 && value < 1_000_000
              }) else { throw DisplayMoneyError.invalidRates }
        self.date = date; self.fetchedAt = fetchedAt; self.bynPerUnit = bynPerUnit
    }

    private enum CodingKeys: String, CodingKey { case date, fetchedAt, bynPerUnit }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(date: values.decode(String.self, forKey: .date),
                      fetchedAt: values.decode(Date.self, forKey: .fetchedAt),
                      bynPerUnit: values.decode([String: Decimal].self, forKey: .bynPerUnit))
    }

    public static func fromNationalBank(_ data: Data, fetchedAt: Date = Date()) throws -> Self {
        struct Row: Decodable {
            let Date: String
            let Cur_Abbreviation: String
            let Cur_Scale: Int
            let Cur_OfficialRate: Decimal
        }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        let selected = ["USD", "RUB"].compactMap { code in rows.first { $0.Cur_Abbreviation == code } }
        guard selected.count == 2, Set(selected.map { String($0.Date.prefix(10)) }).count == 1,
              selected.allSatisfy({ $0.Cur_Scale > 0 && $0.Cur_Scale <= 1_000_000 && $0.Cur_OfficialRate > 0 }) else {
            throw DisplayMoneyError.invalidRates
        }
        var rates: [String: Decimal] = ["BYN": 1]
        for row in selected { rates[row.Cur_Abbreviation] = row.Cur_OfficialRate / Decimal(row.Cur_Scale) }
        return try Self(date: String(selected[0].Date.prefix(10)), fetchedAt: fetchedAt, bynPerUnit: rates)
    }

    public func units(cents: Int, from: String, to: String) throws -> Decimal {
        if from == to { return Decimal(cents) / 100 }
        guard let source = bynPerUnit[from], let target = bynPerUnit[to], source > 0, target > 0,
              !source.isNaN, !target.isNaN else { throw DisplayMoneyError.missingRate }
        return Decimal(cents) / 100 * source / target
    }
}

public struct MoneyValue: Equatable {
    public let units: Decimal
    public let currency: String
    public let roundedToWhole: Bool
    public let converted: Bool

    public init(units: Decimal, currency: String, roundedToWhole: Bool = false, converted: Bool = false) {
        self.units = units; self.currency = currency; self.roundedToWhole = roundedToWhole; self.converted = converted
    }
    public init(cents: Int, currency: String, roundedToWhole: Bool = false) {
        self.init(units: Decimal(cents) / 100, currency: currency, roundedToWhole: roundedToWhole)
    }
    public var symbol: String { ["BYN": "Br", "USD": "$", "RUB": "₽"][currency] ?? currency }
    public var symbolLeading: Bool { currency == "USD" }
    public var approximate: Bool { converted || (roundedToWhole && units != roundedUnits) }
    public var roundedUnits: Decimal {
        var original = units, result = Decimal()
        NSDecimalRound(&result, &original, roundedToWhole ? 0 : 2, .plain)
        return result
    }
    public var number: String {
        let value = roundedUnits
        var original = value, whole = Decimal()
        NSDecimalRound(&whole, &original, 0, .plain)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = roundedToWhole ? 0 : 2
        formatter.minimumFractionDigits = roundedToWhole || whole == value ? 0 : 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }
    public func text(sign: String = "") -> String {
        let prefix = approximate ? "≈ " : ""
        return symbolLeading ? "\(prefix)\(sign)\(symbol)\(number)" : "\(prefix)\(sign)\(number) \(symbol)"
    }
}
