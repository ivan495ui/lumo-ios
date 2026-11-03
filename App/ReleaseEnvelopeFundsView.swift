import SwiftUI
import LumoCore

/// An explicit journal event releases allocated money; it does not move account balances.
struct ReleaseEnvelopeFundsView: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var preview: ExpenseCoveragePreview?
    @State private var localError: String?
    @State private var confirming = false
    var body: some View {
        Form {
            Section {
                TextField("Сумма, \(model.currency)", text: $amount).keyboardType(.decimalPad)
                    .font(LumoType.cardAmount).accessibilityIdentifier("release.amount")
            } footer: {
                Text("Освободи часть отложенных денег для покупки криптовалюты или других операций из свободного остатка. Балансы карты и наличных не изменятся.")
            }
            if let preview {
                Section("Будет освобождено") {
                    ForEach(preview.rows.filter { $0.used > 0 }) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent(row.name, value: money(row.used, currency: model.currency))
                            Text("Останется \(money(row.after, currency: model.currency))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Свободно после", value: money(preview.freeAfter, currency: model.currency))
                }
            }
            if let localError { Section { Text(localError).foregroundStyle(.red) } }
            Section {
                Button("Освободить деньги") { confirming = true }.disabled(preview == nil)
            } footer: { Text("Сумма берётся из положительных конвертов пропорционально их остаткам. Криптовалюта и налоговый резерв исключены. Расчёт показан точно в \(model.currency).") }
        }.navigationTitle("Свободные деньги").navigationBarTitleDisplayMode(.inline)
            .onChange(of: amount) { _, _ in refresh() }
            .confirmationDialog("Освободить эту сумму из конвертов?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Освободить") {
                    guard let preview else { return }
                    if model.mutate("releaseEnvelopeFunds", [preview.amount, preview.fingerprint], failure: { localError = $0 }) { dismiss() }
                    else { refresh() }
                }
            }
    }
    private func refresh() {
        guard !amount.isEmpty else { preview = nil; localError = nil; return }
        do { preview = try model.releasePreview(model.cents(amount)); localError = nil }
        catch { preview = nil; localError = error.localizedDescription }
    }
}
