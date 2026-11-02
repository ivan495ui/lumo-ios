import SwiftUI
import LumoCore

enum LumoTheme {
    static let background = Color(hex: "#080A0E")
    static let surface = Color(hex: "#191D24")
    static let text = Color(hex: "#F7F9FD")
    static let heroStart = Color(hex: "#195DAD")
    static let heroEnd = Color(hex: "#18375F")
    static let heroSecondary = Color(hex: "#D1E2F7")
    static let accent = Color(hex: "#72ADFF")
    static let positive = Color(hex: "#72DEB0")
    static let actionPrimaryFill = Color(hex: "#EDF5FF")
    static let actionPrimaryText = Color(hex: "#12417D")
    static let actionSecondaryFill = Color.white.opacity(0.09)
    static let separator = Color.white.opacity(0.08)

    static func envelopeSurface(_ envelope: LumoCore.Envelope) -> Color {
        if let palette = defaultEnvelopePalette(envelope) {
            return Color(hex: palette.surface)
        }
        // Custom envelopes retain their chosen hue on an opaque dark surface.
        let hex = normalizedHex(envelope.color)
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return surface }
        let tint = 0.18
        let red = Double((value >> 16) & 255) * tint + 25 * (1 - tint)
        let green = Double((value >> 8) & 255) * tint + 29 * (1 - tint)
        let blue = Double(value & 255) * tint + 36 * (1 - tint)
        return Color(red: red / 255, green: green / 255, blue: blue / 255)
    }

    static func envelopeAccent(_ envelope: LumoCore.Envelope) -> Color {
        if let palette = defaultEnvelopePalette(envelope) {
            return Color(hex: palette.accent)
        }
        return Color(hex: normalizedHex(envelope.color))
    }

    private static func defaultEnvelopePalette(_ envelope: LumoCore.Envelope) -> (surface: String, accent: String)? {
        // Only restyle unchanged defaults; an edited color is a user preference.
        switch (envelope.id, normalizedHex(envelope.color)) {
        case ("env_music", "4690FF"):
            return ("#14263F", "#79AEFF")
        case ("env_personal", "9B8CFF"):
            return ("#261E38", "#B8A0FF")
        case ("env_savings", "4FD1A5"):
            return ("#15312C", "#69D8B7")
        default:
            return nil
        }
    }

    private static func normalizedHex(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "").uppercased()
    }
}
