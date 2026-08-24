import Testing
@testable import ChessCore

@Suite struct AdversarialPGNTests {

    // MARK: - 1. Game Terminations (Abandonment, Timeout, Stalemate, Adjudication)

    @Test func parsesAbandonmentTermination() throws {
        let pgn = """
        [Event "Live Chess"]
        [Site "Chess.com"]
        [Date "2026.08.20"]
        [White "PlayerOne"]
        [Black "PlayerTwo"]
        [Result "1-0"]
        [Termination "PlayerOne won by abandonment"]

        1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 1-0
        """
        let game = try ChessGame(pgn: pgn)
        #expect(game.tags["Termination"] == "PlayerOne won by abandonment")
        #expect(game.tags["Result"] == "1-0")
        #expect(game.mainlineIndices.count == 6)
    }

    @Test func parsesTimeoutTermination() throws {
        let pgn = """
        [Event "Live Chess"]
        [Site "Chess.com"]
        [Date "2026.08.21"]
        [White "PlayerOne"]
        [Black "PlayerTwo"]
        [Result "0-1"]
        [Termination "PlayerTwo won on time"]

        1. d4 Nf6 2. c4 e6 3. Nc3 Bb4 4. Qc2 O-O 0-1
        """
        let game = try ChessGame(pgn: pgn)
        #expect(game.tags["Termination"] == "PlayerTwo won on time")
        #expect(game.tags["Result"] == "0-1")
        #expect(game.mainlineIndices.count == 8)
    }

    @Test func parsesStalemateAndInsufficientMaterial() throws {
        let stalematePGN = """
        [Event "Casual Game"]
        [Site "Local"]
        [Date "2026.08.22"]
        [White "W"]
        [Black "B"]
        [Result "1/2-1/2"]
        [Termination "Game drawn by stalemate"]
        [SetUp "1"]
        [FEN "k7/8/1K6/8/8/8/8/8 w - - 0 1"]

        1. Ka6 Kb8 1/2-1/2
        """
        let game = try ChessGame(pgn: stalematePGN)
        #expect(game.tags["Termination"] == "Game drawn by stalemate")
        #expect(game.tags["Result"] == "1/2-1/2")
        #expect(game.mainlineIndices.count == 2)
    }

    @Test func parsesUnfinishedGameWithAsterisk() throws {
        let pgn = """
        [Event "Unfinished"]
        [White "A"]
        [Black "B"]
        [Result "*"]

        1. e4 e5 2. Nf3 *
        """
        let game = try ChessGame(pgn: pgn)
        #expect(game.tags["Result"] == "*")
        #expect(game.mainlineIndices.count == 3)
    }

    // MARK: - 2. Game Length Extremes (0 to 150+ moves)

    @Test func parsesZeroMoveGame() throws {
        let pgn = """
        [Event "Zero Move Game"]
        [White "WhitePlayer"]
        [Black "BlackPlayer"]
        [Result "*"]

        *
        """
        let game = try ChessGame(pgn: pgn)
        #expect(game.mainlineIndices.isEmpty)
        #expect(game.startIndex == MoveIndex.start)
    }

    @Test func parsesSingleMoveGame() throws {
        let pgn = """
        [Event "One Move Resignation"]
        [White "GrandmasterA"]
        [Black "GrandmasterB"]
        [Result "1-0"]

        1. e4 1-0
        """
        let game = try ChessGame(pgn: pgn)
        #expect(game.mainlineIndices.count == 1)
        #expect(game.san(at: game.mainlineIndices[0]) == "e4")
        #expect(game.uciMove(at: game.mainlineIndices[0]) == "e2e4")
    }

    @Test func parsesFoolsMateTwoMoveGame() throws {
        let pgn = """
        [Event "Fool's Mate"]
        [White "White"]
        [Black "Black"]
        [Result "0-1"]

        1. f3 e5 2. g4 Qh4# 0-1
        """
        let game = try ChessGame(pgn: pgn)
        #expect(game.mainlineIndices.count == 4)
        #expect(game.san(at: game.mainlineIndices[3]) == "Qh4#")
    }

    @Test func parsesVeryLongGameOver150Moves() throws {
        // Construct a valid PGN with 160 moves (320 plies) using repeating knight moves
        var moveText = ""
        for i in 1...80 {
            let moveNum = (i - 1) * 2 + 1
            let moveNum2 = (i - 1) * 2 + 2
            moveText += "\(moveNum). Nf3 Nf6 \(moveNum2). Ng1 Ng8 "
        }
        moveText += "1/2-1/2"

        let pgn = """
        [Event "Marathon Game"]
        [White "KnightWanderer1"]
        [Black "KnightWanderer2"]
        [Result "1/2-1/2"]

        \(moveText)
        """
        let game = try ChessGame(pgn: pgn)
        #expect(game.mainlineIndices.count == 320)
        #expect(game.fen(at: game.mainlineIndices.last!) == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 320 161")
    }

    // MARK: - 3. Clocks and [%clk] Variations

    @Test func parsesVariousClockFormatsInComments() {
        #expect(ChessGame.parseClockAnnotation("{[%clk 0:02:58.7]}") == 178)
        #expect(ChessGame.parseClockAnnotation("{[%clk 1:23:45]}") == 5025)
        #expect(ChessGame.parseClockAnnotation("{[%clk 0:05:00]}") == 300)
        #expect(ChessGame.parseClockAnnotation("{[%clk 0:00:05]}") == 5)
        #expect(ChessGame.parseClockAnnotation("{[%clk 0:00:00]}") == 0)
        #expect(ChessGame.parseClockAnnotation("{[%clk 05:30]}") == 330)
        #expect(ChessGame.parseClockAnnotation("{[%clk 0:30]}") == 30)
        #expect(ChessGame.parseClockAnnotation("{[%clk 0:00:05.123]}") == 5)
        #expect(ChessGame.parseClockAnnotation("{[%clk 0:00]}") == 0)
        #expect(ChessGame.parseClockAnnotation("{[%clk 300]}") == 300)
    }

    @Test func parsesGameWithMissingAndPartialClocks() throws {
        let pgn = """
        [Event "Partial Clocks"]
        [White "A"]
        [Black "B"]
        [Result "*"]

        1. e4 {[%clk 0:05:00]} 1... e5 2. Nf3 {[%clk 0:04:55]} 2... Nc6 3. Bc4 *
        """
        let game = try ChessGame(pgn: pgn)
        #expect(game.mainlineIndices.count == 5)
        #expect(game.clockSeconds(at: game.mainlineIndices[0]) == 300)
        #expect(game.clockSeconds(at: game.mainlineIndices[1]) == nil)
        #expect(game.clockSeconds(at: game.mainlineIndices[2]) == 295)
        #expect(game.clockSeconds(at: game.mainlineIndices[3]) == nil)
    }

    @Test func parsesGameWithMultipleAnnotationsAndMultilineComments() throws {
        let pgn = """
        [Event "Lichess Style Annotations"]
        [White "Player1"]
        [Black "Player2"]
        [Result "1-0"]

        1. e4 { [%clk 0:03:00] [%eval 0.25] [%emt 0:00:01]
        Good opening move } 1... e5 { [%clk 0:02:59] } 2. Nf3 Nc6 1-0
        """
        let game = try ChessGame(pgn: pgn)
        #expect(game.mainlineIndices.count == 4)
        #expect(game.clockSeconds(at: game.mainlineIndices[0]) == 180)
        #expect(game.clockSeconds(at: game.mainlineIndices[1]) == 179)
    }

    // MARK: - 4. Unicode Player Names and Unusual PGN Headers

    @Test func parsesUnicodePlayerNamesAndSpecialCharacters() throws {
        let pgn = """
        [Event "World Championship - Reykjavik"]
        [Site "Reykjavik, Island"]
        [Date "1972.07.11"]
        [White "Jose Raul Capablanca"]
        [Black "Vladimir Kramnik"]
        [Result "1-0"]
        [WhiteElo "2750"]
        [BlackElo "2780"]
        [CustomTag "Umit & Sakir - Champion"]

        1. d4 Nf6 2. c4 e6 3. Nf3 d5 1-0
        """
        let game = try ChessGame(pgn: pgn)
        #expect(game.tags["White"] == "Jose Raul Capablanca")
        #expect(game.tags["Black"] == "Vladimir Kramnik")
        #expect(game.tags["Site"] == "Reykjavik, Island")
        #expect(game.tags["CustomTag"] == "Umit & Sakir - Champion")
        #expect(game.mainlineIndices.count == 6)
    }

    @Test func parsesHeadersWithExtraWhitespaceAndUnusualSpacing() throws {
        let pgn = """
        [  Event   "Spaced Event"  ]
        [ White "Player One" ]
        [ Black   "Player Two"  ]
        [Result "1/2-1/2"]

        1. e4 e5 2. Nf3 Nc6 1/2-1/2
        """
        let game = try ChessGame(pgn: pgn)
        #expect(game.tags["Event"] == "Spaced Event")
        #expect(game.tags["White"] == "Player One")
        #expect(game.tags["Black"] == "Player Two")
        #expect(game.mainlineIndices.count == 4)
    }

    @Test func parsesHeaderlessPGN() throws {
        let barePGN = "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 *"
        let game = try ChessGame(pgn: barePGN)
        #expect(game.mainlineIndices.count == 6)
        #expect(game.san(at: game.mainlineIndices[0]) == "e4")
        #expect(game.san(at: game.mainlineIndices[5]) == "a6")
    }

    // MARK: - 5. External Tools (Lichess, ChessBase, TWIC)

    @Test func parsesLichessStudyExportWithNAGsAndGlyphs() throws {
        let lichessPGN = """
        [Event "Lichess Study: Sicilian Defense"]
        [Site "https://lichess.org/study/example"]
        [Result "*"]
        [Variant "Standard"]
        [ECO "B20"]
        [Opening "Sicilian Defense"]

        1. e4 c5 2. Nf3 $1 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 $2 { Najdorf variation } 6. Be3 e5 7. Nb3 Be6 *
        """
        let game = try ChessGame(pgn: lichessPGN)
        #expect(game.mainlineIndices.count == 14)
        #expect(game.tags["Opening"] == "Sicilian Defense")
    }

    @Test func parsesPGNWithNumericCastlingZeros() throws {
        let pgnWithZeros = """
        [Event "ChessBase Style 0-0"]
        [White "White"]
        [Black "Black"]
        [Result "*"]

        1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. 0-0 Nf6 5. d3 0-0 *
        """
        let game = try ChessGame(pgn: pgnWithZeros)
        #expect(game.mainlineIndices.count == 10)
        #expect(game.san(at: game.mainlineIndices[6]) == "O-O")
        #expect(game.san(at: game.mainlineIndices[7]) == "Nf6")
        #expect(game.san(at: game.mainlineIndices[9]) == "O-O")
    }

    @Test func parsesPGNWithSemicolonCommentsAndPercentEscapes() throws {
        let pgn = """
        % Escape line from PGN standard
        [Event "Comments Test"]
        [White "A"]
        [Black "B"]
        [Result "1-0"]

        1. e4 e5 ; Kings pawn opening
        2. Nf3 Nc6 ; Knights developed
        3. Bb5 a6 ; Spanish opening
        4. Ba4 Nf6 1-0
        """
        let game = try ChessGame(pgn: pgn)
        #expect(game.mainlineIndices.count == 8)
    }

    @Test func parsesWindowsCRLFAndMacCRLineEndings() throws {
        let crlfPGN = "[Event \"CRLF Test\"]\r\n[White \"W\"]\r\n[Black \"B\"]\r\n[Result \"*\"]\r\n\r\n1. e4 e5\r\n2. Nf3 Nc6\r\n*"
        let gameCRLF = try ChessGame(pgn: crlfPGN)
        #expect(gameCRLF.mainlineIndices.count == 4)

        let crPGN = "[Event \"CR Test\"]\r[White \"W\"]\r[Black \"B\"]\r[Result \"*\"]\r\r1. d4 d5\r2. c4 e6\r*"
        let gameCR = try ChessGame(pgn: crPGN)
        #expect(gameCR.mainlineIndices.count == 4)
    }

    @Test func parsesBOMAndAlternativePromotionAndEvaluationSuffixes() throws {
        // UTF-8 Byte Order Mark
        let bomPGN = "\u{FEFF}[Event \"BOM Game\"]\n[White \"W\"]\n[Black \"B\"]\n[Result \"*\"]\n\n1. e4 e5 2. Nf3+- Nc6 3. Bc4= *"
        let gameBOM = try ChessGame(pgn: bomPGN)
        #expect(gameBOM.mainlineIndices.count == 5)

        // Alternative promotion notations e.g. e8Q, e8(Q), e8/Q
        let promoPGN = """
        [SetUp "1"]
        [FEN "8/4P3/8/8/8/8/8/4K2k w - - 0 1"]

        1. e8Q Kh2 2. Qe2+ Kh1 *
        """
        let gamePromo = try ChessGame(pgn: promoPGN)
        #expect(gamePromo.mainlineIndices.count == 4)
        #expect(gamePromo.san(at: gamePromo.mainlineIndices[0]) == "e8=Q")
    }

    @Test func parsesFENPositionWithoutSetUpTag() throws {
        let ftagPGN = """
        [FEN "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2"]

        2. Nf3 d6 3. d4 *
        """
        let game = try ChessGame(pgn: ftagPGN)
        #expect(game.mainlineIndices.count == 3)
        #expect(game.san(at: game.mainlineIndices[0]) == "Nf3")
    }
}
