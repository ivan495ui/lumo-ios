import SwiftUI
import Charts
import LumoCore

struct AnalyticsView: View {
    @EnvironmentObject var model: WalletModel
    var body: some View {
        if let snapshot = model.snapshot {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    MonthSelector()
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            metric("Доходы", cents: snapshot.summary.income, color: LumoTheme.positive)
                            metric("Расходы", cents: snapshot.summary.expenses, color: LumoTheme.text)
                        }
                        VStack(spacing: 12) {
                            metric("Доходы", cents: snapshot.summary.income, color: LumoTheme.positive)
                            metric("Расходы", cents: snapshot.summary.expenses, color: LumoTheme.text)
                        }
                    }
                    HStack {
                        Text("Разница").foregroundStyle(.secondary)
                        Spacer()
                        Text(money(snapshot.summary.net, currency: model.currency)).monospacedDigit()
                    }.font(LumoType.body)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Динамика за полгода").font(LumoType.section)
                        Chart(snapshot.months) { month in
                            BarMark(x: .value("Месяц", month.month), y: .value("Сумма", Double(month.income) / 100))
                                .foregroundStyle(by: .value("Тип", "Доходы")).position(by: .value("Тип", "Доходы"))
                            BarMark(x: .value("Месяц", month.month), y: .value("Сумма", Double(month.expenses) / 100))
                                .foregroundStyle(by: .value("Тип", "Расходы")).position(by: .value("Тип", "Расходы"))
                        }.chartForegroundStyleScale(["Доходы": LumoTheme.positive, "Расходы": LumoTheme.accent])
                            .chartXAxis {
                                AxisMarks { value in
                                    AxisValueLabel {
                                        if let key = value.as(String.self) { Text(monthLabel(key)).font(LumoType.caption) }
                                    }
                                }
                            }
                            .frame(height: 180)
                            .accessibilityLabel("Доходы и расходы за шесть месяцев")
                    }.padding(16).background(LumoTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(alignment: .leading, spacing: 12) {
                        Text("По категориям").font(LumoType.section)
                        if snapshot.summary.byCategory.isEmpty {
                            Text("В выбранном месяце расходов нет").font(LumoType.body).foregroundStyle(.secondary)
                                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(LumoTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        } else {
                            VStack(spacing: 0) {
                                ForEach(snapshot.summary.byCategory) { row in
                                    HStack {
                                        Text(model.categoryName(row.id) ?? "Без категории").font(LumoType.body)
                                        Spacer()
                                        Text(money(row.amount, currency: model.currency)).font(LumoType.amount).monospacedDigit()
                                    }.padding(16)
                                    if row.id != snapshot.summary.byCategory.last?.id { Divider().padding(.leading, 16) }
                                }
                            }.background(LumoTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                    Text("Без переводов, криптовалюты и налоговых платежей.").font(LumoType.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
            }.background(LumoTheme.background)
        }
    }
    private func metric(_ title: String, cents: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(LumoType.caption).foregroundStyle(.secondary)
            Text(money(cents, currency: model.currency)).font(LumoType.cardAmount).foregroundStyle(color).monospacedDigit().fixedSize(horizontal: true, vertical: false)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(LumoTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    private func monthLabel(_ key: String) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: key) else { return key }
        formatter.locale = Locale(identifier: "ru_RU"); formatter.dateFormat = "LLL"
        return formatter.string(from: date)
    }
}
