import Testing
import EngineKit
@testable import Chessanto

@MainActor
struct BoundedSearchTests {
    private func info(generation: Int, rank: Int? = 1, cp: Int = 10) -> AnalysisEngine.EngineInfo {
        AnalysisEngine.EngineInfo(
            generation: generation, depth: 10, scoreCentipawns: cp, mateIn: nil,
            principalVariation: [], multiPVRank: rank
        )
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
