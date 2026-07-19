import AnalysisKit
import SwiftUI

struct CoachStageContent: Equatable {
    let eyebrow: String
    let headline: String
    let message: String
    let source: String
}

enum CoachStageText {
    static func headline(for classification: MoveClassification) -> String {
        switch classification {
        case .blunder:
            return "This move changed the game."
        case .mistake:
            return "This is where the position turned."
        case .inaccuracy:
            return "A quieter move kept the edge."
        case .missedWin:
            return "The win was here."
        case .brilliant:
            return "That idea deserves a closer look."
        case .best, .excellent, .good:
            return "This move kept the position on course."
        }
    }

    static func condensed(_ text: String, maxCharacters: Int = 280) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard normalized.count > maxCharacters else { return normalized }

        let sentences = normalized
            .split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let firstTwo = sentences.prefix(2).joined(separator: ". ")
        if !firstTwo.isEmpty, firstTwo.count <= maxCharacters {
            return firstTwo + "."
        }
        let clipped = normalized.prefix(max(1, maxCharacters - 1))
        let wordSafe = clipped.split(separator: " ").dropLast().joined(separator: " ")
        return (wordSafe.isEmpty ? String(clipped) : wordSafe) + "…"
    }
}

struct CoachStageView: View {
    @Environment(\.moveNotation) private var moveNotation
    let content: CoachStageContent
    var primaryActionTitle: String?
    var onPrimaryAction: (() -> Void)?
    var secondaryActionTitle: String?
    var onSecondaryAction: (() -> Void)?
    var onAskCoach: (() -> Void)?

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Image("coach-comic")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 148, alignment: .bottom)
                .accessibilityHidden(true)

            speechBubble
                .padding(.leading, -8)
                .padding(.bottom, DesignSpacing.xs)
        }
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var speechBubble: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Text(moveNotation.text(content.eyebrow).uppercased())
                .font(.dsSecondary.weight(.bold))
                .foregroundStyle(DesignColors.accentText)
                .tracking(0.8)
                .accessibilityLabel(
                    moveNotation.accessibilityText(content.eyebrow)
                )
            Text(moveNotation.text(content.headline))
                .font(.dsTitle)
                .foregroundStyle(DesignColors.textPrimary)
                .accessibilityLabel(
                    moveNotation.accessibilityText(content.headline)
                )
            Text(moveNotation.text(content.message))
                .font(.dsBody)
                .foregroundStyle(DesignColors.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(
                    moveNotation.accessibilityText(content.message)
                )

            HStack(spacing: DesignSpacing.sm) {
                if let primaryActionTitle, let onPrimaryAction {
                    Button(primaryActionTitle, action: onPrimaryAction)
                        .buttonStyle(.dsPrimary)
                }
                if let secondaryActionTitle, let onSecondaryAction {
                    Button(secondaryActionTitle, action: onSecondaryAction)
                        .buttonStyle(.bordered)
                }
                if let onAskCoach {
                    Button("Ask Coach", action: onAskCoach)
                        .buttonStyle(.borderless)
                }
                Spacer()
                Text(content.source)
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
            }
        }
        .padding(DesignSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignColors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(DesignColors.hairline, lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            SpeechTail()
                .fill(DesignColors.surface2)
                .frame(width: 18, height: 24)
                .offset(x: -13, y: 28)
        }
        .shadow(color: DesignColors.textPrimary.opacity(0.08), radius: 10, y: 4)
    }
}

struct CoachPlaybackStageView: View {
    @ObservedObject var playback: LinePreviewController
    let fallback: CoachStageContent

    private var content: CoachStageContent {
        let moveNumber = max(0, playback.stepIndex)
        let moveTotal = max(0, playback.stepCount - 1)
        guard let san = playback.current.san else {
            return CoachStageContent(
                eyebrow: playback.label,
                headline: fallback.headline,
                message: "Watch the board. I’ll demonstrate the verified line move by move.",
                source: fallback.source
            )
        }
        return CoachStageContent(
            eyebrow: "\(playback.label) \(moveNumber)/\(moveTotal)",
            headline: san,
            message: fallback.message,
            source: fallback.source
        )
    }

    var body: some View {
        CoachStageView(content: content)
    }
}

private struct SpeechTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
