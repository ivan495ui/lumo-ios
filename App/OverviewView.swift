import SwiftUI
import LumoCore

struct OverviewView: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var quickKind: TransactionKind?
    var body: some View {
        if let snapshot = model.snapshot {
            let showTotal = snapshot.state.settings.balanceView == "total" && !snapshot.state.settings.hideCrypto
            let amount = showTotal ? snapshot.derived.total : snapshot.derived.fiatTotal
            List {
                Section {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Label("Мой баланс", systemImage: "wallet.bifold").foregroundStyle(.secondary)
                            Spacer()
                            if !snapshot.state.settings.hideCrypto {
                                Menu {
                                    Button("Карта и наличные", systemImage: showTotal ? "circle" : "checkmark.circle.fill") { setMode("fiat") }
                                    Button("Включая крипту", systemImage: showTotal ? "checkmark.circle.fill" : "circle") { setMode("total") }
                                } label: {
                                    Label(showTotal ? "С криптой" : "Без крипты", systemImage: "chevron.down").font(.caption.weight(.medium))
                                }.accessibilityLabel("Режим баланса")
                            }
                        }.font(.subheadline)
                        Text(money(amount, currency: model.currency))
                            .font(.system(size: 54, weight: .light, design: .default)).tracking(-2.4)
                            .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: amount)
                            .accessibilityIdentifier("overview.balance")
                        HStack(spacing: 9) {
                            Image(systemName: "circle.grid.2x2.fill").foregroundStyle(.blue)
                            Text("В конвертах \(money(snapshot.derived.envelopeTotal, currency: model.currency))")
                            Spacer()
                        }.font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                }.listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))

                Section {
                    HStack(spacing: 12) {
                        quickButton("Расход", symbol: "arrow.up.right", kind: .expense)
                        quickButton("Доход", symbol: "arrow.down.left", kind: .income)
                        quickButton("Перевод", symbol: "arrow.left.arrow.right", kind: .transfer)
                    }.padding(.vertical, 3)
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                Section("Счета") {
                    ForEach(model.visibleAccounts) { account in
                        NavigationLink { AccountDetail(accountID: account.id) } label: { AccountRow(account: account, currency: model.currency) }
                    }
                }

                Section("На важное") {
                    ForEach(snapshot.derived.envelopes) { envelope in
                        NavigationLink { EnvelopeForm(envelope: envelope) } label: {
                            HStack(spacing: 13) {
                                Badge(symbol: envelope.symbol, color: Color(hex: envelope.color))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(envelope.name).font(.body.weight(.medium))
                                    if envelope.goal > 0 {
                                        ProgressView(value: min(1, max(0, Double(envelope.balance ?? 0) / Double(envelope.goal))))
                                            .tint(Color(hex: envelope.color)).frame(maxWidth: 140)
                                    } else { Text(shareLabel(envelope, all: snapshot.derived.envelopes)).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Text(money(envelope.balance ?? 0, currency: model.currency)).monospacedDigit()
                            }.padding(.vertical, 6)
                        }
                    }
                    if snapshot.derived.unallocated != 0 {
                        NavigationLink { RebalanceView() } label: {
                            Label("Распределить свободные \(money(snapshot.derived.unallocated, currency: model.currency))", systemImage: "arrow.triangle.branch")
                                .font(.subheadline)
                        }
                    }
                }

                Section("Последние операции") {
                    if model.transactions.isEmpty { EmptyLedger().listRowBackground(Color.clear) }
                    ForEach(Array(model.transactions.prefix(4))) { transaction in
                        NavigationLink { TransactionDetail(transactionID: transaction.id) } label: { TransactionRow(transaction: transaction) }
                    }
                }
                if model.restoredBackup {
                    Section { Label("Открыта резервная копия. Экспортируй её в Файлы.", systemImage: "externaldrive.badge.checkmark").font(.footnote).foregroundStyle(.secondary) }
                }
            }.listStyle(.insetGrouped)
                .sheet(item: $quickKind) { kind in NavigationStack { TransactionForm(initialKind: kind) } }
        }
    }
    private func setMode(_ value: String) { model.mutate("updateSettings", [["balanceView": value]]) }
    private func quickButton(_ title: String, symbol: String, kind: TransactionKind) -> some View {
        Button { quickKind = kind } label: {
            VStack(spacing: 9) { Image(systemName: symbol).font(.title3.weight(.medium)); Text(title).font(.caption.weight(.medium)) }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
        }.buttonStyle(.bordered).tint(.gray).foregroundStyle(.primary)
    }
}

func shareLabel(_ envelope: Envelope, all: [Envelope]) -> String {
    let share = envelope.percent ?? max(0, 100 - all.compactMap(\.percent).reduce(0, +))
    return "\(share.formatted(.number.precision(.fractionLength(0...2))))% от дохода"
}
