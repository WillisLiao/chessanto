import Testing
import EngineKit
@testable import Chessanto

@MainActor
struct BoundedSearchTests {
    private func info(
        generation: Int,
        rank: Int? = 1,
        cp: Int = 10,
        depth: Int = 10
    ) -> AnalysisEngine.EngineInfo {
        AnalysisEngine.EngineInfo(
            generation: generation, depth: depth, scoreCentipawns: cp, mateIn: nil,
            principalVariation: [], multiPVRank: rank
        )
    }

    // MARK: - Final-iteration delivery race

    /// Stockfish always completes the depth it was asked for, but that
    /// iteration's `info` lines race the terminating `bestmove` in
    /// delivery (measured live: 8 depth-12 searches reported depth 11 in
    /// five of them). Resolving on the bestmove alone therefore stores a
    /// nondeterministically shallower evaluation, which is exactly what a
    /// fixed-depth budget exists to prevent.

    @Test func bestMoveBeforeFinalDepthDoesNotResolve() async throws {
        let session = BoundedSearchSession(generation: 1, targetDepth: 12)
        session.record(info(generation: 1, cp: 10, depth: 11))
        session.complete(generation: 1)

        #expect(session.isAwaitingFinalDepth)
    }

    @Test func lateFinalDepthInfoResolvesWithTheDeeperEvaluation() async throws {
        let session = BoundedSearchSession(generation: 1, targetDepth: 12)
        session.record(info(generation: 1, cp: 10, depth: 11))
        session.complete(generation: 1)
        session.record(info(generation: 1, cp: 42, depth: 12))

        #expect(!session.isAwaitingFinalDepth)
        let infos = try await session.value()
        #expect(infos.count == 1)
        #expect(infos[0].depth == 12)
        #expect(infos[0].scoreCentipawns == 42)
    }

    @Test func settleResolvesWithTheShallowerResultRatherThanHanging() async throws {
        let session = BoundedSearchSession(generation: 1, targetDepth: 12)
        session.record(info(generation: 1, cp: 10, depth: 11))
        session.complete(generation: 1)
        session.settle()

        let infos = try await session.value()
        #expect(infos.count == 1)
        #expect(infos[0].depth == 11)
    }

    @Test func settleOnAResolvedSessionIsANoOp() async throws {
        let session = BoundedSearchSession(generation: 1, targetDepth: 12)
        session.record(info(generation: 1, cp: 10, depth: 12))
        session.complete(generation: 1)
        session.settle()

        let infos = try await session.value()
        #expect(infos.count == 1)
        #expect(infos[0].scoreCentipawns == 10)
    }

    @Test func everyRankMustReachTheTargetDepth() async throws {
        let session = BoundedSearchSession(generation: 1, targetDepth: 12)
        session.record(info(generation: 1, rank: 1, cp: 10, depth: 12))
        session.record(info(generation: 1, rank: 2, cp: 5, depth: 11))
        session.complete(generation: 1)

        // Rank two is still one iteration behind, so the MultiPV set is not
        // yet the set that was paid for.
        #expect(session.isAwaitingFinalDepth)

        session.record(info(generation: 1, rank: 2, cp: 7, depth: 12))
        let infos = try await session.value()
        #expect(infos.count == 2)
        #expect(infos.allSatisfy { $0.depth == 12 })
    }

    @Test func movetimeSearchResolvesOnBestMoveRegardlessOfDepth() async throws {
        // A movetime budget promises no particular depth, so there is
        // nothing to wait for and the old behaviour must be preserved.
        let session = BoundedSearchSession(generation: 1)
        session.record(info(generation: 1, cp: 10, depth: 7))
        session.complete(generation: 1)

        #expect(!session.isAwaitingFinalDepth)
        let infos = try await session.value()
        #expect(infos.count == 1)
    }

    @Test func completionBeforeAwaitStillResolves() async throws {
        let session = BoundedSearchSession(generation: 1)
        session.record(info(generation: 1))
        session.complete(generation: 1)

        let infos = try await session.value()
        #expect(infos.count == 1)
        #expect(infos[0].scoreCentipawns == 10)
    }

    @Test func completionResolvesExactlyOnce() async throws {
        let session = BoundedSearchSession(generation: 1)
        session.record(info(generation: 1, cp: 10))
        session.complete(generation: 1)
        session.record(info(generation: 1, cp: 999))
        session.complete(generation: 1)

        let infos = try await session.value()
        #expect(infos.count == 1)
        #expect(infos[0].scoreCentipawns == 10)
    }

    @Test func timeoutFailsWithTypedError() async throws {
        let session = BoundedSearchSession(generation: 1)
        Task {
            try? await Task.sleep(nanoseconds: 20_000_000)
            session.fail(.timedOut(milliseconds: 20))
        }

        await #expect(throws: EngineSearchError.timedOut(milliseconds: 20)) {
            try await session.value()
        }
    }

    @Test func cancellationFailsWithTypedError() async throws {
        let session = BoundedSearchSession(generation: 1)
        Task {
            try? await Task.sleep(nanoseconds: 20_000_000)
            session.fail(.cancelled)
        }

        await #expect(throws: EngineSearchError.cancelled) {
            try await session.value()
        }
    }

    @Test func lateUpdatesAfterResolutionAreIgnored() async throws {
        let session = BoundedSearchSession(generation: 1)
        session.record(info(generation: 1, cp: 10))
        session.complete(generation: 1)
        session.record(info(generation: 1, cp: 999))

        let infos = try await session.value()
        #expect(infos.count == 1)
        #expect(infos[0].scoreCentipawns == 10)
    }

    @Test func updatesFromAnotherGenerationAreIgnored() async throws {
        let session = BoundedSearchSession(generation: 2)
        session.record(info(generation: 1, cp: 999))
        session.record(info(generation: 2, cp: 10))
        session.complete(generation: 2)

        let infos = try await session.value()
        #expect(infos.count == 1)
        #expect(infos[0].scoreCentipawns == 10)
    }

    @Test func emptyResultsSurfaceNoAnalysis() async throws {
        let session = BoundedSearchSession(generation: 1)
        session.complete(generation: 1)

        await #expect(throws: EngineSearchError.noAnalysis) {
            try await session.value()
        }
    }

    @Test func resolvedSessionIgnoresRepeatedFailures() async throws {
        let session = BoundedSearchSession(generation: 1)
        session.record(info(generation: 1, cp: 10))
        session.complete(generation: 1)
        session.fail(.timedOut(milliseconds: 1))
        session.fail(.cancelled)

        let infos = try await session.value()
        #expect(infos.count == 1)
        #expect(infos[0].scoreCentipawns == 10)
    }
}
