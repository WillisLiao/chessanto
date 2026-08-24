import Testing
@testable import ChessCore

// MARK: - Invariants and Generator Tests

@Test func all960PositionsSatisfyInvariants() {
    for index in 0...959 {
        let rank = Chess960.backRank(index: index)
        #expect(rank.count == 8, "Position \(index) must have length 8")
        #expect(Chess960.isValidBackRank(rank), "Position \(index) (\(rank)) must be a valid back rank")

        let chars = Array(rank)
        var counts: [Character: Int] = [:]
        for c in chars { counts[c, default: 0] += 1 }

        #expect(counts["B"] == 2, "Position \(index) must have exactly 2 bishops")
        #expect(counts["R"] == 2, "Position \(index) must have exactly 2 rooks")
        #expect(counts["N"] == 2, "Position \(index) must have exactly 2 knights")
        #expect(counts["Q"] == 1, "Position \(index) must have exactly 1 queen")
        #expect(counts["K"] == 1, "Position \(index) must have exactly 1 king")

        // Invariant 1: Two bishops on opposite colors
        let bishopIndices = chars.indices.filter { chars[$0] == "B" }
        #expect(bishopIndices.count == 2)
        #expect((bishopIndices[0] % 2) != (bishopIndices[1] % 2), "Position \(index) bishops must be on opposite-colored squares")

        // Invariant 2: King strictly between the two rooks
        let rookIndices = chars.indices.filter { chars[$0] == "R" }
        let kingIndex = chars.firstIndex(of: "K")!
        #expect(rookIndices[0] < kingIndex && kingIndex < rookIndices[1], "Position \(index) king must be between rooks")
    }
}

@Test func all960PositionsRoundTripIndexBijectively() {
    var seenRanks = Set<String>()
    for index in 0...959 {
        let rank = Chess960.backRank(index: index)
        #expect(!seenRanks.contains(rank), "Position \(index) (\(rank)) must be unique")
        seenRanks.insert(rank)

        let recoveredIndex = Chess960.index(of: rank)
        #expect(recoveredIndex == index, "Recovered index for position \(index) (\(rank)) was \(String(describing: recoveredIndex))")
    }
    #expect(seenRanks.count == 960)
}

@Test func knownPositionsMatchCanonicalRankStrings() {
    // Standard chess position is index 518
    #expect(Chess960.backRank(index: 518) == "RNBQKBNR")
    #expect(Chess960.index(of: "RNBQKBNR") == 518)

    // Position 0 is BBQNNRKR
    #expect(Chess960.backRank(index: 0) == "BBQNNRKR")
    #expect(Chess960.index(of: "BBQNNRKR") == 0)

    // Position 959 is RKRNNQBB
    #expect(Chess960.backRank(index: 959) == "RKRNNQBB")
    #expect(Chess960.index(of: "RKRNNQBB") == 959)
}

@Test func seedableRandomGenerationIsDeterministic() {
    let seed1: UInt64 = 42
    let seed2: UInt64 = 42
    let seed3: UInt64 = 9999

    let rank1 = Chess960.backRank(seed: seed1)
    let rank2 = Chess960.backRank(seed: seed2)
    let rank3 = Chess960.backRank(seed: seed3)

    #expect(rank1 == rank2)
    #expect(rank1 == Chess960.backRank(index: Int(seed1 % 960)))
    #expect(rank3 == Chess960.backRank(index: Int(seed3 % 960)))
}

@Test func startingFENGeratesValidFENWithShredderAndTraditionalCastling() {
    // Standard position (index 518)
    let shredder518 = Chess960.startingFEN(index: 518, useShredderFEN: true)
    #expect(shredder518 == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w AHah - 0 1")
    #expect(Chess960.isChess960(startingFEN: shredder518))
    #expect(ChessGame.isValidFEN(shredder518))

    let traditional518 = Chess960.startingFEN(index: 518, useShredderFEN: false)
    #expect(traditional518 == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    #expect(Chess960.isChess960(startingFEN: traditional518))
    #expect(ChessGame.isValidFEN(traditional518))

    // Position 0 (BBQNNRKR) with rooks on f (5) and h (7)
    let shredder0 = Chess960.startingFEN(index: 0, useShredderFEN: true)
    #expect(shredder0 == "bbqnnrkr/pppppppp/8/8/8/8/PPPPPPPP/BBQNNRKR w FHfh - 0 1")
    #expect(Chess960.isChess960(startingFEN: shredder0))
    #expect(ChessGame.isValidFEN(shredder0))

    // Seed-based FEN
    let seededFEN = Chess960.startingFEN(seed: 518, useShredderFEN: true)
    #expect(seededFEN == shredder518)
}

@Test func invalidBackRankStringsAreRejected() {
    #expect(Chess960.isValidBackRank("RNBQKBNN") == false)
    #expect(Chess960.isValidBackRank("KRRBNNBQ") == false)
    #expect(Chess960.isValidBackRank("BBQNNRKK") == false)
    #expect(Chess960.isValidBackRank("RNBQKBN") == false)
    #expect(Chess960.isValidBackRank("ABCDEFGH") == false)
    #expect(Chess960.isValidBackRank("") == false)

    #expect(Chess960.index(of: "RNBQKBNN") == nil)
    #expect(Chess960.index(of: "KRRBNNBQ") == nil)
    #expect(Chess960.index(of: "") == nil)
}

// MARK: - Castling Legality and Execution Tests

@Test func chess960CastlingDestinationSquaresAreAlwaysConstant() {
    // In every 960 arrangement:
    // Kingside castling always puts King on g1 (or g8) and Rook on f1 (or f8).
    // Queenside castling always puts King on c1 (or c8) and Rook on d1 (or d8).

    // RNNBBKQR (King on f1, Queenside Rook on a1, Kingside Rook on h1)
    let fen105 = "rnnbbkqr/pppppppp/8/8/8/8/PPPPPPPP/RNNBBKQR w AHah - 0 1"
    let game = ChessGame(startingFEN: fen105)
    #expect(game.fen(at: game.startIndex) == fen105)

    // In initial position, king is blocked by pieces at b1, c1, d1, e1 (for O-O-O) and g1 (for O-O)
    #expect(!Chess960.canCastle(color: .white, side: .kingside, in: fen105))
    #expect(!Chess960.canCastle(color: .white, side: .queenside, in: fen105))

    // Clear g1 for kingside castle: King on f1, Rook on h1, g1 empty
    let fenClearKingside = "rnnbbkqr/pppppppp/8/8/8/8/PPPPPPPP/RNNBBK1R w AHah - 0 1"
    #expect(Chess960.canCastle(color: .white, side: .kingside, in: fenClearKingside))
    let castledK = Chess960.performCastle(color: .white, side: .kingside, in: fenClearKingside)
    #expect(castledK != nil)
    #expect(castledK?.san.hasPrefix("O-O") == true)
    // Board rank 1 should have King on g1 (index 6) and Rook on f1 (index 5)
    guard let r1K = Chess960.backRanks(from: castledK!.resultingFEN.split(separator: " ")[0].description)?.rank1 else {
        Issue.record("Failed to extract rank1 from castled FEN")
        return
    }
    #expect(r1K[6] == "K", "King must be on g1 (index 6)")
    #expect(r1K[5] == "R", "Rook must be on f1 (index 5)")
}

@Test func chess960QueensideCastlingFromF1PositionsKingOnC1AndRookOnD1() {
    // Position: King on f1, Rook on a1, rank 1 empty between them (b1, c1, d1, e1 all empty)
    let fen = "7k/8/8/8/8/8/8/R4K2 w A - 0 1"
    #expect(Chess960.canCastle(color: .white, side: .queenside, in: fen))

    guard let result = Chess960.performCastle(color: .white, side: .queenside, in: fen) else {
        Issue.record("Castling should succeed")
        return
    }

    #expect(result.san == "O-O-O")
    #expect(result.uci == "f1a1")

    guard let (r1, _) = Chess960.backRanks(from: result.resultingFEN.split(separator: " ")[0].description) else {
        Issue.record("Failed to read back ranks")
        return
    }
    #expect(r1[2] == "K", "King must end on c1")
    #expect(r1[3] == "R", "Rook must end on d1")
    #expect(r1[0] == ".", "a1 must be empty")
    #expect(r1[5] == ".", "f1 must be empty")
}

@Test func chess960CastlingBlockedByTransitAttackOrCheck() {
    // White King on f1, Rook on a1. Black Rook on d8 attacks d1 (a transit square for King from f1 to c1).
    let attackedTransitFEN = "3r3k/8/8/8/8/8/8/R4K2 w A - 0 1"
    #expect(!Chess960.canCastle(color: .white, side: .queenside, in: attackedTransitFEN), "King cannot castle through attacked transit square d1")

    // White King on f1 is in check from Black Rook on f8
    let inCheckFEN = "5r1k/8/8/8/8/8/8/R4K2 w A - 0 1"
    #expect(!Chess960.canCastle(color: .white, side: .queenside, in: inCheckFEN), "King cannot castle out of check")

    // White King destination c1 is attacked by Black Bishop on f4
    let attackedDestFEN = "7k/8/8/8/5b2/8/8/R4K2 w A - 0 1"
    #expect(!Chess960.canCastle(color: .white, side: .queenside, in: attackedDestFEN), "King cannot castle into attacked destination square c1")
}

@Test func chess960CastlingRightsInvalidatedOnMove() {
    // Position with White King on f1 and Rooks on a1 and h1: FEN castling "HA"
    let fen = "7k/8/8/8/8/8/8/R4K1R w HA - 0 1"

    // Moving rook from h1 to h2 invalidates H right, retains A right
    let afterH1H2 = Chess960.updateCastlingRights(in: fen, movingFrom: "h1", movingTo: "h2", movedPieceKind: .rook, movedPieceColor: .white)
    #expect(afterH1H2.split(separator: " ")[2] == "A")

    // Moving King from f1 to f2 invalidates all White castling rights
    let afterKingMove = Chess960.updateCastlingRights(in: fen, movingFrom: "f1", movingTo: "f2", movedPieceKind: .king, movedPieceColor: .white)
    #expect(afterKingMove.split(separator: " ")[2] == "-")
}

@Test func shredderFENRightsAreInCanonicalAscendingOrder() {
    // After White castles kingside, remaining rights (Black's a+h rooks)
    // must be written in canonical ascending Shredder order "ah", not "ha".
    let cleared = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w AHah - 0 1"
    #expect(ChessGame.isValidFEN(cleared))
    let castled = Chess960.performCastle(color: .white, side: .kingside, in: cleared)
    #expect(castled != nil)
    #expect(castled?.resultingFEN.split(separator: " ")[2] == "ah")
}

@Test func plainOneFileKingStepIsNotCastled() {
    // King on f1 with kingside rook on h1: the single-step move f1-g1 must
    // stay a plain king move; castling is king-onto-rook or multi-file jump.
    let fen = "7k/8/8/8/8/8/8/R4K1R w HA - 0 1"
    var game = ChessGame(startingFEN: fen)
    let played = game.playMove(from: SquareCoordinate(notation: "f1"), to: SquareCoordinate(notation: "g1"), at: game.startIndex)
    #expect(played != nil)
    let after = game.fen(at: played!)
    #expect(after?.hasPrefix("7k/8/8/8/8/8/8/R5KR b") == true, "Rook must still be on h1, got \(String(describing: after))")

    // Dropping the king onto its own rook (h1) castles.
    var game2 = ChessGame(startingFEN: fen)
    let castleMove = game2.playMove(from: SquareCoordinate(notation: "f1"), to: SquareCoordinate(notation: "h1"), at: game2.startIndex)
    #expect(castleMove != nil)
    let afterCastle = game2.fen(at: castleMove!)
    #expect(afterCastle?.contains("R4RK1") == true, "King g1 rook f1 expected, got \(String(describing: afterCastle))")
}

@Test func replayLineHandlesGenericChess960CastlingUCI() {
    // King on c1, rooks a1/h1: kingside castle UCI is c1g1 (multi-file king
    // jump), landing king g1 / rook f1.
    let explicit = "rbk4r/pppppppp/8/8/8/8/PPPPPPPP/RBK4R w AHah - 0 1"
    let replayed = ChessGame.replayLine(fromUCI: ["c1g1"], startingFEN: explicit)
    #expect(replayed.count == 1)
    #expect(replayed.first?.san == "O-O")
    #expect(replayed.first?.resultingFEN.contains("RB3RK1") == true,
            "King must land on g1 and rook on f1, got \(String(describing: replayed.first?.resultingFEN))")

    // A plain ROOK move to the c-file must not be mistaken for castling
    // even though it lands on the queenside castled-king file.
    let rookUCI = ChessGame.replayLine(fromUCI: ["a1c1"], startingFEN: "7k/8/8/8/8/8/8/R3K2R w HA - 0 1")
    #expect(rookUCI.count == 1)
    #expect(rookUCI.first?.movedPieceKind == .rook)
}

@Test func castlingRightsSurviveNormalMovesInReplayAndPlay() {
    // ChessKit's FEN serialization strips Shredder rights, so a normal move
    // must carry them forward or later castling would be impossible.
    let fen = "rbk4r/pppppppp/8/8/8/8/PPPPPPPP/RBK4R w AHah - 0 1"

    let replayed = ChessGame.replayLine(fromUCI: ["a2a3"], startingFEN: fen)
    #expect(replayed.count == 1)
    #expect(replayed.first?.resultingFEN.contains(" AHah ") == true,
            "Rights must survive a normal move in replay, got \(String(describing: replayed.first?.resultingFEN))")

    var game = ChessGame(startingFEN: fen)
    let played = game.playMove(from: SquareCoordinate(notation: "a2"), to: SquareCoordinate(notation: "a3"), at: game.startIndex)
    #expect(played != nil)
    #expect(game.fen(at: played!)?.contains(" AHah ") == true,
            "Rights must survive a normal move in play, got \(String(describing: game.fen(at: played!)))")

    // And castling still works afterwards: multi-file king jump to g-file.
    _ = game.playMove(from: SquareCoordinate(notation: "h7"), to: SquareCoordinate(notation: "h6"), at: played!)
    let blackReplied = game.mainlineIndices[1]
    let castled = game.playMove(from: SquareCoordinate(notation: "c1"), to: SquareCoordinate(notation: "g1"), at: blackReplied)
    #expect(castled != nil)
    let afterCastle = game.fen(at: castled!)
    #expect(afterCastle?.contains("RB3RK1") == true, "King g1 rook f1 expected, got \(String(describing: afterCastle))")
    #expect(afterCastle?.contains(" ah ") == true,
            "Only Black rights remain after White castles, got \(String(describing: afterCastle))")
}

@Test func chess960PGNExportRoundTripsHeadersAndMoves() throws {
    let game = try ChessGame(pgn: lichessFixture960)
    let reparsed = try ChessGame(pgn: game.pgnString)

    #expect(reparsed.tags["Variant"] == "Chess960")
    #expect(reparsed.tags["SetUp"] == "1")
    #expect(reparsed.tags["FEN"] == game.tags["FEN"])
    #expect(reparsed.mainlineIndices.count == game.mainlineIndices.count)

    for (original, roundTripped) in zip(game.mainlineIndices, reparsed.mainlineIndices) {
        #expect(reparsed.san(at: roundTripped) == game.san(at: original))
        #expect(reparsed.fen(at: roundTripped) == game.fen(at: original))
    }
}

@Test func standardFromFENGamesAreNotTaggedChess960() {
    let midgame = ChessGame(startingFEN: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1")
    #expect(midgame.tags["Variant"] == nil)
    #expect(midgame.tags["SetUp"] == nil)
}

@Test func chess960GamePlayMoveAndLegalMoves() {
    // Start game from position RNNBBKQR
    let fen = Chess960.startingFEN(backRank: "RNNBBKQR", useShredderFEN: true)
    var game = ChessGame(startingFEN: fen)
    let start = game.startIndex

    // King on f1 initially has 0 legal moves (blocked by pawns and pieces)
    let kingLegalMoves = game.legalMoves(from: SquareCoordinate(notation: "f1"), at: start)
    #expect(kingLegalMoves.isEmpty)

    // Knights on b1 and c1 can jump
    let nb1Moves = game.legalMoves(from: SquareCoordinate(notation: "b1"), at: start)
    #expect(nb1Moves.contains(SquareCoordinate(notation: "a3")))
    #expect(nb1Moves.contains(SquareCoordinate(notation: "c3")))

    // Play 1. Nc3
    let move1 = game.playMove(from: SquareCoordinate(notation: "b1"), to: SquareCoordinate(notation: "c3"), at: start)
    #expect(move1 != nil)
    #expect(game.san(at: move1!) == "Nc3")
}

// MARK: - Engine Mode Detection

@Test func standardPositionsDoNotRequireChess960EngineMode() {
    #expect(!Chess960.requiresChess960EngineMode(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"))
    #expect(!Chess960.requiresChess960EngineMode(fen: "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"))
    #expect(!Chess960.requiresChess960EngineMode(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
    // Rights that have lapsed entirely leave nothing for the engine to
    // misinterpret, in any position.
    #expect(!Chess960.requiresChess960EngineMode(fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1"))
    // A partial traditional field whose implied squares hold is standard.
    #expect(!Chess960.requiresChess960EngineMode(fen: "r3k2r/8/8/8/8/8/8/4K3 b kq - 0 1"))
}

@Test func chess960PositionsRequireChess960EngineMode() {
    // Shredder-FEN file letters always mean non-standard rights.
    #expect(Chess960.requiresChess960EngineMode(fen: Chess960.startingFEN(index: 0)))
    // X-FEN spelling (traditional letters) with non-standard geometry:
    // the Lichess export shape, king on f1/f8 with outer rooks.
    #expect(Chess960.requiresChess960EngineMode(fen: "rnnbbkqr/pppppppp/8/8/8/8/PPPPPPPP/RNNBBKQR w KQkq - 0 1"))
    // A single traditional right whose rook square doesn't hold.
    #expect(Chess960.requiresChess960EngineMode(fen: "4k3/8/8/8/8/8/8/2R1K3 w K - 0 1"))
    // A traditional right whose rook square doesn't hold (king on e1,
    // rook on b1).
    #expect(Chess960.requiresChess960EngineMode(fen: "4k3/8/8/8/8/8/8/1R2K3 w Q - 0 1"))
}

// MARK: - Real Game PGN Fixture Tests

private let lichessFixture960 = """
[Event "Chess960 Titled Arena September '25"]
[Site "https://lichess.org/Lu5CMX4w"]
[Date "2025.09.06"]
[Round "-"]
[White "yoseph2013"]
[Black "penguingim1"]
[Result "0-1"]
[GameId "Lu5CMX4w"]
[UTCDate "2025.09.06"]
[UTCTime "21:55:56"]
[WhiteElo "2368"]
[BlackElo "2499"]
[Variant "Chess960"]
[TimeControl "180+2"]
[Termination "Time forfeit"]
[FEN "rnnbbkqr/pppppppp/8/8/8/8/PPPPPPPP/RNNBBKQR w KQkq - 0 1"]
[SetUp "1"]

1. Nc3 c6 2. Nb3 e5 3. e4 Bb6 4. g3 Ne7 5. Qg2 f5 6. d3 d6 7. Be2 Nd7 8. Bd2 Nf6 9. O-O-O a5 10. Kb1 a4 11. Nc1 a3 12. b3 d5 13. f4 exf4 14. e5 Ng4 15. Bxg4 fxg4 16. Bxf4 Qe6 17. Rhf1 O-O 18. d4 Bg6 19. Na4 Ba7 20. Qd2 Nf5 21. Ne2 b5 22. Nc5 Qe7 23. b4 Bxc5 24. dxc5 Ra4 25. Ka1 d4 26. Nxd4 Nxd4 27. Qxd4 Bxc2 28. Rd2 Bf5 29. Re1 Qe6 30. Qc3 Qc4 31. Qxc4+ bxc4 32. e6 Rxb4 33. e7 Re8 34. Rd8 Kf7 35. Rxe8 Kxe8 36. Be5 Rb5 37. Bxg7 Rxc5 38. Bc3 Rb5 39. Bd4 Bd3 40. Bc3 Rb7 41. Bd4 Rxe7 42. Rxe7+ Kxe7 43. Bc5+ Ke6 44. Bxa3 c3 45. Bb4 c2 46. Kb2 Kd5 47. Kc1 Kc4 48. Bd2 Bf5 49. Bf4 Kb5 50. Kb2 Kb4 51. Bc1 Kc4 52. a3 Bd3 53. Bd2 Kd4 54. a4 Ke4 55. a5 Kf3 56. Kc1 Bb5 57. Bf4 Kg2 58. Bd6 Kxh2 59. Bf4 Kg2 60. Bd6 Bd3 61. Bf4 Kf3 62. Kd2 h5 63. Bd6 Ke4 64. Bc7 Ba6 65. Bb8 Bd3 66. Bc7 c5 67. Bb8 c4 68. Kc1 c3 69. Bc7 Ba6 70. Bb8 Kf5 71. Bc7 Kg5 72. Bb8 h4 73. gxh4+ Kxh4 74. Bc7 Bd3 75. Bd6 Kh3 76. a6 Bxa6 77. Kxc2 Kg2 78. Kxc3 Kf3 79. Kd4 Bb7 80. Bc5 Ba6 81. Kc3 Bf1 82. Kd2 Bg2 83. Ke1 Bh3 84. Bg1 Ke4 85. Bh2 Kf3 86. Bg1 g3 87. Bd4 Be6 0-1
"""

@Test func parsesRealLichessChess960GameWithCastling() throws {
    do {
        let game = try ChessGame(pgn: lichessFixture960)
        #expect(game.tags["White"] == "yoseph2013")
        #expect(game.tags["Black"] == "penguingim1")
        #expect(game.tags["Variant"] == "Chess960")
        #expect(game.tags["Result"] == "0-1")

        let indices = game.mainlineIndices
        #expect(indices.count == 174)
        #expect(game.san(at: indices[16]) == "O-O-O")
        #expect(game.san(at: indices[33]) == "O-O")
    } catch {
        print("DEBUG lichessFixture960 caught: \(error)")
        throw error
    }
}

private let lichessFixture960DrNykterstein = """
[Event "Chess960 Titled Arena December '22"]
[Site "https://lichess.org/2vUNiLP8"]
[Date "2022.12.03"]
[Round "-"]
[White "DrNykterstein"]
[Black "Vladimirovich9000"]
[Result "1-0"]
[GameId "2vUNiLP8"]
[Variant "Chess960"]
[FEN "rkbnrnqb/pppppppp/8/8/8/8/PPPPPPPP/RKBNRNQB w KQkq - 0 1"]
[SetUp "1"]

1. a4 g6 2. a5 f5 3. g4 a6 4. g5 Nc6 5. Bxc6 dxc6 6. d3 e5 7. e4 f4 8. f3 Ne6 9. Nd2 Nd4 10. b3 Be6 11. Bb2 Rd8 12. Ra4 c5 13. Nc3 Qe8 14. Ne2 b5 15. axb6 cxb6 16. Nc1 Qc6 17. h4 a5 18. Ra1 b5 19. c3 Nxb3 20. Ndxb3 c4 21. dxc4 bxc4 22. Qc5 Qc7 23. Qb5+ Qb7 24. Qxb7+ Kxb7 25. Nc5+ Kc6 26. Nxe6 Re8 27. Nd4+ exd4 28. cxd4 Reb8 29. Ne2 Rb3 30. Kc2 Rxf3 31. d5+ Kc5 32. Bxh8 Rxh8 33. Rxa5+ Kd6 34. Ra6+ Kc5 35. Rc6+ Kb4 36. Rb1+ Rb3 37. Rb6+ Kc5 38. R6xb3 cxb3+ 39. Rxb3 Ra8 40. Kd3 Ra1 41. Rc3+ Kd6 42. Rc6+ Kd7 43. Nxf4 Ra3+ 44. Kd4 Ra4+ 45. Ke5 Ra1 46. Ne6 Rh1 47. Rc7+ Ke8 48. d6 Rxh4 49. Re7# 1-0
"""

@Test func parsesDrNyktersteinChess960GameWithCheckmate() throws {
    let game = try ChessGame(pgn: lichessFixture960DrNykterstein)
    #expect(game.tags["White"] == "DrNykterstein")
    #expect(game.tags["Black"] == "Vladimirovich9000")
    #expect(game.tags["Variant"] == "Chess960")
    #expect(game.tags["Result"] == "1-0")

    let indices = game.mainlineIndices
    #expect(indices.count == 97)

    // Final move is 49. Re7#
    guard let last = indices.last else {
        Issue.record("Expected moves")
        return
    }
    #expect(game.san(at: last) == "Re7#")
}
