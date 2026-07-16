import SwiftUI
import AnalysisKit

extension MoveClassification {
    var color: Color {
        switch self {
        case .best, .excellent: return .green
        case .good: return .gray
        case .inaccuracy: return .yellow
        case .mistake: return .orange
        case .blunder: return .red
        case .missedWin: return .purple
        case .brilliant: return .cyan
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
