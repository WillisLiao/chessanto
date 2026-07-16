import Testing
@testable import ChessCore

private let samplePGN = """
[Event "Test Game"]
[Site "chess.com"]
[Date "2026.01.01"]
[White "Alice"]
[Black "Bob"]
[Result "1-0"]

1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 1-0
"""

@Test func parsesTagsFromPGN() throws {
    let game = try ChessGame(pgn: samplePGN)
    #expect(game.tags["White"] == "Alice")
    #expect(game.tags["Black"] == "Bob")
    #expect(game.tags["Result"] == "1-0")
}

@Test func walksMainlineAndReadsFEN() throws {
    let game = try ChessGame(pgn: samplePGN)
    let indices = game.mainlineIndices
    #expect(indices.count == 10)

    let afterE4 = game.fen(at: indices[0])
    #expect(afterE4 == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1")
}

@Test func reExportsPGNRoundTrip() throws {
    let game = try ChessGame(pgn: samplePGN)
    let reparsed = try ChessGame(pgn: game.pgnString)
    #expect(reparsed.mainlineIndices.count == game.mainlineIndices.count)
}

@Test func startingPositionHasTwentyLegalMoves() {
    let game = ChessGame()
    let start = game.startIndex
    let squaresWithPieces = ["a2", "b2", "c2", "d2", "e2", "f2", "g2", "h2", "b1", "g1"]
    let total = squaresWithPieces.reduce(into: 0) { count, square in
        count += game.legalMoves(from: SquareCoordinate(notation: square), at: start).count
    }
    #expect(total == 20)
}

@Test func afterE4BlackHasTwentyLegalReplies() {
    var game = ChessGame()
    let afterE4 = game.playMove(san: "e4", at: game.startIndex)
    #expect(afterE4 != nil)

    let squaresWithPieces = ["a7", "b7", "c7", "d7", "e7", "f7", "g7", "h7", "b8", "g8"]
    let total = squaresWithPieces.reduce(into: 0) { count, square in
        count += game.legalMoves(from: SquareCoordinate(notation: square), at: afterE4!).count
    }
    #expect(total == 20)
}

@Test func illegalMoveIsRejected() {
    var game = ChessGame()
    let result = game.playMove(from: SquareCoordinate(notation: "e2"), to: SquareCoordinate(notation: "e5"), at: game.startIndex)
    #expect(result == nil)
}
