import SwiftUI
import AnalysisKit

enum MoveClassificationCompactMark: Equatable {
    case systemImage(String)
    case text(String)
}

extension MoveClassification {
    /// The move-quality spectrum stays a separate, reserved semantic scale
    /// (never used for chrome) per the redesign plan's decision B.
    var color: Color {
        switch self {
        case .best, .excellent: return Color(NSColor(hex: "#6F9E4C"))
        case .good: return Color(NSColor(hex: "#8C8C8C"))
        case .inaccuracy: return Color(NSColor(hex: "#E0A93B"))
        case .mistake: return Color(NSColor(hex: "#E0803B"))
        case .blunder: return Color(NSColor(hex: "#D14B4B"))
        case .missedWin: return Color(NSColor(hex: "#9B6FD1"))
        case .brilliant: return Color(NSColor(hex: "#26C1B6"))
        }
    }

    var abbreviation: String {
        switch self {
        case .best: return "Best"
        case .brilliant: return "Brilliant"
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .inaccuracy: return "Inaccuracy"
        case .mistake: return "Mistake"
        case .blunder: return "Blunder"
        case .missedWin: return "Missed Win"
        }
    }

    /// Compact, familiar chess-review notation that remains recognizable
    /// without asking the player to decode an app-specific abbreviation.
    var compactMark: MoveClassificationCompactMark {
        switch self {
        case .best: return .systemImage("star.fill")
        case .brilliant: return .text("!!")
        case .excellent: return .systemImage("hand.thumbsup.fill")
        case .good: return .systemImage("checkmark")
        case .inaccuracy: return .text("?!")
        case .mistake: return .text("?")
        case .blunder: return .text("??")
        case .missedWin: return .systemImage("xmark")
        }
    }
}

struct ClassificationChip: View {
    let classification: MoveClassification
    var count: Int?

    var body: some View {
        HStack(spacing: 4) {
            compactMark
                .frame(minWidth: 12)

            if let count {
                Text(count, format: .number)
                    .monospacedDigit()
            }
        }
        .font(.dsSecondary.weight(.semibold))
        .padding(.horizontal, DesignSpacing.sm)
        .padding(.vertical, 3)
        .background(classification.color.opacity(0.16))
        .foregroundStyle(classification.color)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var compactMark: some View {
        switch classification.compactMark {
        case .systemImage(let name):
            Image(systemName: name)
                .imageScale(.small)
        case .text(let mark):
            Text(mark)
                .monospaced()
        }
    }

    private var accessibilityLabel: String {
        guard let count else { return classification.abbreviation }
        return "\(classification.abbreviation), \(count) \(count == 1 ? "move" : "moves")"
    }
}

struct ClassificationBadge: View {
    let classification: MoveClassification

    var body: some View {
        Text(classification.abbreviation)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(classification.color.opacity(0.25))
            .foregroundStyle(classification.color)
            .clipShape(Capsule())
            .accessibilityLabel(classification.abbreviation)
    }
}
