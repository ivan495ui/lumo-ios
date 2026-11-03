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
            (search.isEmpty || [transaction.comment, model.categoryName(transaction.categoryId), transaction.label, model.accountName(transaction.accountId), model.accountName(transaction.toAccountId)]
                .compactMap { $0 }.joined(separator: " ").localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        let grouped = Dictionary(grouping: rows, by: \.date)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 8) {
                    if allTime { Text("За всё время").font(LumoType.section); Spacer() }
                    else { MonthSelector() }
                    filterMenu
                }
                if !account.isEmpty || !type.isEmpty {
                    HStack {
                        Text(filterDescription).font(LumoType.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Сбросить") { account = ""; type = "" }.font(LumoType.caption).frame(minHeight: 44)
                    }
                }
                if rows.isEmpty {
                    if model.transactions.isEmpty { EmptyLedger() }
                    else { ContentUnavailableView("Операций не найдено", systemImage: "line.3.horizontal.decrease.circle", description: Text("Попробуй другой месяц, поиск или фильтр.")) }
                }
                ForEach(grouped.keys.sorted(by: >), id: \.self) { day in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(dayLabel(day)).font(LumoType.section)
                        VStack(spacing: 0) {
                            ForEach(grouped[day] ?? []) { transaction in
                                NavigationLink { TransactionDetail(transactionID: transaction.id) } label: {
                                    HStack(spacing: 8) {
                                        TransactionRow(transaction: transaction, showsDate: false, compact: true)
                                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                                    }.padding(.horizontal, 14).padding(.vertical, 7).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                if transaction.id != grouped[day]?.last?.id { Divider().padding(.leading, 61) }
                            }
                        }.background(LumoTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
        }.background(LumoTheme.background).searchable(text: $search, prompt: "Поиск по операциям")
    }
    private var filterMenu: some View {
        Menu {
            Picker("Период", selection: $allTime) { Text("По месяцам").tag(false); Text("За всё время").tag(true) }
            Picker("Счёт", selection: $account) {
                Text("Все счета").tag("")
                ForEach(model.snapshot?.state.accounts ?? []) { Text($0.name).tag($0.id) }
            }
            Picker("Тип", selection: $type) {
                Text("Все операции").tag("")
                ForEach(TransactionKind.allCases) { Text($0.title).tag($0.rawValue) }
                Text("Перераспределение").tag("env_rebalance")
            }
        } label: {
            Image(systemName: account.isEmpty && type.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .font(.title3).frame(width: 44, height: 44)
        }.accessibilityLabel("Фильтры истории")
    }
    private var filterDescription: String {
        [account.isEmpty ? nil : model.accountName(account), type.isEmpty ? nil : TransactionKind(rawValue: type)?.title ?? "Перераспределение"]
            .compactMap { $0 }.joined(separator: " · ")
    }
    private func dayLabel(_ key: String) -> String {
        if key == WalletModel.dateKey(Date()) { return "Сегодня" }
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()), key == WalletModel.dateKey(yesterday) { return "Вчера" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: key) else { return key }
        formatter.locale = Locale(identifier: "ru_RU"); formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
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
                        if ["crypto_buy", "crypto_sell", "crypto_spend"].contains(transaction.type) {
                            Text(model.cryptoQuantity(transaction)).font(LumoType.balance).monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true)
                            Text(transaction.amount == 0 ? "Оценка не указана" : "\(transaction.accountId == nil ? "Оценка записи" : transaction.type == "crypto_buy" ? "Оплачено" : "Получено"): \(transaction.accountId == nil ? model.estimatedMoney(transaction.amount) : model.displayMoney(transaction.amount))")
                                .font(LumoType.body).foregroundStyle(.secondary)
                        } else {
                            BalanceValue(cents: transaction.amount, currency: model.currency, presentation: model.displayValue(transaction.amount), sign: transaction.moneySign)
                        }
                        if model.effectiveDisplayCurrency != model.currency {
                            Text("В учёте: \(money(transaction.amount, currency: model.currency))").font(.footnote).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 12)
                    LabeledContent("Дата", value: transaction.date)
                    if let name = model.accountName(transaction.accountId) { LabeledContent("Счёт", value: name) }
                    if let name = model.accountName(transaction.toAccountId) { LabeledContent("Куда", value: name) }
                    if let name = model.categoryName(transaction.categoryId) { LabeledContent("Категория", value: name) }
                    if let name = model.envelopeName(transaction.envelopeId) { LabeledContent("Конверт", value: name) }
                    if let name = model.envelopeName(transaction.toEnvelopeId) { LabeledContent("В конверт", value: name) }
                    if let qty = transaction.qty, qty != 0 { LabeledContent("Количество", value: model.cryptoQuantity(transaction)) }
                    if let comment = transaction.comment, !comment.isEmpty { Text(comment) }
                }
                if let alloc = transaction.alloc, !alloc.isEmpty {
                    Section("Распределение") {
                        ForEach(alloc.keys.sorted(), id: \.self) { id in
                            LabeledContent(model.envelopeName(id) ?? id, value: model.displayMoney(alloc[id] ?? 0))
                        }
                    }
                }
                if transaction.type == "expense", transaction.envelopeId == nil {
                    Section("Из чего оплачен расход") {
                        let coverage = model.expenseCoverage(transaction.id)
                        let used = coverage.reduce(into: [String: Int]()) { values, entry in
                            for (id, delta) in entry.alloc ?? [:] { values[id, default: 0] += max(0, -delta) }
                        }
                        ForEach(used.keys.sorted(), id: \.self) { id in
                            LabeledContent(model.envelopeName(id) ?? id, value: money(used[id] ?? 0, currency: model.currency))
                        }
                        let free = transaction.amount - used.values.reduce(0, +)
                        if free > 0 { LabeledContent("Свободные деньги", value: money(free, currency: model.currency)) }
                        Text("Точное покрытие в \(model.currency). При изменении или удалении расхода оно пересчитывается вместе с ним.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let tax = transaction.taxAccrued, tax > 0 {
                    Section("Налог") {
                        LabeledContent("Начислено", value: model.displayMoney(tax))
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
