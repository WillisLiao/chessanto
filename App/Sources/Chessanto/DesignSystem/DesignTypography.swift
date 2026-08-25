import SwiftUI

/// A restrained macOS type scale for a dense analysis workspace.
/// System text carries the interface and monospaced figures carry chess data.
///
/// Every font is built on a system text style rather than a fixed point
/// size, so text tracks the user's System Settings text-size slider
/// (including the largest accessibility sizes) instead of staying frozen.
/// The default-size rendering stays within a point or two of the original
/// fixed sizes: body 13, secondary 11, section header 11 semibold,
/// title 17 semibold, notation 13 monospaced.
extension Font {
    static let dsTitle = Font.system(.title2, design: .default).weight(.semibold)
    static let dsSectionHeader = Font.system(.subheadline, design: .default).weight(.semibold)
    static let dsBody = Font.system(.body, design: .default)
    static let dsSecondary = Font.system(.subheadline, design: .default)
    static let dsNotation = Font.system(.body, design: .monospaced)
}

extension View {
    /// Sentence-case section labels keep the hierarchy quiet and native.
    func dsSectionHeaderStyle() -> some View {
        self
            .font(.dsSectionHeader)
            .foregroundStyle(DesignColors.textPrimary)
    }
}
