import AnalysisKit
import ChessCore
import CoachKit
import CompanionDomain
import Foundation
import Persistence

enum MacGameAnalysisBackendError: LocalizedError {
    case missingGame
    case invalidPGN
    case engineUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingGame:
            return "This game is no longer available on the Mac."
        case .invalidPGN:
            return "The Mac could not replay this game's PGN."
        case .engineUnavailable(let reason):
            return reason
        }
    }
}

@MainActor
final class MacGameAnalysisBackend: MacGameAnalysisBacking {
    private let store: GameStore
    private let engine: EngineService
    private let coach: CoachService
    private let mappingStore: CompanionGameMappingStore

    init(
        store: GameStore,
        engine: EngineService,
        coach: CoachService,
        mappingStore: CompanionGameMappingStore
    ) {
        self.store = store
        self.engine = engine
        self.coach = coach
        self.mappingStore = mappingStore
    }

    func analyze(
        gameID: CompanionGameID,
        quality: CompanionAnalysisQuality,
        progress: @escaping @Sendable (AnalysisProgress) -> Void
    ) async throws -> MacCompletedAnalysis {
        let localGameID = try await mappingStore.localGameID(for: gameID)
        guard let record = try store.game(id: localGameID) else {
            throw MacGameAnalysisBackendError.missingGame
        }
        guard let game = try? ChessGame(pgn: record.pgn) else {
            throw MacGameAnalysisBackendError.invalidPGN
        }
        let indices = [game.startIndex] + game.mainlineIndices
        let fens = indices.compactMap { game.fen(at: $0) }
        guard fens.count == indices.count else {
            throw MacGameAnalysisBackendError.invalidPGN
        }

        await engine.start()
        guard engine.isStarted else {
            throw MacGameAnalysisBackendError.engineUnavailable(
                engine.unavailableReason ?? "Analysis is unavailable on this Mac."
            )
        }

        let terminalMateWhiteWins: Bool? = {
            guard
                let last = indices.last,
                game.san(at: last)?.hasSuffix("#") == true
            else {
                return nil
            }
            return (indices.count - 1) % 2 == 1
        }()

        try await engine.analyze(
            gameId: localGameID,
            fens: fens,
            quality: AnalysisQuality(quality),
            store: store,
            terminalMateWhiteWins: terminalMateWhiteWins
        ) { done, total in
            progress(
                AnalysisProgress(
                    completedPlies: done,
                    totalPlies: total
                )
            )
        }

        let analysisRows = try await store.analysis(gameId: localGameID)
        let userProfile = try store.userProfile()
        let chessComUsername = userProfile.chessComUsername
        var narrationsByPly: [Int: CoachNarration] = [:]
        if
            let input = ReportBuilding.buildInput(
                record: record,
                analysisRows: analysisRows,
                chessComUsername: chessComUsername
            ),
            let report = ReportBuilder.build(
                input: input,
                openingBook: OpeningBook.shared
            )
        {
            narrationsByPly = await coach.portableNarrations(
                report: report,
                input: input,
                userProfile: userProfile,
                userRating: rating(
                    for: record,
                    chessComUsername: chessComUsername
                ),
                executor: engine
            )
        }

        return MacCompletedAnalysis(
            record: record,
            analysisRows: analysisRows,
            chessComUsername: chessComUsername,
            narrationsByPly: narrationsByPly
        )
    }

    private func rating(
        for record: GameRecord,
        chessComUsername: String?
    ) -> Int? {
        guard let username = chessComUsername, !username.isEmpty else {
            return nil
        }
        if record.white.caseInsensitiveCompare(username) == .orderedSame {
            return record.whiteRating
        }
        if record.black.caseInsensitiveCompare(username) == .orderedSame {
            return record.blackRating
        }
        return nil
    }
}

private extension AnalysisQuality {
    init(_ quality: CompanionAnalysisQuality) {
        switch quality {
        case .fast:
            self = .fast
        case .standard:
            self = .standard
        case .deep:
            self = .deep
        }
    }
}
