import SwiftUI
import LumoCore

struct OverviewView: View {
    @EnvironmentObject var model: WalletModel
    @State private var quickKind: TransactionKind?
    var body: some View {
        if let snapshot = model.snapshot {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    balanceCard(snapshot)
                    envelopeSection(snapshot)
                    accountsSection
                    if model.restoredBackup {
                        Label("Открыта резервная копия. Экспортируй её в Файлы.", systemImage: "externaldrive.badge.checkmark")
                            .font(LumoType.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
            }.background(Color.black)
                .navigationBarTitleDisplayMode(.inline)
                .sheet(item: $quickKind) { kind in NavigationStack { TransactionForm(initialKind: kind) } }
        }
    }
    private func setMode(_ value: String) { model.mutate("updateSettings", [["balanceView": value]]) }
    private func balanceCard(_ snapshot: Snapshot) -> some View {
        let showTotal = snapshot.state.settings.balanceView == "total" && !snapshot.state.settings.hideCrypto
        let amount = showTotal ? snapshot.derived.total : snapshot.derived.fiatTotal
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Мой баланс").foregroundStyle(.secondary)
                Spacer()
                if !snapshot.state.settings.hideCrypto {
                    Menu {
                        Button("Карта и наличные", systemImage: showTotal ? "circle" : "checkmark.circle.fill") { setMode("fiat") }
                        Button("Включая крипту", systemImage: showTotal ? "checkmark.circle.fill" : "circle") { setMode("total") }
                    } label: {
                        HStack(spacing: 6) {
                            Text(showTotal ? "С криптой" : "Без крипты")
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        }
                    }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Режим баланса")
                }
            }.font(LumoType.body)
            BalanceValue(cents: amount, currency: model.currency, identifier: "overview.balance")
            HStack {
                monthMetric("Доходы", amount: snapshot.summary.income, month: snapshot.month, color: .green)
                Spacer()
                monthMetric("Расходы", amount: snapshot.summary.expenses, month: snapshot.month, color: .primary)
            }.padding(.vertical, 3)
            Divider().overlay(Color.white.opacity(0.04))
            HStack(spacing: 8) {
                quickButton("Расход", symbol: "arrow.up.right", kind: .expense)
                quickButton("Доход", symbol: "arrow.down.left", kind: .income)
                quickButton("Перевод", symbol: "arrow.left.arrow.right", kind: .transfer)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(hex: "#1D222C"), Color(hex: "#171A21")], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func quickButton(_ title: String, symbol: String, kind: TransactionKind) -> some View {
        Button { quickKind = kind } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(title).font(LumoType.label).lineLimit(1).minimumScaleFactor(0.85)
            }.frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }.buttonStyle(.plain).foregroundStyle(.primary)
    }

    private func monthMetric(_ title: String, amount: Int, month: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(title) · \(monthCaption(month))").font(LumoType.caption).foregroundStyle(.secondary)
            Text(money(amount, currency: model.currency)).font(LumoType.amount)
                .monospacedDigit().foregroundStyle(color)
        }
    }

    private func monthCaption(_ key: String) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: key) else { return key }
        formatter.locale = Locale(identifier: "ru_RU"); formatter.dateFormat = "LLL"
        return formatter.string(from: date)
    }

    private func envelopeSection(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Конверты").font(LumoType.section)
            HStack(alignment: .top, spacing: 10) {
                ForEach(snapshot.derived.envelopes) { envelope in
                    NavigationLink { EnvelopeForm(envelope: envelope) } label: {
                        envelopeTile(envelope, all: snapshot.derived.envelopes)
                    }.buttonStyle(.plain)
                }
            }
            if snapshot.derived.unallocated != 0 {
                NavigationLink { RebalanceView() } label: {
                    HStack {
                        Text(snapshot.derived.unallocated > 0 ? "Распределить свободные \(money(snapshot.derived.unallocated, currency: model.currency))" : "Проверить распределение")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2)
                    }.font(LumoType.caption)
                }.buttonStyle(.plain).foregroundStyle(.blue)
            }
        }
    }

    private func envelopeTile(_ envelope: Envelope, all: [Envelope]) -> some View {
        let share = envelope.percent ?? max(0, 100 - all.compactMap(\.percent).reduce(0, +))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: envelope.symbol).font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 4)
                Text("\(share.formatted(.number.precision(.fractionLength(0...2))))%")
                    .font(LumoType.caption).monospacedDigit()
            }.foregroundStyle(Color(hex: envelope.color))
            Text(envelope.name).font(LumoType.label)
                .lineLimit(2).frame(minHeight: 36, alignment: .topLeading)
            Text(money(envelope.balance ?? 0, currency: model.currency))
                .font(LumoType.cardAmount).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: envelope.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Счета").font(LumoType.section)
            VStack(spacing: 0) {
                ForEach(model.visibleAccounts) { account in
                    NavigationLink { AccountDetail(accountID: account.id) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: account.symbol).font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color(hex: account.color)).frame(width: 22)
                            Text(account.name).font(LumoType.label).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(money(account.balance ?? 0, currency: model.currency)).font(LumoType.amount).monospacedDigit()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                        }.padding(.horizontal, 14).padding(.vertical, 13)
                    }.buttonStyle(.plain)
                    if account.id != model.visibleAccounts.last?.id { Divider().padding(.leading, 48) }
                }
            }.background(Color(hex: "#1C1C1E"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

}

func shareLabel(_ envelope: Envelope, all: [Envelope]) -> String {
    let share = envelope.percent ?? max(0, 100 - all.compactMap(\.percent).reduce(0, +))
    return "\(share.formatted(.number.precision(.fractionLength(0...2))))% от дохода"
}
