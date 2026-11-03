import SwiftUI
import LumoCore

struct CurrencySettingsView: View {
    @EnvironmentObject var model: WalletModel
    @ObservedObject var exchange: ExchangeDisplay
    var body: some View {
        Form {
            Section {
                Picker("Показывать суммы в", selection: Binding(get: { exchange.selected(base: model.currency) }, set: { exchange.select($0, base: model.currency) })) {
                    CurrencyChoices()
                }.accessibilityIdentifier("currency.display")
                LabeledContent("Пример · 100 \(model.currency)", value: model.displayMoney(10_000))
                    .accessibilityIdentifier("currency.example")
            } footer: {
                Text("Меняется только отображение. Ввод операций, цели и ручные курсы остаются в \(model.currency). Журнал и количество криптовалюты сохраняются без пересчёта.")
            }
            Section("Курс") {
                if exchange.isLoading { ProgressView("Обновляем курс…") }
                Text(exchange.status(base: model.currency) ?? "Валюта отображения совпадает с валютой учёта. Пересчёт не требуется.")
                if let error = exchange.lastError { Text(error).foregroundStyle(.secondary) }
                Button("Обновить курс НБРБ") { Task { await exchange.refresh(base: model.currency, force: true) } }
                    .disabled(exchange.isLoading)
            }
            Section {
                LabeledContent("Валюта учёта", value: model.currency)
            } footer: {
                Text("Официальный курс НБРБ используется для приблизительной оценки. Курс обмена банка или криптосервиса может отличаться.")
            }
        }.navigationTitle("Валюта отображения").navigationBarTitleDisplayMode(.inline)
    }
}

struct CurrencyChoices: View {
    var body: some View {
        Text("Белорусский рубль · BYN").tag("BYN")
        Text("Доллар · USD").tag("USD")
        Text("Российский рубль · RUB").tag("RUB")
    }
}

/// Earlier versions changed only the label. The owner, rather than a guessed rate,
/// identifies the unit of every stored number before converted readouts are enabled.
struct ConfirmLedgerCurrencyView: View {
    @EnvironmentObject var model: WalletModel
    @State private var actualCurrency = ""
    var body: some View {
        Form {
            Section {
                Text("Уточним валюту старых сумм").font(.title2.weight(.semibold))
                Text("В прошлой версии переключатель менял только знак валюты. Сейчас в данных указан \(model.currency). В какой валюте ты на самом деле вводил суммы?")
                Picker("Суммы вводились в", selection: $actualCurrency) {
                    Text("Выбери валюту").tag("")
                    CurrencyChoices()
                }
            } footer: { Text("Числа и операции останутся прежними. После подтверждения USD и RUB будут отдельным пересчитанным видом.") }
            Section {
                Button("Подтвердить валюту") { _ = model.confirmCurrency(actualCurrency) }
                    .disabled(actualCurrency.isEmpty)
            }
        }.navigationTitle("Валюта учёта")
    }
}

struct ImportReviewView: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.dismiss) private var dismiss
    let text: String
    let candidate: Snapshot
    let onSuccess: () -> Void
    @State private var actualCurrency = ""
    @State private var confirming = false
    @State private var localError: String?
    private var requiresChoice: Bool { candidate.state.settings.currency != "BYN" }
    private var unit: String { actualCurrency.isEmpty ? candidate.state.settings.currency : actualCurrency }
    var body: some View {
        NavigationStack {
            Form {
                Section("Содержимое копии") {
                    LabeledContent("Операций", value: String(candidate.state.transactions.count))
                    LabeledContent("Счетов", value: String(candidate.state.accounts.count))
                    LabeledContent("Карта и наличные", value: money(candidate.derived.fiatTotal, currency: unit))
                }
                if requiresChoice {
                    Section {
                        Picker("Суммы вводились в", selection: $actualCurrency) {
                            Text("Выбери валюту").tag("")
                            CurrencyChoices()
                        }
                    } footer: { Text("В старой версии переключатель менял только знак. Укажи фактическую валюту чисел в копии. Числа не будут пересчитаны при импорте.") }
                }
                Section {
                    Button("Заменить данные этой копией", role: .destructive) { confirming = true }
                        .disabled(requiresChoice && actualCurrency.isEmpty)
                    if let localError { Text(localError).foregroundStyle(.red) }
                } footer: { Text("Текущие операции будут заменены. Предыдущая версия останется локальной резервной копией.") }
            }.navigationTitle("Проверка копии").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
                .confirmationDialog("Заменить текущие данные?", isPresented: $confirming, titleVisibility: .visible) {
                    Button("Импортировать", role: .destructive) {
                        if model.importText(text, actualCurrency: requiresChoice ? actualCurrency : nil) { onSuccess(); dismiss() }
                        else { localError = model.error; model.error = nil }
                    }
                }
        }
    }
}
