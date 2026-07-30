import AnalysisKit
import ChessCore
import Foundation
import Persistence
import Testing
@testable import Chessanto

struct TrainingDomainTests {
    /// Games here start from a bare king-and-pawn position rather than the
    /// standard array. Every legal first move from the standard array is a
    /// named opening in the bundled book, so a move-one key moment there is
    /// classified `.book` and correctly never becomes a training card -
    /// which would make these fixtures test the book exemption instead of
    /// the card factory.
    private static let outOfBookStartFEN = "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1"

    @Test
    func cardFactoryCanRepresentAnAuditedFirstMove() throws {
        let input = ReportInput(
            plies: [
                PlyRecord(
                    fen: Self.outOfBookStartFEN,
                    lines: [
                        RankedLine(
                            rank: 1,
                            scoreCentipawns: 0,
                            mateIn: nil,
                            principalVariationUCI: ["e1e2"],
                            depth: 16
                        )
                    ],
                    playedUCI: nil
                ),
                PlyRecord(
                    fen: "4k3/8/8/8/8/4P3/8/4K3 b - - 0 1",
                    lines: [
                        RankedLine(
                            rank: 1,
                            scoreCentipawns: -500,
                            mateIn: nil,
                            principalVariationUCI: ["e8d7"],
                            depth: 16
                        )
                    ],
                    playedUCI: "e2e3"
                )
            ],
            whiteName: "White",
            blackName: "Black",
            result: "*",
            chessComUsername: nil
        )
        let report = try #require(
            ReportBuilder.build(input: input, openingBook: OpeningBook.shared)
        )
        #expect(report.keyMoments.map(\.ply) == [1])

        let drafts = TrainingCardFactory.drafts(report: report, input: input)

        #expect(drafts.count == 1)
        #expect(drafts[0].sourcePly == 1)
        #expect(drafts[0].preMoveFEN == input.plies[0].fen)
    }

    @Test
    func cardFactoryUsesThePositionImmediatelyBeforeTheMissedMove() throws {
        let preMoveFEN = "4k3/8/8/8/8/4P3/8/4K3 b - - 0 1"
        let input = ReportInput(
            plies: [
                PlyRecord(
                    fen: Self.outOfBookStartFEN,
                    lines: [
                        RankedLine(
                            rank: 1,
                            scoreCentipawns: 0,
                            mateIn: nil,
                            principalVariationUCI: ["e1e2"],
                            depth: 16
                        )
                    ],
                    playedUCI: nil
                ),
                PlyRecord(
                    fen: preMoveFEN,
                    lines: [
                        RankedLine(
                            rank: 1,
                            scoreCentipawns: 0,
                            mateIn: nil,
                            principalVariationUCI: ["e8d7"],
                            depth: 16
                        )
                    ],
                    playedUCI: "e2e3"
                ),
                PlyRecord(
                    fen: "8/4k3/8/8/8/4P3/8/4K3 w - - 1 2",
                    lines: [
                        RankedLine(
                            rank: 1,
                            scoreCentipawns: 500,
                            mateIn: nil,
                            principalVariationUCI: ["e1e2"],
                            depth: 16
                        )
                    ],
                    playedUCI: "e8e7"
                )
            ],
            whiteName: "White",
            blackName: "Black",
            result: "*",
            chessComUsername: nil
        )
        let report = try #require(
            ReportBuilder.build(input: input, openingBook: OpeningBook.shared)
        )
        #expect(report.keyMoments.map(\.ply) == [2])

        let draft = try #require(
            TrainingCardFactory.drafts(report: report, input: input).first
        )

        #expect(draft.sourcePly == 2)
        #expect(draft.preMoveFEN == preMoveFEN)
        #expect(draft.sideToMove == .black)
        #expect(draft.rankedLines.first?.principalVariationUCI.first == "e8d7")

        let whitePlayerInput = ReportInput(
            plies: input.plies,
            whiteName: input.whiteName,
            blackName: input.blackName,
            result: input.result,
            chessComUsername: "WHITE"
        )
        let whitePlayerReport = try #require(
            ReportBuilder.build(
                input: whitePlayerInput,
                openingBook: OpeningBook.shared
            )
        )

        #expect(
            TrainingCardFactory.drafts(
                report: whitePlayerReport,
                input: whitePlayerInput
            ).isEmpty
        )
    }

    @Test
    func cachedTopLineIsAcceptedWithoutEngineSearch() async throws {
        let probe = SearchProbe()
        let evaluator = DefaultTrainingMoveEvaluator { _ in
            await probe.markSearched()
            return .centipawns(0)
        }

        let result = try await evaluator.evaluate(card: card(), attemptedUCI: "e2e4")

        #expect(result.outcome == .strong)
        #expect(result.lossCentipawns == 0)
        #expect(await probe.wasSearched == false)
    }

    @Test
    func centipawnLossUsesMoverPerspectiveForBlack() async throws {
        let evaluator = DefaultTrainingMoveEvaluator { _ in
            .centipawns(20)
        }
        let result = try await evaluator.evaluate(
            card: card(
                fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
                side: .black,
                rankedLines: [
                    RankedLine(rank: 1, scoreCentipawns: -60, mateIn: nil, principalVariationUCI: ["b8c6"], depth: 12)
                ]
            ),
            attemptedUCI: "g8f6"
        )

        #expect(result.outcome == .playable)
        #expect(result.lossCentipawns == 80)
    }

    @Test
    func illegalMoveIsRejectedBeforeEngineSearch() async throws {
        let probe = SearchProbe()
        let evaluator = DefaultTrainingMoveEvaluator { _ in
            await probe.markSearched()
            return .centipawns(0)
        }

        let result = try await evaluator.evaluate(card: card(), attemptedUCI: "e2e5")

        #expect(result.outcome == .incorrect)
        #expect(result.attemptedMoveSAN == nil)
        #expect(await probe.wasSearched == false)
    }

    @Test
    func mateScoresAreClassifiedWithoutFakeCentipawns() async throws {
        let evaluator = DefaultTrainingMoveEvaluator { _ in
            .mate(3)
        }
        let result = try await evaluator.evaluate(
            card: card(
                rankedLines: [
                    RankedLine(rank: 1, scoreCentipawns: nil, mateIn: 1, principalVariationUCI: ["e2e4"], depth: 12)
                ]
            ),
            attemptedUCI: "d2d4"
        )

        #expect(result.outcome == .playable)
        #expect(result.lossCentipawns == nil)
    }

    @Test
    func cachedLowerRankedLineIsGradedAgainstRankOne() async throws {
        let probe = SearchProbe()
        let evaluator = DefaultTrainingMoveEvaluator { _ in
            await probe.markSearched()
            return .centipawns(0)
        }
        let result = try await evaluator.evaluate(
            card: card(rankedLines: [
                RankedLine(rank: 1, scoreCentipawns: 40, mateIn: nil, principalVariationUCI: ["e2e4"], depth: 12),
                RankedLine(rank: 2, scoreCentipawns: -260, mateIn: nil, principalVariationUCI: ["d2d4"], depth: 12)
            ]),
            attemptedUCI: "d2d4"
        )

        #expect(result.outcome == .incorrect)
        #expect(result.lossCentipawns == 300)
        #expect(await probe.wasSearched == false)
    }

    @Test
    func cachedRankOneRemainsStrongWithoutEngineSearch() async throws {
        let probe = SearchProbe()
        let evaluator = DefaultTrainingMoveEvaluator { _ in
            await probe.markSearched()
            return .centipawns(-9999)
        }
        let result = try await evaluator.evaluate(
            card: card(rankedLines: [
                RankedLine(rank: 1, scoreCentipawns: 40, mateIn: nil, principalVariationUCI: ["e2e4"], depth: 12),
                RankedLine(rank: 2, scoreCentipawns: -260, mateIn: nil, principalVariationUCI: ["d2d4"], depth: 12)
            ]),
            attemptedUCI: "e2e4"
        )

        #expect(result.outcome == .strong)
        #expect(result.lossCentipawns == 0)
        #expect(await probe.wasSearched == false)
    }

    @Test
    func deliveringMateIsStrongEvenWhenCachedBestIsCentipawns() async throws {
        let probe = SearchProbe()
        let evaluator = DefaultTrainingMoveEvaluator { _ in
            await probe.markSearched()
            return .centipawns(0)
        }
        // 6k1/5ppp/8/8/8/8/8/R6K w - - 0 1, Ra1-a8 is a real back-rank mate:
        // the king on g8 is boxed in by its own pawns, and the open a8-h8
        // rank leaves no escape square.
        let result = try await evaluator.evaluate(
            card: card(
                fen: "6k1/5ppp/8/8/8/8/8/R6K w - - 0 1",
                rankedLines: [
                    RankedLine(rank: 1, scoreCentipawns: 500, mateIn: nil, principalVariationUCI: ["h1g2"], depth: 12)
                ]
            ),
            attemptedUCI: "a1a8"
        )

        #expect(result.outcome == .strong)
        #expect(result.lossCentipawns == nil)
        #expect(await probe.wasSearched == false)
    }

    @Test
    func slowerWinningMateIsStillCredited() async throws {
        let evaluator = DefaultTrainingMoveEvaluator { _ in .mate(4) }
        let result = try await evaluator.evaluate(
            card: card(rankedLines: [
                RankedLine(rank: 1, scoreCentipawns: nil, mateIn: 2, principalVariationUCI: ["e2e4"], depth: 12)
            ]),
            attemptedUCI: "d2d4"
        )

        #expect(result.outcome == .playable)
        #expect(result.lossCentipawns == nil)
    }

    @Test
    func losingAForcedMateIsNotStrong() async throws {
        let evaluator = DefaultTrainingMoveEvaluator { _ in .centipawns(500) }
        let result = try await evaluator.evaluate(
            card: card(rankedLines: [
                RankedLine(rank: 1, scoreCentipawns: nil, mateIn: 2, principalVariationUCI: ["e2e4"], depth: 12)
            ]),
            attemptedUCI: "d2d4"
        )

        #expect(result.outcome != .strong)
        #expect(result.outcome == .inaccurate)
    }

    @Test
    func walkingIntoMateIsIncorrect() async throws {
        let evaluator = DefaultTrainingMoveEvaluator { _ in .mate(-1) }
        let result = try await evaluator.evaluate(
            card: card(rankedLines: [
                RankedLine(rank: 1, scoreCentipawns: nil, mateIn: 3, principalVariationUCI: ["e2e4"], depth: 12)
            ]),
            attemptedUCI: "d2d4"
        )

        #expect(result.outcome == .incorrect)
    }

    @Test
    func stalematingMoveIsGradedWithoutEngineSearch() async throws {
        let probe = SearchProbe()
        let evaluator = DefaultTrainingMoveEvaluator { _ in
            await probe.markSearched()
            return .centipawns(500)
        }
        // 7k/8/6K1/8/8/8/5Q2/8 w - - 0 1, Qf2-f7 stalemates the king on h8:
        // g8/g7/h7 are all covered by the queen and king, with no check.
        let result = try await evaluator.evaluate(
            card: card(
                fen: "7k/8/6K1/8/8/8/5Q2/8 w - - 0 1",
                rankedLines: [
                    RankedLine(rank: 1, scoreCentipawns: 900, mateIn: nil, principalVariationUCI: ["g6g5"], depth: 12)
                ]
            ),
            attemptedUCI: "f2f7"
        )

        #expect(result.outcome == .incorrect)
        #expect(await probe.wasSearched == false)
    }

    @Test
    func terminalPositionsNeverCallTheEngine() async throws {
        let evaluator = DefaultTrainingMoveEvaluator { _ in
            Issue.record("evaluateAttemptedMove must not be called for a terminal position")
            return .centipawns(0)
        }
        // Same back-rank mate as deliveringMateIsStrongEvenWhenCachedBestIsCentipawns.
        _ = try await evaluator.evaluate(
            card: card(
                fen: "6k1/5ppp/8/8/8/8/8/R6K w - - 0 1",
                rankedLines: [
                    RankedLine(rank: 1, scoreCentipawns: 500, mateIn: nil, principalVariationUCI: ["h1g2"], depth: 12)
                ]
            ),
            attemptedUCI: "a1a8"
        )
    }

    @Test
    func blackToMoveMateOrientationIsCorrect() async throws {
        // White-perspective: best is mate(-3) (Black forces mate in 3),
        // attempted is mate(-2) (Black forces mate in 2, i.e. faster).
        let evaluator = DefaultTrainingMoveEvaluator { _ in .mate(-2) }
        let result = try await evaluator.evaluate(
            card: card(
                fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
                side: .black,
                rankedLines: [
                    RankedLine(rank: 1, scoreCentipawns: nil, mateIn: -3, principalVariationUCI: ["b8c6"], depth: 12)
                ]
            ),
            attemptedUCI: "g8f6"
        )

        #expect(result.outcome == .strong)
    }

    @Test
    func unavailableCachedScoreDoesNotCrashGrading() async throws {
        let evaluator = DefaultTrainingMoveEvaluator { _ in
            Issue.record("evaluateAttemptedMove must not be called when the cached best score is unavailable")
            return .centipawns(0)
        }
        let result = try await evaluator.evaluate(
            card: card(rankedLines: [
                RankedLine(rank: 1, scoreCentipawns: nil, mateIn: nil, principalVariationUCI: ["e2e4"], depth: 12)
            ]),
            attemptedUCI: "d2d4"
        )

        #expect(result.outcome == .incorrect)
        #expect(result.lossCentipawns == nil)
    }

    /// The board hands the evaluator whatever UCI the interaction produced.
    /// A promotion's engine UCI is five characters (`b7b8q`), so a card whose
    /// rank-one line is a promotion can only be answered correctly if the
    /// attempted move carries its promotion piece too.
    ///
    /// Position: white pawn b7, kings on e1 and h5. Promoting is neither
    /// check nor stalemate, so nothing terminal short-circuits the grading
    /// and the cached-line path is the one under test.
    private static let promotionFEN = "8/1P6/8/7k/8/8/8/4K3 w - - 0 1"

    @Test
    func promotionMatchesItsCachedRankOneLineWithoutEngineSearch() async throws {
        let probe = SearchProbe()
        let evaluator = DefaultTrainingMoveEvaluator { _ in
            await probe.markSearched()
            return .centipawns(-9999)
        }

        let result = try await evaluator.evaluate(
            card: card(
                fen: Self.promotionFEN,
                rankedLines: [
                    RankedLine(rank: 1, scoreCentipawns: 900, mateIn: nil, principalVariationUCI: ["b7b8q"], depth: 16)
                ]
            ),
            attemptedUCI: "b7b8q"
        )

        #expect(result.outcome == .strong)
        #expect(result.lossCentipawns == 0)
        #expect(result.attemptedMoveSAN == "b8=Q")
        #expect(await probe.wasSearched == false)
    }

    @Test
    func underpromotionIsReplayedAsTheChosenPieceRatherThanAQueen() async throws {
        let evaluator = DefaultTrainingMoveEvaluator { _ in .centipawns(300) }

        let result = try await evaluator.evaluate(
            card: card(
                fen: Self.promotionFEN,
                rankedLines: [
                    RankedLine(rank: 1, scoreCentipawns: 900, mateIn: nil, principalVariationUCI: ["b7b8q"], depth: 16)
                ]
            ),
            attemptedUCI: "b7b8n"
        )

        #expect(result.attemptedMoveSAN == "b8=N")
        #expect(result.outcome == .incorrect)
        #expect(result.lossCentipawns == 600)
    }

    /// A square pair cannot name a promotion, and the evaluator must not
    /// pretend otherwise. Before `replayLine` learned to reject it, `b7b8`
    /// replayed into a position with a *pawn on b8* and that illegal
    /// position was then sent to the engine to be scored. It is now refused
    /// outright, like any other move that cannot be played.
    @Test
    func squarePairUCIIsRefusedRatherThanScoredAsAnIllegalPosition() async throws {
        let probe = SearchProbe()
        let evaluator = DefaultTrainingMoveEvaluator { _ in
            await probe.markSearched()
            return .centipawns(-9999)
        }

        let result = try await evaluator.evaluate(
            card: card(
                fen: Self.promotionFEN,
                rankedLines: [
                    RankedLine(rank: 1, scoreCentipawns: 900, mateIn: nil, principalVariationUCI: ["b7b8q"], depth: 16)
                ]
            ),
            attemptedUCI: "b7b8"
        )

        #expect(result.outcome == .incorrect)
        #expect(result.attemptedMoveSAN == nil)
        #expect(await probe.wasSearched == false)
    }

    @Test
    func deterministicScheduleTransitionsToMasteredAfterThreeStrongRecalls() {
        let scheduler = DeterministicReviewScheduler()
        let now = Date(timeIntervalSince1970: 1_000)
        var record = TrainingCardRecord(
            id: 10,
            gameId: 1,
            sourcePly: 1,
            preMoveFEN: "fen",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: "[]",
            classification: "mistake",
            consecutiveSuccesses: 2,
            masteryState: "review"
        )

        record = scheduler.next(card: record, outcome: .strong, now: now)

        #expect(record.consecutiveSuccesses == 3)
        #expect(record.masteryState == "mastered")
        #expect(Calendar.current.dateComponents([.day], from: now, to: record.dueAt).day == 14)
    }

    @Test
    func playableResetsSuccessesAndIsDueTomorrow() {
        let scheduler = DeterministicReviewScheduler()
        let now = Date(timeIntervalSince1970: 1_000)
        let record = TrainingCardRecord(
            id: 10,
            gameId: 1,
            sourcePly: 1,
            preMoveFEN: "fen",
            sideToMove: "white",
            bestMoveUCI: "e2e4",
            rankedLinesJSON: "[]",
            classification: "mistake",
            consecutiveSuccesses: 2,
            masteryState: "review"
        )

        let updated = scheduler.next(card: record, outcome: .playable, now: now)

        #expect(updated.consecutiveSuccesses == 0)
        #expect(updated.masteryState == "learning")
        #expect(Calendar.current.dateComponents([.day], from: now, to: updated.dueAt).day == 1)
    }

    private func card(
        fen: String = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        side: ChessCore.PieceColor = .white,
        rankedLines: [RankedLine] = [
            RankedLine(rank: 1, scoreCentipawns: 40, mateIn: nil, principalVariationUCI: ["e2e4"], depth: 12),
            RankedLine(rank: 2, scoreCentipawns: 32, mateIn: nil, principalVariationUCI: ["d2d4"], depth: 12)
        ]
    ) -> TrainingCard {
        TrainingCard(
            id: 1,
            gameId: 1,
            sourcePly: 1,
            preMoveFEN: fen,
            sideToMove: side,
            rankedLines: rankedLines,
            classification: .mistake,
            themes: [],
            explanation: "Better was e4.",
            dueAt: Date(),
            consecutiveSuccesses: 0,
            masteryState: .new,
            lastResult: nil
        )
    }
}

private actor SearchProbe {
    private var searched = false

    var wasSearched: Bool { searched }

    func markSearched() {
        searched = true
    }
}
