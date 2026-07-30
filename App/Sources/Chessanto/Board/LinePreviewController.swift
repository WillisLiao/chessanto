import ChessCore
import Foundation

struct LinePreviewStep {
    let position: BoardPosition
    let lastMove: (from: BoardSquare, to: BoardSquare)?
    let san: String?
    /// Whether reaching this step took a piece, so playback can sound the
    /// same as the real board does.
    let isCapture: Bool
}

/// A read-only board playback of an engine line.
///
/// It owns no store and never touches the replay variation tree, so watching
/// a line cannot create user-authored variation records.
@MainActor
final class LinePreviewController: ObservableObject {
    let label: String
    let steps: [LinePreviewStep]

    @Published private(set) var stepIndex = 0
    @Published private(set) var isPlaying = false

    init(label: String, startingFEN: String, uciMoves: [String]) {
        self.label = label
        let start = LinePreviewStep(
            position: BoardPositionMapper.position(fromFEN: startingFEN) ?? .empty,
            lastMove: nil,
            san: nil,
            isCapture: false
        )
        let replayed = ChessGame.replayLine(fromUCI: uciMoves, startingFEN: startingFEN)
        self.steps = [start] + replayed.map { move in
            let from = BoardSquare(algebraic: String(move.uci.prefix(2)))
            let to = BoardSquare(algebraic: String(move.uci.dropFirst(2).prefix(2)))
            return LinePreviewStep(
                position: BoardPositionMapper.position(fromFEN: move.resultingFEN) ?? .empty,
                lastMove: from.flatMap { from in to.map { (from: from, to: $0) } },
                san: move.san,
                isCapture: move.capturedPieceKind != nil
            )
        }
    }

    var current: LinePreviewStep {
        steps[stepIndex]
    }

    var stepCount: Int {
        steps.count
    }

    var canStepForward: Bool {
        stepIndex + 1 < steps.count
    }

    var canStepBackward: Bool {
        stepIndex > 0
    }

    func play() {
        isPlaying = canStepForward
    }

    func pause() {
        isPlaying = false
    }

    func replay() {
        stepIndex = 0
        play()
    }

    func autoplayTick() {
        guard isPlaying, canStepForward else {
            isPlaying = false
            return
        }
        advance()
        if !canStepForward {
            isPlaying = false
        }
    }

    func stepForward() {
        pause()
        guard canStepForward else { return }
        advance()
    }

    /// Moves one step further into the line and sounds the move that got
    /// there. Stepping back, replaying from the start, and jumping stay
    /// silent - none of them is a move being made.
    private func advance() {
        stepIndex += 1
        BoardSounds.shared.play(current.isCapture ? .capture : .move)
    }

    func stepBackward() {
        pause()
        guard canStepBackward else { return }
        stepIndex -= 1
    }

    func jumpToStart() {
        pause()
        stepIndex = 0
    }

    func jumpToEnd() {
        pause()
        stepIndex = max(0, steps.count - 1)
    }
}
