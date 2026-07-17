import AppKit
import Testing
@testable import Chessanto

struct PieceAssetsTests {
    @Test func allTwelveCburnettPieceAssetsResolveToNonNilImages() {
        let colors: [PieceColor] = [.white, .black]
        let kinds: [PieceKind] = [.pawn, .knight, .bishop, .rook, .queen, .king]
        for color in colors {
            for kind in kinds {
                let piece = DisplayPiece(color: color, kind: kind)
                let image = NSImage(named: piece.assetNameForTesting)
                #expect(image != nil, "missing asset for \(piece.assetNameForTesting)")
            }
        }
    }
}
