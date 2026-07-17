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

@Test func variationBranchesOffMainlineAndNestsFurther() throws {
    var game = try ChessGame(pgn: samplePGN)
    let mainline = game.mainlineIndices
    // Branch a variation after 2. Nf3 (mainline[2]): 2...d5 instead of 2...Nc6.
    let branchPoint = mainline[2]
    let variationMove = game.playMove(san: "d5", at: branchPoint)
    #expect(variationMove != nil)
    #expect(!game.isMainline(variationMove!))
    #expect(game.parent(of: variationMove!) == branchPoint)
    #expect(game.mainlineAncestor(of: variationMove!) == branchPoint)

    // Nest a sub-variation inside it.
    let subVariationMove = game.playMove(san: "Nc3", at: variationMove!)
    #expect(subVariationMove != nil)
    #expect(game.parent(of: subVariationMove!) == variationMove!)
    #expect(game.mainlineAncestor(of: subVariationMove!) == branchPoint)

    // The original mainline is untouched.
    #expect(game.mainlineIndices.count == mainline.count)
}

@Test func pawnMoveToBackRankAutoPromotesToQueen() {
    var game = ChessGame(startingFEN: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
    let start = game.startIndex
    let result = game.playMove(from: SquareCoordinate(notation: "a7"), to: SquareCoordinate(notation: "a8"), at: start)
    #expect(result != nil)
    #expect(game.san(at: result!) == "a8=Q+")
}
