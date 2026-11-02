import SwiftUI
import LumoCore

struct AccountsView: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var adding = false

    private var archivedAccounts: [Account] {
        model.snapshot?.derived.accounts.filter(\.archived) ?? []
    }

    private var usesCompactGallery: Bool {
        dynamicTypeSize <= .large && model.visibleAccounts.allSatisfy {
            money($0.balance ?? 0, currency: model.currency).count <= 11
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(spacing: 12) {
                    if let first = model.visibleAccounts.first {
                        accountLink(first, featured: true)
                    }
                    let remaining = Array(model.visibleAccounts.dropFirst())
                    if usesCompactGallery && remaining.count > 1 {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                            ForEach(remaining) { account in
                                accountLink(account)
                            }
                        }
                    } else {
                        ForEach(remaining) { account in
                            accountLink(account)
                        }
                    }
                    if model.visibleAccounts.isEmpty {
                        Text("Нет видимых счетов")
                            .font(LumoType.body).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                    }
                }

                Text("На карте учитываются только твои деньги. Операции родителей сюда не добавляй.")
                    .font(LumoType.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button { adding = true } label: {
                    Label("Добавить счёт", systemImage: "plus")
                        .font(LumoType.label)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 16).padding(.vertical, 4)
                        .background(LumoTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }.buttonStyle(.plain).foregroundStyle(LumoTheme.accent)

                if !archivedAccounts.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Скрытые счета").font(LumoType.section)
                            .accessibilityAddTraits(.isHeader)
                        VStack(spacing: 10) {
                            ForEach(archivedAccounts) { account in
                                NavigationLink { AccountForm(account: account) } label: {
                                    accountCard(account, featured: false)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
        }
        .background(LumoTheme.background)
        .foregroundStyle(LumoTheme.text)
        .sheet(isPresented: $adding) { NavigationStack { AccountForm() } }
    }

    private func accountLink(_ account: Account, featured: Bool = false) -> some View {
        NavigationLink { AccountDetail(accountID: account.id) } label: {
            accountCard(account, featured: featured)
        }.buttonStyle(.plain)
    }

    private func accountCard(_ account: Account, featured: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Image(systemName: account.symbol).font(.title3.weight(.medium))
                    .foregroundStyle(featured ? LumoTheme.heroSecondary : Color(hex: account.color))
                    .accessibilityHidden(true)
                Spacer(minLength: 12)
                Image(systemName: "chevron.right").font(LumoType.caption.weight(.semibold))
                    .foregroundStyle(featured ? LumoTheme.heroSecondary : Color.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(account.name).font(LumoType.label)
                    .fixedSize(horizontal: false, vertical: true)
                Text(money(account.balance ?? 0, currency: model.currency))
                    .font(featured ? LumoType.balance : LumoType.cardAmount)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(featured ? 20 : 16)
        .background {
            if featured {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [LumoTheme.heroStart, LumoTheme.heroEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LumoTheme.surface)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: featured ? 22 : 18, style: .continuous))
        .accessibilityElement(children: .combine)
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
                        BalanceValue(cents: account.balance ?? 0, currency: model.currency)
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
                                        Text(asset.symbol).font(LumoType.section)
                                        Text("\((asset.qty ?? 0).formatted(.number.precision(.fractionLength(0...8)))) · \(money(asset.price, currency: model.currency)) за 1")
                                            .font(LumoType.caption).foregroundStyle(.secondary)
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
