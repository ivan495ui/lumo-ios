import SwiftUI
import LumoCore

struct AccountsView: View {
    @EnvironmentObject var model: WalletModel
    @State private var adding = false
    var body: some View {
        List {
            Section {
                ForEach(model.visibleAccounts) { account in
                    NavigationLink { AccountDetail(accountID: account.id) } label: { AccountRow(account: account, currency: model.currency) }
                }
            } footer: { Text("На карте учитываются только твои деньги. Операции родителей сюда не добавляй.") }
            Section { Button("Добавить счёт", systemImage: "plus") { adding = true } }
            if let archived = model.snapshot?.derived.accounts.filter(\.archived), !archived.isEmpty {
                Section("Скрытые счета") {
                    ForEach(archived) { account in
                        NavigationLink { AccountForm(account: account) } label: { AccountRow(account: account, currency: model.currency) }
                    }
                }
            }
        }.sheet(isPresented: $adding) { NavigationStack { AccountForm() } }
    }
}

struct AccountDetail: View {
    @EnvironmentObject var model: WalletModel
    let accountID: String
    @State private var editing = false
    @State private var addingAsset = false
    @State private var kind: TransactionKind?
    var body: some View {
        if let account = model.snapshot?.derived.accounts.first(where: { $0.id == accountID }) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(account.kind == "crypto" ? "Стоимость активов" : "Остаток", systemImage: account.symbol).foregroundStyle(.secondary)
                        Text(money(account.balance ?? 0, currency: model.currency)).font(.system(size: 42, weight: .light)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    }.padding(.vertical, 12)
                }
                Section {
                    if account.kind == "crypto" {
                        Button("Получить крипту", systemImage: "arrow.down.left") { kind = .cryptoBuy }
                        Button("Потратить крипту", systemImage: "arrow.up.right") { kind = .cryptoSpend }
                        Button("Вывести в деньги", systemImage: "arrow.left.arrow.right") { kind = .cryptoSell }
                    } else {
                        Button("Добавить доход", systemImage: "arrow.down.left") { kind = .income }
                        Button("Добавить расход", systemImage: "arrow.up.right") { kind = .expense }
                    }
                }
                if account.kind == "crypto" {
                    Section {
                        ForEach(model.snapshot?.derived.cryptoAssets.filter { $0.accountId == accountID } ?? []) { asset in
                            NavigationLink { AssetForm(accountID: accountID, asset: asset) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(asset.symbol).font(.headline)
                                        Text("\((asset.qty ?? 0).formatted(.number.precision(.fractionLength(0...8)))) · \(money(asset.price, currency: model.currency)) за 1")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(money(asset.value ?? 0, currency: model.currency)).monospacedDigit()
                                }.padding(.vertical, 5)
                            }
                        }
                        Button("Добавить актив", systemImage: "plus") { addingAsset = true }
                    } header: { Text("Активы") } footer: { Text("Курс обновляется вручную. Крипта не попадает в фиатные конверты.") }
                }
                Section("Операции по счёту") {
                    let assets = Set((account.assets ?? []).map(\.id))
                    let rows = model.transactions.filter { $0.accountId == accountID || $0.toAccountId == accountID || assets.contains($0.assetId ?? "") }
                    if rows.isEmpty { EmptyLedger() }
                    ForEach(rows) { transaction in
                        NavigationLink { TransactionDetail(transactionID: transaction.id) } label: { TransactionRow(transaction: transaction) }
                    }
                }
            }.navigationTitle(account.name)
                .toolbar { Button("Изменить") { editing = true } }
                .sheet(isPresented: $editing) { NavigationStack { AccountForm(account: account) } }
                .sheet(isPresented: $addingAsset) { NavigationStack { AssetForm(accountID: accountID) } }
                .sheet(item: $kind) { kind in NavigationStack { TransactionForm(initialKind: kind, initialAccountID: accountID) } }
        }
    }
}
