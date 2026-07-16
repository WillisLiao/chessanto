import Testing
@testable import EngineKit

// chesskit-engine 0.7.0's own StockfishTests are commented out upstream
// ("Failing in CI since update to Stockfish 17 - to be investigated"), so a
// live `engine.start()` is not reliable in an automated test environment yet.
// Keep these tests structural until that's resolved upstream; M2's manual
// acceptance pass is what actually exercises live analysis.

@Test func analysisEngineConstructsAndExposesUpdatesStream() {
    let engine = AnalysisEngine()
    _ = engine.updates.makeAsyncIterator()
}
