import SwiftUI
import LumoCore

struct TransactionForm: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.dismiss) private var dismiss
    var initialKind: TransactionKind = .expense
    var initialAccountID: String?
    var existing: LedgerTransaction?
    @State private var kind: TransactionKind = .expense
    @State private var amount = ""
    @State private var quantity = ""
    @State private var accountID = ""
    @State private var toAccountID = ""
    @State private var categoryID = ""
    @State private var envelopeID = ""
    @State private var toEnvelopeID = ""
    @State private var assetID = ""
    @State private var comment = ""
    @State private var date = Date()
    @State private var fiatFlow = false
    @State private var taxable = false
    @State private var reserved = true
    @State private var localError: String?
    @State private var initialized = false
    @State private var lastAutoAmount = ""

    private var fiatAccounts: [Account] { (model.snapshot?.state.accounts ?? []).filter { $0.kind != "crypto" && (!$0.archived || $0.id == existing?.accountId || $0.id == existing?.toAccountId) } }
    private var assets: [Asset] { model.snapshot?.derived.cryptoAssets ?? [] }
    private var envelopes: [Envelope] { model.snapshot?.state.envelopes ?? [] }
    private var categories: [LedgerCategory] { (model.snapshot?.state.categories ?? []).filter { $0.kind == (kind == .income ? "income" : "expense") } }

    var body: some View {
        Form {
            if existing == nil {
                Section {
                    Picker("Операция", selection: Binding(get: { kind }, set: { value in
                        kind = value; applyDefaults(); toEnvelopeID = ""; taxable = false; fiatFlow = false
                        if !assets.contains(where: { $0.id == assetID }) { assetID = assets.first?.id ?? "" }
                    })) { ForEach(TransactionKind.allCases) { Text($0.title).tag($0) } }
                }
            }
            if kind.isCrypto {
                Section("Криптовалюта") {
                    Picker("Актив", selection: $assetID) {
                        Text("Выбери актив").tag("")
                        ForEach(assets) { asset in Text("\(asset.symbol) · \(model.accountName(asset.accountId) ?? "")").tag(asset.id) }
                    }
                    TextField("Количество", text: $quantity).keyboardType(.decimalPad)
                    if assets.isEmpty { Text("Сначала добавь актив на криптосчёте.").font(LumoType.caption).foregroundStyle(.secondary) }
                    if kind != .cryptoSpend {
                        Toggle(kind == .cryptoBuy ? "Оплачено с карты / наличными" : "Зачислено на карту / наличными", isOn: $fiatFlow)
                    }
                }
            }
            Section {
                TextField(kind == .adjustment ? "Изменение суммы: + или −" : "Сумма, \(model.currency)", text: $amount)
                    .font(LumoType.balance).monospacedDigit()
                    .keyboardType(kind == .adjustment ? .numbersAndPunctuation : .decimalPad)
                    .accessibilityIdentifier("transaction.amount")
                if kind != .envTransfer && (!kind.isCrypto || fiatFlow) {
                    Picker(kind == .transfer ? "Откуда" : "Счёт", selection: $accountID) {
                        Text("Выбери счёт").tag("")
                        ForEach(fiatAccounts) { Text($0.name).tag($0.id) }
                    }
                }
                if kind == .transfer {
                    Picker("Куда", selection: $toAccountID) {
                        Text("Выбери счёт").tag("")
                        ForEach(fiatAccounts.filter { $0.id != accountID }) { Text($0.name).tag($0.id) }
                    }
                }
            } header: { Text(kind.isCrypto && !fiatFlow ? "Стоимость в \(model.currency)" : "Сумма") }
            footer: {
                if kind.isCrypto && !fiatFlow { Text("Оценка операции. Остаток на карте и наличные не изменятся.") }
                if kind == .adjustment { Text("Введи разницу с текущим остатком. Например, −10 уменьшит счёт на 10 \(model.currency).") }
            }

            if [.income, .expense, .refund].contains(kind) {
                Section {
                    Picker("Категория", selection: Binding(get: { categoryID }, set: { id in
                        categoryID = id; taxable = categories.first { $0.id == id }?.taxable ?? false
                    })) {
                        Text("Без категории").tag("")
                        ForEach(categories) { Text($0.name).tag($0.id) }
                    }
                }
            }
            if [.expense, .refund, .envTransfer].contains(kind) {
                Section {
                    Picker(kind == .envTransfer ? "Из конверта" : "Конверт", selection: $envelopeID) {
                        Text(kind == .envTransfer ? "Выбери конверт" : "Свободные деньги").tag("")
                        ForEach(envelopes) { Text($0.name).tag($0.id) }
                    }
                    if kind == .envTransfer {
                        Picker("В конверт", selection: $toEnvelopeID) {
                            Text("Выбери конверт").tag("")
                            ForEach(envelopes.filter { $0.id != envelopeID }) { Text($0.name).tag($0.id) }
                        }
                    }
                }
            }
            if kind == .income {
                Section {
                    if model.snapshot?.state.settings.taxEnabled == true || (existing?.taxAccrued ?? 0) > 0 {
                        Toggle("Облагается налогом", isOn: $taxable)
                        if taxable { Toggle("Сразу отложить налог", isOn: $reserved) }
                    }
                    if let preview = incomePreview {
                        if (preview.taxAccrued ?? 0) > 0 { LabeledContent("В налоговый резерв", value: money(preview.taxAccrued ?? 0, currency: model.currency)) }
                        ForEach(envelopes) { envelope in
                            LabeledContent(envelope.name, value: money(preview.alloc?[envelope.id] ?? 0, currency: model.currency))
                        }
                    }
                } header: { Text("Распределение дохода") }
            }
            Section {
                DatePicker("Дата", selection: $date, displayedComponents: .date).environment(\.locale, Locale(identifier: "ru_RU"))
                TextField("Комментарий", text: $comment, axis: .vertical).lineLimit(2...4)
            }
            if let localError { Section { Text(localError).foregroundStyle(.red) } }
        }.navigationTitle(existing == nil ? kind.title : "Изменить операцию")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { save() }.fontWeight(.semibold) }
            }
            .onAppear { initialize() }
            .onChange(of: quantity) { _, _ in updateCryptoCost() }
            .onChange(of: assetID) { _, _ in updateCryptoCost() }
    }

    private var incomePreview: PreparedTransaction? {
        guard kind == .income, let draft = try? draft() else { return nil }
        return model.prepared(draft, existingID: existing?.id)
    }

    private func draft() throws -> [String: Any] {
        let cents = try model.cents(amount)
        var draft: [String: Any] = ["type": kind.rawValue, "amount": cents, "date": WalletModel.dateKey(date), "comment": comment,
            "accountId": (!kind.isCrypto || fiatFlow) && kind != .envTransfer && !accountID.isEmpty ? accountID as Any : NSNull(),
            "toAccountId": kind == .transfer && !toAccountID.isEmpty ? toAccountID as Any : NSNull(),
            "categoryId": [.income, .expense, .refund].contains(kind) && !categoryID.isEmpty ? categoryID as Any : NSNull(),
            "envelopeId": [.expense, .refund, .envTransfer].contains(kind) && !envelopeID.isEmpty ? envelopeID as Any : NSNull(),
            "toEnvelopeId": kind == .envTransfer && !toEnvelopeID.isEmpty ? toEnvelopeID as Any : NSNull()]
        if kind.isCrypto {
            guard let qty = Double(quantity.replacingOccurrences(of: ",", with: ".")), qty.isFinite, qty > 0 else { throw FinanceError.message("Введите количество криптовалюты") }
            draft["assetId"] = assetID
            draft["qty"] = qty
        }
        if kind == .income { draft["taxable"] = taxable; draft["reserved"] = reserved }
        return draft
    }
    private func save() {
        do {
            let draft = try draft()
            let success: Bool
            if let existing { success = model.mutate("updateTransaction", [existing.id, draft]) { localError = $0 } }
            else { success = model.mutate("addTransaction", [draft]) { localError = $0 } }
            if success { dismiss() }
        } catch { localError = error.localizedDescription }
    }
    private func updateCryptoCost() {
        // Preserve an explicitly entered or historical valuation.
        guard kind.isCrypto, amount.isEmpty || amount == lastAutoAmount, let qty = Double(quantity.replacingOccurrences(of: ",", with: ".")),
              qty.isFinite, let asset = assets.first(where: { $0.id == assetID }) else { return }
        let value = qty * Double(asset.price)
        guard value.isFinite, abs(value) < 9_000_000_000_000_000 else { return }
        lastAutoAmount = amountText(Int(value.rounded()))
        amount = lastAutoAmount
    }
    private func initialize() {
        guard !initialized else { return }
        kind = existing.flatMap { TransactionKind(rawValue: $0.type) } ?? initialKind
        accountID = existing?.accountId ?? (fiatAccounts.contains { $0.id == initialAccountID } ? initialAccountID : nil) ?? fiatAccounts.first?.id ?? ""
        toAccountID = existing?.toAccountId ?? fiatAccounts.first { $0.id != accountID }?.id ?? ""
        categoryID = existing?.categoryId ?? ""
        envelopeID = existing?.envelopeId ?? ""
        if existing == nil { applyDefaults() }
        toEnvelopeID = existing?.toEnvelopeId ?? ""
        assetID = existing?.assetId ?? assets.first { $0.accountId == initialAccountID }?.id ?? assets.first?.id ?? ""
        comment = existing?.comment ?? ""
        amount = existing.map { amountText($0.amount) } ?? ""
        quantity = existing?.qty.map { String($0) } ?? ""
        fiatFlow = existing?.accountId != nil && (existing?.amount ?? 0) > 0
        taxable = existing?.taxable ?? ((existing?.taxAccrued ?? 0) > 0)
        reserved = existing?.reserved ?? model.snapshot?.state.settings.autoReserve ?? true
        if let key = existing?.date {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
            date = formatter.date(from: key) ?? Date()
        }
        initialized = true
    }
    private func applyDefaults() {
        categoryID = categories.first { $0.id == (kind == .income ? "cat_income_other" : "cat_other") }?.id ?? ""
        envelopeID = [.expense, .refund].contains(kind) ? (envelopes.first { $0.id == "env_personal" }?.id ?? envelopes.first?.id ?? "") : ""
    }
}
