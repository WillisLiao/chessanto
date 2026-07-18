import Persistence
import Testing
@testable import Chessanto

@MainActor
struct TrainingCardSynchronizerTests {
    @Test
    func readinessWaitsForTheCurrentReconciliation() async throws {
        let gate = TrainingCardOperationGate()
        let synchronizer = TrainingCardSynchronizer()
        let expected = trainingRecord(sourcePly: 7)

        synchronizer.start {
            await gate.run()
        }
        await gate.waitUntilStarted()

        #expect(synchronizer.state == .preparing)

        await gate.finish(with: [expected])
        let records = try await synchronizer.records()

        #expect(records.map(\.sourcePly) == [7])
        #expect(
            synchronizer.state == .ready(
                cardCount: 1,
                sourcePlies: [7]
            )
        )
    }

    @Test
    func staleGenerationCannotReplaceTheLatestReadiness() async throws {
        let staleGate = TrainingCardOperationGate()
        let synchronizer = TrainingCardSynchronizer()

        synchronizer.start {
            await staleGate.run()
        }
        await staleGate.waitUntilStarted()

        synchronizer.start {
            [trainingRecord(sourcePly: 11)]
        }
        _ = try await synchronizer.records()
        await staleGate.finish(with: [trainingRecord(sourcePly: 3)])
        await Task.yield()

        #expect(
            synchronizer.state == .ready(
                cardCount: 1,
                sourcePlies: [11]
            )
        )
    }

    @Test
    func failureCanBeRetriedWithoutReportingAFalseEmptyLesson() async throws {
        let synchronizer = TrainingCardSynchronizer()

        synchronizer.start {
            throw SynchronizerTestError.preparationFailed
        }

        await #expect(throws: SynchronizerTestError.self) {
            _ = try await synchronizer.records()
        }
        #expect(
            synchronizer.state
                == .failed(SynchronizerTestError.preparationFailed.localizedDescription)
        )

        synchronizer.start {
            [trainingRecord(sourcePly: 13)]
        }
        let records = try await synchronizer.records()

        #expect(records.map(\.sourcePly) == [13])
        #expect(
            synchronizer.state == .ready(
                cardCount: 1,
                sourcePlies: [13]
            )
        )
    }

    @Test
    func cancellationReturnsToIdleAndRejectsLateCompletion() async {
        let gate = TrainingCardOperationGate()
        let synchronizer = TrainingCardSynchronizer()

        synchronizer.start {
            await gate.run()
        }
        await gate.waitUntilStarted()
        synchronizer.cancel()
        await gate.finish(with: [trainingRecord(sourcePly: 17)])
        await Task.yield()

        #expect(synchronizer.state == .idle)
    }
}

private enum SynchronizerTestError: Error {
    case preparationFailed
}

private actor TrainingCardOperationGate {
    private var hasStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<[TrainingCardRecord], Never>?

    func run() async -> [TrainingCardRecord] {
        hasStarted = true
        startWaiters.forEach { $0.resume() }
        startWaiters = []
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finish(with records: [TrainingCardRecord]) {
        resultContinuation?.resume(returning: records)
        resultContinuation = nil
    }
}

private func trainingRecord(sourcePly: Int) -> TrainingCardRecord {
    TrainingCardRecord(
        gameId: 1,
        sourcePly: sourcePly,
        preMoveFEN: "",
        sideToMove: "white",
        bestMoveUCI: "",
        rankedLinesJSON: "[]",
        classification: "mistake"
    )
}
