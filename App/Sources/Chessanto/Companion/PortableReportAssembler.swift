import AnalysisKit
import ChessCore
import CoachKit
import CompanionDomain
import Foundation
import Persistence

/// Converts the Mac's persistence and analysis models into the complete,
/// platform-neutral report that the iPhone can keep and read offline.
enum PortableReportAssembler {
    static func assemble(
        id: ReportID,
        gameID: CompanionGameID,
        record: GameRecord,
        quality: CompanionAnalysisQuality,
        analysisRows: [AnalysisRecord],
        chessComUsername: String?,
        narrationsByPly: [Int: CoachNarration],
        generatedAt: Date = Date()
    ) -> PortableAnalysisReport? {
        guard
            let game = try? ChessGame(pgn: record.pgn),
            let input = ReportBuilding.buildInput(
                record: record,
                analysisRows: analysisRows,
                chessComUsername: chessComUsername
            )
        else {
            return nil
        }

        guard let report = ReportBuilder.build(input: input, openingBook: OpeningBook.shared) else {
            return nil
        }
        let indices = [game.startIndex] + game.mainlineIndices
        let mainlineSAN = game.mainlineIndices.compactMap {
            game.san(at: $0)
        }
        let positions = indices.enumerated().map { ply, index in
            PortablePosition(
                ply: ply,
                fen: game.fen(at: index) ?? input.plies[ply].fen,
                playedSAN: ply == 0 ? nil : game.san(at: index)
            )
        }

        let rowsByPly = Dictionary(grouping: analysisRows, by: \.plyIndex)
        let evaluations = input.plies.indices.map { ply in
            let rankOne = rowsByPly[ply]?.first(where: { $0.multiPVRank == 1 })
            return PortableEvaluation(
                ply: ply,
                scoreCentipawns: rankOne?.scoreCentipawns,
                mateIn: rankOne?.mateIn
            )
        }

        let rankedLines = input.plies.indices.flatMap { ply in
            (rowsByPly[ply] ?? [])
                .sorted { $0.multiPVRank < $1.multiPVRank }
                .map { row in
                    let uci = row.principalVariation.isEmpty
                        ? []
                        : row.principalVariation.split(separator: " ").map(String.init)
                    return PortableRankedLine(
                        ply: ply,
                        rank: row.multiPVRank,
                        depth: row.depth,
                        scoreCentipawns: row.scoreCentipawns,
                        mateIn: row.mateIn,
                        principalVariationUCI: uci,
                        principalVariationSAN: ChessGame.sanLine(
                            fromUCI: uci,
                            startingFEN: input.plies[ply].fen
                        )
                    )
                }
        }

        let classifications = classify(input: input)
        let portableClassifications: [PortableMoveClassification] = classifications.enumerated().compactMap { pair in
            let (offset, classification) = pair
            let ply = offset + 1
            guard let san = game.san(at: indices[ply]) else { return nil }
            return PortableMoveClassification(
                ply: ply,
                canonicalSAN: san,
                classification: classification.rawValue
            )
        }

        let portableMoments = report.keyMoments.compactMap { moment -> PortableKeyMoment? in
            guard moment.ply < indices.count, let playedSAN = game.san(at: indices[moment.ply]) else {
                return nil
            }
            let fallbackText = ReportText.momentSummary(moment, report: report)
            let narration = narrationsByPly[moment.ply]
            let auditedNarration = AuditedCoachNarration(
                id: NarrationID("\(id.rawValue)-ply-\(moment.ply)"),
                text: narration?.text ?? fallbackText,
                source: narrationSource(narration),
                mood: emotion(for: moment.evalSwing.classification)
            )
            return PortableKeyMoment(
                ply: moment.ply,
                canonicalPlayedSAN: playedSAN,
                classification: moment.evalSwing.classification.rawValue,
                summary: fallbackText,
                betterLineSAN: moment.betterMove?.lineSANs ?? [],
                playedContinuationSAN: playedContinuationSAN(
                    afterPly: moment.ply,
                    mainlineSAN: mainlineSAN
                ),
                narration: auditedNarration
            )
        }

        return PortableAnalysisReport(
            protocolVersion: .v1,
            id: id,
            gameID: gameID,
            generatedAt: generatedAt,
            analysisQuality: quality,
            metadata: PortableGameMetadata(
                white: record.white,
                black: record.black,
                result: record.result ?? "*",
                playedAt: record.playedAt,
                timeControl: record.timeControl
            ),
            pgn: record.pgn,
            positions: positions,
            evaluations: evaluations,
            rankedLines: rankedLines,
            classifications: portableClassifications,
            opening: report.opening.map {
                PortableOpening(eco: $0.eco, name: $0.name, deepestBookPly: $0.deepestBookPly)
            },
            keyMoments: portableMoments,
            takeaways: report.takeaways
        )
    }

    static func playedContinuationSAN(
        afterPly ply: Int,
        mainlineSAN: [String]
    ) -> [String] {
        Array(mainlineSAN.dropFirst(ply).prefix(10))
    }

    private static func classify(input: ReportInput) -> [MoveClassification] {
        let evaluations = input.plies.map { ply in
            let rankOne = ply.lines.first(where: { $0.rank == 1 })
            return PlyEvaluation(
                scoreCentipawns: rankOne?.scoreCentipawns,
                mateIn: rankOne?.mateIn,
                bestMoveUCI: rankOne?.principalVariationUCI.first
            )
        }
        let playedUCIs = input.plies.dropFirst().compactMap(\.playedUCI)
        guard playedUCIs.count + 1 == input.plies.count else { return [] }
        let whiteToMove = (1..<input.plies.count).map { $0 % 2 == 1 }
        return MoveClassifier.classify(
            positionEvaluations: evaluations,
            playedUCIs: playedUCIs,
            whiteToMove: whiteToMove
        )
    }

    private static func narrationSource(_ narration: CoachNarration?) -> NarrationSource {
        switch narration?.source {
        case .coach:
            return .verifiedCoach
        case .fallback:
            return .engineVerifiedFallback
        case nil:
            return .deterministicPrecheck
        }
    }

    private static func emotion(for classification: MoveClassification) -> CoachEmotion {
        switch classification {
        case .blunder, .mistake:
            return .concerned
        case .inaccuracy, .missedWin:
            return .encouraging
        case .brilliant, .best:
            return .delighted
        case .excellent, .good:
            return .instructive
        }
    }
}
