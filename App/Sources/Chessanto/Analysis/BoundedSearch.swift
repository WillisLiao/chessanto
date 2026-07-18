import EngineKit

enum EngineSearchError: Error, Equatable {
    case timedOut(milliseconds: Int)
    case cancelled
    case noAnalysis
    case engineUnavailable(String)
}

/// Owns exactly one bounded search: collection, exactly-once completion,
/// and rejection of updates from other generations. Deliberately engine-free
/// (no import of `EngineKit`'s `AnalysisEngine` actor) so its lifecycle is
/// driven entirely by method calls and every test runs deterministically
/// with no Stockfish process - `EngineKit` cannot be tested against a live
/// engine under XCTest (chesskit-engine needs a free main run loop).
///
/// Timeout and cancellation are the caller's responsibility (`fail(_:)` is
/// how they're reported here); this type only latches the outcome so it can
/// never be lost, in particular when `complete`/`fail` arrive before anyone
/// has started awaiting `value()` - that ordering is what makes F1 (an
/// unbounded hang from arming the waiter after `go` was already sent)
/// impossible to reproduce.
@MainActor
final class BoundedSearchSession {
    private enum Outcome {
        case success([AnalysisEngine.EngineInfo])
        case failure(EngineSearchError)
    }

    let generation: Int
    private var collector = BatchCollector()
    private var outcome: Outcome?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(generation: Int) {
        self.generation = generation
    }

    /// Records an info if it belongs to this session and it is still open.
    func record(_ info: AnalysisEngine.EngineInfo) {
        guard outcome == nil, info.generation == generation else { return }
        collector.record(info)
    }

    /// Marks the search finished. Safe to call before, during, or after a
    /// caller begins awaiting, and safe to call more than once.
    func complete(generation: Int) {
        guard outcome == nil, generation == self.generation else { return }
        resolve(.success(collector.rankedInfos))
    }

    /// Resolves the session with a failure exactly once.
    func fail(_ error: EngineSearchError) {
        guard outcome == nil else { return }
        resolve(.failure(error))
    }

    /// Awaits completion. Returns immediately if the search already
    /// completed before this was called.
    func value() async throws -> [AnalysisEngine.EngineInfo] {
        await waitForOutcome()
        switch outcome! {
        case .success(let infos):
            if infos.isEmpty { throw EngineSearchError.noAnalysis }
            return infos
        case .failure(let error):
            throw error
        }
    }

    private func resolve(_ outcome: Outcome) {
        self.outcome = outcome
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume() }
    }

    private func waitForOutcome() async {
        if outcome != nil { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if outcome != nil {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }
}
