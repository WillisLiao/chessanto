import Foundation
import Persistence
import Testing
@testable import Chessanto

@MainActor
struct BatchAnalysisCoordinatorTests {
    private func game(id: Int64, white: String = "Alice", black: String = "Bob") -> GameRecord {
        var record = GameRecord(source: .pgnImport, pgn: "1. e4 e5", white: white, black: black)
        record.id = id
        return record
    }

    /// Waits for the batch to settle rather than sleeping a fixed interval,
    /// so the test cannot pass or fail on machine speed.
    private func finished(_ coordinator: BatchAnalysisCoordinator) async -> BatchAnalysisCoordinator.Summary? {
        for _ in 0..<400 {
            if case .finished(let summary) = coordinator.state { return summary }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return nil
    }

    @Test
    func unanalyzedSkipsGamesThatAlreadyHaveAnalysis() {
        let games = [game(id: 1), game(id: 2), game(id: 3)]

        let pending = BatchAnalysisCoordinator.unanalyzed(in: games, analyzedGameIDs: [2])

        #expect(pending.map(\.id) == [1, 3])
    }

    @Test
    func analyzesEveryGameInOrder() async {
        let recorder = CallRecorder()
        let coordinator = BatchAnalysisCoordinator()
        let analyze: BatchAnalysisCoordinator.AnalyzeGame = { game in
            await recorder.record(game.id ?? -1)
        }

        coordinator.start(games: [game(id: 7), game(id: 8), game(id: 9)], analyze: analyze)
        let summary = await finished(coordinator)

        #expect(summary?.analyzed == 3)
        #expect(summary?.isCleanSweep == true)
        #expect(await recorder.calls == [7, 8, 9])
    }

    /// The reason batch analysis is worth having is that it can be left
    /// alone, which it cannot be if one unreadable PGN ends the run.
    @Test
    func oneFailingGameDoesNotStopTheRest() async {
        let recorder = CallRecorder()
        let analyze: BatchAnalysisCoordinator.AnalyzeGame = { game in
            await recorder.record(game.id ?? -1)
            if game.id == 2 {
                throw MacGameAnalysisBackendError.invalidPGN
            }
        }
        let coordinator = BatchAnalysisCoordinator()

        coordinator.start(games: [game(id: 1), game(id: 2, white: "Broken"), game(id: 3)], analyze: analyze)
        let summary = await finished(coordinator)

        #expect(await recorder.calls == [1, 2, 3])
        #expect(summary?.analyzed == 2)
        #expect(summary?.failures.map(\.gameID) == [2])
        #expect(summary?.failures.first?.title == "Broken - Bob")
        #expect(summary?.isCleanSweep == false)
    }

    @Test
    func progressReportsTheGameCurrentlyBeingAnalyzed() async {
        let gate = Gate()
        let coordinator = BatchAnalysisCoordinator()
        let analyze: BatchAnalysisCoordinator.AnalyzeGame = { _ in
            await gate.wait()
        }

        coordinator.start(games: [game(id: 1, white: "First"), game(id: 2, white: "Second")], analyze: analyze)

        guard case .running(let progress) = coordinator.state else {
            Issue.record("Expected running, got \(coordinator.state)")
            return
        }
        #expect(progress.total == 2)
        #expect(progress.completed == 0)
        #expect(progress.currentTitle == "First - Bob")
        #expect(progress.fraction == 0)

        await gate.open()
        _ = await finished(coordinator)
    }

    /// Stop must mean stop: the games after the one in flight are never
    /// started, and the summary says the run was cut short rather than
    /// reporting a clean sweep of however many happened to finish.
    @Test
    func cancellingStopsBeforeTheRemainingGames() async {
        let recorder = CallRecorder()
        let gate = Gate()
        let coordinator = BatchAnalysisCoordinator()
        let analyze: BatchAnalysisCoordinator.AnalyzeGame = { game in
            await recorder.record(game.id ?? -1)
            await gate.wait()
        }

        coordinator.start(games: [game(id: 1), game(id: 2), game(id: 3)], analyze: analyze)
        while await recorder.calls.isEmpty {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        coordinator.cancel()
        await gate.open()
        let summary = await finished(coordinator)

        #expect(summary?.wasCancelled == true)
        #expect(summary?.isCleanSweep == false)
        #expect(await recorder.calls == [1])
    }

    @Test
    func startIsIgnoredWhileAlreadyRunning() async {
        let recorder = CallRecorder()
        let gate = Gate()
        let coordinator = BatchAnalysisCoordinator()
        let analyze: BatchAnalysisCoordinator.AnalyzeGame = { game in
            await recorder.record(game.id ?? -1)
            await gate.wait()
        }

        coordinator.start(games: [game(id: 1)], analyze: analyze)
        coordinator.start(games: [game(id: 2)], analyze: analyze)

        await gate.open()
        _ = await finished(coordinator)

        #expect(await recorder.calls == [1])
    }

    @Test
    func startIsIgnoredWithNoGames() {
        let coordinator = BatchAnalysisCoordinator()

        coordinator.start(games: []) { _ in }

        #expect(coordinator.state == .idle)
        #expect(coordinator.isRunning == false)
    }

    @Test
    func acknowledgeClearsTheSummary() async {
        let coordinator = BatchAnalysisCoordinator()

        coordinator.start(games: [game(id: 1)]) { _ in }
        _ = await finished(coordinator)
        coordinator.acknowledge()

        #expect(coordinator.state == .idle)
    }
}

private actor CallRecorder {
    private(set) var calls: [Int64] = []

    func record(_ id: Int64) {
        calls.append(id)
    }
}

private actor Gate {
    private var isOpen = false

    func open() {
        isOpen = true
    }

    func wait() async {
        while !isOpen {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}
