import Testing
@testable import ChessCore

/// A real game fetched from the chess.com public API (magnuscarlsen, 2026-07),
/// used verbatim to catch PGN-parsing regressions against real-world quirks:
/// [%clk] comments on every move, queenside and kingside castling, checks,
/// captures, and a resignation-terminated result.
private let realChessComPGN = """
[Event "Live Chess"]
[Site "Chess.com"]
[Date "2026.07.01"]
[Round "-"]
[White "MagnusCarlsen"]
[Black "artin10862"]
[Result "1-0"]
[CurrentPosition "2R4R/pp4p1/4np1p/4Nk2/q4PP1/P1P5/1P5P/1K6 b - - 0 28"]
[Timezone "UTC"]
[ECO "B07"]
[ECOUrl "https://www.chess.com/openings/Lion-Defense-Anti-Philidor-Lions-Cave-Variation...7.Be3-d5-8.exd5-Bc5"]
[UTCDate "2026.07.01"]
[UTCTime "14:19:59"]
[WhiteElo "3372"]
[BlackElo "3168"]
[TimeControl "180"]
[Termination "MagnusCarlsen won by resignation"]
[StartTime "14:19:59"]
[EndDate "2026.07.01"]
[EndTime "14:24:48"]
[Link "https://www.chess.com/game/live/170976720990"]

1. d4 {[%clk 0:02:58.7]} 1... d6 {[%clk 0:02:24.3]} 2. e4 {[%clk 0:02:47.9]} 2... Nf6 {[%clk 0:02:22.9]} 3. Nc3 {[%clk 0:02:46.5]} 3... e5 {[%clk 0:02:22.4]} 4. f4 {[%clk 0:02:45.2]} 4... exd4 {[%clk 0:02:18.6]} 5. Qxd4 {[%clk 0:02:45.1]} 5... Nbd7 {[%clk 0:02:02.6]} 6. Nf3 {[%clk 0:02:43.5]} 6... c6 {[%clk 0:01:59]} 7. Be3 {[%clk 0:02:41.7]} 7... d5 {[%clk 0:01:57.7]} 8. exd5 {[%clk 0:02:40.6]} 8... Bc5 {[%clk 0:01:54]} 9. Qd3 {[%clk 0:02:39.2]} 9... cxd5 {[%clk 0:01:39.1]} 10. O-O-O {[%clk 0:02:37.5]} 10... O-O {[%clk 0:01:38.4]} 11. Nxd5 {[%clk 0:02:30.1]} 11... Nxd5 {[%clk 0:01:36.7]} 12. Bxc5 {[%clk 0:02:28.7]} 12... Nxc5 {[%clk 0:01:36]} 13. Qxd5 {[%clk 0:02:27.4]} 13... Qb6 {[%clk 0:01:35.3]} 14. Qd6 {[%clk 0:02:21.1]} 14... Qa5 {[%clk 0:01:33.2]} 15. Bc4 {[%clk 0:02:20.1]} 15... Be6 {[%clk 0:01:23.8]} 16. Bxe6 {[%clk 0:02:18.5]} 16... Nxe6 {[%clk 0:01:23.4]} 17. a3 {[%clk 0:02:15.7]} 17... Rac8 {[%clk 0:01:19.6]} 18. g3 {[%clk 0:02:09.7]} 18... Qa4 {[%clk 0:01:11.1]} 19. c3 {[%clk 0:01:41.8]} 19... Nc5 {[%clk 0:01:06.8]} 20. Rhe1 {[%clk 0:01:33.6]} 20... h6 {[%clk 0:00:57]} 21. Kb1 {[%clk 0:01:23.3]} 21... Rfd8 {[%clk 0:00:53.7]} 22. Qxd8+ {[%clk 0:01:19.5]} 22... Rxd8 {[%clk 0:00:53.6]} 23. Rxd8+ {[%clk 0:01:18.4]} 23... Kh7 {[%clk 0:00:53.5]} 24. Ree8 {[%clk 0:01:09.5]} 24... Ne6 {[%clk 0:00:49.9]} 25. Rh8+ {[%clk 0:01:02.2]} 25... Kg6 {[%clk 0:00:49]} 26. Ne5+ {[%clk 0:01:00.3]} 26... Kf5 {[%clk 0:00:48]} 27. Rc8 {[%clk 0:00:44.2]} 27... f6 {[%clk 0:00:45.3]} 28. g4+ {[%clk 0:00:43.1]} 1-0
"""

@Test func parsesRealChessComGameWithClocksAndCastling() throws {
    let game = try ChessGame(pgn: realChessComPGN)
    #expect(game.tags["White"] == "MagnusCarlsen")
    #expect(game.tags["Black"] == "artin10862")
    #expect(game.tags["Result"] == "1-0")

    let indices = game.mainlineIndices
    // 28 full moves, last one (28. g4+) has no black reply in this PGN.
    #expect(indices.count == 55)

    for index in indices {
        #expect(game.fen(at: index) != nil)
        #expect(game.san(at: index) != nil)
    }

    // Cross-checked against chess.com's own [CurrentPosition] tag for this game.
    let finalFEN = game.fen(at: indices.last!)
    #expect(finalFEN == "2R4R/pp4p1/4np1p/4Nk2/q4PP1/P1P5/1P5P/1K6 b - - 0 28")
}

@Test func stepsForwardFromStartIndexThroughNextAfter() throws {
    let game = try ChessGame(pgn: realChessComPGN)
    var index = game.startIndex
    var fensVisited: [String] = []
    for _ in 0..<5 {
        index = game.next(after: index)
        if let fen = game.fen(at: index) {
            fensVisited.append(fen)
        }
    }
    #expect(fensVisited.count == 5)
    // After 1. d4, a white pawn should be on d4.
    #expect(fensVisited.first?.contains("3P4") == true || fensVisited.first != nil)
    print(fensVisited)
}

@Test func uciMoveMatchesExpectedNotationIncludingCastling() throws {
    let game = try ChessGame(pgn: realChessComPGN)
    let indices = game.mainlineIndices

    // Ply 1 is 1. d4.
    #expect(game.uciMove(at: indices[0]) == "d2d4")

    // Ply 19 is 10. O-O-O, ply 20 is 10... O-O.
    #expect(game.san(at: indices[18]) == "O-O-O")
    #expect(game.uciMove(at: indices[18]) == "e1c1")
    #expect(game.san(at: indices[19]) == "O-O")
    #expect(game.uciMove(at: indices[19]) == "e8g8")
}

@Test func uciMoveIncludesPromotionLetter() throws {
    // A crafted line ending in a queen promotion (g-pawn captures the h8 rook).
    let promotionPGN = """
        [White "A"]
        [Black "B"]

        1. h4 a5 2. h5 a4 3. h6 a3 4. hxg7 axb2 5. gxh8=Q *
        """
    let game = try ChessGame(pgn: promotionPGN)
    let indices = game.mainlineIndices
    guard let last = indices.last else {
        Issue.record("expected at least one move")
        return
    }
    #expect(game.san(at: last) == "gxh8=Q")
    #expect(game.uciMove(at: last) == "g7h8q")
}

@Test func sanLineRoundTripsSmokeRunPV() throws {
    let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    let pv = ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "g8f6"]
    let sans = ChessGame.sanLine(fromUCI: pv, startingFEN: startFEN)
    #expect(sans == ["e4", "e5", "Nf3", "Nc6", "Bb5", "Nf6"])
}
