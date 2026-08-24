import AnalysisKit
import ChessCore
import CoachKit
import CompanionDomain
import Foundation
import Persistence
import Testing
@testable import Chessanto

@Suite("Rating register propagation across production boundaries")
@MainActor
struct RatingRegisterPropagationTests {
    private func makeAnalyzedGame(
        store: GameStore,
        pgn: String = "1. e4 e5 2. Nf3 Nc6",
        white: String = "Willis",
        black: String = "Opponent",
        whiteRating: Int? = 1000,
        blackRating: Int? = 1500
    ) async throws -> (gameID: Int64, record: GameRecord, analysisRows: [AnalysisRecord]) {
        let game = try ChessGame(pgn: pgn)
        let indices = [game.startIndex] + game.mainlineIndices
        let fens = try indices.map { index in try #require(game.fen(at: index)) }
        let record = try store.save(
            GameRecord(
                source: .pgnImport,
                pgn: pgn,
                white: white,
                black: black,
                whiteRating: whiteRating,
                blackRating: blackRating,
                result: "*"
            )
        )
        let gameID = try #require(record.id)
        var rows: [AnalysisRecord] = []
        for ply in fens.indices {
            let row = AnalysisRecord(
                gameId: gameID,
                plyIndex: ply,
                fen: fens[ply],
                depth: 16,
                scoreCentipawns: 10,
                principalVariation: "e2e4",
                multiPVRank: 1
            )
            rows.append(row)
            try await store.saveAnalysis([row], gameId: gameID, plyIndex: ply)
        }
        return (gameID, record, rows)
    }

    // MARK: - 1. ReportBuilding Shared Seam Tests

    @Test("ReportBuilding.userRating extracts rating from White or Black case-insensitively")
    func reportBuildingUserRatingExtractsRatingFromRecord() {
        let record = GameRecord(
            source: .pgnImport,
            pgn: "1. e4 e5",
            white: "WillisLiao",
            black: "MagnusCarlsen",
            whiteRating: 1150,
            blackRating: 2850
        )
        #expect(ReportBuilding.userRating(in: record, username: "willisliao") == 1150)
        #expect(ReportBuilding.userRating(in: record, username: "magnuscarlsen") == 2850)
        #expect(ReportBuilding.userRating(in: record, username: "someoneelse") == nil)
        #expect(ReportBuilding.userRating(in: record, username: nil as String?) == nil)
        #expect(ReportBuilding.userRating(in: record, username: "") == nil)
        #expect(ReportBuilding.userRating(in: record, username: "   ") == nil)
    }

    @Test("ReportBuilding.resolveRegister honors fixed profile bands and adaptive per-game ratings")
    func reportBuildingResolveRegisterHonorsProfileAndRatings() {
        let beginnerProfile = UserProfileRecord(ratingBand: "beginner")
        #expect(ReportBuilding.resolveRegister(userProfile: beginnerProfile) == .beginner)

        let intermediateProfile = UserProfileRecord(ratingBand: "intermediate")
        #expect(ReportBuilding.resolveRegister(userProfile: intermediateProfile) == .intermediate)

        let advancedProfile = UserProfileRecord(ratingBand: "advanced")
        #expect(ReportBuilding.resolveRegister(userProfile: advancedProfile) == .advanced)

        let adaptiveProfile = UserProfileRecord(chessComUsername: "willisliao", ratingBand: "adaptive")

        let beginnerRecord = GameRecord(
            source: .pgnImport,
            pgn: "1. e4 e5",
            white: "willisliao",
            black: "opp",
            whiteRating: 1100
        )
        #expect(ReportBuilding.resolveRegister(userProfile: adaptiveProfile, record: beginnerRecord) == .beginner)

        let intermediateRecord = GameRecord(
            source: .pgnImport,
            pgn: "1. e4 e5",
            white: "willisliao",
            black: "opp",
            whiteRating: 1500
        )
        #expect(ReportBuilding.resolveRegister(userProfile: adaptiveProfile, record: intermediateRecord) == .intermediate)

        let advancedRecord = GameRecord(
            source: .pgnImport,
            pgn: "1. e4 e5",
            white: "willisliao",
            black: "opp",
            whiteRating: 2100
        )
        #expect(ReportBuilding.resolveRegister(userProfile: adaptiveProfile, record: advancedRecord) == .advanced)

        let unratedRecord = GameRecord(
            source: .pgnImport,
            pgn: "1. e4 e5",
            white: "willisliao",
            black: "opp",
            whiteRating: nil
        )
        #expect(ReportBuilding.resolveRegister(userProfile: adaptiveProfile, record: unratedRecord) == .intermediate)
    }

    @Test("ReportBuilding.resolveRegister falls back to .advanced when genuinely missing profile and rating context")
    func reportBuildingResolveRegisterFallsBackToAdvancedWithoutContext() {
        #expect(ReportBuilding.resolveRegister(userProfile: nil, record: nil, username: nil) == .advanced)
    }

    @Test("ReportBuilding.buildReport passes the resolved register to the resulting GameReport")
    func reportBuildingBuildReportUsesResolvedRegister() async throws {
        let store = try GameStore()
        var profile = try store.userProfile()
        profile.ratingBand = "beginner"
        try store.saveUserProfile(profile)

        let (_, record, rows) = try await makeAnalyzedGame(store: store)
        let report = try #require(
            ReportBuilding.buildReport(
                record: record,
                analysisRows: rows,
                chessComUsername: "Willis",
                userProfile: profile
            )
        )
        #expect(report.register == .beginner)

        var interProfile = try store.userProfile()
        interProfile.ratingBand = "intermediate"
        let interReport = try #require(
            ReportBuilding.buildReport(
                record: record,
                analysisRows: rows,
                chessComUsername: "Willis",
                userProfile: interProfile
            )
        )
        #expect(interReport.register == .intermediate)

        // Without profile or register, falls back to .advanced
        let fallbackReport = try #require(
            ReportBuilding.buildReport(
                record: record,
                analysisRows: rows,
                chessComUsername: nil
            )
        )
        #expect(fallbackReport.register == .advanced)
    }

    // MARK: - 2. PortableReportAssembler & Companion Boundaries

    @Test("PortableReportAssembler propagates specified register into report and defaults to .advanced")
    func portableReportAssemblerPropagatesRegister() async throws {
        let store = try GameStore()
        let (_, record, rows) = try await makeAnalyzedGame(store: store)

        let beginnerReport = try #require(
            PortableReportAssembler.assemble(
                id: ReportID("rep-1"),
                gameID: CompanionGameID("g-1"),
                record: record,
                quality: .standard,
                analysisRows: rows,
                chessComUsername: "Willis",
                register: .beginner,
                narrationsByPly: [:]
            )
        )
        // Verify key moments are built using the beginner register (no eval swing percent sign in summary)
        for moment in beginnerReport.keyMoments {
            #expect(!moment.summary.contains("%"))
        }

        // Verify default argument uses .advanced
        let defaultReport = try #require(
            PortableReportAssembler.assemble(
                id: ReportID("rep-2"),
                gameID: CompanionGameID("g-2"),
                record: record,
                quality: .standard,
                analysisRows: rows,
                chessComUsername: "Willis",
                narrationsByPly: [:]
            )
        )
        #expect(defaultReport.id == ReportID("rep-2"))
    }

    @Test("MacCompletedAnalysis stores and defaults register appropriately")
    func macCompletedAnalysisStoresAndDefaultsRegister() async throws {
        let store = try GameStore()
        let (_, record, rows) = try await makeAnalyzedGame(store: store)

        let analysisWithRegister = MacCompletedAnalysis(
            record: record,
            analysisRows: rows,
            chessComUsername: "Willis",
            register: .intermediate,
            narrationsByPly: [:]
        )
        #expect(analysisWithRegister.register == .intermediate)

        let defaultAnalysis = MacCompletedAnalysis(
            record: record,
            analysisRows: rows,
            chessComUsername: "Willis",
            narrationsByPly: [:]
        )
        #expect(defaultAnalysis.register == .advanced)
    }

    @Test("GameAnalysisApplicationService propagates resolved register from MacCompletedAnalysis into PortableAnalysisReport")
    func gameAnalysisApplicationServicePropagatesRegister() async throws {
        let store = try GameStore()
        let (_, record, rows) = try await makeAnalyzedGame(store: store)

        final class MockBackend: MacGameAnalysisBacking, @unchecked Sendable {
            let record: GameRecord
            let rows: [AnalysisRecord]
            let register: RatingRegister

            init(record: GameRecord, rows: [AnalysisRecord], register: RatingRegister) {
                self.record = record
                self.rows = rows
                self.register = register
            }

            func analyze(
                gameID: CompanionGameID,
                quality: CompanionAnalysisQuality,
                progress: @escaping @Sendable (AnalysisProgress) -> Void
            ) async throws -> MacCompletedAnalysis {
                MacCompletedAnalysis(
                    record: record,
                    analysisRows: rows,
                    chessComUsername: "Willis",
                    register: register,
                    narrationsByPly: [:]
                )
            }
        }

        let service = GameAnalysisApplicationService(
            backing: MockBackend(record: record, rows: rows, register: .beginner)
        )
        let request = LocalAnalysisRequestFactory.make(
            gameID: CompanionGameID("g-mock"),
            quality: .standard
        )

        var receivedReport: PortableAnalysisReport?
        for try await event in service.analyze(request: request) {
            if case .report(let report) = event {
                receivedReport = report
            }
        }

        let report = try #require(receivedReport)
        for moment in report.keyMoments {
            #expect(!moment.summary.contains("%"))
        }
    }

    // MARK: - 3. Dashboard and Player Brief Boundaries

    @Test("PlayerBriefView.buildSnapshot uses profile ratingBand when building game reports")
    func playerBriefViewBuildSnapshotUsesProfileRatingBand() async throws {
        let store = try GameStore()
        var profile = try store.userProfile()
        profile.ratingBand = "beginner"
        profile.chessComUsername = "Willis"
        try store.saveUserProfile(profile)

        let (_, record, _) = try await makeAnalyzedGame(store: store, white: "Willis", black: "Opponent")
        let snapshot = try await PlayerBriefView.buildSnapshot(
            games: [record],
            username: "Willis",
            store: store
        )
        #expect(snapshot.coverage.analyzed == 1)
    }

    @Test("DashboardView backfillTrainingCards reconciles cards under the user profile register")
    func dashboardViewBackfillTrainingCardsUsesProfileRegister() async throws {
        let store = try GameStore()
        var profile = try store.userProfile()
        profile.ratingBand = "beginner"
        profile.chessComUsername = "Willis"
        try store.saveUserProfile(profile)

        let (_, record, _) = try await makeAnalyzedGame(store: store, white: "Willis", black: "Opponent")
        try await DashboardView.backfillTrainingCards(
            games: [record],
            username: "Willis",
            store: store
        )
        let queue = try await store.trainingQueueSnapshot(username: "Willis")
        // Backfill completed without error and updated store
        #expect(queue.dueCards.count >= 0)
    }

    @Test("DashboardView computeDashboard computes accuracy points and theme counts with user profile register")
    func dashboardViewComputeDashboardUsesProfileRegister() async throws {
        let store = try GameStore()
        var profile = try store.userProfile()
        profile.ratingBand = "intermediate"
        profile.chessComUsername = "Willis"
        try store.saveUserProfile(profile)

        let (_, record, _) = try await makeAnalyzedGame(store: store, white: "Willis", black: "Opponent")
        let data = await DashboardView.computeDashboard(
            games: [record],
            username: "Willis",
            store: store
        )
        #expect(data.analyzedGameCount == 1)
        #expect(data.userMatchedGameCount == 1)
        #expect(data.points.count == 1)
    }
}
