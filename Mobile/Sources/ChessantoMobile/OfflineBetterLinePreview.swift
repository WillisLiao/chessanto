import ChessCore
import CompanionDomain
import Foundation

struct OfflineBetterLinePreview {
    struct Frame {
        let fen: String
        let san: String?
    }

    let frames: [Frame]

    init?(
        report: PortableAnalysisReport,
        moment: PortableKeyMoment
    ) {
        let sourcePly = max(0, moment.ply - 1)
        guard
            let source = report.positions.first(where: {
                $0.ply == sourcePly
            }),
            let line = report.rankedLines.first(where: {
                $0.ply == sourcePly && $0.rank == 1
            }),
            !line.principalVariationUCI.isEmpty
        else {
            return nil
        }
        frames = [
            Frame(fen: source.fen, san: nil)
        ] + ChessGame.replayLine(
            fromUCI: line.principalVariationUCI,
            startingFEN: source.fen
        ).map {
            Frame(fen: $0.resultingFEN, san: $0.san)
        }
    }
}
