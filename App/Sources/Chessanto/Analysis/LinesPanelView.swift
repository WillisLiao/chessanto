import SwiftUI
import EngineKit
import ChessCore

/// MultiPV lines panel: eval + first few SAN moves of each engine line for
/// the currently displayed position. Clicking a line adopts it as a new
/// variation branch (`onAdopt` receives the line's raw UCI moves).
struct LinesPanelView: View {
    let lines: [AnalysisEngine.EngineInfo]
    let fen: String
    var onAdopt: ([String]) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if lines.isEmpty {
                Text("No live lines yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(lines.prefix(3).enumerated()), id: \.offset) { _, line in
                    Button {
                        onAdopt(Array(line.principalVariation.prefix(6)))
                    } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Text(evalLabel(line))
                                .font(.caption.monospacedDigit().bold())
                                .frame(width: 44, alignment: .leading)
                            Text(sanLine(line))
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func evalLabel(_ line: AnalysisEngine.EngineInfo) -> String {
        let mate = EngineScoreNormalizer.whitePerspectiveMate(line.mateIn, fen: fen)
        let cp = EngineScoreNormalizer.whitePerspectiveScore(line.scoreCentipawns, fen: fen)
        if let mate {
            return mate > 0 ? "M\(mate)" : "-M\(abs(mate))"
        }
        if let cp {
            return String(format: "%+.1f", Double(cp) / 100)
        }
        return "--"
    }

    private func sanLine(_ line: AnalysisEngine.EngineInfo) -> String {
        let sans = ChessGame.sanLine(fromUCI: Array(line.principalVariation.prefix(6)), startingFEN: fen)
        return sans.isEmpty ? "-" : sans.joined(separator: " ")
    }
}
