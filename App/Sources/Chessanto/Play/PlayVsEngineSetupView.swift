import SwiftUI
import ChessCore
import EngineKit

/// Setup view for starting a new game against the engine.
/// Allows the user to select their side (White, Random, Black) and engine difficulty.
struct PlayVsEngineSetupView: View {
    @Binding var selectedSide: PlayerSideSelection
    @Binding var selectedStrength: EngineStrength
    let onStartGame: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                headerSection

                sideSelectionSection

                strengthSelectionSection

                HStack {
                    Spacer()
                    Button("Start Game", action: onStartGame)
                        .buttonStyle(.dsPrimary)
                        .accessibilityIdentifier("start-game-button")
                }
                .padding(.top, DesignSpacing.sm)
            }
            .padding(DesignSpacing.xl)
            .frame(maxWidth: 580, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(DesignColors.surface0)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Text("Play vs Engine")
                .font(.dsTitle)
                .foregroundStyle(DesignColors.textPrimary)

            Rectangle()
                .fill(DesignColors.accent)
                .frame(width: 36, height: 2)

            Text("Play a live game against Stockfish at your chosen difficulty level. Finished games automatically save and open for analysis and coaching.")
                .font(.dsBody)
                .foregroundStyle(DesignColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sideSelectionSection: some View {
        Card {
            SectionHeader(title: "Choose your side")

            HStack(spacing: DesignSpacing.md) {
                sideOptionCard(
                    side: .white,
                    title: "White",
                    subtitle: "Play first",
                    systemImage: "circle.fill",
                    imageColor: DesignColors.textPrimary
                )

                sideOptionCard(
                    side: .random,
                    title: "Random",
                    subtitle: "50 / 50 chance",
                    systemImage: "dice",
                    imageColor: DesignColors.accent
                )

                sideOptionCard(
                    side: .black,
                    title: "Black",
                    subtitle: "Engine plays first",
                    systemImage: "circle",
                    imageColor: DesignColors.textPrimary
                )
            }
        }
    }

    private func sideOptionCard(
        side: PlayerSideSelection,
        title: String,
        subtitle: String,
        systemImage: String,
        imageColor: Color
    ) -> some View {
        let isSelected = selectedSide == side
        return Button {
            selectedSide = side
        } label: {
            VStack(spacing: DesignSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 24))
                    .foregroundStyle(imageColor)
                    .frame(height: 32)

                Text(title)
                    .font(.dsBody.weight(.semibold))
                    .foregroundStyle(DesignColors.textPrimary)

                Text(subtitle)
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
            }
            .padding(DesignSpacing.md)
            .frame(maxWidth: .infinity)
            .background(isSelected ? DesignColors.selection : DesignColors.surface1)
            .overlay(
                RoundedRectangle(cornerRadius: DesignShape.controlRadius)
                    .strokeBorder(isSelected ? DesignColors.accent : DesignColors.hairline, lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignShape.controlRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("side-option-\(side.rawValue)")
        .accessibilityLabel("\(title) side. \(subtitle). \(isSelected ? "Selected" : "")")
    }

    private var strengthSelectionSection: some View {
        Card {
            SectionHeader(title: "Engine strength")

            VStack(spacing: DesignSpacing.xs) {
                ForEach(EngineStrength.allCases) { strength in
                    strengthRow(strength)
                }
            }
        }
    }

    private func strengthRow(_ strength: EngineStrength) -> some View {
        let isSelected = selectedStrength.id == strength.id
        return Button {
            selectedStrength = strength
        } label: {
            HStack(spacing: DesignSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DesignSpacing.xs) {
                        Text(strength.name)
                            .font(.dsBody.weight(.semibold))
                            .foregroundStyle(DesignColors.textPrimary)

                        if let elo = strength.estimatedElo {
                            Text("~\(elo) Elo")
                                .font(.dsSecondary.weight(.medium))
                                .foregroundStyle(DesignColors.accentText)
                        }
                    }

                    Text(strengthDescription(for: strength))
                        .font(.dsSecondary)
                        .foregroundStyle(DesignColors.textSecondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DesignColors.accent)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(DesignColors.hairline)
                }
            }
            .padding(.horizontal, DesignSpacing.md)
            .padding(.vertical, DesignSpacing.sm)
            .background(isSelected ? DesignColors.selection : DesignColors.surface1)
            .overlay(
                RoundedRectangle(cornerRadius: DesignShape.controlRadius)
                    .strokeBorder(isSelected ? DesignColors.accent : DesignColors.hairline, lineWidth: isSelected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignShape.controlRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("strength-option-\(strength.id)")
        .accessibilityLabel("\(strength.name), estimated \(strength.estimatedElo ?? 0) Elo. \(isSelected ? "Selected" : "")")
    }

    private func strengthDescription(for strength: EngineStrength) -> String {
        switch strength.id {
        case EngineStrength.beginner.id:
            return "Skill level 0, depth 3 - ideal for beginners learning the fundamentals."
        case EngineStrength.casual.id:
            return "Skill level 4, depth 5 - relaxed play with occasional inaccuracies."
        case EngineStrength.intermediate.id:
            return "Skill level 9, depth 8 - solid tactical play around club level."
        case EngineStrength.advanced.id:
            return "Skill level 14, depth 12 - strong competitive play."
        case EngineStrength.master.id:
            return "Skill level 20, depth 18 - maximum strength engine play."
        default:
            return "Skill level \(strength.skillLevel), depth \(strength.depth)."
        }
    }
}
