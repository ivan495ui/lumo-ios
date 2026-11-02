import SwiftUI
import Charts
import LumoCore

struct AnalyticsView: View {
    @EnvironmentObject var model: WalletModel
    var body: some View {
        if let snapshot = model.snapshot {
            List {
                Section { MonthSelector() }
                Section {
                    HStack {
                        metric("Доходы", cents: snapshot.summary.income, color: .green)
                        Spacer()
                        metric("Расходы", cents: snapshot.summary.expenses, color: .primary)
                    }.padding(.vertical, 10)
                    LabeledContent("Разница", value: money(snapshot.summary.net, currency: model.currency))
                } footer: { Text("Переводы, криптовалюта и налоговые платежи не искажают обычные доходы и расходы.") }
                Section("За полгода") {
                    Chart(snapshot.months) { month in
                        BarMark(x: .value("Месяц", String(month.month.suffix(2))), y: .value("Сумма", Double(month.income) / 100))
                            .foregroundStyle(by: .value("Тип", "Доходы")).position(by: .value("Тип", "Доходы"))
                        BarMark(x: .value("Месяц", String(month.month.suffix(2))), y: .value("Сумма", Double(month.expenses) / 100))
                            .foregroundStyle(by: .value("Тип", "Расходы")).position(by: .value("Тип", "Расходы"))
                    }.chartForegroundStyleScale(["Доходы": Color.green, "Расходы": Color.blue])
                        .frame(height: 210).padding(.vertical, 12)
                        .accessibilityLabel("Доходы и расходы за шесть месяцев")
                }
                Section("Расходы по категориям") {
                    if snapshot.summary.byCategory.isEmpty { Text("В этом месяце расходов нет").foregroundStyle(.secondary) }
                    ForEach(snapshot.summary.byCategory) { row in
                        LabeledContent(model.categoryName(row.id) ?? "Без категории", value: money(row.amount, currency: model.currency))
                    }
                }
            }
        }
    }
    private func metric(_ title: String, cents: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(money(cents, currency: model.currency)).font(.title2.weight(.medium)).foregroundStyle(color).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
        }
    }
}
