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
    #expect(fensVisited.first?.contains("3P4") == true)
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

@Test func minimalDisambiguatedCaptureRegression() throws {
    let pgn = """
    [SetUp "1"]
    [FEN "7k/p7/8/8/8/8/8/1R2nR1K w - - 0 1"]

    1. Rfxe1 a5 2. Rb5 *
    """
    let game = try ChessGame(pgn: pgn)
    let indices = game.mainlineIndices
    #expect(indices.count == 3)
    #expect(game.san(at: indices[0]) == "Rfxe1")
    #expect(game.san(at: indices[1]) == "a5")
    #expect(game.san(at: indices[2]) == "Rb5")
}

@Test func parsesHikaruVsCasablancaGame() throws {
    let pgn = """
    [Event "Live Chess"]
    [Site "Chess.com"]
    [Date "2026.07.17"]
    [Round "-"]
    [White "Hikaru"]
    [Black "Casablanca"]
    [Result "1-0"]
    [CurrentPosition "1r6/1PR5/8/3B4/1k2P2p/p2K3P/8/8 b - - 0 57"]
    [Timezone "UTC"]
    [ECO "D27"]
    [ECOUrl "https://www.chess.com/openings/Queens-Gambit-Accepted-Classical-Main-Line-Furman-Variation...9.Ne5-Ke7-10.Be2-Nbd7"]
    [UTCDate "2026.07.17"]
    [UTCTime "01:26:46"]
    [WhiteElo "3445"]
    [BlackElo "2900"]
    [TimeControl "180"]
    [Termination "Hikaru won by resignation"]
    [StartTime "01:26:46"]
    [EndDate "2026.07.17"]
    [EndTime "01:31:58"]
    [Link "https://www.chess.com/game/live/171673575376"]

    1. d4 {[%clk 0:03:00]} 1... d5 {[%clk 0:03:00]} 2. Nf3 {[%clk 0:02:59.9]} 2... Nf6 {[%clk 0:02:59]} 3. c4 {[%clk 0:02:59.2]} 3... dxc4 {[%clk 0:02:58.2]} 4. e3 {[%clk 0:02:58.2]} 4... a6 {[%clk 0:02:56.8]} 5. Bxc4 {[%clk 0:02:56.3]} 5... e6 {[%clk 0:02:56.1]} 6. O-O {[%clk 0:02:54.6]} 6... c5 {[%clk 0:02:55.5]} 7. dxc5 {[%clk 0:02:54.2]} 7... Bxc5 {[%clk 0:02:54.8]} 8. Qxd8+ {[%clk 0:02:52.8]} 8... Kxd8 {[%clk 0:02:54.7]} 9. Be2 {[%clk 0:02:49.1]} 9... Ke7 {[%clk 0:02:50.7]} 10. Ne5 {[%clk 0:02:43.2]} 10... Nbd7 {[%clk 0:02:48.6]} 11. Nd3 {[%clk 0:02:42.7]} 11... Bd6 {[%clk 0:02:47.6]} 12. Nd2 {[%clk 0:02:41.2]} 12... b5 {[%clk 0:02:40.9]} 13. Nb3 {[%clk 0:02:32.6]} 13... Bb7 {[%clk 0:02:36.3]} 14. Na5 {[%clk 0:02:31.5]} 14... Bd5 {[%clk 0:02:35.7]} 15. f3 {[%clk 0:02:31.1]} 15... Rhc8 {[%clk 0:02:14.7]} 16. Bd2 {[%clk 0:02:20.4]} 16... Ne5 {[%clk 0:02:00]} 17. Nb4 {[%clk 0:02:17.3]} 17... Nc4 {[%clk 0:01:46.1]} 18. Nxd5+ {[%clk 0:02:06.1]} 18... exd5 {[%clk 0:01:46]} 19. Nxc4 {[%clk 0:02:01.5]} 19... dxc4 {[%clk 0:01:43.6]} 20. e4 {[%clk 0:01:55.3]} 20... Bc5+ {[%clk 0:01:42.4]} 21. Kh1 {[%clk 0:01:54.7]} 21... Rd8 {[%clk 0:01:41.8]} 22. Bc3 {[%clk 0:01:53]} 22... Bd4 {[%clk 0:01:34.2]} 23. Bb4+ {[%clk 0:01:52.5]} 23... Ke6 {[%clk 0:01:33.7]} 24. Rab1 {[%clk 0:01:52.4]} 24... a5 {[%clk 0:01:32.1]} 25. Be1 {[%clk 0:01:51.1]} 25... Nd7 {[%clk 0:01:27.5]} 26. a4 {[%clk 0:01:49.4]} 26... Nc5 {[%clk 0:01:11]} 27. axb5 {[%clk 0:01:47.9]} 27... Nd3 {[%clk 0:01:10.3]} 28. b3 {[%clk 0:01:41.1]} 28... Bc5 {[%clk 0:01:03.7]} 29. bxc4 {[%clk 0:01:37.4]} 29... Nxe1 {[%clk 0:01:03.1]} 30. Rfxe1 {[%clk 0:01:36.6]} 30... g5 {[%clk 0:00:58.9]} 31. b6 {[%clk 0:01:33.3]} 31... Bb4 {[%clk 0:00:53.6]} 32. Rec1 {[%clk 0:01:30.6]} 32... Rac8 {[%clk 0:00:51.9]} 33. c5 {[%clk 0:01:19.5]} 33... Rxc5 {[%clk 0:00:49.3]} 34. Rxc5 {[%clk 0:01:18.9]} 34... Bxc5 {[%clk 0:00:49.2]} 35. b7 {[%clk 0:01:18.1]} 35... Rb8 {[%clk 0:00:48]} 36. Bc4+ {[%clk 0:01:17.2]} 36... Ke7 {[%clk 0:00:46.3]} 37. Rb5 {[%clk 0:01:14.6]} 37... Bb4 {[%clk 0:00:44.4]} 38. g3 {[%clk 0:01:12.9]} 38... f6 {[%clk 0:00:40.5]} 39. Bd5 {[%clk 0:01:11.7]} 39... Kd6 {[%clk 0:00:33.6]} 40. Rb6+ {[%clk 0:01:10.7]} 40... Kc5 {[%clk 0:00:32.8]} 41. Ra6 {[%clk 0:01:04.9]} 41... Kb5 {[%clk 0:00:29.1]} 42. Ra8 {[%clk 0:01:04.2]} 42... Bd6 {[%clk 0:00:28.7]} 43. Kg2 {[%clk 0:01:03.8]} 43... a4 {[%clk 0:00:27.5]} 44. Kf2 {[%clk 0:01:03.2]} 44... a3 {[%clk 0:00:25.3]} 45. Ke2 {[%clk 0:01:02.7]} 45... Kb4 {[%clk 0:00:24.4]} 46. Kd3 {[%clk 0:01:00.9]} 46... h5 {[%clk 0:00:22.9]} 47. Ke3 {[%clk 0:00:58.1]} 47... Bc5+ {[%clk 0:00:20.7]} 48. Ke2 {[%clk 0:00:56.8]} 48... Bd6 {[%clk 0:00:20.6]} 49. Kd3 {[%clk 0:00:56.1]} 49... h4 {[%clk 0:00:19.4]} 50. gxh4 {[%clk 0:00:54]} 50... gxh4 {[%clk 0:00:19.3]} 51. h3 {[%clk 0:00:53.5]} 51... Bf4 {[%clk 0:00:18.9]} 52. Ra6 {[%clk 0:00:51.2]} 52... Be5 {[%clk 0:00:16.1]} 53. f4 {[%clk 0:00:50.5]} 53... Bxf4 {[%clk 0:00:15]} 54. Rxf6 {[%clk 0:00:50.1]} 54... Bc7 {[%clk 0:00:14.5]} 55. Ra6 {[%clk 0:00:49.3]} 55... Kc5 {[%clk 0:00:13.2]} 56. Rc6+ {[%clk 0:00:48.2]} 56... Kb4 {[%clk 0:00:12.4]} 57. Rxc7 {[%clk 0:00:48.1]} 1-0
    """
    let game = try ChessGame(pgn: pgn)
    #expect(game.tags["White"] == "Hikaru")
    #expect(game.tags["Black"] == "Casablanca")
    #expect(game.tags["Result"] == "1-0")

    let indices = game.mainlineIndices
    #expect(indices.count == 113)

    // Move 30 (ply 59) is 30. Rfxe1
    #expect(game.san(at: indices[58]) == "Rfxe1")
    #expect(game.uciMove(at: indices[58]) == "f1e1")

    // Move 37 (ply 73) is 37. Rb5
    #expect(game.san(at: indices[72]) == "Rb5")
    #expect(game.uciMove(at: indices[72]) == "b1b5")

    // Final position at ply 113 (57. Rxc7)
    let finalFEN = game.fen(at: indices.last!)
    #expect(finalFEN == "1r6/1PR5/8/3B4/1k2P2p/p2K3P/8/8 b - - 0 57")
}
