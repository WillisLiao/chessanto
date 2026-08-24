import Testing
@testable import ChessCore

@Test func parsesDisambiguatedCaptureByRank() throws {
    let pgn = """
    [SetUp "1"]
    [FEN "7k/8/8/8/8/8/8/R3n2R w - - 0 1"]

    1. Raxe1 *
    """
    let game = try ChessGame(pgn: pgn)
    let indices = game.mainlineIndices
    #expect(indices.count == 1)
    #expect(game.san(at: indices[0]) == "Raxe1")
    #expect(game.uciMove(at: indices[0]) == "a1e1")
}

@Test func parsesDisambiguatedCaptureByRankOnSameFile() throws {
    let pgnSameFile = """
    [SetUp "1"]
    [FEN "R6k/8/8/8/8/b7/8/R6K w - - 0 1"]

    1. R1xa3 *
    """
    let game = try ChessGame(pgn: pgnSameFile)
    let indices = game.mainlineIndices
    #expect(indices.count == 1)
    #expect(game.san(at: indices[0]) == "R1xa3")
    #expect(game.uciMove(at: indices[0]) == "a1a3")
}

@Test func parsesDisambiguatedCaptureBySquare() throws {
    // 3 queens on a1, h1, a8: to capture on h8
    let pgn = """
    [SetUp "1"]
    [FEN "Q6r/8/8/8/8/8/8/Q6Q w - - 0 1"]

    1. Qa1xh8 *
    """
    let game = try ChessGame(pgn: pgn)
    let indices = game.mainlineIndices
    #expect(indices.count == 1)
    #expect(game.san(at: indices[0]) == "Qa1xh8")
    #expect(game.uciMove(at: indices[0]) == "a1h8")
}

@Test func parsesKnightDisambiguatedCaptures() throws {
    let pgn = """
    [SetUp "1"]
    [FEN "7k/8/8/3p4/8/2N1N3/8/7K w - - 0 1"]

    1. Ncxd5 *
    """
    let game = try ChessGame(pgn: pgn)
    let indices = game.mainlineIndices
    #expect(indices.count == 1)
    #expect(game.san(at: indices[0]) == "Ncxd5")
    #expect(game.uciMove(at: indices[0]) == "c3d5")
}

@Test func parsesCommentsAndNAGs() throws {
    let pgn = """
    [Event "Test"]
    [Site "Chessanto"]
    [Date "2026.08.24"]
    [White "W"]
    [Black "B"]
    [Result "1-0"]

    1. e4 { [%clk 0:05:00] Great move } 1... e5 $1 2. Nf3! Nc6? 3. Bb5!? a6 1-0
    """
    let game = try ChessGame(pgn: pgn)
    let indices = game.mainlineIndices
    #expect(indices.count == 6)
    #expect(game.tags["Event"] == "Test")
}

@Test func parsesVariationsAndNestedVariations() throws {
    let pgn = """
    1. e4 e5 (1... c5 2. Nf3 (2. Nc3 Nc6)) 2. Nf3 Nc6 *
    """
    let game = try ChessGame(pgn: pgn)
    #expect(game.mainlineIndices.count == 4)
    #expect(game.allIndices.count > 4)
}

@Test func rejectsIllegalMoveInPGN() {
    let pgn = """
    1. e5 *
    """
    #expect(throws: (any Error).self) {
        try ChessGame(pgn: pgn)
    }
}

@Test func rejectsImpossiblePieceMoveInPGN() {
    let pgn = """
    1. Ra5 *
    """
    #expect(throws: (any Error).self) {
        try ChessGame(pgn: pgn)
    }
}
