// Hallmark: native app redesign; charcoal, phosphor, lowercase grotesk.
// Ruled sections, lowercase labels, one phosphor readout.
import AppKit
import SwiftUI

enum Brand {
    static let name = "computer, listen"
    static let displayFont = "HelveticaNeue-Bold"
    static func display(_ size: CGFloat) -> Font { .custom(displayFont, size: size) }
    static func mono(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
}

enum Palette {
    static let signal = Color(nsColor: color(0xD5F66B))
    static let charcoal = Color(nsColor: color(0x171B17))
    static let overlay = Color(nsColor: color(0x171B17))
    static let screen = Color(nsColor: color(0x0F120F))
    static let accent = adaptive(light: 0x426008, dark: 0xD5F66B)
    static let paper = adaptive(light: 0xF2F3EB, dark: 0x171B17)
    static let surface = adaptive(light: 0xFAFBF5, dark: 0x21261F)
    static let sidebar = adaptive(light: 0xE9ECE1, dark: 0x1B201A)
    static let line = adaptive(light: 0xCCD2C3, dark: 0x3A4234)
    static let ink = adaptive(light: 0x1C2318, dark: 0xEEF2E6)
    static let muted = adaptive(light: 0x606A56, dark: 0xB1BBA5)

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            color(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        })
    }
}

/// The one loud button per screen: phosphor fill, charcoal type.
struct SignalButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: compact ? 12 : 14, weight: .semibold))
            .padding(.horizontal, compact ? 12 : 18).frame(height: compact ? 28 : 40)
            .foregroundStyle(Palette.charcoal)
            .background(Palette.signal, in: RoundedRectangle(cornerRadius: compact ? 6 : 8))
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
            .opacity(enabled ? 1 : 0.4)
    }
}

/// Everything else: a hairline outline that stays out of the way.
struct LineButtonStyle: ButtonStyle {
    var destructive = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium)).labelStyle(.titleOnly)
            .padding(.horizontal, 11).frame(height: 28)
            .foregroundStyle(destructive ? Color.red : Palette.ink)
            .background(configuration.isPressed ? Palette.line.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line) }
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
            .opacity(enabled ? 1 : 0.4)
    }
}

/// Mono, lowercase metadata: section labels, timestamps, counts.
struct MonoLabel: View {
    let text: String
    var color = Palette.muted
    init(_ text: String, color: Color = Palette.muted) { self.text = text; self.color = color }
    var body: some View { Text(text.lowercased()).font(Brand.mono(11)).foregroundStyle(color).monospacedDigit() }
}
