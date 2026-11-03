import SwiftUI
import LumoCore

struct EnvelopesView: View {
    @EnvironmentObject var model: WalletModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let snapshot = model.snapshot {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Распределено по конвертам")
                            .font(LumoType.body).foregroundStyle(.secondary)
                        Text(model.envelopeMoney(snapshot.derived.envelopeTotal))
                            .font(LumoType.balance).monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("envelopes.balance")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if snapshot.derived.envelopes.contains(where: { ($0.balance ?? 0) < 0 }) {
                        NavigationLink { RebalanceView() } label: {
                            Label("Есть перерасход. Проверить распределение", systemImage: "exclamationmark.circle")
                                .font(LumoType.body).frame(maxWidth: .infinity, alignment: .leading)
                        }.accessibilityIdentifier("envelopes.repair")
                    }

                    VStack(spacing: 10) {
                        ForEach(snapshot.derived.envelopes) { envelope in
                            NavigationLink { EnvelopeForm(envelope: envelope) } label: {
                                envelopeCard(envelope, all: snapshot.derived.envelopes)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Изменить название и цель конверта")
                        }
                    }

                    managementSection
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
            }
            .background(LumoTheme.background)
            .foregroundStyle(LumoTheme.text)
        }
    }

    private func envelopeCard(_ envelope: Envelope, all: [Envelope]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: envelope.symbol)
                    .font(LumoType.section)
                    .foregroundStyle(LumoTheme.envelopeAccent(envelope))
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(envelope.name)
                    .font(LumoType.label)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(LumoType.caption).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            if dynamicTypeSize.isAccessibilitySize {
                verticalMetrics(envelope, all: all)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        amount(envelope).fixedSize()
                        Spacer(minLength: 0)
                        allocation(envelope, all: all).fixedSize()
                    }
                    verticalMetrics(envelope, all: all)
                }
            }

            if envelope.goal > 0 {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Цель · \(model.envelopeMoney(envelope.goal))")
                        .font(LumoType.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ProgressView(value: min(1, max(0, Double(envelope.balance ?? 0) / Double(envelope.goal))))
                        .tint(LumoTheme.envelopeAccent(envelope))
                        .accessibilityLabel("Накоплено на цель")
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EnvelopeDecoration(envelope: envelope))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func amount(_ envelope: Envelope) -> some View {
        Text(model.envelopeMoney(envelope.balance ?? 0))
            .font(LumoType.cardAmount).monospacedDigit()
            .foregroundStyle(LumoTheme.text)
    }

    private func allocation(_ envelope: Envelope, all: [Envelope]) -> some View {
        Text(shareLabel(envelope, all: all))
            .font(LumoType.caption).foregroundStyle(.secondary)
    }

    private func verticalMetrics(_ envelope: Envelope, all: [Envelope]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            amount(envelope).fixedSize(horizontal: false, vertical: true)
            allocation(envelope, all: all).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Управление").font(LumoType.section)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                NavigationLink { PercentagesView() } label: {
                    managementRow("Настроить доли", symbol: "slider.horizontal.3")
                }
                Divider().overlay(LumoTheme.separator).padding(.leading, 46)
                NavigationLink { RebalanceView() } label: {
                    managementRow("Перераспределить накопленное", symbol: "arrow.triangle.branch")
                }
                Divider().overlay(LumoTheme.separator).padding(.leading, 46)
                NavigationLink { TransactionForm(initialKind: .envTransfer) } label: {
                    managementRow("Перевести между конвертами", symbol: "arrow.left.arrow.right")
                }
                Divider().overlay(LumoTheme.separator).padding(.leading, 46)
                NavigationLink { ReleaseEnvelopeFundsView() } label: {
                    managementRow("Освободить часть денег", symbol: "arrow.up.bin")
                }
            }
            .buttonStyle(.plain)
            .background(LumoTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("По конвертам распределяются карта и наличные. Криптовалюта и налоговый резерв учитываются отдельно. Суммы округлены до целых; копейки сохранены в учёте.")
                .font(LumoType.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func managementRow(_ title: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(LumoType.body).foregroundStyle(LumoTheme.accent)
                .frame(width: 22).accessibilityHidden(true)
            Text(title).font(LumoType.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(LumoType.caption).foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .contentShape(Rectangle())
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
                } footer: { Text("Без криптовалюты и налогового резерва. Суммы здесь показаны точно в \(model.currency), включая копейки.") }
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
