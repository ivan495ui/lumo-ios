import SwiftUI
import LumoCore

struct CryptoAccountView: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let accountID: String
    @State private var mode: CryptoEntryMode?
    @State private var addingAsset = false
    @State private var editing = false

    private var account: Account? { model.snapshot?.derived.accounts.first { $0.id == accountID } }
    private var assets: [Asset] { model.snapshot?.derived.cryptoAssets.filter { $0.accountId == accountID } ?? [] }
    private var transactions: [LedgerTransaction] {
        let ids = Set(assets.map(\.id))
        return model.transactions.filter { ids.contains($0.assetId ?? "") || $0.accountId == accountID || $0.toAccountId == accountID }
    }

    var body: some View {
        if let account {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    balance(account)
                    if assets.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Начни с актива").font(LumoType.section)
                            Text("Выбери USDT или добавь другую криптовалюту. Количество и ручной курс укажешь сам.")
                                .font(LumoType.body).foregroundStyle(.secondary)
                            Button("Добавить актив", systemImage: "plus") { addingAsset = true }
                                .buttonStyle(.borderedProminent).frame(minHeight: 44)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(LumoTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        actions
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Активы и курс").font(LumoType.section).accessibilityAddTraits(.isHeader)
                            ForEach(assets) { asset in
                                NavigationLink { AssetForm(accountID: accountID, asset: asset) } label: { assetCard(asset) }
                                    .buttonStyle(.plain).accessibilityIdentifier("crypto.asset.\(asset.id)")
                            }
                            Button("Добавить актив", systemImage: "plus") { addingAsset = true }
                                .font(LumoType.body).foregroundStyle(LumoTheme.accent).frame(minHeight: 44)
                        }
                    }
                    Text("Курс вводится вручную. Криптовалюта не распределяется по фиатным конвертам.")
                        .font(LumoType.caption).foregroundStyle(.secondary)
                    history
                }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
            }
            .background(LumoTheme.background).foregroundStyle(LumoTheme.text)
            .navigationTitle(account.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Изменить") { editing = true } }
            .sheet(isPresented: $editing) { NavigationStack { AccountForm(account: account) } }
            .sheet(isPresented: $addingAsset) { NavigationStack { AssetForm(accountID: accountID) } }
            .sheet(item: $mode) { mode in NavigationStack { CryptoEntryView(accountID: accountID, mode: mode) } }
        }
    }

    private func balance(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if assets.count == 1, let asset = assets.first {
                Text("\(cryptoQuantityText(asset.qty ?? 0)) \(asset.symbol)")
                    .font(LumoType.balance).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("crypto.balance.quantity")
            } else {
                Text(assets.isEmpty ? "Криптовалюта" : "Стоимость активов").font(LumoType.section)
            }
            if !assets.isEmpty {
                let unpriced = assets.contains { ($0.qty ?? 0) != 0 && $0.price == 0 }
                if assets.allSatisfy({ $0.price == 0 }) && unpriced {
                    Text("Укажи курс для оценки").font(LumoType.body).foregroundStyle(.secondary)
                } else {
                    Text("\(unpriced ? "Частичная оценка " : "")\(model.estimatedMoney(account.balance ?? 0))")
                        .font(LumoType.cardAmount).monospacedDigit().foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) { primaryActions }
            } else {
                HStack(spacing: 8) { primaryActions }
            }
            Button("Купил за \(model.currency)", systemImage: "creditcard") { mode = .bought }
                .font(LumoType.body).foregroundStyle(LumoTheme.accent).frame(minHeight: 44)
                .accessibilityIdentifier("crypto.bought")
        }
    }
    @ViewBuilder private var primaryActions: some View {
        action(.received)
        action(.sent)
        action(.withdraw)
    }
    private func action(_ value: CryptoEntryMode) -> some View {
        Button { mode = value } label: {
            VStack(spacing: 6) {
                Image(systemName: value.symbol).font(LumoType.section).accessibilityHidden(true)
                Text(value.title).font(LumoType.body).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 64).padding(.vertical, 6)
                .background(LumoTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityIdentifier("crypto.\(value.rawValue)")
    }

    private func assetCard(_ asset: Asset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(cryptoQuantityText(asset.qty ?? 0)) \(asset.symbol)")
                    .font(LumoType.cardAmount).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(LumoType.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            Text(asset.price == 0 ? "Нет оценки · укажи курс" : model.estimatedMoney(asset.value ?? 0))
                .font(LumoType.body).foregroundStyle(.secondary)
            if asset.price > 0 {
                Text("Ручной курс: 1 \(asset.symbol) \(model.estimatedMoney(asset.price))")
                    .font(LumoType.caption).foregroundStyle(.secondary)
            }
            if let date = rateDate(asset.updatedAt) {
                Text("Обновлён \(date.formatted(date: .abbreviated, time: .omitted))")
                    .font(LumoType.caption).foregroundStyle(.secondary)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(LumoTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Операции").font(LumoType.section).accessibilityAddTraits(.isHeader)
            if transactions.isEmpty {
                Text("Пока нет записей").font(LumoType.body).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(transactions) { transaction in
                        NavigationLink { TransactionDetail(transactionID: transaction.id) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(transactionTitle(transaction)).font(LumoType.body)
                                    Spacer(minLength: 8)
                                    Text(transaction.date).font(LumoType.caption).foregroundStyle(.secondary)
                                }
                                if let qty = transaction.qty, let asset = assets.first(where: { $0.id == transaction.assetId }) {
                                    Text("\(transaction.type == "crypto_buy" ? "+" : "−")\(cryptoQuantityText(qty)) \(asset.symbol)")
                                        .font(LumoType.amount).monospacedDigit()
                                }
                                Text("\(transaction.accountId == nil ? "Оценка записи" : transaction.type == "crypto_sell" ? "Получено" : "Оплачено"): \(model.displayMoney(transaction.amount))")
                                    .font(LumoType.caption).foregroundStyle(.secondary)
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if transaction.id != transactions.last?.id { Divider().padding(.leading, 14) }
                    }
                }.background(LumoTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
    private func transactionTitle(_ transaction: LedgerTransaction) -> String {
        if transaction.comment?.hasPrefix("Корректировка остатка:") == true { return "Корректировка остатка" }
        if transaction.type == "crypto_buy" { return transaction.accountId == nil ? "Получил" : "Купил за \(model.currency)" }
        return transaction.type == "crypto_sell" ? "В деньги" : transaction.type == "crypto_spend" ? "Отправил" : transaction.label
    }
    private func rateDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
