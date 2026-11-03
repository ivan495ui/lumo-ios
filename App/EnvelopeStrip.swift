import SwiftUI
import UIKit
import LumoCore

/// Overview-only presentation. Names, balances and allocation settings stay unchanged.
struct EnvelopeStrip: View {
    @EnvironmentObject var model: WalletModel
    let envelopes: [LumoCore.Envelope]
    let currency: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var availableWidth: CGFloat = 353

    private let spacing: CGFloat = 10
    private let inset: CGFloat = 12
    private let currencySpacing: CGFloat = 2

    var body: some View {
        Group {
            if needsVerticalLayout {
                VStack(spacing: spacing) {
                    ForEach(envelopes) { envelope in
                        NavigationLink {
                            EnvelopeForm(envelope: envelope)
                        } label: {
                            verticalCard(envelope)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accessibilityLabel(envelope))
                        .accessibilityIdentifier("overview.envelope.\(envelope.id)")
                    }
                }
            } else {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(envelopes) { envelope in
                        NavigationLink {
                            EnvelopeForm(envelope: envelope)
                        } label: {
                            tile(envelope)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(accessibilityLabel(envelope))
                        .accessibilityIdentifier("overview.envelope.\(envelope.id)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            if width > 0, abs(width - availableWidth) > 0.5 {
                availableWidth = width
            }
        }
    }

    private func tile(_ envelope: LumoCore.Envelope) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: envelope.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                Text(share(envelope))
                    .font(LumoType.caption)
                    .monospacedDigit()
            }
            .foregroundStyle(LumoTheme.envelopeAccent(envelope))

            Text(displayName(envelope))
                .font(LumoType.cardLabel)
                .lineLimit(1)

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: currencySpacing) {
                Text(roundedValue(envelope).number)
                    .font(LumoType.cardAmount)
                    .monospacedDigit()
                    .lineLimit(1)
                Text(roundedValue(envelope).symbol)
                    .font(LumoType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(inset)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(EnvelopeDecoration(envelope: envelope))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func verticalCard(_ envelope: LumoCore.Envelope) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: envelope.symbol)
                    .font(LumoType.label)
                    .foregroundStyle(LumoTheme.envelopeAccent(envelope))
                    .accessibilityHidden(true)
                Text(displayName(envelope))
                    .font(LumoType.label)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(share(envelope))
                    .font(LumoType.caption)
                    .monospacedDigit()
                    .foregroundStyle(LumoTheme.envelopeAccent(envelope))
                    .fixedSize()
            }

            Text(model.displayMoney(envelope.balance ?? 0, rounded: true))
                .font(LumoType.cardAmount)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EnvelopeDecoration(envelope: envelope))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var needsVerticalLayout: Bool {
        guard !envelopes.isEmpty else { return false }
        if dynamicTypeSize.isAccessibilitySize || envelopes.count > 3 { return true }

        let tileWidth = (availableWidth - spacing * CGFloat(envelopes.count - 1)) / CGFloat(envelopes.count)
        let textWidth = tileWidth - inset * 2
        let traits = UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
        let amountSize = UIFont.preferredFont(forTextStyle: .title3, compatibleWith: traits).pointSize
        let amountFont = UIFont.monospacedDigitSystemFont(ofSize: amountSize, weight: .medium)
        let currencyFont = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traits)
        let currencyWidth = (currencySymbol(model.effectiveDisplayCurrency) as NSString)
            .size(withAttributes: [.font: currencyFont]).width
        let labelSize = UIFont.preferredFont(forTextStyle: .footnote, compatibleWith: traits).pointSize
        let labelFont = UIFont.systemFont(ofSize: labelSize, weight: .medium)

        return envelopes.contains { envelope in
            // Measure the same two baseline-aligned runs shown in the tile.
            // The number keeps title3, including cents; only the currency is caption.
            let numberWidth = (roundedValue(envelope).number as NSString)
                .size(withAttributes: [.font: amountFont]).width
            let amountWidth = numberWidth + currencySpacing + currencyWidth
            let nameWidth = (displayName(envelope) as NSString)
                .size(withAttributes: [.font: labelFont]).width
            // Keep a small reserve for rounding and SwiftUI/UIKit font metrics.
            return max(amountWidth, nameWidth) + 4 > textWidth
        }
    }

    private var contentSizeCategory: UIContentSizeCategory {
        switch dynamicTypeSize {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }

    private func displayName(_ envelope: LumoCore.Envelope) -> String {
        envelope.id == "env_personal" && envelope.name == "Личные расходы" ? "Личные" : envelope.name
    }

    private func share(_ envelope: LumoCore.Envelope) -> String {
        let percent = envelope.percent ?? max(0, 100 - envelopes.compactMap(\.percent).reduce(0, +))
        return "\(percent.formatted(.number.precision(.fractionLength(0...2))))%"
    }

    private func accessibilityLabel(_ envelope: LumoCore.Envelope) -> String {
        "\(envelope.name), \(model.displayMoney(envelope.balance ?? 0, rounded: true)), \(share(envelope)) от дохода. Точно в учёте: \(money(envelope.balance ?? 0, currency: currency))"
    }
    private func roundedValue(_ envelope: LumoCore.Envelope) -> MoneyValue {
        model.displayValue(envelope.balance ?? 0, rounded: true)
    }
}
