import SwiftUI
import LumoCore

enum CryptoEntryMode: String, Identifiable {
    case received, sent, withdraw, bought
    var id: String { rawValue }
    var title: String {
        switch self {
        case .received: "Получил"
        case .sent: "Отправил"
        case .withdraw: "В деньги"
        case .bought: "Купил"
        }
    }
    var kind: TransactionKind {
        switch self {
        case .received, .bought: .cryptoBuy
        case .sent: .cryptoSpend
        case .withdraw: .cryptoSell
        }
    }
    var hasFiatFlow: Bool { self == .withdraw || self == .bought }
    var isOutgoing: Bool { self == .sent || self == .withdraw }
    var symbol: String {
        switch self {
        case .received: "arrow.down.left"
        case .sent: "arrow.up.right"
        case .withdraw: "arrow.left.arrow.right"
        case .bought: "creditcard"
        }
    }
}

/// Records an already completed operation; it never sends crypto or contacts a wallet.
struct CryptoEntryView: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.dismiss) private var dismiss
    let accountID: String
    var initialAssetID: String? = nil
    let mode: CryptoEntryMode

    @State private var assetID = ""
    @State private var quantity = ""
    @State private var amount = ""
    @State private var fiatAccountID = ""
    @State private var date = Date()
    @State private var comment = ""
    @State private var localError: String?
    @State private var initialized = false
    @State private var lastAutoAmount = ""

    private var assets: [Asset] {
        model.snapshot?.derived.cryptoAssets.filter { $0.accountId == accountID } ?? []
    }
    private var asset: Asset? { assets.first { $0.id == assetID } }
    private var fiatAccounts: [Account] {
        (model.snapshot?.state.accounts ?? []).filter { $0.kind != "crypto" && !$0.archived }
    }

    var body: some View {
        Form {
            Section {
                Text("Запись уже совершённой операции. lumo не переводит средства.")
                    .font(LumoType.caption).foregroundStyle(.secondary)
            }
            Section("Криптовалюта") {
                if assets.isEmpty {
                    Text("На этом счёте пока нет активов.").font(LumoType.body)
                    NavigationLink("Добавить USDT или другой актив") { AssetForm(accountID: accountID) }
                } else {
                    Picker("Актив", selection: $assetID) {
                        Text("Выбери актив").tag("")
                        ForEach(assets) { Text($0.symbol).tag($0.id) }
                    }.accessibilityIdentifier("crypto.asset")
                    TextField("Количество \(asset?.symbol ?? "актива")", text: $quantity)
                        .keyboardType(.decimalPad).accessibilityIdentifier("crypto.quantity")
                    if let asset, mode.isOutgoing {
                        Text("Доступно: \(cryptoQuantityText(asset.qty ?? 0)) \(asset.symbol)")
                            .font(LumoType.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                TextField("Сумма, \(model.currency)", text: $amount)
                    .keyboardType(.decimalPad).font(LumoType.cardAmount).monospacedDigit()
                    .accessibilityIdentifier("crypto.amount")
                if mode.hasFiatFlow {
                    Picker(mode == .withdraw ? "Куда зачислено" : "Откуда оплачено", selection: $fiatAccountID) {
                        Text("Выбери счёт").tag("")
                        ForEach(fiatAccounts) { Text($0.name).tag($0.id) }
                    }.accessibilityIdentifier("crypto.fiatAccount")
                    if mode == .bought {
                        LabeledContent("Свободные деньги", value: model.displayMoney(model.snapshot?.derived.unallocated ?? 0))
                        NavigationLink("Освободить из конвертов") { ReleaseEnvelopeFundsView() }
                            .accessibilityIdentifier("crypto.releaseFunds")
                    }
                }
            } header: {
                Text(mode == .withdraw ? "Получено в \(model.currency)" : mode == .bought ? "Оплачено в \(model.currency)" : "Оценка операции в \(model.currency)")
            } footer: {
                if mode.hasFiatFlow {
                    Text("Укажи фактически \(mode == .withdraw ? "полученную" : "оплаченную") сумму. Изменится только выбранный денежный счёт; конверты останутся прежними.")
                    if mode == .bought {
                        Text("Покупка записывается из свободных денег. Отложенные в конвертах суммы автоматически не используются.")
                    }
                } else {
                    Text(mode == .received
                         ? "Карта и наличные не изменятся. Если оценка неизвестна, оставь её пустой; курс актива можно указать позднее."
                         : "Оценка нужна для истории. Карта, наличные и конверты не изменятся. Для перевода между своими счетами эта запись не подходит.")
                }
                Text("Оценка записи не меняет ручной курс актива.")
            }
            Section {
                DatePicker("Дата", selection: $date, displayedComponents: .date)
                TextField("Комментарий", text: $comment, axis: .vertical).lineLimit(2...4)
                    .accessibilityIdentifier("crypto.comment")
            }
            if let localError { Section { Text(localError).foregroundStyle(.red) } }
        }
        .navigationTitle(mode.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Записать") { save() }.fontWeight(.semibold).disabled(assets.isEmpty)
                    .accessibilityIdentifier("crypto.save")
            }
        }
        .onAppear { initialize() }
        .onChange(of: quantity) { _, _ in updateValuation() }
        .onChange(of: assetID) { _, _ in updateValuation() }
        .onChange(of: assets.map(\.id)) { _, ids in
            if !ids.contains(assetID) { selectAsset() }
        }
    }

    private func initialize() {
        guard !initialized else { return }
        selectAsset()
        fiatAccountID = fiatAccounts.first?.id ?? ""
        initialized = true
    }
    private func selectAsset() {
        assetID = assets.first { $0.id == initialAssetID }?.id
            ?? assets.first { $0.symbol.uppercased() == "USDT" }?.id ?? assets.first?.id ?? ""
    }
    private func updateValuation() {
        guard amount.isEmpty || amount == lastAutoAmount, let asset, asset.price > 0,
              let qty = try? parsedCryptoQuantity(quantity) else { return }
        let value = qty * Double(asset.price)
        guard value.isFinite, value >= 0, value < 9_000_000_000_000_000 else { return }
        lastAutoAmount = amountText(Int(value.rounded()))
        amount = lastAutoAmount
    }
    private func save() {
        do {
            guard let asset else { throw FinanceError.message("Выбери актив этого счёта") }
            let qty = try parsedCryptoQuantity(quantity)
            let cents: Int
            if mode == .received && amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { cents = 0 }
            else { cents = try model.cents(amount) }
            guard cents >= 0 else { throw FinanceError.message("Стоимость не может быть отрицательной") }
            if mode != .received && cents == 0 { throw FinanceError.message("Укажи сумму больше нуля в \(model.currency)") }
            if mode.hasFiatFlow && !fiatAccounts.contains(where: { $0.id == fiatAccountID }) {
                throw FinanceError.message("Выбери карту или наличные для денежной части операции")
            }
            let draft: [String: Any] = ["type": mode.kind.rawValue, "assetId": asset.id, "qty": qty,
                "amount": cents, "accountId": mode.hasFiatFlow ? fiatAccountID as Any : NSNull(),
                "date": WalletModel.dateKey(date), "comment": comment]
            if model.mutate("addTransaction", [draft], failure: { localError = $0 }) { dismiss() }
        } catch { localError = error.localizedDescription }
    }
}

/// Stable decimal input with no grouping or exponent notation, up to core's eight places.
func cryptoQuantityText(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.maximumFractionDigits = 8
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
}

func parsedCryptoQuantity(_ text: String, allowZero: Bool = false) throws -> Double {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
    guard normalized.range(of: #"^\d+(?:\.\d{0,8})?$"#, options: .regularExpression) != nil,
          let value = Double(normalized), value.isFinite, (allowZero ? value >= 0 : value > 0) else {
        throw FinanceError.message(allowZero ? "Введи количество от нуля, до 8 знаков после запятой" : "Введи количество больше нуля, до 8 знаков после запятой")
    }
    return value
}
