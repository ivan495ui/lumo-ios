import SwiftUI
import LumoCore

struct OverviewView: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var quickKind: TransactionKind?
    var body: some View {
        if let snapshot = model.snapshot {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    balanceCard(snapshot)
                    HStack(spacing: 16) {
                        quickButton("Расход", symbol: "arrow.up.right", kind: .expense)
                        quickButton("Доход", symbol: "arrow.down.left", kind: .income)
                        quickButton("Перевод", symbol: "arrow.left.arrow.right", kind: .transfer)
                    }
                    envelopeSection(snapshot)
                    accountsSection
                    recentSection
                    if model.restoredBackup {
                        Label("Открыта резервная копия. Экспортируй её в Файлы.", systemImage: "externaldrive.badge.checkmark")
                            .font(.footnote).foregroundStyle(.secondary)
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
            }.font(.subheadline)
            Text(money(amount, currency: model.currency))
                .font(.system(size: 50, weight: .light)).tracking(-1.8)
                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: amount)
                .accessibilityIdentifier("overview.balance")
            Text(showTotal ? "Карта, наличные и криптовалюта" : "Карта и наличные")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "#1C1C1E"), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func quickButton(_ title: String, symbol: String, kind: TransactionKind) -> some View {
        Button { quickKind = kind } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                    .frame(width: 46, height: 46)
                    .background(Color(hex: "#1C1C1E"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(title).font(.caption.weight(.medium))
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain).foregroundStyle(.primary)
    }

    private func envelopeSection(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Конверты").font(.headline)
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
                    }.font(.footnote)
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
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
            }.foregroundStyle(Color(hex: envelope.color))
            Text(envelope.name).font(.system(size: 12, weight: .medium))
                .lineLimit(2).frame(minHeight: 30, alignment: .topLeading)
            Text(money(envelope.balance ?? 0, currency: model.currency))
                .font(.system(size: 18, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: envelope.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Счета").font(.headline)
            VStack(spacing: 0) {
                ForEach(model.visibleAccounts) { account in
                    NavigationLink { AccountDetail(accountID: account.id) } label: {
                        HStack(spacing: 10) {
                            AccountRow(account: account, currency: model.currency)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                        }.padding(.horizontal, 14).padding(.vertical, 6)
                    }.buttonStyle(.plain)
                    if account.id != model.visibleAccounts.last?.id { Divider().padding(.leading, 69) }
                }
            }.background(Color(hex: "#1C1C1E"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Последние операции").font(.headline)
            if model.transactions.isEmpty { EmptyLedger() }
            ForEach(Array(model.transactions.prefix(3))) { transaction in
                NavigationLink { TransactionDetail(transactionID: transaction.id) } label: { TransactionRow(transaction: transaction) }
                    .buttonStyle(.plain)
                if transaction.id != model.transactions.prefix(3).last?.id { Divider().padding(.leading, 55) }
            }
        }
    }
}

func shareLabel(_ envelope: Envelope, all: [Envelope]) -> String {
    let share = envelope.percent ?? max(0, 100 - all.compactMap(\.percent).reduce(0, +))
    return "\(share.formatted(.number.precision(.fractionLength(0...2))))% от дохода"
}
