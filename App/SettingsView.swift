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
                    NavigationLink("Валюта отображения") { CurrencySettingsView(exchange: model.exchange) }
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
            Section("Сохранность и защита") {
                NavigationLink("Автоматическая защищённая копия") { BackupSettingsView(service: model.automaticBackup) }
                NavigationLink("Face ID и код-пароль") { AppLockSettingsView(lock: model.appLock) }
            }
            Section {
                if let dataError { Text(dataError).foregroundStyle(.red).font(LumoType.body) }
                Button("Экспортировать JSON", systemImage: "square.and.arrow.up") {
                    do { document = LedgerDocument(text: try model.exportText()); exporting = true }
                    catch { dataError = error.localizedDescription }
                }.disabled(model.recoveryRequired)
                Button("Импортировать JSON", systemImage: "square.and.arrow.down") { importing = true }
            } header: { Text("Данные") }
            footer: { Text("Журнал хранится на этом iPhone. Настрой автоматическую защищённую копию в iCloud Drive один раз. JSON нужен для переноса из Telegram или ручного экспорта; он содержит незашифрованные операции.") }
            Section {
                LabeledContent("Приложение", value: "lumo")
                LabeledContent("Версия", value: "2.1")
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
            .sheet(isPresented: $replacing, onDismiss: { candidate = nil; candidateText = nil }) {
                if let candidate, let candidateText {
                    ImportReviewView(text: candidateText, candidate: candidate) { replacing = false }
                }
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
                    LabeledContent("Доступно в резерве", value: model.displayMoney(tax.reserveAvailable))
                    LabeledContent("Ещё не отложено", value: model.displayMoney(tax.pending))
                    LabeledContent("Уплачено", value: model.displayMoney(tax.paid))
                }
                Section {
                    if tax.pending > 0 { Button("Отложить весь начисленный налог") { model.mutate("reserveAll") } }
                    NavigationLink("Записать уплату налога") { TransactionForm(initialKind: .taxPayment) }
                }
                Section("Начисления") {
                    ForEach(tax.items) { item in
                        Toggle(isOn: Binding(get: { item.reserved }, set: { model.mutate("setReserved", [item.txId, $0]) })) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.displayMoney(item.amount)).monospacedDigit()
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
