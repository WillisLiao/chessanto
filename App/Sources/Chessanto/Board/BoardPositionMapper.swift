import Foundation

/// Converts a FEN board field into the app's generic `BoardPosition` for
/// rendering, without pulling ChessKit's piece types into the view layer.
enum BoardPositionMapper {
    static func position(fromFEN fen: String) -> BoardPosition? {
        let boardField = fen.split(separator: " ").first.map(String.init) ?? fen
        let ranks = boardField.split(separator: "/")
        guard ranks.count == 8 else { return nil }

        var pieces: [BoardSquare: DisplayPiece] = [:]
        for (rowFromTop, rankString) in ranks.enumerated() {
            let rank = 7 - rowFromTop
            var file = 0
            for character in rankString {
                if let emptyCount = character.wholeNumberValue {
                    file += emptyCount
                } else if let piece = displayPiece(for: character) {
                    pieces[BoardSquare(file: file, rank: rank)] = piece
                    file += 1
                }
            }
        }
        return BoardPosition(pieces: pieces)
    }

    private static func displayPiece(for character: Character) -> DisplayPiece? {
        let color: PieceColor = character.isUppercase ? .white : .black
        let kind: PieceKind
        switch Character(character.lowercased()) {
        case "p": kind = .pawn
        case "n": kind = .knight
        case "b": kind = .bishop
        case "r": kind = .rook
        case "q": kind = .queen
        case "k": kind = .king
        default: return nil
        }
        return DisplayPiece(color: color, kind: kind)
    }
}
