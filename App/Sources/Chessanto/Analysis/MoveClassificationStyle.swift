import SwiftUI
import AnalysisKit

enum MoveClassificationCompactMark: Equatable {
    case systemImage(String)
    case text(String)
}

extension MoveClassification {
    /// The move-quality spectrum stays a separate, reserved semantic scale
    /// (never used for chrome) per the redesign plan's decision B.
    ///
    /// Each hue has a light and a dark variant, both measured at 4.5:1 or
    /// better against the worst surface of their mode (light #F3F0E9,
    /// dark #2D2A26), because these colors render as 11pt text in chips
    /// and move-list marks. The original single fixed hex values failed
    /// AA in light mode for every classification except book/forced.
    var color: Color {
        switch self {
        case .best, .excellent:
            return Color.dynamic(light: NSColor(hex: "#527630"), dark: NSColor(hex: "#7BA84F"))
        case .good:
            return Color.dynamic(light: NSColor(hex: "#6B6B6B"), dark: NSColor(hex: "#9C9C9C"))
        case .inaccuracy:
            return Color.dynamic(light: NSColor(hex: "#8A6116"), dark: NSColor(hex: "#E0A93B"))
        case .mistake:
            return Color.dynamic(light: NSColor(hex: "#A05216"), dark: NSColor(hex: "#E0803B"))
        case .blunder:
            return Color.dynamic(light: NSColor(hex: "#C03A3A"), dark: NSColor(hex: "#E86B6B"))
        case .missedWin:
            return Color.dynamic(light: NSColor(hex: "#7C4FB8"), dark: NSColor(hex: "#B08AE0"))
        case .brilliant:
            return Color.dynamic(light: NSColor(hex: "#08756D"), dark: NSColor(hex: "#26C1B6"))
        // Book and forced moves are context, not quality, so they stay off
        // the move-quality spectrum entirely and read as secondary text.
        case .book, .forced: return DesignColors.textSecondary
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
        case .book: return "Book"
        case .forced: return "Forced"
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
        case .book: return .systemImage("book.closed")
        case .forced: return .systemImage("arrow.turn.down.right")
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
            } else {
                Text(classification.abbreviation)
            }
        }
        .font(.dsSecondary.weight(.semibold))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(classification.color)
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
            .foregroundStyle(classification.color)
            .accessibilityLabel(classification.abbreviation)
    }
}
