import Testing
@testable import Chessanto

struct PGNTagScannerTests {
    @Test func extractsStandardTags() {
        let pgn = """
        [Event "Live Chess"]
        [White "alice"]
        [Black "bob"]
        [Result "1-0"]
        [Date "2026.05.01"]

        1. e4 e5 2. Nf3 Nc6 1-0
        """
        let tags = PGNTagScanner.tags(from: pgn)
        #expect(tags?["White"] == "alice")
        #expect(tags?["Black"] == "bob")
        #expect(tags?["Result"] == "1-0")
    }

    @Test func returnsNilForNonPGNText() {
        #expect(PGNTagScanner.tags(from: "not a pgn") == nil)
    }

    @Test func parsesDate() {
        let tags = ["Date": "2026.05.01"]
        let date = PGNTagScanner.date(from: tags)
        #expect(date != nil)
    }
}
