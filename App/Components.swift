import SwiftUI
import LumoCore

typealias LedgerTransaction = LumoCore.Transaction
typealias LedgerCategory = LumoCore.Category

/// Semantic system styles adapt to Dynamic Type; no bundled SF files or fixed tracking.
enum LumoType {
    static let balance = Font.largeTitle.weight(.medium)
    static let pageTitle = Font.headline
    static let cardAmount = Font.title3.weight(.medium)
    static let section = Font.headline
    static let amount = Font.body.weight(.medium)
    static let body = Font.body
    static let label = Font.body
    static let caption = Font.caption
    static let cardLabel = Font.footnote.weight(.medium)
}

struct BalanceValue: View {
    let cents: Int
    let currency: String
    var identifier: String? = nil
    var onAccent = false
    var presentation: MoneyValue? = nil
    var sign = ""
    private var value: MoneyValue { presentation ?? MoneyValue(cents: cents, currency: currency) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stackedValue
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if value.symbolLeading { unit.fixedSize() }
                    number.fixedSize()
                    if !value.symbolLeading { unit.fixedSize() }
                }
                stackedValue
            }
        }
    }
    private var stackedValue: some View {
        VStack(alignment: .leading, spacing: 4) {
            number.fixedSize(horizontal: false, vertical: true)
            unit
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var number: some View {
        Text((value.approximate ? "≈ " : "") + sign + value.number).font(LumoType.balance).foregroundStyle(LumoTheme.text)
            .monospacedDigit().contentTransition(.numericText())
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: cents)
            .accessibilityLabel(value.text(sign: sign))
            .accessibilityIdentifier(identifier ?? "")
    }
    private var unit: some View {
        Text(value.symbol).font(LumoType.amount)
            .foregroundStyle(onAccent ? LumoTheme.heroSecondary : Color.secondary).accessibilityHidden(true)
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
    MoneyValue(cents: cents, currency: currency).text()
}

func amountText(_ cents: Int) -> String {
    NSDecimalNumber(value: cents).dividing(by: 100).stringValue
}

struct Badge: View {
    let symbol: String
    var color: Color = .blue
    var size: CGFloat = 42
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(color).frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.31))
    }
}

struct AccountRow: View {
    @EnvironmentObject var model: WalletModel
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
            Text(model.displayMoney(account.balance ?? 0)).font(LumoType.amount).monospacedDigit()
        }.padding(.vertical, 5)
    }
}

struct TransactionRow: View {
    @EnvironmentObject var model: WalletModel
    let transaction: LedgerTransaction
    var showsDate = true
    var compact = false
    var body: some View {
        HStack(spacing: 13) {
            Badge(symbol: transaction.symbol, color: transaction.isIncome ? LumoTheme.positive : .gray, size: compact ? 34 : 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.categoryName(transaction.categoryId) ?? transaction.label).font(LumoType.label)
                Text([transaction.comment?.isEmpty == false ? transaction.comment : nil, model.accountName(transaction.accountId), showsDate ? transaction.date : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(LumoType.caption).foregroundStyle(.secondary).lineLimit(compact ? 2 : 1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(amountLabel)
                    .font(LumoType.amount)
                    .foregroundStyle(transaction.isIncome ? LumoTheme.positive : LumoTheme.text).monospacedDigit()
                if let qty = transaction.qty, qty != 0 {
                    Text(model.cryptoQuantity(transaction))
                        .font(LumoType.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(.vertical, 4)
    }
    private var amountLabel: String {
        model.displayMoney(transaction.amount, sign: transaction.moneySign)
    }
}

extension LedgerTransaction {
    var moneySign: String {
        if ["income", "refund"].contains(type) { return "+" }
        if ["expense", "tax_payment"].contains(type) { return "−" }
        if type == "crypto_buy", accountId != nil { return "−" }
        if type == "crypto_sell", accountId != nil { return "+" }
        if type == "adjustment", amount > 0 { return "+" }
        return ""
    }
}

struct MonthSelector: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 6) {
                Text(label).font(LumoType.section).multilineTextAlignment(.center)
                HStack {
                    previousButton
                    Spacer()
                    nextButton
                }
            }
        } else {
            HStack {
                previousButton
                Spacer(minLength: 4)
                Text(label).font(LumoType.section)
                Spacer(minLength: 4)
                nextButton
            }
        }
    }
    private var previousButton: some View {
        Button { model.changeMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Предыдущий месяц")
    }
    private var nextButton: some View {
        Button { model.changeMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Следующий месяц")
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
