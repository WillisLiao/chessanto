import SwiftUI

struct BoardView: View {
    let position: BoardPosition
    var lastMove: (from: BoardSquare, to: BoardSquare)?
    var flipped: Bool = false
    var theme: BoardTheme = .classic
    var showCoordinates: Bool = true
    var selectedSquare: BoardSquare?
    var legalDestinations: Set<BoardSquare> = []
    var hintSquares: Set<BoardSquare> = []
    /// Suggested-move arrows (engine best line, "Better was..." moves) -
    /// drawn green like most match-analysis tools (chess.com/Lichess),
    /// reusing the app's own move-quality green (`MoveClassification.best`)
    /// rather than an unrelated ad-hoc color.
    var arrows: [(from: BoardSquare, to: BoardSquare)] = []
    var onSquareTapped: ((BoardSquare) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let squareSize = size / 8

            ZStack(alignment: .topLeading) {
                ForEach(0..<8, id: \.self) { row in
                    ForEach(0..<8, id: \.self) { col in
                        let square = square(atRow: row, col: col)
                        Button {
                            onSquareTapped?(square)
                        } label: {
                            ZStack(alignment: .topLeading) {
                                baseColor(for: square)
                                if isLastMoveSquare(square) {
                                    theme.highlight
                                }
                                if square == selectedSquare {
                                    theme.selected
                                } else if legalDestinations.contains(square) {
                                    theme.destination
                                }
                                if hintSquares.contains(square) {
                                    theme.hint
                                    Rectangle()
                                        .strokeBorder(DesignColors.accent, lineWidth: max(squareSize * 0.06, 2))
                                }
                                if showCoordinates {
                                    coordinateOverlay(for: square, row: row, col: col, squareSize: squareSize)
                                }
                            }
                            .frame(width: squareSize, height: squareSize)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .position(
                            x: CGFloat(col) * squareSize + squareSize / 2,
                            y: CGFloat(row) * squareSize + squareSize / 2
                        )
                        .accessibilityIdentifier("square-\(square.algebraic)")
                        .accessibilityLabel(square.algebraic)
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
                                .allowsHitTesting(false)
                        }
                    }
                }

                ForEach(Array(arrows.enumerated()), id: \.offset) { _, arrow in
                    arrowShape(from: arrow.from, to: arrow.to, squareSize: squareSize)
                        .fill(Color(NSColor(hex: "#6F9E4C")).opacity(0.75))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// A center-of-square-to-center-of-square arrow with a triangular head,
    /// the standard chess-analysis-tool move suggestion.
    private func arrowShape(from: BoardSquare, to: BoardSquare, squareSize: CGFloat) -> some Shape {
        let (fromRow, fromCol) = rowCol(for: from)
        let (toRow, toCol) = rowCol(for: to)
        let start = CGPoint(x: CGFloat(fromCol) * squareSize + squareSize / 2, y: CGFloat(fromRow) * squareSize + squareSize / 2)
        let end = CGPoint(x: CGFloat(toCol) * squareSize + squareSize / 2, y: CGFloat(toRow) * squareSize + squareSize / 2)
        return ArrowShape(start: start, end: end, lineWidth: squareSize * 0.16, headLength: squareSize * 0.42, headWidth: squareSize * 0.36)
    }

    private func rowCol(for square: BoardSquare) -> (row: Int, col: Int) {
        let col = flipped ? 7 - square.file : square.file
        let row = flipped ? square.rank : 7 - square.rank
        return (row, col)
    }

    private func square(atRow row: Int, col: Int) -> BoardSquare {
        let file = flipped ? 7 - col : col
        let rank = flipped ? row : 7 - row
        return BoardSquare(file: file, rank: rank)
    }

    private func baseColor(for square: BoardSquare) -> Color {
        let isLight = (square.file + square.rank) % 2 == 0
        return isLight ? theme.lightSquare : theme.darkSquare
    }

    private func isLastMoveSquare(_ square: BoardSquare) -> Bool {
        guard let lastMove else { return false }
        return square == lastMove.from || square == lastMove.to
    }

    /// File letter along the bottom edge, rank number along the left edge -
    /// the standard lichess/chess.com in-square placement, adjusted for
    /// board orientation.
    @ViewBuilder
    private func coordinateOverlay(for square: BoardSquare, row: Int, col: Int, squareSize: CGFloat) -> some View {
        let font = Font.system(size: max(squareSize * 0.16, 8), weight: .semibold)
        let color = baseColor(for: square) == theme.lightSquare ? theme.darkSquare : theme.lightSquare
        VStack {
            HStack {
                Spacer()
                if col == (flipped ? 0 : 7) {
                    Text("\(square.rank + 1)")
                        .font(font)
                        .foregroundStyle(color)
                        .padding(.trailing, 2)
                        .padding(.top, 1)
                }
            }
            Spacer()
            HStack {
                if row == (flipped ? 0 : 7) {
                    Text(String(UnicodeScalar(UInt8(97 + square.file))))
                        .font(font)
                        .foregroundStyle(color)
                        .padding(.leading, 2)
                        .padding(.bottom, 1)
                }
                Spacer()
            }
        }
        .allowsHitTesting(false)
    }
}

/// A straight shaft with a triangular arrowhead from `start` to `end`,
/// shortened at both ends so it doesn't cover the piece glyphs it points
/// between.
private struct ArrowShape: Shape {
    let start: CGPoint
    let end: CGPoint
    let lineWidth: CGFloat
    let headLength: CGFloat
    let headWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 1 else { return Path() }
        let unit = CGPoint(x: dx / length, y: dy / length)
        let perpendicular = CGPoint(x: -unit.y, y: unit.x)

        let inset = length * 0.18
        let trueStart = CGPoint(x: start.x + unit.x * inset, y: start.y + unit.y * inset)
        let trueEnd = CGPoint(x: end.x - unit.x * inset, y: end.y - unit.y * inset)
        let shaftEnd = CGPoint(x: trueEnd.x - unit.x * headLength, y: trueEnd.y - unit.y * headLength)

        var path = Path()
        path.move(to: CGPoint(x: trueStart.x + perpendicular.x * lineWidth / 2, y: trueStart.y + perpendicular.y * lineWidth / 2))
        path.addLine(to: CGPoint(x: shaftEnd.x + perpendicular.x * lineWidth / 2, y: shaftEnd.y + perpendicular.y * lineWidth / 2))
        path.addLine(to: CGPoint(x: shaftEnd.x + perpendicular.x * headWidth / 2, y: shaftEnd.y + perpendicular.y * headWidth / 2))
        path.addLine(to: trueEnd)
        path.addLine(to: CGPoint(x: shaftEnd.x - perpendicular.x * headWidth / 2, y: shaftEnd.y - perpendicular.y * headWidth / 2))
        path.addLine(to: CGPoint(x: shaftEnd.x - perpendicular.x * lineWidth / 2, y: shaftEnd.y - perpendicular.y * lineWidth / 2))
        path.addLine(to: CGPoint(x: trueStart.x - perpendicular.x * lineWidth / 2, y: trueStart.y - perpendicular.y * lineWidth / 2))
        path.closeSubpath()
        return path
    }
}

private struct PieceView: View {
    let piece: DisplayPiece
    let squareSize: CGFloat

    var body: some View {
        Image(piece.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: squareSize * 0.82, height: squareSize * 0.82)
            .accessibilityLabel("\(piece.color.rawValue) \(piece.kind.rawValue)")
    }
}

extension DisplayPiece {
    /// Asset catalog names for the cburnett piece set fetched by
    /// `scripts/fetch-pieces.sh` into `App/Resources/Pieces.xcassets`.
    /// Internal (not private) so `PieceAssetsTests` can assert every asset
    /// resolves to a real image.
    var assetNameForTesting: String { assetName }

    fileprivate var assetName: String {
        let colorLetter = color == .white ? "w" : "b"
        let kindLetter: String
        switch kind {
        case .pawn: kindLetter = "P"
        case .knight: kindLetter = "N"
        case .bishop: kindLetter = "B"
        case .rook: kindLetter = "R"
        case .queen: kindLetter = "Q"
        case .king: kindLetter = "K"
        }
        return "cburnett-\(colorLetter)\(kindLetter)"
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
