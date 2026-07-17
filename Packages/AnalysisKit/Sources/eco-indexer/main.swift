import AnalysisKit
import Foundation

// Precomputes Resources/eco-index.json from Resources/eco.json: replays
// every raw dataset line through ChessGame, resolves transpositions, and
// writes one {epd, eco, name} row per surviving position. Run via
// scripts/fetch-eco.sh (`swift run eco-indexer <eco.json path> <output path>`).

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("usage: eco-indexer <path to eco.json> <output path>\n".data(using: .utf8)!)
    exit(1)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

do {
    let data = try Data(contentsOf: inputURL)
    let entries = try JSONDecoder().decode([OpeningEntry].self, from: data)
    // A handful of dataset lines end in a move chesskit-swift cannot replay
    // from a bare FEN - notably en-passant captures, since chesskit's FENs
    // omit the en-passant target square even when legal (a documented,
    // pre-existing chesskit gap, not a converter bug - see the M5 handoff's
    // verified fact 6). Such entries are skipped, not silently miscounted:
    // log them so a *new* unreplayable entry (an actual converter bug) is
    // never missed.
    let unreplayable = OpeningBook.unreplayableEntries(in: entries)
    for entry in unreplayable {
        FileHandle.standardError.write("skipping unreplayable entry (\(entry.eco) \(entry.name)): \(entry.pgn)\n".data(using: .utf8)!)
    }
    let replayable = entries.filter { entry in !unreplayable.contains { $0.name == entry.name && $0.pgn == entry.pgn } }
    let indexData = try OpeningBook.precomputedIndexData(from: replayable)
    try indexData.write(to: outputURL)
    print("wrote index for \(replayable.count)/\(entries.count) entries to \(outputURL.path) (\(unreplayable.count) skipped)")
} catch {
    FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
