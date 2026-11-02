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
    var body: some View {
        Form {
            Section {
                TextField("Название счёта", text: $name)
                if account == nil {
                    Picker("Тип", selection: $kind) { Text("Карта").tag("card"); Text("Наличные").tag("cash"); Text("Криптовалюта").tag("crypto") }
                }
                if kind != "crypto" { TextField("Стартовый остаток", text: $opening).keyboardType(.numbersAndPunctuation) }
                if account != nil { Toggle("Скрыть счёт", isOn: $archived) }
            } footer: { Text("Стартовый остаток — сумма до первой операции. Для изменения сегодняшнего баланса добавь корректировку.") }
            if account != nil { Section { Button("Удалить счёт", role: .destructive) { deleting = true } } }
            if let localError { Text(localError).foregroundStyle(.red) }
        }.navigationTitle(account == nil ? "Новый счёт" : "Настройки счёта").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { save() } }
            }
            .onAppear { name = account?.name ?? ""; kind = account?.kind ?? "card"; opening = amountText(account?.opening ?? 0); archived = account?.archived ?? false }
            .confirmationDialog("Удалить счёт?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { if let account, model.mutate("deleteAccount", [account.id]) { dismiss() } }
            }
    }
    private func save() {
        do {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw FinanceError.message("Напиши название счёта") }
            var args: [String: Any] = ["name": trimmed, "kind": kind, "opening": kind == "crypto" ? 0 : try model.cents(opening), "archived": archived, "color": account?.color ?? "#4690FF"]
            if let account { args["id"] = account.id }
            if model.mutate("saveAccount", [args]) { dismiss() }
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
    @State private var quantity = "0"
    @State private var price = "0"
    @State private var localError: String?
    @State private var deleting = false
    var body: some View {
        Form {
            Section {
                TextField("Тикер, например USDT", text: $symbol).textInputAutocapitalization(.characters).autocorrectionDisabled()
                TextField("Название", text: $name)
                TextField("Количество сейчас", text: $quantity).keyboardType(.decimalPad)
                TextField("Курс за 1, \(model.currency)", text: $price).keyboardType(.decimalPad)
            } footer: { Text("Курс вводится вручную. Изменение количества здесь — корректировка остатка, а не доход или расход.") }
            if asset != nil { Section { Button("Удалить актив", role: .destructive) { deleting = true } } }
            if let localError { Text(localError).foregroundStyle(.red) }
        }.navigationTitle(asset == nil ? "Новый актив" : "Актив").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { save() } }
            }
            .onAppear { symbol = asset?.symbol ?? ""; name = asset?.name ?? ""; quantity = String(asset?.qty ?? asset?.initialQty ?? 0); price = amountText(asset?.price ?? 0) }
            .confirmationDialog("Удалить актив?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { if let asset, model.mutate("deleteAsset", [accountID, asset.id]) { dismiss() } }
            }
    }
    private func save() {
        do {
            let ticker = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !ticker.isEmpty, let qty = Double(quantity.replacingOccurrences(of: ",", with: ".")), qty.isFinite, qty >= 0 else { throw FinanceError.message("Проверь тикер и количество") }
            let cents = try model.cents(price)
            guard cents >= 0 else { throw FinanceError.message("Курс не может быть отрицательным") }
            let initial = (asset?.initialQty ?? 0) + qty - (asset?.qty ?? asset?.initialQty ?? 0)
            var args: [String: Any] = ["symbol": ticker, "name": name.isEmpty ? ticker : name, "initialQty": initial, "price": cents]
            if let asset { args["id"] = asset.id }
            if model.mutate("saveAsset", [accountID, args]) { dismiss() }
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
    var body: some View {
        Form {
            Section { TextField("Название", text: $name); TextField("Цель, \(model.currency)", text: $goal).keyboardType(.decimalPad) }
            Section { NavigationLink("Изменить доли распределения") { PercentagesView() } }
            if let localError { Text(localError).foregroundStyle(.red) }
        }.navigationTitle("Конверт").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { save() } } }
            .onAppear { name = envelope.name; goal = amountText(envelope.goal) }
    }
    private func save() {
        do {
            let cents = try model.cents(goal)
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, cents >= 0 else { throw FinanceError.message("Проверь название и цель") }
            if model.mutate("saveEnvelope", [["id": envelope.id, "name": name, "goal": cents]]) { dismiss() }
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
        if model.mutate("setEnvelopePercents", [values]) { dismiss() }
    }
}
