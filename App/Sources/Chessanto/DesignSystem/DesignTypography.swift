import SwiftUI

/// A restrained macOS type scale for a dense analysis workspace.
/// System text carries the interface and monospaced figures carry chess data.
extension Font {
    static let dsTitle = Font.system(size: 20, weight: .semibold, design: .default)
    static let dsSectionHeader = Font.system(size: 12, weight: .semibold, design: .default)
    static let dsBody = Font.system(size: 13, weight: .regular, design: .default)
    static let dsSecondary = Font.system(size: 11, weight: .regular, design: .default)
    static let dsNotation = Font.system(size: 12, weight: .regular, design: .monospaced)
}

extension View {
    /// Sentence-case section labels keep the hierarchy quiet and native.
    func dsSectionHeaderStyle() -> some View {
        self
            .font(.dsSectionHeader)
            .foregroundStyle(DesignColors.textPrimary)
    }
}
