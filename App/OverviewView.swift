import SwiftUI
import LumoCore

struct OverviewView: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            }.background(LumoTheme.background)
                .navigationBarTitleDisplayMode(.inline)
                .sheet(item: $quickKind) { kind in NavigationStack { TransactionForm(initialKind: kind) } }
        }
    }
    private func setMode(_ value: String) { model.mutate("updateSettings", [["balanceView": value]]) }
    private func balanceCard(_ snapshot: Snapshot) -> some View {
        let showTotal = snapshot.state.settings.balanceView == "total" && !snapshot.state.settings.hideCrypto
        let amount = showTotal ? snapshot.derived.total : snapshot.derived.fiatTotal
        return VStack(alignment: .leading, spacing: 12) {
            balanceMode(snapshot, showTotal: showTotal)
            BalanceValue(cents: amount, currency: model.currency, identifier: "overview.balance", onAccent: true)
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5)
            dailyActions
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [LumoTheme.heroStart, LumoTheme.heroEnd], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func balanceMode(_ snapshot: Snapshot, showTotal: Bool) -> some View {
        if snapshot.state.settings.hideCrypto {
            HStack {
                Text("Карта и наличные")
                Spacer()
                Image(systemName: "wallet.bifold").accessibilityHidden(true)
            }.font(LumoType.body).foregroundStyle(LumoTheme.heroSecondary).frame(minHeight: 44)
        } else {
            Menu {
                Button("Карта и наличные", systemImage: showTotal ? "circle" : "checkmark.circle.fill") { setMode("fiat") }
                Button("Включая крипту", systemImage: showTotal ? "checkmark.circle.fill" : "circle") { setMode("total") }
            } label: {
                HStack(spacing: 7) {
                    Text(showTotal ? "Включая крипту" : "Карта и наличные").fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    Spacer()
                    Image(systemName: "wallet.bifold").font(.system(size: 17)).accessibilityHidden(true)
                }.font(LumoType.body).frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(LumoTheme.heroSecondary).accessibilityLabel("Режим баланса")
        }
    }

    private func quickButton(_ title: String, symbol: String, kind: TransactionKind) -> some View {
        Button { quickKind = kind } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.body.weight(.semibold)).imageScale(.small)
                Text(title).font(LumoType.label).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 44)
                .background(kind == .expense ? LumoTheme.actionPrimaryFill : LumoTheme.actionSecondaryFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }.buttonStyle(.plain)
            .foregroundStyle(kind == .expense ? LumoTheme.actionPrimaryText : LumoTheme.text)
            .accessibilityLabel(title)
    }

    @ViewBuilder
    private var dailyActions: some View {
        if dynamicTypeSize > .large {
            VStack(spacing: 8) {
                quickButton("Расход", symbol: "arrow.up.right", kind: .expense)
                quickButton("Доход", symbol: "arrow.down.left", kind: .income)
                quickButton("Перевод", symbol: "arrow.left.arrow.right", kind: .transfer)
            }
        } else {
            HStack(spacing: 8) {
                quickButton("Расход", symbol: "arrow.up.right", kind: .expense)
                quickButton("Доход", symbol: "arrow.down.left", kind: .income)
                quickButton("Перевод", symbol: "arrow.left.arrow.right", kind: .transfer)
            }
        }
    }

    private func envelopeSection(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Конверты").font(LumoType.section)
            EnvelopeStrip(envelopes: snapshot.derived.envelopes, currency: model.currency)
            if snapshot.derived.unallocated != 0 {
                NavigationLink { RebalanceView() } label: {
                    HStack {
                        Text(snapshot.derived.unallocated > 0 ? "Распределить свободные \(money(snapshot.derived.unallocated, currency: model.currency))" : "Проверить распределение")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2)
                    }.font(LumoType.caption).frame(minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(LumoTheme.accent)
            }
        }
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
                            if dynamicTypeSize > .large {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(account.name).font(LumoType.label).fixedSize(horizontal: false, vertical: true)
                                    Text(money(account.balance ?? 0, currency: model.currency)).font(LumoType.amount).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            } else {
                                Text(account.name).font(LumoType.label).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(money(account.balance ?? 0, currency: model.currency)).font(LumoType.amount).monospacedDigit()
                            }
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                        }.padding(.horizontal, 14).padding(.vertical, 16)
                    }.buttonStyle(.plain).accessibilityIdentifier("overview.account.\(account.id)")
                    if account.id != model.visibleAccounts.last?.id { Divider().padding(.leading, 48) }
                }
            }.background(LumoTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

}

func shareLabel(_ envelope: Envelope, all: [Envelope]) -> String {
    let share = envelope.percent ?? max(0, 100 - all.compactMap(\.percent).reduce(0, +))
    return "\(share.formatted(.number.precision(.fractionLength(0...2))))% от дохода"
}
