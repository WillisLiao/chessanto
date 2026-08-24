import ChessCore
import Persistence
import AnalysisKit
import Testing
@testable import Chessanto

@MainActor
struct AdversarialPGNImportTests {

    // MARK: - 1. PGNTagScanner Edge Cases

    @Test func pgnTagScannerHandlesBareMoveText() {
        let barePGN = "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 *"
        let tags = PGNTagScanner.tags(from: barePGN)
        #expect(tags != nil)
        #expect(tags?["White"] == "White")
        #expect(tags?["Black"] == "Black")
        #expect(tags?["Result"] == "*")
    }

    @Test func pgnTagScannerHandlesSpacedTagsAndUnicode() {
        let pgn = """
        [  Event   "Reykjavik Open"  ]
        [ White "Jose Raul Capablanca" ]
        [ Black "Vladimir Kramnik" ]
        [Result "1-0"]

        1. d4 Nf6 2. c4 e6 1-0
        """
        let tags = PGNTagScanner.tags(from: pgn)
        #expect(tags?["Event"] == "Reykjavik Open")
        #expect(tags?["White"] == "Jose Raul Capablanca")
        #expect(tags?["Black"] == "Vladimir Kramnik")
        #expect(tags?["Result"] == "1-0")
    }

    @Test func pgnTagScannerRejectsInvalidText() {
        #expect(PGNTagScanner.tags(from: "") == nil)
        #expect(PGNTagScanner.tags(from: "    ") == nil)
        #expect(PGNTagScanner.tags(from: "Hello world, this is not chess.") == nil)
        #expect(PGNTagScanner.tags(from: "1. e99 z99") == nil)
    }

    // MARK: - 2. GameLibrary Import Pathways

    @Test func gameLibraryImportsBareMoveText() throws {
        let library = GameLibrary()

        let barePGN = "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 *"
        let record = library.importPGN(barePGN, source: .pgnImport)
        #expect(record != nil)
        #expect(record?.white == "White")
        #expect(record?.black == "Black")
        #expect(record?.result == "*")
        #expect(library.games.contains(where: { $0.id == record?.id }))
    }

    @Test func gameLibraryImportsAbandonmentAndTimeoutGames() throws {
        let library = GameLibrary()

        let timeoutPGN = """
        [Event "Live Chess"]
        [Site "Chess.com"]
        [Date "2026.08.20"]
        [White "TimeMaster"]
        [Black "FlagFaller"]
        [Result "1-0"]
        [Termination "TimeMaster won on time"]

        1. e4 e5 2. Nf3 Nc6 1-0
        """
        let record = library.importPGN(timeoutPGN, source: .pgnImport)
        #expect(record != nil)
        #expect(record?.white == "TimeMaster")
        #expect(record?.black == "FlagFaller")
        #expect(record?.result == "1-0")
    }

    @Test func gameLibraryImportsExternalToolExports() throws {
        let library = GameLibrary()

        // ChessBase format with 0-0 castling
        let chessBasePGN = """
        [Event "ChessBase Export"]
        [White "W"]
        [Black "B"]
        [Result "*"]

        1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. 0-0 Nf6 5. d3 0-0 *
        """
        let cbRecord = library.importPGN(chessBasePGN, source: .pgnImport)
        #expect(cbRecord != nil)

        // Lichess study export with $1 NAGs
        let lichessPGN = """
        [Event "Lichess Study"]
        [Result "*"]

        1. e4 c5 2. Nf3 $1 d6 3. d4 cxd4 4. Nxd4 Nf6 *
        """
        let lichessRecord = library.importPGN(lichessPGN, source: .pgnImport)
        #expect(lichessRecord != nil)

        // Semicolon comments and CRLF line endings
        let crlfPGN = "[Event \"CRLF\"]\r\n[White \"W\"]\r\n[Black \"B\"]\r\n[Result \"*\"]\r\n\r\n1. e4 e5 ; Kings pawn\r\n2. Nf3 Nc6\r\n*"
        let crlfRecord = library.importPGN(crlfPGN, source: .pgnImport)
        #expect(crlfRecord != nil)
    }

    // MARK: - 3. GameReplayViewModel Navigation Edge Cases

    @Test func gameReplayViewModelHandlesZeroMoveGame() throws {
        let store = try GameStore()
        let record = GameRecord(
            id: 1,
            source: .pgnImport,
            pgn: "[Event \"Zero\"]\n[White \"A\"]\n[Black \"B\"]\n[Result \"*\"]\n*",
            white: "A",
            black: "B",
            result: "*"
        )
        let viewModel = GameReplayViewModel(record: record, store: store)
        #expect(viewModel.loadError == nil)
        #expect(viewModel.moveIndices.count == 1)
        #expect(viewModel.fens.count == 1)
        #expect(viewModel.canStepBackward == false)
        #expect(viewModel.canStepForward == false)

        // Navigation should not crash on empty game
        viewModel.stepForward()
        viewModel.stepBackward()
        viewModel.jump(to: viewModel.moveIndices.first!)
        viewModel.jump(to: viewModel.moveIndices.last!)
        #expect(viewModel.currentFEN != nil)
    }

    @Test func gameReplayViewModelHandlesSingleMoveGame() throws {
        let store = try GameStore()
        let record = GameRecord(
            id: 2,
            source: .pgnImport,
            pgn: "[Event \"One Move\"]\n[White \"A\"]\n[Black \"B\"]\n[Result \"1-0\"]\n\n1. e4 1-0",
            white: "A",
            black: "B",
            result: "1-0"
        )
        let viewModel = GameReplayViewModel(record: record, store: store)
        #expect(viewModel.loadError == nil)
        #expect(viewModel.moveIndices.count == 2)
        #expect(viewModel.fens.count == 2)
        #expect(viewModel.canStepForward == true)

        viewModel.stepForward()
        #expect(viewModel.canStepBackward == true)
        #expect(viewModel.currentIndex == viewModel.moveIndices[1])
        viewModel.stepBackward()
        #expect(viewModel.currentIndex == viewModel.moveIndices[0])
    }

    @Test func gameReplayViewModelHandlesLongGame() throws {
        let store = try GameStore()
        var moveText = ""
        for i in 1...80 {
            let moveNum = (i - 1) * 2 + 1
            let moveNum2 = (i - 1) * 2 + 2
            moveText += "\(moveNum). Nf3 Nf6 \(moveNum2). Ng1 Ng8 "
        }
        moveText += "1/2-1/2"

        let record = GameRecord(
            id: 3,
            source: .pgnImport,
            pgn: "[Event \"Marathon\"]\n[White \"A\"]\n[Black \"B\"]\n[Result \"1/2-1/2\"]\n\n\(moveText)",
            white: "A",
            black: "B",
            result: "1/2-1/2"
        )
        let viewModel = GameReplayViewModel(record: record, store: store)
        #expect(viewModel.loadError == nil)
        #expect(viewModel.moveIndices.count == 321)
        #expect(viewModel.fens.count == 321)

        viewModel.jump(to: viewModel.moveIndices.last!)
        #expect(viewModel.currentIndex == viewModel.moveIndices.last!)
        viewModel.jump(to: viewModel.moveIndices.first!)
        #expect(viewModel.currentIndex == viewModel.moveIndices.first!)
    }

    // MARK: - 4. ReportBuilding with Clocks and Edge Case Games

    @Test func reportBuildingReturnsNilForZeroMoveGame() {
        let record = GameRecord(
            id: 10,
            source: .pgnImport,
            pgn: "[Event \"Zero\"]\n[White \"A\"]\n[Black \"B\"]\n[Result \"*\"]\n*",
            white: "A",
            black: "B",
            result: "*"
        )
        let analyses = [
            AnalysisRecord(
                id: 1,
                gameId: 10,
                plyIndex: 0,
                fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
                depth: 10,
                scoreCentipawns: 20,
                mateIn: nil,
                principalVariation: "e2e4",
                multiPVRank: 1
            )
        ]
        let input = ReportBuilding.buildInput(record: record, analysisRows: analyses, chessComUsername: nil)
        #expect(input == nil)
    }

    @Test func reportBuildingExtractsClocksAndFiresTimePressureTakeaway() {
        // Construct a game with 6 plies where Black makes 2 errors with low clock (under 30s)
        let pgn = """
        [Event "Blitz"]
        [White "WhitePlayer"]
        [Black "BlackPlayer"]
        [Result "1-0"]

        1. e4 {[%clk 0:03:00]} 1... e5 {[%clk 0:00:20]} 2. Nf3 {[%clk 0:02:50]} 2... f6 {[%clk 0:00:15]} 3. Nxe5 {[%clk 0:02:40]} 3... fxe5 {[%clk 0:00:10]} 1-0
        """
        let record = GameRecord(
            id: 20,
            source: .pgnImport,
            pgn: pgn,
            white: "WhitePlayer",
            black: "BlackPlayer",
            result: "1-0"
        )
        // 7 positions (ply 0 to 6)
        let analyses: [AnalysisRecord] = [
            AnalysisRecord(id: 1, gameId: 20, plyIndex: 0, fen: "", depth: 10, scoreCentipawns: 20, mateIn: nil, principalVariation: "e2e4", multiPVRank: 1),
            AnalysisRecord(id: 2, gameId: 20, plyIndex: 1, fen: "", depth: 10, scoreCentipawns: 20, mateIn: nil, principalVariation: "e7e5", multiPVRank: 1),
            AnalysisRecord(id: 3, gameId: 20, plyIndex: 2, fen: "", depth: 10, scoreCentipawns: 20, mateIn: nil, principalVariation: "g8f6", multiPVRank: 1),
            AnalysisRecord(id: 4, gameId: 20, plyIndex: 3, fen: "", depth: 10, scoreCentipawns: 20, mateIn: nil, principalVariation: "b8c6", multiPVRank: 1),
            AnalysisRecord(id: 5, gameId: 20, plyIndex: 4, fen: "", depth: 10, scoreCentipawns: 250, mateIn: nil, principalVariation: "f3e5", multiPVRank: 1), // Black blunder on ply 4 (2... f6)
            AnalysisRecord(id: 6, gameId: 20, plyIndex: 5, fen: "", depth: 10, scoreCentipawns: 250, mateIn: nil, principalVariation: "d8e7", multiPVRank: 1),
            AnalysisRecord(id: 7, gameId: 20, plyIndex: 6, fen: "", depth: 10, scoreCentipawns: 700, mateIn: nil, principalVariation: "d1h5", multiPVRank: 1) // Black blunder on ply 6 (3... fxe5)
        ]

        let input = ReportBuilding.buildInput(record: record, analysisRows: analyses, chessComUsername: nil)
        #expect(input != nil)
        #expect(input?.plies.count == 7)
        #expect(input?.plies[1].clockSeconds == 180)
        #expect(input?.plies[2].clockSeconds == 20)
        #expect(input?.plies[4].clockSeconds == 15)
        #expect(input?.plies[6].clockSeconds == 10)

        let emptyBook = OpeningBook.build(from: [])
        let report = ReportBuilder.build(input: input!, openingBook: emptyBook)
        #expect(report != nil)
        #expect(report?.takeaways.contains(where: { $0.contains("while low on time") }) == true)
    }
}
