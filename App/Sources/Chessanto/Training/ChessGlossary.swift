import AnalysisKit
import Foundation

/// Plain-language glosses for the chess jargon this codebase actually
/// produces, kept beside the real term rather than replacing it (DD2).
enum ChessGlossary {
    /// Ordered longest-term-first so `"O-O-O"` is matched before `"O-O"`,
    /// since the short-castle token is a substring of the long-castle one.
    private static let termGlosses: [(term: String, gloss: String)] = [
        ("forced mate", "a sequence that wins by checkmate no matter how the opponent replies"),
        ("O-O-O", "castling long, moving the king two squares toward the queenside rook"),
        ("en prise", "left where the opponent can capture it for free"),
        ("hanging", "left where the opponent can capture it for free"),
        ("O-O", "castling short, moving the king two squares toward the kingside rook"),
    ]

    private static let classificationGlosses: [MoveClassification: String] = [
        .best: "the strongest move the engine found",
        .brilliant: "a move that wins material or the game through a sacrifice the engine confirms is sound",
        .excellent: "very close to the engine's top choice",
        .good: "a solid move with only a small cost",
        .inaccuracy: "a small slip that gives back some advantage",
        .mistake: "a clear error that gives up real advantage",
        .blunder: "a serious error that loses significant advantage",
        .missedWin: "a winning continuation was available and was not played",
    ]

    /// Returns the gloss for whichever known term appears in `text`, or
    /// `nil` if `text` contains none of them. Never invents a gloss for an
    /// unrecognized term.
    static func gloss(for text: String) -> String? {
        for entry in termGlosses where text.contains(entry.term) {
            return entry.gloss
        }
        return nil
    }

    static func gloss(for classification: MoveClassification) -> String {
        classificationGlosses[classification] ?? ""
    }
}
