import SwiftUI
import LumoCore

struct HistoryView: View {
    @EnvironmentObject var model: WalletModel
    @State private var search = ""
    @State private var allTime = false
    @State private var account = ""
    @State private var type = ""
    private var rows: [LedgerTransaction] {
        model.transactions.filter { transaction in
            (allTime || transaction.date.hasPrefix(model.snapshot?.month ?? "")) &&
            (account.isEmpty || transaction.accountId == account || transaction.toAccountId == account ||
             model.snapshot?.derived.cryptoAssets.contains { $0.id == transaction.assetId && $0.accountId == account } == true) &&
            (type.isEmpty || transaction.type == type) &&
            (search.isEmpty || [transaction.comment, model.categoryName(transaction.categoryId), transaction.label, model.accountName(transaction.accountId)]
                .compactMap { $0 }.joined(separator: " ").localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        List {
            Section {
                if !allTime { MonthSelector() }
                Toggle("За всё время", isOn: $allTime)
            }
            Section {
                Picker("Счёт", selection: $account) {
                    Text("Все счета").tag("")
                    ForEach(model.snapshot?.state.accounts ?? []) { Text($0.name).tag($0.id) }
                }
                Picker("Тип", selection: $type) {
                    Text("Все операции").tag("")
                    ForEach(TransactionKind.allCases) { Text($0.title).tag($0.rawValue) }
                    Text("Перераспределение").tag("env_rebalance")
                }
            }
            Section {
                if rows.isEmpty { EmptyLedger() }
                ForEach(rows) { transaction in
                    NavigationLink { TransactionDetail(transactionID: transaction.id) } label: { TransactionRow(transaction: transaction) }
                }
            }
        }.searchable(text: $search, prompt: "Комментарий, категория или счёт")
    }
}

struct TransactionDetail: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.dismiss) private var dismiss
    let transactionID: String
    @State private var editing = false
    @State private var deleting = false
    var body: some View {
        if let transaction = model.snapshot?.state.transactions.first(where: { $0.id == transactionID }) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(transaction.label, systemImage: transaction.symbol).foregroundStyle(.secondary)
                        Text(money(transaction.amount, currency: model.currency)).font(.system(size: 42, weight: .light)).monospacedDigit()
                    }.padding(.vertical, 12)
                    LabeledContent("Дата", value: transaction.date)
                    if let name = model.accountName(transaction.accountId) { LabeledContent("Счёт", value: name) }
                    if let name = model.accountName(transaction.toAccountId) { LabeledContent("Куда", value: name) }
                    if let name = model.categoryName(transaction.categoryId) { LabeledContent("Категория", value: name) }
                    if let name = model.envelopeName(transaction.envelopeId) { LabeledContent("Конверт", value: name) }
                    if let name = model.envelopeName(transaction.toEnvelopeId) { LabeledContent("В конверт", value: name) }
                    if let qty = transaction.qty, qty != 0 { LabeledContent("Количество", value: qty.formatted(.number.precision(.fractionLength(0...8)))) }
                    if let comment = transaction.comment, !comment.isEmpty { Text(comment) }
                }
                if let alloc = transaction.alloc, !alloc.isEmpty {
                    Section("Распределение") {
                        ForEach(alloc.keys.sorted(), id: \.self) { id in
                            LabeledContent(model.envelopeName(id) ?? id, value: money(alloc[id] ?? 0, currency: model.currency))
                        }
                    }
                }
                if let tax = transaction.taxAccrued, tax > 0 {
                    Section("Налог") {
                        LabeledContent("Начислено", value: money(tax, currency: model.currency))
                        Toggle("Отложено в резерв", isOn: Binding(get: { transaction.reserved != false }, set: { model.mutate("setReserved", [transaction.id, $0]) }))
                    }
                }
                Section {
                    if transaction.type != "env_rebalance" { Button("Изменить") { editing = true } }
                    Button("Удалить операцию", role: .destructive) { deleting = true }
                }
            }.navigationTitle(transaction.label).navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $editing) { NavigationStack { TransactionForm(existing: transaction) } }
                .confirmationDialog("Удалить операцию?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Удалить", role: .destructive) { if model.mutate("deleteTransaction", [transaction.id]) { dismiss() } }
                } message: { Text("Балансы счетов и конвертов будут пересчитаны.") }
        }
    }
}
