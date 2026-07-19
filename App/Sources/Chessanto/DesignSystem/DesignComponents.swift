import SwiftUI

/// A ruled register section.
/// The name remains for source compatibility while screens move away from
/// floating cards toward one continuous analysis surface.
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            content
        }
        .padding(.top, DesignSpacing.md)
        .padding(.bottom, DesignSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DesignColors.hairline)
                .frame(height: 1)
        }
    }
}

/// A sentence-case label used at the top of a ruled register section.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title).dsSectionHeaderStyle()
    }
}

/// A compact inline status mark.
struct Chip: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color = DesignColors.accent) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.dsSecondary.weight(.medium))
            .foregroundStyle(color)
            .padding(.leading, DesignSpacing.xs)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(color)
                    .frame(width: 2)
            }
    }
}

/// The single brass-accent primary action used on a workspace.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsBody.weight(.semibold))
            .padding(.horizontal, DesignSpacing.md)
            .padding(.vertical, DesignSpacing.sm)
            .background(
                DesignColors.accentText.opacity(
                    isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.34
                )
            )
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: DesignShape.controlRadius))
            .opacity(isEnabled ? 1 : 0.72)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var dsPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
