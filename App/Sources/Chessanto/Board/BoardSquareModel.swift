import Foundation

enum PieceColor: String, Sendable {
    case white
    case black
}

enum PieceKind: String, Sendable {
    case pawn, knight, bishop, rook, queen, king
}

struct DisplayPiece: Identifiable, Sendable {
    let color: PieceColor
    let kind: PieceKind
    var id: String { "\(color.rawValue)-\(kind.rawValue)" }
}

/// A file/rank pair, 0-indexed from a1 (file 0, rank 0) to h8 (file 7, rank 7).
/// Independent of ChessKit's `Square` so the board view can be previewed and
/// tested without pulling in the engine/rules dependency.
struct BoardSquare: Hashable, Sendable {
    let file: Int
    let rank: Int

    var algebraic: String {
        let fileLetter = Character(UnicodeScalar(UInt8(97 + file)))
        return "\(fileLetter)\(rank + 1)"
    }
}

/// A snapshot of a position, ready for rendering. Built from ChessCore's
/// position type by the replay view model.
struct BoardPosition: Sendable {
    var pieces: [BoardSquare: DisplayPiece]

    static let empty = BoardPosition(pieces: [:])
}
