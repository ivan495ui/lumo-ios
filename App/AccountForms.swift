import SwiftUI
import LumoCore

struct AccountForm: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.dismiss) private var dismiss
    var account: Account?
    @State private var name = ""
    @State private var kind = "card"
    @State private var opening = "0"
    @State private var archived = false
    @State private var localError: String?
    @State private var deleting = false
    @State private var initialized = false
    var body: some View {
        Form {
            Section {
                TextField("Название счёта", text: $name)
                if account == nil {
                    Picker("Тип", selection: $kind) { Text("Карта").tag("card"); Text("Наличные").tag("cash"); Text("Криптовалюта").tag("crypto") }
                }
                if kind != "crypto" { TextField("Стартовый остаток, \(model.currency)", text: $opening).keyboardType(.numbersAndPunctuation) }
                if account != nil { Toggle("Скрыть счёт", isOn: $archived) }
            } footer: { Text("Стартовый остаток — сумма до первой операции. Для изменения сегодняшнего баланса добавь корректировку.") }
            if account != nil { Section { Button("Удалить счёт", role: .destructive) { deleting = true } } }
            if let localError { Text(localError).foregroundStyle(.red) }
        }.navigationTitle(account == nil ? "Новый счёт" : "Настройки счёта").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { save() } }
            }
            .onAppear {
                guard !initialized else { return }
                name = account?.name ?? ""; kind = account?.kind ?? "card"
                opening = amountText(account?.opening ?? 0); archived = account?.archived ?? false
                initialized = true
            }
            .confirmationDialog("Удалить счёт?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { if let account, model.mutate("deleteAccount", [account.id], failure: { localError = $0 }) { dismiss() } }
            }
    }
    private func save() {
        do {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw FinanceError.message("Напиши название счёта") }
            var args: [String: Any] = ["name": trimmed, "kind": kind, "opening": kind == "crypto" ? 0 : try model.cents(opening), "archived": archived, "color": account?.color ?? "#4690FF"]
            if let account { args["id"] = account.id }
            if model.mutate("saveAccount", [args], failure: { localError = $0 }) { dismiss() }
        } catch { localError = error.localizedDescription }
    }
}

struct AssetForm: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.dismiss) private var dismiss
    let accountID: String
    var asset: Asset?
    @State private var symbol = ""
    @State private var name = ""
    @State private var quantity = ""
    @State private var price = ""
    @State private var localError: String?
    @State private var deleting = false
    @State private var initialized = false

    private var currentAsset: Asset? {
        guard let asset else { return nil }
        return model.snapshot?.derived.cryptoAssets.first { $0.id == asset.id && $0.accountId == accountID }
    }
    var body: some View {
        Form {
            if asset == nil {
                Section {
                    Button("USDT · Tether") { symbol = "USDT"; name = "Tether" }
                        .accessibilityIdentifier("asset.preset.usdt")
                } footer: { Text("Быстрый выбор заполняет только название. Количество и курс укажи самостоятельно.") }
            }
            Section {
                TextField("Тикер, например USDT", text: $symbol).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .accessibilityIdentifier("asset.symbol")
                TextField("Название", text: $name)
                if asset == nil {
                    TextField("Количество до первой операции", text: $quantity).keyboardType(.decimalPad)
                        .accessibilityIdentifier("asset.initialQuantity")
                } else if let currentAsset {
                    LabeledContent("Количество", value: "\(cryptoQuantityText(currentAsset.qty ?? 0)) \(currentAsset.symbol)")
                    NavigationLink("Исправить количество") { AssetQuantityCorrectionView(accountID: accountID, assetID: currentAsset.id) }
                        .accessibilityIdentifier("asset.correctQuantity")
                }
            } footer: {
                Text(asset == nil
                     ? "Если начинаешь с нуля, введи 0. Новые поступления затем записывай кнопкой «Получил»."
                     : "Исправление количества сохранится отдельной записью в истории. Обновление курса количество не меняет.")
            }
            Section {
                TextField("Курс за 1, \(model.currency)", text: $price).keyboardType(.decimalPad)
                    .accessibilityIdentifier("asset.price")
            } header: { Text("Ручной курс") }
            footer: { Text("Введи стоимость одной единицы в \(model.currency). Если курс неизвестен, оставь поле пустым: количество сохранится без денежной оценки.") }
            if asset != nil { Section { Button("Удалить актив", role: .destructive) { deleting = true } } }
            if let localError { Text(localError).foregroundStyle(.red) }
        }.navigationTitle(asset == nil ? "Новый актив" : "Актив").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { save() } }
            }
            .onAppear {
                guard !initialized else { return }
                symbol = asset?.symbol ?? ""; name = asset?.name ?? ""
                quantity = asset.map { cryptoQuantityText($0.initialQty) } ?? ""
                price = asset.map { amountText($0.price) } ?? ""
                initialized = true
            }
            .confirmationDialog("Удалить актив?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { if let asset, model.mutate("deleteAsset", [accountID, asset.id], failure: { localError = $0 }) { dismiss() } }
            }
    }
    private func save() {
        do {
            let ticker = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !ticker.isEmpty else { throw FinanceError.message("Напиши тикер актива") }
            guard model.snapshot?.state.accounts.contains(where: { $0.id == accountID && $0.kind == "crypto" }) == true else {
                throw FinanceError.message("Криптосчёт больше недоступен")
            }
            let initial: Double
            if asset != nil {
                guard let currentAsset else { throw FinanceError.message("Актив больше недоступен") }
                initial = currentAsset.initialQty
            } else {
                initial = try parsedCryptoQuantity(quantity, allowZero: true)
            }
            let cents: Int
            if price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { cents = 0 }
            else { cents = try model.cents(price) }
            guard cents >= 0 else { throw FinanceError.message("Курс не может быть отрицательным") }
            var args: [String: Any] = ["symbol": ticker, "name": name.isEmpty ? ticker : name, "initialQty": initial, "price": cents]
            if let asset { args["id"] = asset.id }
            if model.mutate("saveAsset", [accountID, args], failure: { localError = $0 }) { dismiss() }
        } catch { localError = error.localizedDescription }
    }
}

struct AssetQuantityCorrectionView: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.dismiss) private var dismiss
    let accountID: String
    let assetID: String
    @State private var quantity = ""
    @State private var valuation = ""
    @State private var reason = ""
    @State private var lastAutoValuation = ""
    @State private var initialized = false
    @State private var localError: String?

    private var asset: Asset? {
        model.snapshot?.derived.cryptoAssets.first { $0.id == assetID && $0.accountId == accountID }
    }
    private var delta: Double? {
        guard let asset, let target = try? parsedCryptoQuantity(quantity, allowZero: true) else { return nil }
        return ((target - (asset.qty ?? 0)) * 1e8).rounded() / 1e8
    }
    var body: some View {
        Form {
            if let asset {
                Section {
                    LabeledContent("По учёту", value: "\(cryptoQuantityText(asset.qty ?? 0)) \(asset.symbol)")
                    TextField("Фактическое количество \(asset.symbol)", text: $quantity)
                        .keyboardType(.decimalPad).accessibilityIdentifier("asset.correction.quantity")
                    if let delta, delta != 0 {
                        Text("\(delta > 0 ? "Добавится" : "Спишется") \(cryptoQuantityText(abs(delta))) \(asset.symbol)")
                            .font(LumoType.body).foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField("Оценка изменения, \(model.currency)", text: $valuation)
                        .keyboardType(.decimalPad).accessibilityIdentifier("asset.correction.amount")
                    TextField("Причина (необязательно)", text: $reason, axis: .vertical)
                } footer: {
                    Text("Исправление появится в истории с прежним и новым количеством. Карта, наличные и конверты не изменятся. Для уменьшения количества нужна оценка больше нуля.")
                }
            } else {
                Text("Актив больше недоступен")
            }
            if let localError { Text(localError).foregroundStyle(.red) }
        }
        .navigationTitle("Исправить количество").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Записать") { save() }.disabled(asset == nil).accessibilityIdentifier("asset.correction.save") } }
        .onAppear {
            guard !initialized, let asset else { return }
            quantity = cryptoQuantityText(asset.qty ?? 0)
            initialized = true
        }
        .onChange(of: quantity) { _, _ in updateValuation() }
    }
    private func updateValuation() {
        guard valuation.isEmpty || valuation == lastAutoValuation, let asset, let delta, asset.price > 0 else { return }
        let value = abs(delta) * Double(asset.price)
        guard value.isFinite, value < 9_000_000_000_000_000 else { return }
        lastAutoValuation = amountText(Int(value.rounded()))
        valuation = lastAutoValuation
    }
    private func save() {
        do {
            guard let asset, let delta, delta != 0 else { throw FinanceError.message("Укажи новое количество, отличное от текущего") }
            let target = try parsedCryptoQuantity(quantity, allowZero: true)
            let cents: Int
            if delta > 0 && valuation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { cents = 0 }
            else { cents = try model.cents(valuation) }
            guard cents >= 0, delta > 0 || cents > 0 else { throw FinanceError.message("Укажи положительную оценку списания в \(model.currency)") }
            let label = "Корректировка остатка: \(cryptoQuantityText(asset.qty ?? 0)) → \(cryptoQuantityText(target)) \(asset.symbol)"
            let note = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            let draft: [String: Any] = ["type": delta > 0 ? "crypto_buy" : "crypto_spend", "assetId": asset.id,
                "qty": abs(delta), "amount": cents, "accountId": NSNull(), "date": WalletModel.dateKey(Date()),
                "comment": label + (note.isEmpty ? "" : ". \(note)")]
            if model.mutate("addTransaction", [draft], failure: { localError = $0 }) { dismiss() }
        } catch { localError = error.localizedDescription }
    }
}

struct EnvelopeForm: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.dismiss) private var dismiss
    let envelope: Envelope
    @State private var name = ""
    @State private var goal = "0"
    @State private var localError: String?
    @State private var initialized = false
    var body: some View {
        Form {
            Section { TextField("Название", text: $name); TextField("Цель, \(model.currency)", text: $goal).keyboardType(.decimalPad) }
            Section { NavigationLink("Изменить доли распределения") { PercentagesView() } }
            if let localError { Text(localError).foregroundStyle(.red) }
        }.navigationTitle("Конверт").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { save() } } }
            .onAppear {
                guard !initialized else { return }
                name = envelope.name; goal = amountText(envelope.goal); initialized = true
            }
    }
    private func save() {
        do {
            let cents = try model.cents(goal)
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, cents >= 0 else { throw FinanceError.message("Проверь название и цель") }
            if model.mutate("saveEnvelope", [["id": envelope.id, "name": name, "goal": cents]], failure: { localError = $0 }) { dismiss() }
        } catch { localError = error.localizedDescription }
    }
}

struct PercentagesView: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.dismiss) private var dismiss
    @State private var percents: [String: String] = [:]
    @State private var remainderID = ""
    @State private var localError: String?
    private var envelopes: [Envelope] { model.snapshot?.state.envelopes ?? [] }
    var body: some View {
        Form {
            Section {
                Picker("Остаток получает", selection: $remainderID) { ForEach(envelopes) { Text($0.name).tag($0.id) } }
                ForEach(envelopes.filter { $0.id != remainderID }) { envelope in
                    HStack {
                        Text(envelope.name); Spacer()
                        TextField("%", text: Binding(get: { percents[envelope.id] ?? "0" }, set: { percents[envelope.id] = $0 }))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 70)
                        Text("%").foregroundStyle(.secondary)
                    }
                }
            } footer: { Text("Новые доли действуют только для будущих доходов. Уже отложенные деньги останутся на местах.") }
            Section {
                Button("Поставить 32 / 32 / 36") {
                    guard envelopes.count == 3 else { return }
                    remainderID = envelopes[2].id; percents[envelopes[0].id] = "32"; percents[envelopes[1].id] = "32"
                }.disabled(envelopes.count != 3)
            }
            if let localError { Text(localError).foregroundStyle(.red) }
        }.navigationTitle("Доли конвертов").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { save() } } }
            .onAppear {
                remainderID = envelopes.first { $0.percent == nil }?.id ?? envelopes.last?.id ?? ""
                percents = Dictionary(uniqueKeysWithValues: envelopes.map { ($0.id, String($0.percent ?? 0)) })
            }
    }
    private func save() {
        var values: [String: Any] = [:]
        for envelope in envelopes {
            if envelope.id == remainderID { values[envelope.id] = NSNull(); continue }
            guard let value = Double((percents[envelope.id] ?? "").replacingOccurrences(of: ",", with: ".")), value.isFinite else { localError = "Проверь проценты"; return }
            values[envelope.id] = value
        }
        if model.mutate("setEnvelopePercents", [values], failure: { localError = $0 }) { dismiss() }
    }
}
