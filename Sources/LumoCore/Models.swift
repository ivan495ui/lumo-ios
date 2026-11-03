import Foundation

public struct Snapshot: Decodable {
    public let state: FinanceState
    public let derived: Derived
    public let month: String
    public let summary: Summary
    public let months: [MonthPoint]
}

public struct FinanceState: Decodable {
    public let version: Int
    public let settings: Settings
    public let accounts: [Account]
    public let envelopes: [Envelope]
    public let categories: [Category]
    public let transactions: [Transaction]
}

public struct Settings: Decodable {
    public let currency: String
    public let balanceView: String
    public let hideCrypto: Bool
    public let autoReserve: Bool
    public let taxEnabled: Bool
    public let taxRate: Double
}

public struct Account: Decodable, Identifiable {
    public let id: String
    public let kind: String
    public let name: String
    public let opening: Int
    public let archived: Bool
    public let color: String
    public let assets: [Asset]?
    public let balance: Int?
    public var symbol: String { kind == "crypto" ? "bitcoinsign.circle.fill" : kind == "cash" ? "banknote.fill" : "creditcard.fill" }
}

public struct Asset: Decodable, Identifiable {
    public let id: String
    public let symbol: String
    public let name: String
    public let price: Int
    public let initialQty: Double
    public let qty: Double?
    public let value: Int?
    public let accountId: String?
    public let updatedAt: String?
}

public struct Envelope: Decodable, Identifiable {
    public let id: String
    public let name: String
    public let percent: Double?
    public let goal: Int
    public let color: String
    public let icon: String
    public let balance: Int?
    public var symbol: String { icon == "music" ? "music.note" : icon == "shield" ? "shield.fill" : "person.fill" }
}

public struct Category: Decodable, Identifiable {
    public let id: String
    public let kind: String
    public let name: String
    public let taxable: Bool
    public let icon: String?
}

public struct Transaction: Decodable, Identifiable {
    public let id: String
    public let type: String
    public let date: String
    public let amount: Int
    public let accountId: String?
    public let toAccountId: String?
    public let categoryId: String?
    public let envelopeId: String?
    public let toEnvelopeId: String?
    public let assetId: String?
    public let qty: Double?
    public let comment: String?
    public let alloc: [String: Int]?
    public let taxAccrued: Int?
    public let taxable: Bool?
    public let reserved: Bool?
    public let createdAt: String?
    public let coverageFor: String?
    public var label: String { TransactionKind(rawValue: type)?.title ?? "Распределение" }
    public var symbol: String { TransactionKind(rawValue: type)?.symbol ?? "arrow.triangle.branch" }
    public var isIncome: Bool { ["income", "refund", "crypto_buy"].contains(type) }
}

public enum TransactionKind: String, CaseIterable, Identifiable {
    case expense, income, transfer, refund, adjustment
    case envTransfer = "env_transfer", cryptoBuy = "crypto_buy", cryptoSell = "crypto_sell"
    case cryptoSpend = "crypto_spend", taxPayment = "tax_payment"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .expense: "Расход"
        case .income: "Доход"
        case .transfer: "Перевод"
        case .refund: "Возврат"
        case .adjustment: "Корректировка"
        case .envTransfer: "Между конвертами"
        case .cryptoBuy: "Получение крипты"
        case .cryptoSell: "Вывод крипты"
        case .cryptoSpend: "Трата крипты"
        case .taxPayment: "Уплата налога"
        }
    }
    public var symbol: String {
        switch self {
        case .income, .cryptoBuy: "arrow.down.left"
        case .expense, .cryptoSpend, .taxPayment: "arrow.up.right"
        case .refund: "arrow.uturn.backward"
        case .transfer, .envTransfer, .cryptoSell: "arrow.left.arrow.right"
        case .adjustment: "equal"
        }
    }
    public var isCrypto: Bool { [.cryptoBuy, .cryptoSell, .cryptoSpend].contains(self) }
}

public struct Derived: Decodable {
    public let accounts: [Account]
    public let envelopes: [Envelope]
    public let cryptoAssets: [Asset]
    public let fiatTotal: Int
    public let cryptoValue: Int
    public let total: Int
    public let envelopeTotal: Int
    public let available: Int
    public let unallocated: Int
    public let tax: TaxSummary
}

public struct TaxSummary: Decodable {
    public let accrued: Int
    public let reserved: Int
    public let pending: Int
    public let paid: Int
    public let reserveAvailable: Int
    public let items: [TaxItem]
}
public struct TaxItem: Decodable, Identifiable {
    public let txId: String
    public let date: String
    public let amount: Int
    public let reserved: Bool
    public var id: String { txId }
}
public struct CategoryTotal: Decodable, Identifiable {
    public let id: String
    public let amount: Int
}
public struct Summary: Decodable {
    public let income: Int
    public let expenses: Int
    public let net: Int
    public let byCategory: [CategoryTotal]
}
public struct MonthPoint: Decodable, Identifiable {
    public let month: String
    public let income: Int
    public let expenses: Int
    public var id: String { month }
}
public struct RebalancePreview: Decodable {
    public let rows: [RebalanceRow]
    public let available: Int
    public let free: Int
    public let fingerprint: String
}
public struct RebalanceRow: Decodable, Identifiable {
    public let id: String
    public let name: String
    public let before: Int
    public let after: Int
}

public struct PreparedTransaction: Decodable {
    public let taxAccrued: Int?
    public let alloc: [String: Int]?
}

public struct ExpenseCoveragePreview: Decodable {
    public let amount: Int
    public let mode: String
    public let rows: [ExpenseFundingRow]
    public let freeBefore: Int
    public let freeAfter: Int
    public let freeUsed: Int
    public let fingerprint: String
}

public struct ExpenseFundingRow: Decodable, Identifiable {
    public let id: String
    public let name: String
    public let before: Int
    public let used: Int
    public let after: Int
}
