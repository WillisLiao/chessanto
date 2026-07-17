import ChessCore
import Foundation
import Testing

@testable import AnalysisKit

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

private func fens(forPGN pgn: String) throws -> [String] {
    let game = try ChessGame(pgn: pgn)
    var result = [game.fen(at: game.startIndex)!]
    for index in game.mainlineIndices {
        result.append(game.fen(at: index)!)
    }
    return result
}

@Test func indexBuildsWithoutDroppingReplayableEntries() {
    let entries: [OpeningEntry] = [
        OpeningEntry(eco: "A00", name: "Amar Opening", pgn: "1. Nh3"),
        OpeningEntry(eco: "C50", name: "Italian Game", pgn: "1. e4 e5 2. Nf3 Nc6 3. Bc4"),
    ]
    let book = OpeningBook.build(from: entries)
    #expect(book.indexedEntryCount == entries.count)
    #expect(OpeningBook.unreplayableEntries(in: entries).isEmpty)

    let italianFENs = try! fens(forPGN: "[White \"A\"][Black \"B\"]\n\n1. e4 e5 2. Nf3 Nc6 3. Bc4 *")
    #expect(book.lookup(fens: italianFENs)?.name == "Italian Game")
}

@Test func realDatasetHasExactlyOneKnownUnreplayableEntry() throws {
    let entries = OpeningBook.loadRawEntriesFromBundle()
    #expect(entries.count == 3803)
    // "Scandinavian Defense: Boehnke Gambit" ends in an en-passant capture
    // (1. e4 d5 2. exd5 e5 3. dxe6) that chesskit-swift cannot replay from a
    // bare FEN, since chesskit's FENs omit the en-passant target square
    // even when legal (a pre-existing chesskit gap - see the M5 handoff's
    // verified fact 6, not a converter bug). A *new* name showing up here
    // would mean a real regression in the tokenizer/replay path.
    let unreplayable = OpeningBook.unreplayableEntries(in: entries)
    #expect(unreplayable.map(\.name) == ["Scandinavian Defense: Boehnke Gambit"])
}

@Test func fullDatasetIndexLoadsFromPrecomputedIndexQuickly() {
    let start = Date()
    let book = OpeningBook.loadFromBundle()
    let elapsed = Date().timeIntervalSince(start)
    print("precomputed index load took \(elapsed)s")
    #expect(elapsed < 1.0)
    #expect(book.indexedEntryCount > 0)
}

@Test func namesKingsPawnFamilyAfterE4() throws {
    let book = OpeningBook.loadFromBundle()
    let openFENs = try fens(forPGN: "[White \"A\"][Black \"B\"]\n\n1. e4 *")
    let match = book.lookup(fens: openFENs)
    #expect(match != nil)
    #expect(match?.name.contains("King's Pawn") == true)
}

@Test func realGameFixtureGetsANonNilMatchWithPlausibleDeviation() throws {
    let book = OpeningBook.loadFromBundle()
    let gameFENs = try fens(forPGN: realChessComPGN)
    let match = book.lookup(fens: gameFENs)
    #expect(match != nil)
    if let match {
        // The fixture's own [ECO "B07"] tag is a sanity signal only, per the
        // M5 plan's opening-book decision - we do not assert equality since
        // chess.com's ECO tagging and this bundled book are separate sources
        // of truth (e.g. it may cover a shorter/longer named line).
        print("book match: \(match.eco) \(match.name) at ply \(match.deepestBookPly), fixture tag: B07")
        #expect(match.deepestBookPly >= 1)
        #expect(match.deepestBookPly < gameFENs.count)
    }
}

@Test func transpositionPrefersLongerLineDeterministically() {
    let entries: [OpeningEntry] = [
        OpeningEntry(eco: "C00", name: "Zebra Line", pgn: "1. e4 e6 2. d4 d5"),
        OpeningEntry(eco: "C00", name: "Alpha Line", pgn: "1. d4 d5 2. e4 e6"),
    ]
    let book = OpeningBook.build(from: entries)
    let fens = try! fens(forPGN: "[White \"A\"][Black \"B\"]\n\n1. e4 e6 2. d4 d5 *")
    // Both lines transpose to the same final position and are the same
    // length, so the lexicographically smaller name wins the tie-break.
    #expect(book.lookup(fens: fens)?.name == "Alpha Line")
}

@Test func fromFENGameReturnsNil() {
    let book = OpeningBook.build(from: [
        OpeningEntry(eco: "C50", name: "Italian Game", pgn: "1. e4 e5 2. Nf3 Nc6 3. Bc4")
    ])
    var game = ChessGame(startingFEN: "4k3/8/8/8/8/8/8/4K3 w - - 0 1")
    var fens = [game.fen(at: game.startIndex)!]
    if let next = game.playMove(from: SquareCoordinate(notation: "e1"), to: SquareCoordinate(notation: "e2"), at: game.startIndex) {
        fens.append(game.fen(at: next)!)
    }
    #expect(book.lookup(fens: fens) == nil)
}
