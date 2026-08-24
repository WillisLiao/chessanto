import SwiftUI
import AppKit

/// Chrome color tokens, per the UI/UX redesign plan (`handoffs/NEXT-SESSION-UIUX-EXECUTE.md`).
/// Colors are now adaptive: light variants are the default warm-neutral
/// palette from the 2026-07-18 execution session; dark variants provide
/// readable contrast in dark mode. The board's own square/piece colors
/// are untouched - these tokens are for surrounding chrome only.
/// See `ChessantoApp` for the app-wide appearance policy.
enum DesignColors {
    static let surface0 = Color.dynamic(light: NSColor(hex: "#FAF9F6"), dark: NSColor(hex: "#1C1A17"))
    static let surface1 = Color.dynamic(light: NSColor(hex: "#F3F0E9"), dark: NSColor(hex: "#252220"))
    static let surface2 = Color.dynamic(light: NSColor(hex: "#FFFFFF"), dark: NSColor(hex: "#2D2A26"))
    static let hairline = Color.dynamic(light: NSColor(hex: "#DDD8CE"), dark: NSColor(hex: "#3D3A35"))
    static let textPrimary = Color.dynamic(light: NSColor(hex: "#26231F"), dark: NSColor(hex: "#E8E2D6"))
    static let textSecondary = Color.dynamic(light: NSColor(hex: "#625E57"), dark: NSColor(hex: "#A09A8E"))
    static let accent = Color.dynamic(light: NSColor(hex: "#A6791F"), dark: NSColor(hex: "#C9A04A"))
    static let accentText = Color.dynamic(light: NSColor(hex: "#765313"), dark: NSColor(hex: "#D4B566"))
    static let selection = Color.dynamic(light: NSColor(hex: "#F2E8D2"), dark: NSColor(hex: "#3A3220"))
    static let error = Color.dynamic(light: NSColor(hex: "#B42318"), dark: NSColor(hex: "#E55A4F"))
}

extension NSColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

extension Color {
    /// Creates an adaptive color that switches between light and dark
    /// variants based on the effective appearance.
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        let nsColor = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                dark
            } else {
                light
            }
        }
        return Color(nsColor)
    }
}
