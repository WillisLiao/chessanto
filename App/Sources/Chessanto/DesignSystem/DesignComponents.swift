import SwiftUI

/// A `surface-2` card with a hairline border - the redesign's replacement for
/// raw `Form`/`List` rows wherever content should read as a grouped unit
/// (Report sections, Settings sections, dashboard blocks).
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            content
        }
        .padding(DesignSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignColors.surface2)
        .overlay(
            RoundedRectangle(cornerRadius: DesignShape.cardRadius)
                .strokeBorder(DesignColors.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignShape.cardRadius))
        .shadow(color: .black.opacity(0.035), radius: 8, y: 2)
    }
}

/// A compact, code-native brand illustration used where a generic SF Symbol
/// would make the app feel anonymous. The tilted board, brass medallion, and
/// crown communicate "chess insight" without adding a raster asset that
/// cannot adapt cleanly to different display scales.
struct ChessantoEmblem: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24)
                .fill(
                    LinearGradient(
                        colors: [DesignColors.surface2, DesignColors.surface1],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24)
                        .strokeBorder(DesignColors.hairline, lineWidth: 1)
                )
                .shadow(color: DesignColors.accent.opacity(0.16), radius: size * 0.14, y: size * 0.05)

            boardMotif
                .frame(width: size * 0.62, height: size * 0.62)
                .rotationEffect(.degrees(-6))

            Circle()
                .fill(
                    LinearGradient(
                        colors: [DesignColors.accent, DesignColors.accent.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.38, height: size * 0.38)
                .overlay(
                    Image(systemName: "crown.fill")
                        .font(.system(size: size * 0.19, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .shadow(color: .black.opacity(0.14), radius: size * 0.06, y: size * 0.025)

            Image(systemName: "sparkles")
                .font(.system(size: size * 0.16, weight: .medium))
                .foregroundStyle(DesignColors.accent)
                .offset(x: size * 0.34, y: -size * 0.34)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chessanto chess insight emblem")
    }

    private var boardMotif: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<4, id: \.self) { row in
                GridRow {
                    ForEach(0..<4, id: \.self) { column in
                        Rectangle()
                            .fill(
                                (row + column).isMultiple(of: 2)
                                    ? DesignColors.surface2
                                    : DesignColors.accent.opacity(0.48)
                            )
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: size * 0.08))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.08)
                .strokeBorder(DesignColors.accent.opacity(0.48), lineWidth: 1)
        )
    }
}

/// Small, tracked, secondary-colored section label - see `dsSectionHeaderStyle()`.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title).dsSectionHeaderStyle()
    }
}

/// A compact, colored capsule for short status text (classification, source labels, etc).
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
            .padding(.horizontal, DesignSpacing.sm)
            .padding(.vertical, 2)
            .background(color.opacity(0.16))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

/// The brass-accent primary button style.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsBody.weight(.semibold))
            .padding(.horizontal, DesignSpacing.md)
            .padding(.vertical, DesignSpacing.sm)
            .background(
                DesignColors.accent.opacity(
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
