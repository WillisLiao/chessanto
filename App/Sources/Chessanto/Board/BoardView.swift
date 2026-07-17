import SwiftUI

struct BoardView: View {
    let position: BoardPosition
    var lastMove: (from: BoardSquare, to: BoardSquare)?
    var flipped: Bool = false
    var theme: BoardTheme = .classic
    var showCoordinates: Bool = true
    var selectedSquare: BoardSquare?
    var legalDestinations: Set<BoardSquare> = []
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
