import Foundation
import Persistence

/// Runs analysis over many games, one at a time.
///
/// Every aggregate surface in the app - Player Brief, the accuracy trend,
/// motif evidence, the review queue - needs a body of analyzed games, and
/// until now the only way to produce one was to open each game and press
/// Analyze. This is the missing verb.
///
/// Sequential by design, not by omission: there is one shared Stockfish and
/// `GameAnalysisApplicationService` already serializes on it, so running
/// games concurrently would queue inside the engine while making progress
/// unreportable and cancellation vague.
@MainActor
final class BatchAnalysisCoordinator: ObservableObject {
    /// Why a game in the batch produced nothing, kept per game so one bad
    /// PGN cannot end a fifty game run.
    struct Failure: Identifiable, Equatable {
        let gameID: Int64
        let title: String
        let reason: String

        var id: Int64 { gameID }
    }

    struct Progress: Equatable {
        let completed: Int
        let total: Int
        let currentTitle: String

        var fraction: Double {
            total == 0 ? 0 : Double(completed) / Double(total)
        }
    }

    struct Summary: Equatable {
        let analyzed: Int
        let failures: [Failure]
        let wasCancelled: Bool

        var isCleanSweep: Bool { failures.isEmpty && !wasCancelled }
    }

    enum State: Equatable {
        case idle
        case running(Progress)
        case finished(Summary)
    }

    typealias AnalyzeGame = @MainActor (GameRecord) async throws -> Void

    @Published private(set) var state: State = .idle

    private var task: Task<Void, Never>?

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// The games in `games` that have no analysis yet, in the order given.
    /// Batch analysis exists to fill gaps, so re-analyzing what is already
    /// done would spend hours to change nothing.
    static func unanalyzed(in games: [GameRecord], analyzedGameIDs: Set<Int64>) -> [GameRecord] {
        games.filter { game in
            guard let id = game.id else { return false }
            return !analyzedGameIDs.contains(id)
        }
    }

    /// The work is supplied per run rather than at construction: the thing
    /// that actually analyzes a game lives in an environment object the
    /// view cannot reach when it builds this coordinator.
    func start(games: [GameRecord], analyze analyzeGame: @escaping AnalyzeGame) {
        guard !isRunning, !games.isEmpty else { return }
        task?.cancel()
        state = .running(Progress(completed: 0, total: games.count, currentTitle: Self.title(for: games[0])))

        task = Task { [weak self] in
            guard let self else { return }
            var failures: [Failure] = []
            var analyzed = 0

            for (index, game) in games.enumerated() {
                if Task.isCancelled { break }
                self.state = .running(
                    Progress(completed: index, total: games.count, currentTitle: Self.title(for: game))
                )
                do {
                    try await analyzeGame(game)
                    analyzed += 1
                } catch is CancellationError {
                    break
                } catch {
                    // One unreadable PGN or one engine hiccup must not end
                    // the run - the whole point is leaving it unattended.
                    failures.append(
                        Failure(
                            gameID: game.id ?? -1,
                            title: Self.title(for: game),
                            reason: error.localizedDescription
                        )
                    )
                }
            }

            self.state = .finished(
                Summary(analyzed: analyzed, failures: failures, wasCancelled: Task.isCancelled)
            )
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// Returns to `.idle` so the summary can be dismissed without starting
    /// another run.
    func acknowledge() {
        guard case .finished = state else { return }
        state = .idle
    }

    static func title(for game: GameRecord) -> String {
        "\(game.white) - \(game.black)"
    }
}
