import SwiftUI
import AnalysisKit

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

    /// A 2-3 letter code for tight inline spaces (the move-list table's
    /// half-width columns), where the full word would wrap (fact 3).
    var shortAbbreviation: String {
        switch self {
        case .best: return "Bst"
        case .brilliant: return "Brl"
        case .excellent: return "Exc"
        case .good: return "Gd"
        case .inaccuracy: return "Inac"
        case .mistake: return "Mist"
        case .blunder: return "Bldr"
        case .missedWin: return "MissW"
        }
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
