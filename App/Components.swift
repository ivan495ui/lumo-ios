import SwiftUI
import LumoCore

typealias LedgerTransaction = LumoCore.Transaction
typealias LedgerCategory = LumoCore.Category

/// Five text sizes at the standard Dynamic Type setting: 48 / 20 / 17 / 15 / 12.
enum LumoType {
    static let balance = Font.system(size: 48, weight: .light)
    static let pageTitle = Font.title3.weight(.semibold)
    static let cardAmount = Font.title3.weight(.medium)
    static let section = Font.headline
    static let amount = Font.body.weight(.medium)
    static let body = Font.subheadline
    static let label = Font.subheadline.weight(.medium)
    static let caption = Font.caption
}

struct BalanceValue: View {
    let cents: Int
    let currency: String
    var identifier: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(moneyNumber(cents)).font(LumoType.balance).tracking(-1.6)
                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: cents)
                .accessibilityLabel(money(cents, currency: currency))
                .accessibilityIdentifier(identifier ?? "")
            Text(currencySymbol(currency)).font(LumoType.amount)
                .foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0x4690FF
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

func moneyNumber(_ cents: Int) -> String {
    let number = NSDecimalNumber(value: cents).dividing(by: 100)
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = cents % 100 == 0 ? 0 : 2
    return formatter.string(from: number) ?? "0"
}

func currencySymbol(_ currency: String) -> String {
    ["BYN": "Br", "RUB": "₽", "USD": "$"][currency] ?? currency
}

func money(_ cents: Int, currency: String = "BYN") -> String {
    "\(moneyNumber(cents)) \(currencySymbol(currency))"
}

func amountText(_ cents: Int) -> String {
    NSDecimalNumber(value: cents).dividing(by: 100).stringValue
}

struct Badge: View {
    let symbol: String
    var color: Color = .blue
    var body: some View {
        Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
            .foregroundStyle(color).frame(width: 42, height: 42)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
    }
}

struct AccountRow: View {
    let account: Account
    let currency: String
    var body: some View {
        HStack(spacing: 13) {
            Badge(symbol: account.symbol, color: Color(hex: account.color))
            VStack(alignment: .leading, spacing: 3) {
                Text(account.name).font(LumoType.label)
                Text(account.kind == "crypto" ? "По введённому курсу" : account.kind == "cash" ? "Всегда под рукой" : "Мои деньги на карте")
                    .font(LumoType.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(money(account.balance ?? 0, currency: currency)).font(LumoType.amount).monospacedDigit()
        }.padding(.vertical, 5)
    }
}

struct TransactionRow: View {
    @EnvironmentObject var model: WalletModel
    let transaction: LedgerTransaction
    var body: some View {
        HStack(spacing: 13) {
            Badge(symbol: transaction.symbol, color: transaction.isIncome ? .green : .gray)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.categoryName(transaction.categoryId) ?? transaction.label).font(LumoType.label)
                Text([transaction.comment?.isEmpty == false ? transaction.comment : nil, model.accountName(transaction.accountId), transaction.date]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(LumoType.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(amountLabel)
                    .font(LumoType.amount)
                    .foregroundStyle(transaction.isIncome ? Color.green : Color.primary).monospacedDigit()
                if let qty = transaction.qty, qty != 0 {
                    Text(qty.formatted(.number.precision(.fractionLength(0...8))))
                        .font(LumoType.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(.vertical, 4)
    }
    private var amountLabel: String {
        let prefix: String
        if ["income", "refund"].contains(transaction.type) { prefix = "+" }
        else if ["expense", "tax_payment"].contains(transaction.type) { prefix = "−" }
        else if transaction.type == "adjustment", transaction.amount > 0 { prefix = "+" }
        else { prefix = "" }
        return prefix + money(transaction.amount, currency: model.currency)
    }
}

struct MonthSelector: View {
    @EnvironmentObject var model: WalletModel
    var body: some View {
        HStack {
            Button { model.changeMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }.accessibilityLabel("Предыдущий месяц")
            Spacer()
            Text(label).font(LumoType.section)
            Spacer()
            Button { model.changeMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }.accessibilityLabel("Следующий месяц")
        }
    }
    private var label: String {
        guard let key = model.snapshot?.month else { return "Этот месяц" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: key) else { return key }
        formatter.locale = Locale(identifier: "ru_RU"); formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized
    }
}

struct EmptyLedger: View {
    var body: some View {
        ContentUnavailableView("Пока нет операций", systemImage: "tray", description: Text("Добавь первый доход или расход. Твои деньги будут здесь."))
    }
}
