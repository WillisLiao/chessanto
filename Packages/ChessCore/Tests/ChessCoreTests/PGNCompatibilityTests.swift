import Testing
@testable import ChessCore

@Test func parsesDisambiguatedCaptureByFile() throws {
    let pgn = """
    [SetUp "1"]
    [FEN "7k/p7/8/8/8/8/8/R3n2R w - - 0 1"]

    1. Rhxe1 a5 2. Ra4 *
    """
    let game = try ChessGame(pgn: pgn)
    let indices = game.mainlineIndices
    #expect(indices.count == 3)
    #expect(game.san(at: indices[0]) == "Rhxe1")
    #expect(game.uciMove(at: indices[0]) == "h1e1")
    #expect(game.san(at: indices[2]) == "Ra4")
    #expect(game.uciMove(at: indices[2]) == "a1a4")
}

@Test func parsesDisambiguatedCaptureByRankOnSameFile() throws {
    let pgnSameFile = """
    [SetUp "1"]
    [FEN "R6k/7p/8/8/8/b7/8/R6K w - - 0 1"]

    1. R8xa3 h6 2. Ra4 *
    """
    let game = try ChessGame(pgn: pgnSameFile)
    let indices = game.mainlineIndices
    #expect(indices.count == 3)
    #expect(game.san(at: indices[0]) == "R8xa3")
    #expect(game.uciMove(at: indices[0]) == "a8a3")
    #expect(game.san(at: indices[2]) == "Ra4")
    #expect(game.uciMove(at: indices[2]) == "a3a4")
}

@Test func parsesDisambiguatedCaptureBySquare() throws {
    let pgn = """
    [SetUp "1"]
    [FEN "Q6r/3k4/8/8/8/8/8/Q6Q w - - 0 1"]

    1. Qa1xh8 Ke7 2. Qa7+ *
    """
    let game = try ChessGame(pgn: pgn)
    let indices = game.mainlineIndices
    #expect(indices.count == 3)
    #expect(game.san(at: indices[0]) == "Qa1xh8")
    #expect(game.uciMove(at: indices[0]) == "a1h8")
    #expect(game.san(at: indices[2]) == "Qa7+")
    #expect(game.uciMove(at: indices[2]) == "a8a7")
}

@Test func parsesKnightDisambiguatedCaptures() throws {
    let pgn = """
    [SetUp "1"]
    [FEN "7k/p7/8/3p4/8/2N1N3/8/7K w - - 0 1"]

    1. Nexd5 a6 2. Ne4 *
    """
    let game = try ChessGame(pgn: pgn)
    let indices = game.mainlineIndices
    #expect(indices.count == 3)
    #expect(game.san(at: indices[0]) == "Nexd5")
    #expect(game.uciMove(at: indices[0]) == "e3d5")
    #expect(game.san(at: indices[2]) == "Ne4")
    #expect(game.uciMove(at: indices[2]) == "c3e4")
}

@Test func parsesOrdinaryUpstreamGame() throws {
    let pgn = """
    [Event "Ordinary Game"]
    [Site "Local"]
    [Date "2026.08.24"]
    [White "Player1"]
    [Black "Player2"]
    [Result "1/2-1/2"]

    1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 1/2-1/2
    """
    let game = try ChessGame(pgn: pgn)
    #expect(game.tags["Event"] == "Ordinary Game")
    #expect(game.mainlineIndices.count == 10)
    #expect(game.san(at: game.mainlineIndices[8]) == "O-O")
}

@Test func parsesCompactLegalPGNFormsAndAttachedMoveNumbers() throws {
    let compactPGN = "1.e4 e5 2.Nf3 Nc6 3.d4 exd4 4.Nxd4 *"
    let game = try ChessGame(pgn: compactPGN)
    #expect(game.mainlineIndices.count == 7)
    #expect(game.san(at: game.mainlineIndices[0]) == "e4")
    #expect(game.san(at: game.mainlineIndices[1]) == "e5")
    #expect(game.san(at: game.mainlineIndices[6]) == "Nxd4")

    let attachedBlackMoves = "1. d4 1...d5 2. c4 2...dxc4 *"
    let game2 = try ChessGame(pgn: attachedBlackMoves)
    #expect(game2.mainlineIndices.count == 4)
    #expect(game2.san(at: game2.mainlineIndices[0]) == "d4")
    #expect(game2.san(at: game2.mainlineIndices[1]) == "d5")
    #expect(game2.san(at: game2.mainlineIndices[2]) == "c4")
    #expect(game2.san(at: game2.mainlineIndices[3]) == "dxc4")
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

@Test func parsesCastlingPromotionsAndEnPassantInFallback() throws {
    // Custom position with pawn promotion and castling
    let pgnPromo = """
    [SetUp "1"]
    [FEN "8/4P3/8/8/8/8/8/4K2k w - - 0 1"]

    1. e8=Q+ Kh2 2. Qe2+ Kh1 *
    """
    let gamePromo = try ChessGame(pgn: pgnPromo)
    #expect(gamePromo.mainlineIndices.count == 4)
    #expect(gamePromo.san(at: gamePromo.mainlineIndices[0]) == "e8=Q+")

    // En passant in fallback
    let pgnEP = """
    [SetUp "1"]
    [FEN "7k/8/8/3Pp3/8/8/8/7K w - e6 0 1"]

    1. dxe6 Kg7 *
    """
    let gameEP = try ChessGame(pgn: pgnEP)
    #expect(gameEP.mainlineIndices.count == 2)
    #expect(gameEP.san(at: gameEP.mainlineIndices[0]) == "dxe6")
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

// MARK: - Carlsen archive QA regressions (2026-08-25)

/// Upstream silently drops the disambiguator on piece captures and moves the
/// wrong piece ("Rhxf1" moved the d1 rook); the game must not go through
/// upstream at all.
@Test func routesDisambiguatedMovesAwayFromUpstream() {
    #expect(PGNCompatibility.requiresFallback(for: "1. Rhxf1 *"))
    #expect(PGNCompatibility.requiresFallback(for: "9...Nfxd5 10. Nbd7 *"))
    #expect(PGNCompatibility.requiresFallback(for: "22. R1xe1+ *"))
    #expect(PGNCompatibility.requiresFallback(for: "(2. Qh4e1) *"))
    #expect(!PGNCompatibility.requiresFallback(for: "1. e4 e5 2. Nf3 Nc6 3. Bb5 *"))
    #expect(!PGNCompatibility.requiresFallback(for: "3. exd5 *"))
    #expect(!PGNCompatibility.requiresFallback(for: "12. O-O-O *"))
}

@Test func resolvesDisambiguatedCaptureToCorrectSource() throws {
    // White rooks d1 and h1, black bishop on f1: "Rhxf1" must move the H-FILE rook.
    let pgn = """
    [SetUp "1"]
    [FEN "3k4/8/8/8/8/8/8/2KR1b1R w - - 0 1"]

    1. Rhxf1 *
    """
    let game = try ChessGame(pgn: pgn)
    #expect(game.uciMove(at: game.mainlineIndices[0]) == "h1f1")
}

@Test func resolvesRankDisambiguatedCaptureThatUpstreamRejects() throws {
    let pgn = """
    [SetUp "1"]
    [FEN "4k3/8/8/8/8/8/8/R3n1KR w - - 0 1"]

    1. R1xe1 *
    """
    let game = try ChessGame(pgn: pgn)
    #expect(game.uciMove(at: game.mainlineIndices[0]) == "a1e1")
}

@Test func resolvesNonCaptureFileDisambiguation() throws {
    // Knights c3 and f3 both reach d5: "Ncd5" must move the C-FILE knight.
    let pgn = """
    [SetUp "1"]
    [FEN "7k/8/8/3p4/8/2N2N2/8/7K w - - 0 1"]

    1. Ncd5 *
    """
    let game = try ChessGame(pgn: pgn)
    #expect(game.uciMove(at: game.mainlineIndices[0]) == "c3d5")
}

@Test func rejectsDisambiguatedMoveNamingNoLegalSource() {
    // No white knight on the f-file, so "Nfxd5" is illegal and must throw
    // rather than fall back to an ambiguous guess.
    let pgn = """
    [SetUp "1"]
    [FEN "7k/8/8/3p4/8/2N2N2/8/7K w - - 0 1"]

    1. Nfxd5 *
    """
    #expect(throws: (any Error).self) {
        try ChessGame(pgn: pgn)
    }
}

/// Replayed double pushes leave no en passant state upstream (Game.make
/// bypasses Board's en-passant bookkeeping), so a genuine ep capture later in
/// the game failed to parse and killed the whole import.
@Test func parsesEnPassantAfterReplayedDoublePush() throws {
    let pgn = """
    [Event "EP after replayed double push"]
    [Result "*"]

    1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Be7 5. O-O b5 6. Bb3 d6
    7. c3 Na5 8. h3 c5 9. d4 exd4 10. cxd4 Bd7 11. e5 f5 12. exf6 *
    """
    let game = try ChessGame(pgn: pgn)
    let indices = game.mainlineIndices
    #expect(indices.count == 23)
    #expect(game.uciMove(at: indices[22]) == "e5f6")
    // The captured pawn must actually disappear from the resulting FEN.
    let fen = game.fen(at: indices[22]) ?? ""
    #expect(fen.contains("1P2"))  // white pawn landed on f6
    #expect(!fen.split(separator: "/").dropFirst(4).first!.contains("pP"))  // black f5 pawn removed from rank 5
}

@Test func parsesCastlingWithCheckSuffix() throws {
    let pgn = """
    [SetUp "1"]
    [FEN "r3k3/8/8/8/8/8/8/R3K3 w Qq - 0 1"]

    1. O-O-O+ *
    """
    let game = try ChessGame(pgn: pgn)
    #expect(game.mainlineIndices.count == 1)
}
