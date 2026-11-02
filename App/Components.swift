import SwiftUI
import LumoCore

typealias LedgerTransaction = LumoCore.Transaction

extension Color {
    init(hex: String) {
        let value = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0x4690FF
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

func money(_ cents: Int, currency: String = "BYN") -> String {
    let number = NSDecimalNumber(value: cents).dividing(by: 100)
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = cents % 100 == 0 ? 0 : 2
    let symbol = ["BYN": "Br", "RUB": "₽", "USD": "$"][currency] ?? currency
    return "\(formatter.string(from: number) ?? "0") \(symbol)"
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
                Text(account.name).font(.body.weight(.medium))
                Text(account.kind == "crypto" ? "По введённому курсу" : account.kind == "cash" ? "Всегда под рукой" : "Мои деньги на карте")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(money(account.balance ?? 0, currency: currency)).monospacedDigit()
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
                Text(model.categoryName(transaction.categoryId) ?? transaction.label).font(.body.weight(.medium))
                Text([transaction.comment?.isEmpty == false ? transaction.comment : nil, model.accountName(transaction.accountId), transaction.date]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(money(transaction.amount, currency: model.currency))
                    .foregroundStyle(transaction.isIncome ? Color.green : Color.primary).monospacedDigit()
                if let qty = transaction.qty, qty != 0 {
                    Text(qty.formatted(.number.precision(.fractionLength(0...8))))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(.vertical, 4)
    }
}

struct MonthSelector: View {
    @EnvironmentObject var model: WalletModel
    var body: some View {
        HStack {
            Button { model.changeMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }.accessibilityLabel("Предыдущий месяц")
            Spacer()
            Text(label).font(.headline)
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
