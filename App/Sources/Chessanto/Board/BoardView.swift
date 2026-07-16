import SwiftUI

struct BoardView: View {
    let position: BoardPosition
    var lastMove: (from: BoardSquare, to: BoardSquare)?
    var flipped: Bool = false

    private let lightColor = Color(red: 0.93, green: 0.87, blue: 0.77)
    private let darkColor = Color(red: 0.55, green: 0.39, blue: 0.29)
    private let highlightColor = Color.yellow.opacity(0.35)

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let squareSize = size / 8

            ZStack(alignment: .topLeading) {
                ForEach(0..<8, id: \.self) { row in
                    ForEach(0..<8, id: \.self) { col in
                        let square = square(atRow: row, col: col)
                        ZStack {
                            baseColor(for: square)
                            if isLastMoveSquare(square) {
                                highlightColor
                            }
                        }
                        .frame(width: squareSize, height: squareSize)
                        .position(
                            x: CGFloat(col) * squareSize + squareSize / 2,
                            y: CGFloat(row) * squareSize + squareSize / 2
                        )
                    }
                }

                ForEach(0..<8, id: \.self) { row in
                    ForEach(0..<8, id: \.self) { col in
                        let square = square(atRow: row, col: col)
                        if let piece = position.pieces[square] {
                            PieceView(piece: piece, squareSize: squareSize)
                                .frame(width: squareSize, height: squareSize)
                                .position(
                                    x: CGFloat(col) * squareSize + squareSize / 2,
                                    y: CGFloat(row) * squareSize + squareSize / 2
                                )
                                .accessibilityIdentifier("piece-\(square.algebraic)")
                        }
                    }
                }
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func square(atRow row: Int, col: Int) -> BoardSquare {
        let file = flipped ? 7 - col : col
        let rank = flipped ? row : 7 - row
        return BoardSquare(file: file, rank: rank)
    }

    private func baseColor(for square: BoardSquare) -> Color {
        let isLight = (square.file + square.rank) % 2 == 0
        return isLight ? lightColor : darkColor
    }

    private func isLastMoveSquare(_ square: BoardSquare) -> Bool {
        guard let lastMove else { return false }
        return square == lastMove.from || square == lastMove.to
    }
}

private struct PieceView: View {
    let piece: DisplayPiece
    let squareSize: CGFloat

    var body: some View {
        Text(piece.glyph)
            .font(.system(size: squareSize * 0.75))
            .lineLimit(1)
            .foregroundStyle(piece.color == .white ? .white : .black)
            .shadow(color: .black.opacity(piece.color == .white ? 0.4 : 0), radius: 0.5)
            .accessibilityLabel("\(piece.color.rawValue) \(piece.kind.rawValue)")
    }
}

private extension DisplayPiece {
    /// Unicode chess glyphs, always the "white" glyph variants so fill color
    /// (not glyph choice) distinguishes side to move. Placeholder art for M1;
    /// replaced with proper piece artwork in the M7 polish pass.
    var glyph: String {
        switch kind {
        case .pawn: return "♙"
        case .knight: return "♘"
        case .bishop: return "♗"
        case .rook: return "♖"
        case .queen: return "♕"
        case .king: return "♔"
        }
    }
}

#Preview {
    BoardView(position: .previewStandard)
        .padding()
        .frame(width: 480, height: 480)
}

extension BoardPosition {
    static let previewStandard: BoardPosition = {
        var pieces: [BoardSquare: DisplayPiece] = [:]
        let backRank: [PieceKind] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for file in 0..<8 {
            pieces[BoardSquare(file: file, rank: 0)] = DisplayPiece(color: .white, kind: backRank[file])
            pieces[BoardSquare(file: file, rank: 1)] = DisplayPiece(color: .white, kind: .pawn)
            pieces[BoardSquare(file: file, rank: 6)] = DisplayPiece(color: .black, kind: .pawn)
            pieces[BoardSquare(file: file, rank: 7)] = DisplayPiece(color: .black, kind: backRank[file])
        }
        return BoardPosition(pieces: pieces)
    }()
}
