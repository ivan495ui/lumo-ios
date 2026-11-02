import SwiftUI
import LumoCore
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.dismiss) private var dismiss
    @State private var exporting = false
    @State private var importing = false
    @State private var document = LedgerDocument(text: "")
    @State private var candidateText: String?
    @State private var candidate: Snapshot?
    @State private var replacing = false
    @State private var dataError: String?
    var body: some View {
        Form {
            if let snapshot = model.snapshot {
                Section("Отображение") {
                    Toggle("Скрыть криптовалюту", isOn: settingBool("hideCrypto", snapshot.state.settings.hideCrypto))
                    Picker("Валюта учёта", selection: Binding(get: { snapshot.state.settings.currency }, set: { model.mutate("updateSettings", [["currency": $0]]) })) {
                        Text("Белорусский рубль · BYN").tag("BYN"); Text("Доллар · USD").tag("USD"); Text("Российский рубль · RUB").tag("RUB")
                    }
                    Text("Смена обозначения валюты не пересчитывает введённые суммы.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Налоговый резерв") {
                    Toggle("Откладывать на налог", isOn: settingBool("taxEnabled", snapshot.state.settings.taxEnabled))
                    if snapshot.state.settings.taxEnabled {
                        Stepper("Ставка \(snapshot.state.settings.taxRate.formatted())%", value: Binding(get: { snapshot.state.settings.taxRate }, set: { model.mutate("updateSettings", [["taxRate": $0]]) }), in: 0...100, step: 1)
                        Toggle("Сразу помещать в резерв", isOn: settingBool("autoReserve", snapshot.state.settings.autoReserve))
                    }
                    NavigationLink("Состояние резерва") { TaxView() }
                }
                Section("Учёт") {
                    NavigationLink("Категории") { CategoriesView() }
                    NavigationLink("Доли конвертов") { PercentagesView() }
                }
            }
            Section {
                if let dataError { Text(dataError).foregroundStyle(.red).font(LumoType.body) }
                Button("Экспортировать JSON", systemImage: "square.and.arrow.up") {
                    do { document = LedgerDocument(text: try model.exportText()); exporting = true }
                    catch { dataError = error.localizedDescription }
                }.disabled(model.recoveryRequired)
                Button("Импортировать JSON", systemImage: "square.and.arrow.down") { importing = true }
            } header: { Text("Данные") }
            footer: { Text("Данные хранятся на этом iPhone. Сохраняй JSON в Файлы. Для переноса из Telegram экспортируй копию на телефоне, где видны твои операции, и открой её здесь. Синхронизация между устройствами пока не включена.") }
            Section {
                LabeledContent("Приложение", value: "lumo")
                LabeledContent("Версия", value: "2.0 · Native Preview")
                Text("Сделано для моих денег.").foregroundStyle(.secondary)
            }
        }.navigationTitle("Настройки").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "lumo-\(WalletModel.dateKey(Date()))") { result in
                if case .failure(let error) = result { dataError = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let text = try String(contentsOf: url, encoding: .utf8)
                    candidate = try model.inspectImport(text)
                    candidateText = text
                    replacing = true
                } catch { dataError = error.localizedDescription }
            }
            .alert("Заменить данные этой копией?", isPresented: $replacing) {
                Button("Отмена", role: .cancel) { candidateText = nil; candidate = nil }
                Button("Импортировать", role: .destructive) {
                    if let candidateText, !model.importText(candidateText) {
                        dataError = model.error; model.error = nil
                    }
                    candidateText = nil; candidate = nil
                }
            } message: {
                Text("В копии: \(candidate?.state.transactions.count ?? 0) операций, \(candidate?.state.accounts.count ?? 0) счетов. Баланс без крипты: \(money(candidate?.derived.fiatTotal ?? 0, currency: candidate?.state.settings.currency ?? "BYN")). Текущие данные приложения будут заменены; предыдущая версия останется резервной копией.")
            }
    }
    private func settingBool(_ key: String, _ value: Bool) -> Binding<Bool> {
        Binding(get: { value }, set: { model.mutate("updateSettings", [[key: $0]]) })
    }
}

struct TaxView: View {
    @EnvironmentObject var model: WalletModel
    var body: some View {
        if let tax = model.snapshot?.derived.tax {
            List {
                Section {
                    LabeledContent("Доступно в резерве", value: money(tax.reserveAvailable, currency: model.currency))
                    LabeledContent("Ещё не отложено", value: money(tax.pending, currency: model.currency))
                    LabeledContent("Уплачено", value: money(tax.paid, currency: model.currency))
                }
                Section {
                    if tax.pending > 0 { Button("Отложить весь начисленный налог") { model.mutate("reserveAll") } }
                    NavigationLink("Записать уплату налога") { TransactionForm(initialKind: .taxPayment) }
                }
                Section("Начисления") {
                    ForEach(tax.items) { item in
                        Toggle(isOn: Binding(get: { item.reserved }, set: { model.mutate("setReserved", [item.txId, $0]) })) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(money(item.amount, currency: model.currency)).monospacedDigit()
                                Text(item.date).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }.navigationTitle("Налоговый резерв")
        }
    }
}

struct CategoriesView: View {
    @EnvironmentObject var model: WalletModel
    @State private var adding = false
    var body: some View {
        List {
            ForEach(["expense", "income"], id: \.self) { kind in
                Section(kind == "income" ? "Доходы" : "Расходы") {
                    ForEach(model.snapshot?.state.categories.filter { $0.kind == kind } ?? []) { category in
                        NavigationLink { CategoryForm(category: category) } label: {
                            HStack { Text(category.name); Spacer(); if category.taxable { Image(systemName: "percent").foregroundStyle(.secondary) } }
                        }
                    }
                }
            }
            Section { Button("Новая категория", systemImage: "plus") { adding = true } }
        }.navigationTitle("Категории")
            .sheet(isPresented: $adding) { NavigationStack { CategoryForm() } }
    }
}

struct CategoryForm: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.dismiss) private var dismiss
    var category: LedgerCategory?
    @State private var name = ""
    @State private var kind = "expense"
    @State private var taxable = false
    @State private var deleting = false
    @State private var localError: String?
    var body: some View {
        Form {
            TextField("Название", text: $name)
            Picker("Тип", selection: $kind) { Text("Расход").tag("expense"); Text("Доход").tag("income") }.disabled(category != nil)
            if kind == "income" { Toggle("Облагается налогом", isOn: $taxable) }
            if category != nil { Button("Удалить категорию", role: .destructive) { deleting = true } }
            if let localError { Text(localError).foregroundStyle(.red) }
        }.navigationTitle(category == nil ? "Новая категория" : "Категория").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") {
                    var args: [String: Any] = ["name": name.trimmingCharacters(in: .whitespacesAndNewlines), "kind": kind, "taxable": kind == "income" && taxable, "icon": category?.icon ?? "dots"]
                    if let category { args["id"] = category.id }
                    if model.mutate("saveCategory", [args], failure: { localError = $0 }) { dismiss() }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .onAppear { name = category?.name ?? ""; kind = category?.kind ?? "expense"; taxable = category?.taxable ?? false }
            .confirmationDialog("Удалить категорию?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { if let category, model.mutate("deleteCategory", [category.id], failure: { localError = $0 }) { dismiss() } }
            }
    }
}
