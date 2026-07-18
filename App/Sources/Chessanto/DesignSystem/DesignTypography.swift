import SwiftUI

/// Type scale from the redesign plan: SF Pro Rounded for titles/section headers
/// (the friendly-modern app voice), system text for body/controls, monospaced
/// digits for notation/evals/ratings/clocks/coordinates.
extension Font {
    static let dsTitle = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let dsSectionHeader = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let dsBody = Font.system(size: 13, weight: .regular, design: .default)
    static let dsSecondary = Font.system(size: 11, weight: .regular, design: .default)
    static let dsNotation = Font.system(size: 12, weight: .regular, design: .monospaced)
}

extension View {
    /// Small, tracked, secondary-colored section header label - not `Form`'s heavy default.
    func dsSectionHeaderStyle() -> some View {
        self
            .font(.dsSectionHeader)
            .foregroundStyle(DesignColors.textSecondary)
            .tracking(0.5)
            .textCase(.uppercase)
    }
}
