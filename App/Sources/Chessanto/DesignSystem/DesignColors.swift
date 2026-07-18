import SwiftUI
import AppKit

/// Chrome color tokens, per the UI/UX redesign plan (`handoffs/NEXT-SESSION-UIUX-EXECUTE.md`).
/// The app forces a light, white-forward appearance always (user decision,
/// 2026-07-18 execution session) - it does not follow the system's dark mode
/// setting. The board's own square/piece colors are untouched - these tokens
/// are for surrounding chrome only. See `ChessantoApp` for the app-wide
/// `.aqua` appearance pin that keeps native chrome (sidebar, titlebar,
/// controls) in lockstep with these always-light values.
enum DesignColors {
    static let surface0 = Color(NSColor(hex: "#FAF9F6"))
    static let surface1 = Color(NSColor(hex: "#F2F0EB"))
    static let surface2 = Color(NSColor(hex: "#FFFFFF"))
    static let hairline = Color(NSColor(hex: "#E6E1D8"))
    static let textPrimary = Color(NSColor(hex: "#26231F"))
    static let textSecondary = textPrimary.opacity(0.6)
    static let accent = Color(NSColor(hex: "#A6791F"))
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
