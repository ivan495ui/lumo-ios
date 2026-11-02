import SwiftUI
import LumoCore

/// A quiet, opaque background for both compact tiles and full-width cards.
struct EnvelopeDecoration: View {
    let envelope: LumoCore.Envelope
    var cornerRadius: CGFloat = 16

    var body: some View {
        ZStack {
            LumoTheme.envelopeSurface(envelope)
            LinearGradient(
                colors: [
                    LumoTheme.envelopeAccent(envelope).opacity(0.08),
                    Color.white.opacity(0.015),
                    Color.black.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
