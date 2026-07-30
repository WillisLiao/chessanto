import ChessCore
import Testing
@testable import Chessanto

struct BoardInteractionTests {
    /// A pawn on b7, kings on e1 and h5 - promoting is neither check nor
    /// stalemate, so the only thing under test is the interaction itself.
    private static let promotionFEN = "8/1P6/8/7k/8/8/8/4K3 w - - 0 1"
    private static let openingFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    private func context(fen: String) -> BoardInteraction.Context {
        let game = ChessGame(startingFEN: fen)
        return BoardInteraction.Context(
            position: BoardPositionMapper.position(fromFEN: fen) ?? .empty,
            legalDestinations: { square in
                Set(
                    game.legalMoves(from: SquareCoordinate(notation: square.algebraic), at: game.startIndex)
                        .compactMap { BoardSquare(algebraic: $0.notation) }
                )
            },
            isPromotion: { from, to in
                game.isPromotion(
                    from: SquareCoordinate(notation: from.algebraic),
                    to: SquareCoordinate(notation: to.algebraic),
                    at: game.startIndex
                )
            }
        )
    }

    /// Force-unwrapped on purpose: every square here is a hardcoded literal,
    /// so a typo should fail loudly at the line that made it rather than be
    /// smuggled into an expectation as `nil`.
    private func square(_ algebraic: String) -> BoardSquare {
        BoardSquare(algebraic: algebraic)!
    }

    @Test
    func clickingAPieceThenALegalDestinationPlaysTheMove() {
        let context = context(fen: Self.openingFEN)
        var interaction = BoardInteraction()

        #expect(interaction.select(square("e2"), context: context) == .none)
        #expect(interaction.selectedSquare == square("e2"))

        let resolution = interaction.select(square("e4"), context: context)

        #expect(resolution == .play(BoardInteraction.Move(from: square("e2"), to: square("e4"), promotion: nil)))
        #expect(interaction.selectedSquare == nil)
    }

    @Test
    func moveUCIIsFourCharactersForAnOrdinaryMove() {
        let move = BoardInteraction.Move(from: square("e2"), to: square("e4"), promotion: nil)
        #expect(move.uci == "e2e4")
    }

    @Test
    func moveUCICarriesThePromotionPiece() {
        let from = square("b7")
        let to = square("b8")
        #expect(BoardInteraction.Move(from: from, to: to, promotion: .queen).uci == "b7b8q")
        #expect(BoardInteraction.Move(from: from, to: to, promotion: .rook).uci == "b7b8r")
        #expect(BoardInteraction.Move(from: from, to: to, promotion: .bishop).uci == "b7b8b")
        #expect(BoardInteraction.Move(from: from, to: to, promotion: .knight).uci == "b7b8n")
    }

    @Test
    func clickingAgainOnTheSelectedSquareDeselects() {
        let context = context(fen: Self.openingFEN)
        var interaction = BoardInteraction()

        _ = interaction.select(square("e2"), context: context)
        #expect(interaction.select(square("e2"), context: context) == .none)
        #expect(interaction.selectedSquare == nil)
    }

    @Test
    func clickingAnotherOwnPieceRetargetsInsteadOfFailingTheMove() {
        let context = context(fen: Self.openingFEN)
        var interaction = BoardInteraction()

        _ = interaction.select(square("e2"), context: context)
        #expect(interaction.select(square("d2"), context: context) == .none)
        #expect(interaction.selectedSquare == square("d2"))
    }

    @Test
    func clickingAnEmptyIllegalSquareClearsTheSelection() {
        let context = context(fen: Self.openingFEN)
        var interaction = BoardInteraction()

        _ = interaction.select(square("e2"), context: context)
        #expect(interaction.select(square("e6"), context: context) == .none)
        #expect(interaction.selectedSquare == nil)
    }

    @Test
    func clickingAnEmptySquareFirstSelectsNothing() {
        let context = context(fen: Self.openingFEN)
        var interaction = BoardInteraction()

        #expect(interaction.select(square("e4"), context: context) == .none)
        #expect(interaction.selectedSquare == nil)
    }

    @Test
    func legalDestinationsFollowTheSelectedPiece() {
        let context = context(fen: Self.openingFEN)
        var interaction = BoardInteraction()

        #expect(interaction.legalDestinations(context: context).isEmpty)
        _ = interaction.select(square("g1"), context: context)
        #expect(interaction.legalDestinations(context: context) == [square("f3"), square("h3")])
    }

    @Test
    func promotionAsksForAPieceInsteadOfPlayingImmediately() {
        let context = context(fen: Self.promotionFEN)
        var interaction = BoardInteraction()

        _ = interaction.select(square("b7"), context: context)
        let resolution = interaction.select(square("b8"), context: context)

        #expect(resolution == .awaitingPromotionPiece)
        #expect(interaction.pendingPromotion?.from == square("b7"))
        #expect(interaction.pendingPromotion?.to == square("b8"))
        #expect(interaction.pendingPromotion?.color == .white)
        #expect(interaction.selectedSquare == nil)
    }

    @Test
    func choosingAPromotionPieceProducesTheFiveCharacterMove() {
        let context = context(fen: Self.promotionFEN)
        var interaction = BoardInteraction()

        _ = interaction.select(square("b7"), context: context)
        _ = interaction.select(square("b8"), context: context)
        let resolution = interaction.choosePromotion(.knight)

        guard case .play(let move) = resolution else {
            Issue.record("Expected a move, got \(resolution)")
            return
        }
        #expect(move.uci == "b7b8n")
        #expect(interaction.pendingPromotion == nil)
    }

    @Test
    func cancellingThePromotionPlaysNothingAndClearsTheBoard() {
        let context = context(fen: Self.promotionFEN)
        var interaction = BoardInteraction()

        _ = interaction.select(square("b7"), context: context)
        _ = interaction.select(square("b8"), context: context)
        interaction.cancelPromotion()

        #expect(interaction.pendingPromotion == nil)
        #expect(interaction.selectedSquare == nil)
    }

    @Test
    func clicksAreIgnoredWhileThePromotionPickerIsOpen() {
        let context = context(fen: Self.promotionFEN)
        var interaction = BoardInteraction()

        _ = interaction.select(square("b7"), context: context)
        _ = interaction.select(square("b8"), context: context)

        #expect(interaction.select(square("e1"), context: context) == .awaitingPromotionPiece)
        #expect(interaction.pendingPromotion != nil)
        #expect(interaction.selectedSquare == nil)
    }

    @Test
    func droppingOnALegalSquarePlaysTheMove() {
        let context = context(fen: Self.openingFEN)
        var interaction = BoardInteraction()

        interaction.beginDrag(from: square("g1"), context: context)
        #expect(interaction.selectedSquare == square("g1"))

        let resolution = interaction.drop(from: square("g1"), to: square("f3"), context: context)

        #expect(resolution == .play(BoardInteraction.Move(from: square("g1"), to: square("f3"), promotion: nil)))
        #expect(interaction.selectedSquare == nil)
    }

    /// A drop is not a click: releasing over a square the piece cannot reach
    /// returns the piece rather than retargeting the selection to whatever
    /// happened to be under the pointer.
    @Test
    func droppingOnAnIllegalSquarePlaysNothingAndSelectsNothing() {
        let context = context(fen: Self.openingFEN)
        var interaction = BoardInteraction()

        interaction.beginDrag(from: square("g1"), context: context)
        let resolution = interaction.drop(from: square("g1"), to: square("d4"), context: context)

        #expect(resolution == .none)
        #expect(interaction.selectedSquare == nil)
    }

    @Test
    func droppingOntoTheBackRankAsksForAPromotionPiece() {
        let context = context(fen: Self.promotionFEN)
        var interaction = BoardInteraction()

        interaction.beginDrag(from: square("b7"), context: context)
        let resolution = interaction.drop(from: square("b7"), to: square("b8"), context: context)

        #expect(resolution == .awaitingPromotionPiece)
        #expect(interaction.pendingPromotion?.to == square("b8"))
    }

    @Test
    func draggingFromAnEmptySquareSelectsNothing() {
        let context = context(fen: Self.openingFEN)
        var interaction = BoardInteraction()

        interaction.beginDrag(from: square("e4"), context: context)

        #expect(interaction.selectedSquare == nil)
    }

    @Test
    func resetClearsBothSelectionAndPendingPromotion() {
        let context = context(fen: Self.promotionFEN)
        var interaction = BoardInteraction()

        _ = interaction.select(square("b7"), context: context)
        _ = interaction.select(square("b8"), context: context)
        interaction.reset()

        #expect(interaction.selectedSquare == nil)
        #expect(interaction.pendingPromotion == nil)
    }

    @Test
    func blackPromotionCarriesBlackArtworkIntoThePicker() {
        let context = context(fen: "4k3/8/8/8/8/8/6p1/4K3 b - - 0 1")
        var interaction = BoardInteraction()

        _ = interaction.select(square("g2"), context: context)
        _ = interaction.select(square("g1"), context: context)

        #expect(interaction.pendingPromotion?.color == .black)
    }

    @Test
    func pickerOffersQueenFirstThenTheUnderpromotions() {
        #expect(PromotionKind.pickerOrder == [.queen, .rook, .bishop, .knight])
    }
}
