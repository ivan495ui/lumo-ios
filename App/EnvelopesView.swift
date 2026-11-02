import SwiftUI
import LumoCore

struct EnvelopesView: View {
    @EnvironmentObject var model: WalletModel
    var body: some View {
        if let snapshot = model.snapshot {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Отложено на важное").foregroundStyle(.secondary)
                        BalanceValue(cents: snapshot.derived.envelopeTotal, currency: model.currency)
                    }.padding(.vertical, 12)
                }
                ForEach(snapshot.derived.envelopes) { envelope in
                    Section {
                        NavigationLink { EnvelopeForm(envelope: envelope) } label: {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Badge(symbol: envelope.symbol, color: Color(hex: envelope.color))
                                    Text(envelope.name).font(LumoType.section)
                                    Spacer()
                                    Text(shareLabel(envelope, all: snapshot.derived.envelopes)).font(LumoType.caption).foregroundStyle(.secondary)
                                }
                                Text(money(envelope.balance ?? 0, currency: model.currency)).font(LumoType.cardAmount).monospacedDigit()
                                if envelope.goal > 0 {
                                    ProgressView(value: min(1, max(0, Double(envelope.balance ?? 0) / Double(envelope.goal))))
                                        .tint(Color(hex: envelope.color))
                                    Text("Цель \(money(envelope.goal, currency: model.currency))").font(LumoType.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 10)
                        }
                    }
                }
                Section {
                    NavigationLink { PercentagesView() } label: { Label("Настроить доли", systemImage: "slider.horizontal.3") }
                    NavigationLink { RebalanceView() } label: { Label("Перераспределить накопленное", systemImage: "arrow.triangle.branch") }
                    NavigationLink { TransactionForm(initialKind: .envTransfer) } label: { Label("Перевести между конвертами", systemImage: "arrow.left.arrow.right") }
                } footer: { Text("Карта и наличные распределяются по конвертам. Криптовалюта и налоговый резерв считаются отдельно.") }
            }
        }
    }
}

struct RebalanceView: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.dismiss) private var dismiss
    @State private var preview: RebalancePreview?
    @State private var confirming = false
    var body: some View {
        List {
            if let preview {
                Section {
                    LabeledContent("К распределению", value: money(preview.available, currency: model.currency))
                    LabeledContent("Сейчас свободно", value: money(preview.free, currency: model.currency))
                } footer: { Text("Без криптовалюты и налогового резерва.") }
                Section("Было → станет") {
                    ForEach(preview.rows) { row in
                        LabeledContent(row.name) { Text("\(money(row.before, currency: model.currency)) → \(money(row.after, currency: model.currency))").font(LumoType.body).monospacedDigit() }
                    }
                }
                Section { Button("Распределить по этим долям") { confirming = true }.disabled(preview.rows.allSatisfy { $0.before == $0.after }) }
            }
        }.navigationTitle("Распределение").navigationBarTitleDisplayMode(.inline)
            .task { do { preview = try model.preview() } catch { model.error = error.localizedDescription } }
            .confirmationDialog("Перераспределить накопленное?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Распределить") {
                    if let preview, model.mutate("rebalanceEnvelopes", [preview.fingerprint]) { dismiss() }
                }
            } message: { Text("Изменятся суммы в конвертах. Балансы счетов останутся прежними. В истории появится запись, которую можно удалить для отмены.") }
    }
}
