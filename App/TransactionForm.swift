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
    @State private var fundingPreview: ExpenseCoveragePreview?
    @State private var fundingError: String?

    private var fiatAccounts: [Account] { (model.snapshot?.state.accounts ?? []).filter { $0.kind != "crypto" && (!$0.archived || $0.id == existing?.accountId || $0.id == existing?.toAccountId) } }
    private var assets: [Asset] {
        let all = model.snapshot?.derived.cryptoAssets ?? []
        if existing == nil, let initialAccountID,
           model.snapshot?.state.accounts.contains(where: { $0.id == initialAccountID && $0.kind == "crypto" }) == true {
            return all.filter { $0.accountId == initialAccountID }
        }
        let visibleIDs = Set((model.snapshot?.state.accounts ?? []).filter { $0.kind == "crypto" && !$0.archived }.map(\.id))
        return all.filter { visibleIDs.contains($0.accountId ?? "") || $0.id == existing?.assetId }
    }
    private var newAssetAccountID: String? {
        if let initialAccountID,
           model.snapshot?.state.accounts.contains(where: { $0.id == initialAccountID && $0.kind == "crypto" && !$0.archived }) == true {
            return initialAccountID
        }
        return model.snapshot?.state.accounts.first { $0.kind == "crypto" && !$0.archived }?.id
    }
    private var envelopes: [Envelope] { model.snapshot?.state.envelopes ?? [] }
    private var categories: [LedgerCategory] { (model.snapshot?.state.categories ?? []).filter { $0.kind == (kind == .income ? "income" : "expense") } }

    var body: some View {
        Form {
            if existing == nil {
                Section {
                    Picker("Операция", selection: Binding(get: { kind }, set: { value in
                        let wasCrypto = kind.isCrypto
                        kind = value; applyDefaults(); toEnvelopeID = ""; taxable = false; fiatFlow = value == .cryptoSell
                        if wasCrypto != value.isCrypto { amount = ""; quantity = ""; lastAutoAmount = "" }
                        if !assets.contains(where: { $0.id == assetID }) { selectDefaultAsset() }
                    })) { ForEach(TransactionKind.allCases) { Text($0.title).tag($0) } }
                }
            }
            if kind.isCrypto {
                Section("Криптовалюта") {
                    Picker("Актив", selection: $assetID) {
                        Text("Выбери актив").tag("")
                        ForEach(assets) { asset in Text("\(asset.symbol) · \(model.accountName(asset.accountId) ?? "")").tag(asset.id) }
                    }
                    TextField("Количество \(assets.first { $0.id == assetID }?.symbol ?? "актива")", text: $quantity)
                        .keyboardType(.decimalPad).accessibilityIdentifier("transaction.quantity")
                    if assets.isEmpty {
                        if let accountID = newAssetAccountID {
                            NavigationLink("Добавить USDT или другой актив") { AssetForm(accountID: accountID) }
                        } else {
                            Text("Сначала добавь криптосчёт в разделе «Счета».").font(LumoType.caption).foregroundStyle(.secondary)
                        }
                    }
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
                if kind.isCrypto && !fiatFlow { Text("Оценка записи в \(model.currency). Карта и наличные не изменятся; криптовалюта учитывается отдельно от фиатных конвертов.") }
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
                        if kind == .expense { Text("Из всех денег").tag("__smart__") }
                        Text(kind == .envTransfer ? "Выбери конверт" : kind == .expense ? "Только свободные" : "Свободные деньги").tag("")
                        ForEach(envelopes) { Text($0.name).tag($0.id) }
                    }.accessibilityIdentifier("transaction.envelope")
                    if kind == .envTransfer {
                        Picker("В конверт", selection: $toEnvelopeID) {
                            Text("Выбери конверт").tag("")
                            ForEach(envelopes.filter { $0.id != envelopeID }) { Text($0.name).tag($0.id) }
                        }
                    }
                }
            }
            if kind == .expense { expenseFundingSection }
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { save() }.fontWeight(.semibold)
                        .disabled(kind == .expense && fundingPreview == nil)
                }
            }
            .onAppear { initialize() }
            .onChange(of: quantity) { _, _ in updateCryptoCost() }
            .onChange(of: assetID) { _, _ in updateCryptoCost() }
            .onChange(of: assets.map(\.id)) { _, ids in
                if existing == nil && !ids.contains(assetID) { selectDefaultAsset() }
            }
            .onChange(of: expensePreviewKey) { _, _ in refreshExpensePreview() }
            .onReceive(model.$snapshot) { _ in
                Task { @MainActor in refreshExpensePreview() }
            }
    }

    private var incomePreview: PreparedTransaction? {
        guard kind == .income, let draft = try? draft() else { return nil }
        return model.prepared(draft, existingID: existing?.id)
    }

    private var expenseMode: String { envelopeID == "__smart__" ? "smart" : envelopeID.isEmpty ? "free" : "envelope" }
    private var expensePreviewKey: String {
        [kind.rawValue, amount, accountID, envelopeID, categoryID, WalletModel.dateKey(date), comment].joined(separator: "|")
    }
    private var expenseFundingSection: some View {
        Section {
            if let preview = fundingPreview {
                if preview.freeUsed > 0 {
                    LabeledContent("Свободные деньги", value: money(preview.freeUsed, currency: model.currency))
                }
                ForEach(preview.rows.filter { $0.used > 0 }) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(row.name, value: money(row.used, currency: model.currency))
                        Text("Останется \(money(row.after, currency: model.currency))")
                            .font(LumoType.caption).foregroundStyle(.secondary)
                    }
                }
            } else if let fundingError {
                Text(fundingError).foregroundStyle(.red)
                if expenseMode != "smart" {
                    Button("Покрыть из всех денег") { envelopeID = "__smart__" }
                        .accessibilityIdentifier("transaction.coverAll")
                }
            } else {
                Text("Введи сумму — здесь появится точное покрытие расхода.")
                    .font(LumoType.caption).foregroundStyle(.secondary)
            }
        } header: { Text("Из чего оплачен расход") }
        footer: {
            Text(expenseMode == "smart"
                 ? "Сначала свободные деньги, затем конверты пропорционально положительным остаткам. Все суммы предпросмотра — в \(model.currency)."
                 : "Расход спишется только из выбранного источника. Если денег не хватает, выбери «Из всех денег» и проверь новое покрытие.")
        }
    }
    private func refreshExpensePreview() {
        guard initialized, kind == .expense else { fundingPreview = nil; fundingError = nil; return }
        guard !amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { fundingPreview = nil; fundingError = nil; return }
        do {
            fundingPreview = try model.expensePreview(draft(), existingID: existing?.id, mode: expenseMode)
            fundingError = nil
        } catch {
            fundingPreview = nil
            fundingError = error.localizedDescription
        }
    }

    private func draft() throws -> [String: Any] {
        let cents = try model.cents(amount)
        var draft: [String: Any] = ["type": kind.rawValue, "amount": cents, "date": WalletModel.dateKey(date), "comment": comment,
            "accountId": (!kind.isCrypto || fiatFlow) && kind != .envTransfer && !accountID.isEmpty ? accountID as Any : NSNull(),
            "toAccountId": kind == .transfer && !toAccountID.isEmpty ? toAccountID as Any : NSNull(),
            "categoryId": [.income, .expense, .refund].contains(kind) && !categoryID.isEmpty ? categoryID as Any : NSNull(),
            "envelopeId": [.expense, .refund, .envTransfer].contains(kind) && !envelopeID.isEmpty && envelopeID != "__smart__" ? envelopeID as Any : NSNull(),
            "toEnvelopeId": kind == .envTransfer && !toEnvelopeID.isEmpty ? toEnvelopeID as Any : NSNull()]
        if kind.isCrypto {
            guard assets.contains(where: { $0.id == assetID }) else { throw FinanceError.message("Выбери актив этого криптосчёта") }
            let qty = try parsedCryptoQuantity(quantity)
            if fiatFlow {
                guard cents > 0, fiatAccounts.contains(where: { $0.id == accountID }) else {
                    throw FinanceError.message("Для денежной части выбери карту или наличные и укажи сумму больше нуля в \(model.currency)")
                }
            }
            draft["assetId"] = assetID
            draft["qty"] = qty
            // Old web entries can carry a spending envelope/category not exposed
            // by this form. A comment edit must preserve that recorded effect.
            if let envelopeID = existing?.envelopeId { draft["envelopeId"] = envelopeID }
            if let categoryID = existing?.categoryId { draft["categoryId"] = categoryID }
        }
        if kind == .income { draft["taxable"] = taxable; draft["reserved"] = reserved }
        return draft
    }
    private func save() {
        do {
            let draft = try draft()
            let success: Bool
            if kind == .expense {
                guard let fundingPreview else { throw FinanceError.message(fundingError ?? "Проверь покрытие расхода") }
                success = model.mutate("saveExpense", [draft, existing?.id as Any? ?? NSNull(), ["mode": expenseMode], fundingPreview.fingerprint]) { localError = $0 }
            } else if let existing { success = model.mutate("updateTransaction", [existing.id, draft]) { localError = $0 } }
            else { success = model.mutate("addTransaction", [draft]) { localError = $0 } }
            if success { dismiss() }
            else if kind == .expense { refreshExpensePreview() }
        } catch { localError = error.localizedDescription }
    }
    private func updateCryptoCost() {
        // Preserve an explicitly entered or historical valuation.
        guard initialized, kind.isCrypto, amount.isEmpty || amount == lastAutoAmount,
              let qty = try? parsedCryptoQuantity(quantity), let asset = assets.first(where: { $0.id == assetID }) else { return }
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
        else if kind == .expense, let existing,
                model.snapshot?.state.transactions.contains(where: { $0.coverageFor == existing.id }) == true {
            envelopeID = "__smart__"
        }
        toEnvelopeID = existing?.toEnvelopeId ?? ""
        if let existing { assetID = existing.assetId ?? "" }
        else { selectDefaultAsset() }
        comment = existing?.comment ?? ""
        amount = existing.map { amountText($0.amount) } ?? ""
        quantity = existing?.qty.map { cryptoQuantityText($0) } ?? ""
        fiatFlow = existing.map { $0.accountId != nil && kind.isCrypto && kind != .cryptoSpend } ?? (kind == .cryptoSell)
        taxable = existing?.taxable ?? ((existing?.taxAccrued ?? 0) > 0)
        reserved = existing?.reserved ?? model.snapshot?.state.settings.autoReserve ?? true
        if let key = existing?.date {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
            date = formatter.date(from: key) ?? Date()
        }
        initialized = true
        refreshExpensePreview()
    }
    private func applyDefaults() {
        categoryID = categories.first { $0.id == (kind == .income ? "cat_income_other" : "cat_other") }?.id ?? ""
        envelopeID = kind == .expense ? "__smart__" : ""
    }
    private func selectDefaultAsset() {
        assetID = assets.first { $0.accountId == initialAccountID && $0.symbol.uppercased() == "USDT" }?.id
            ?? assets.first { $0.accountId == initialAccountID }?.id
            ?? assets.first { $0.symbol.uppercased() == "USDT" }?.id ?? assets.first?.id ?? ""
    }
}
