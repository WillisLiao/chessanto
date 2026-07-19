import SwiftUI
import EngineKit
import ChessCore

/// MultiPV lines panel: eval + first few SAN moves of each engine line for
/// the currently displayed position. Clicking a line adopts it as a new
/// variation branch (`onAdopt` receives the line's raw UCI moves).
struct LinesPanelView: View {
    @Environment(\.moveNotation) private var moveNotation
    let lines: [AnalysisEngine.EngineInfo]
    let fen: String
    var onAdopt: ([String]) -> Void = { _ in }

    /// Reserves space for a fixed 3 rows regardless of how many lines are
    /// actually live right now - the engine clears and repopulates `lines`
    /// on every position change (debounced ~200ms per M2), and without a
    /// stable height here the surrounding column reflows on every move,
    /// visibly resizing the board (it sizes itself from whatever space is
    /// left via `GeometryReader` + `.aspectRatio(fit)`).
    private static let rowHeight: CGFloat = 16
    private static let rowSpacing: CGFloat = 4
    private static let reservedHeight = rowHeight * 3 + rowSpacing * 2

    var body: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            if lines.isEmpty {
                Text("No live lines yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: Self.rowHeight, alignment: .top)
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
                    .frame(height: Self.rowHeight, alignment: .top)
                    .accessibilityLabel(
                        "\(evalLabel(line)), \(spokenSANLine(line))"
                    )
                }
            }
        }
        .frame(height: Self.reservedHeight, alignment: .top)
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
        return sans.isEmpty ? "-" : moveNotation.line(sans)
    }

    private func spokenSANLine(_ line: AnalysisEngine.EngineInfo) -> String {
        let sans = ChessGame.sanLine(
            fromUCI: Array(line.principalVariation.prefix(6)),
            startingFEN: fen
        )
        return sans.isEmpty
            ? "No moves"
            : sans.map { moveNotation.move($0).spoken }.joined(separator: ", ")
    }
}
