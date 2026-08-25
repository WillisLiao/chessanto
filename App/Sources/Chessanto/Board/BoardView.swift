import ChessCore
import SwiftUI

struct BoardView: View {
    let position: BoardPosition
    var lastMove: (from: BoardSquare, to: BoardSquare)?
    var flipped: Bool = false
    var theme: BoardTheme = .classic
    var showCoordinates: Bool = true
    var selectedSquare: BoardSquare?
    var legalDestinations: Set<BoardSquare> = []
    var hintSquares: Set<BoardSquare> = []
    /// Suggested-move arrows (engine best line, "Better was..." moves) -
    /// drawn green like most match-analysis tools (chess.com/Lichess),
    /// reusing the app's own move-quality green (`MoveClassification.best`)
    /// rather than an unrelated ad-hoc color.
    var arrows: [(from: BoardSquare, to: BoardSquare)] = []
    /// When set, the board is waiting for the mover to name a promotion
    /// piece and shows the picker over the promotion file.
    var pendingPromotion: BoardInteraction.PendingPromotion?
    var onSquareTapped: ((BoardSquare) -> Void)?
    /// Set alongside `onPieceDropped` to make the board draggable. Boards
    /// that leave both `nil` (line preview, report thumbnails) stay purely
    /// display-only and never install a drag gesture.
    var onPieceDragStarted: ((BoardSquare) -> Void)?
    var onPieceDropped: ((BoardSquare, BoardSquare) -> Void)?
    var onPromotionChosen: ((PromotionKind) -> Void)?
    var onPromotionCancelled: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The square a piece is currently being dragged off, and how far the
    /// pointer has travelled since. Held in the view because it is pure
    /// pointer state: nothing outside the board can act on a half-finished
    /// drag, and a drag that is abandoned must leave no trace.
    @State private var dragOrigin: BoardSquare?
    @State private var dragTranslation: CGSize = .zero

    /// The move currently sliding into place, and how much of the slide is
    /// left (1 at the origin square, 0 once it has arrived). Animating this
    /// scalar rather than the piece's `position` keeps the movement inside
    /// the piece layer, so nothing about the board's own geometry changes
    /// and the surrounding column never reflows.
    @State private var slidingMove: (from: BoardSquare, to: BoardSquare)?
    @State private var slideProgress: CGFloat = 0

    /// User-drawn arrows and circles for the position currently on the
    /// board. Owned here and cleared whenever the position changes - see
    /// `BoardAnnotations` for why they are not persisted.
    @State private var annotations = BoardAnnotations()

    /// The keyboard cursor, which IS the keyboard focus: the square arrow
    /// keys walk (moving real focus with it) and Space/Return activate via
    /// the button's own native action. Keeping cursor and focus as one thing
    /// avoids the split-brain failure mode where arrows move an internal
    /// cursor while Space activates whichever square button holds focus -
    /// which is exactly what happens under Full Keyboard Access.
    @FocusState private var focusedSquare: BoardSquare?

    private var isDraggable: Bool { onPieceDropped != nil && pendingPromotion == nil }

    /// Keyboard piece movement only applies where pieces can be moved;
    /// display-only boards (line preview, thumbnails) never take focus.
    private var isInteractive: Bool { onSquareTapped != nil }

    /// An `onChange`-comparable stand-in for the non-`Equatable` `lastMove`
    /// tuple.
    private var lastMoveKey: String? {
        lastMove.map { "\($0.from.algebraic)\($0.to.algebraic)" }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let squareSize = size / 8

            ZStack(alignment: .topLeading) {
                ForEach(0..<8, id: \.self) { row in
                    ForEach(0..<8, id: \.self) { col in
                        let square = square(atRow: row, col: col)
                        Button {
                            // A left click is the user moving on from
                            // whatever they had drawn, same as every other
                            // board.
                            annotations.clear()
                            onSquareTapped?(square)
                        } label: {
                            ZStack(alignment: .topLeading) {
                                baseColor(for: square)
                                if isLastMoveSquare(square) {
                                    theme.highlight
                                }
                                if square == selectedSquare {
                                    theme.selected
                                } else if legalDestinations.contains(square) {
                                    theme.destination
                                }
                                if hintSquares.contains(square) {
                                    theme.hint
                                    Rectangle()
                                        .strokeBorder(DesignColors.accent, lineWidth: max(squareSize * 0.06, 2))
                                }
                                if showCoordinates {
                                    coordinateOverlay(for: square, row: row, col: col, squareSize: squareSize)
                                }
                            }
                            .frame(width: squareSize, height: squareSize)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focused($focusedSquare, equals: square)
                        .position(
                            x: CGFloat(col) * squareSize + squareSize / 2,
                            y: CGFloat(row) * squareSize + squareSize / 2
                        )
                        .accessibilityIdentifier("square-\(square.algebraic)")
                        .accessibilityLabel(BoardAccessibility.squareLabel(piece: position.pieces[square], square: square))
                        .accessibilityValue(
                            BoardAccessibility.squareValue(
                                isSelected: square == selectedSquare,
                                isLegalDestination: legalDestinations.contains(square),
                                isHint: hintSquares.contains(square),
                                isLastMoveSquare: isLastMoveSquare(square)
                            )
                        )
                        .accessibilityAddTraits(
                            square == selectedSquare ? [.isSelected] : []
                        )
                    }
                }

                ForEach(0..<8, id: \.self) { row in
                    ForEach(0..<8, id: \.self) { col in
                        let square = square(atRow: row, col: col)
                        if let piece = position.pieces[square] {
                            let isDragged = square == dragOrigin
                            let slide = slideOffset(for: square, squareSize: squareSize)
                            PieceView(piece: piece, squareSize: squareSize)
                                .frame(width: squareSize, height: squareSize)
                                .scaleEffect(isDragged ? 1.08 : 1)
                                .shadow(
                                    color: Color.black.opacity(isDragged ? 0.3 : 0),
                                    radius: isDragged ? 8 : 0,
                                    y: isDragged ? 3 : 0
                                )
                                .position(
                                    x: CGFloat(col) * squareSize + squareSize / 2,
                                    y: CGFloat(row) * squareSize + squareSize / 2
                                )
                                .offset(isDragged ? dragTranslation : slide)
                                // The piece in hand and the piece arriving
                                // both have to clear whatever they pass over
                                // or land on, or a capture animates behind
                                // the piece it just took.
                                .zIndex(isDragged ? 2 : (slide == .zero ? 0 : 1))
                                .accessibilityIdentifier("piece-\(square.algebraic)")
                                // Pieces are spoken through their square's
                                // own label ("white pawn e4"); as separate
                                // elements they would be up to 32 floating,
                                // location-free announcements.
                                .accessibilityHidden(true)
                                .allowsHitTesting(false)
                        }
                    }
                }

                if let focusedSquare {
                    let (row, col) = rowCol(for: focusedSquare)
                    Rectangle()
                        .strokeBorder(DesignColors.accent, lineWidth: max(squareSize * 0.05, 2))
                        .frame(width: squareSize, height: squareSize)
                        .position(
                            x: CGFloat(col) * squareSize + squareSize / 2,
                            y: CGFloat(row) * squareSize + squareSize / 2
                        )
                        // The cursor ring itself must not block clicks or
                        // reads; it is pure focus indication. VoiceOver users
                        // navigate squares directly and never see this.
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                ForEach(Array(arrows.enumerated()), id: \.offset) { _, arrow in
                    arrowShape(from: arrow.from, to: arrow.to, squareSize: squareSize)
                        .fill(Color(NSColor(hex: "#6F9E4C")).opacity(0.75))
                        .allowsHitTesting(false)
                }

                ForEach(Array(annotations.circles), id: \.self) { square in
                    let (row, col) = rowCol(for: square)
                    Circle()
                        .strokeBorder(Self.annotationColor, lineWidth: max(squareSize * 0.07, 3))
                        .frame(width: squareSize * 0.9, height: squareSize * 0.9)
                        .position(
                            x: CGFloat(col) * squareSize + squareSize / 2,
                            y: CGFloat(row) * squareSize + squareSize / 2
                        )
                        .allowsHitTesting(false)
                }

                ForEach(Array(annotations.arrows), id: \.self) { arrow in
                    arrowShape(from: arrow.from, to: arrow.to, squareSize: squareSize)
                        .fill(Self.annotationColor)
                        .allowsHitTesting(false)
                }

                RightDragCatcher { start, end in
                    handleRightDrag(from: start, to: end, squareSize: squareSize)
                }
                .frame(width: size, height: size)

                if let pendingPromotion {
                    promotionPicker(for: pendingPromotion, squareSize: squareSize, boardSize: size)
                }
            }
            .frame(width: size, height: size)
            .simultaneousGesture(dragGesture(squareSize: squareSize), including: isDraggable ? .all : .none)
            // Keyboard-only piece movement: arrows walk the focused square
            // (establishing it on the last move when nothing is focused
            // yet), Space/Return press the focused square through its own
            // native button action, and a visible brass ring shows where
            // you are. Without this, playing a move needs a mouse even
            // though every other control in the app is keyboard-reachable.
            .focusable(isInteractive)
            .onMoveCommand { direction in
                guard let mapped = cursorDirection(for: direction) else { return }
                let current = focusedSquare ?? BoardAccessibility.initialCursor(lastMove: lastMove)
                focusedSquare = BoardAccessibility.neighbor(of: current, direction: mapped, flipped: flipped) ?? current
            }
            .onChange(of: lastMoveKey) { _, _ in
                startSlide()
                postMoveAnnouncement()
            }
            .onChange(of: position) { _, _ in
                // An annotation is about the position it was drawn on.
                // Showing a different one retires it.
                annotations.clear()
            }
            // Escape backs out of the picker - the shortcut anyone would
            // try first for a modal choice they did not mean to open.
            .onExitCommand {
                if pendingPromotion != nil {
                    onPromotionCancelled?()
                } else {
                    annotations.clear()
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Brass, the app's own accent - deliberately not the green the engine's
    /// suggestion arrows use, so what the user drew never reads as something
    /// the engine claimed.
    private static let annotationColor = DesignColors.accent.opacity(0.85)

    private func cursorDirection(for direction: MoveCommandDirection) -> CursorDirection? {
        switch direction {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        @unknown default: return nil
        }
    }

    /// Tells VoiceOver what just moved without requiring the user to
    /// re-walk the board. Announcements are speech, not motion, so they are
    /// posted regardless of Reduce Motion.
    private func postMoveAnnouncement() {
        guard let lastMove else { return }
        let text = BoardAccessibility.moveAnnouncement(position: position, lastMove: lastMove)
        AccessibilityNotification.Announcement(text).post()
    }

    private func handleRightDrag(from start: CGPoint, to end: CGPoint, squareSize: CGFloat) {
        guard let fromSquare = square(at: start, squareSize: squareSize),
            let toSquare = square(at: end, squareSize: squareSize)
        else { return }
        annotations.toggleArrow(from: fromSquare, to: toSquare)
    }

    /// Dragging runs *alongside* the per-square buttons rather than
    /// replacing them: a click still selects and moves (the accessible,
    /// keyboard-reachable path the AX QA scripts drive), while a press that
    /// travels far enough becomes a drag. The 4pt threshold is what keeps a
    /// slightly unsteady click from being read as a drag.
    private func dragGesture(squareSize: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragOrigin == nil {
                    guard let origin = square(at: value.startLocation, squareSize: squareSize),
                        position.pieces[origin] != nil
                    else { return }
                    dragOrigin = origin
                    onPieceDragStarted?(origin)
                }
                dragTranslation = value.translation
            }
            .onEnded { value in
                let origin = dragOrigin
                dragOrigin = nil
                dragTranslation = .zero
                guard let origin, let destination = square(at: value.location, squareSize: squareSize) else {
                    return
                }
                onPieceDropped?(origin, destination)
            }
    }

    /// Begins the arrival slide for whatever move just landed. Skipped
    /// entirely under Reduce Motion, which leaves the piece exactly where it
    /// belongs rather than moving it more slowly.
    private func startSlide() {
        guard let lastMove, !reduceMotion else {
            slidingMove = nil
            slideProgress = 0
            return
        }
        slidingMove = lastMove
        slideProgress = 1
        withAnimation(.easeOut(duration: 0.18)) {
            slideProgress = 0
        }
    }

    /// How far `square`'s piece still is from where it came from, in points.
    /// Zero for every piece except the one that just moved.
    private func slideOffset(for square: BoardSquare, squareSize: CGFloat) -> CGSize {
        guard let slidingMove, square == slidingMove.to, slideProgress > 0 else { return .zero }
        let (fromRow, fromCol) = rowCol(for: slidingMove.from)
        let (toRow, toCol) = rowCol(for: slidingMove.to)
        return CGSize(
            width: CGFloat(fromCol - toCol) * squareSize * slideProgress,
            height: CGFloat(fromRow - toRow) * squareSize * slideProgress
        )
    }

    /// The square under a point in board coordinates, or `nil` if the point
    /// fell outside the board - which is how a piece dragged off the edge
    /// returns home instead of moving somewhere arbitrary.
    private func square(at point: CGPoint, squareSize: CGFloat) -> BoardSquare? {
        let col = Int(floor(point.x / squareSize))
        let row = Int(floor(point.y / squareSize))
        guard (0..<8).contains(col), (0..<8).contains(row) else { return nil }
        return square(atRow: row, col: col)
    }

    /// The promotion chooser, drawn as a column of four pieces on the file
    /// the pawn just promoted on rather than as a detached dialog - the move
    /// is decided where the eye already is, which is how every mainstream
    /// board does it. The column grows from the promotion square toward the
    /// middle of the board, so it always fits whichever edge it lands on and
    /// whichever way the board is flipped.
    @ViewBuilder
    private func promotionPicker(
        for promotion: BoardInteraction.PendingPromotion,
        squareSize: CGFloat,
        boardSize: CGFloat
    ) -> some View {
        let (row, col) = rowCol(for: promotion.to)
        let direction: CGFloat = row == 0 ? 1 : -1

        // A scrim over the board makes the four pieces the only live thing
        // and gives the click-anywhere-to-cancel escape route a surface.
        // It is a real Button, not a tap gesture on a shape: the only way
        // out of the picker has to be reachable by keyboard and by assistive
        // technology, not just by a pointer.
        Button {
            onPromotionCancelled?()
        } label: {
            Rectangle()
                .fill(Color.black.opacity(0.42))
                .frame(width: boardSize, height: boardSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("promotion-cancel")
        .accessibilityLabel("Cancel promotion")

        ForEach(Array(PromotionKind.pickerOrder.enumerated()), id: \.element) { offset, kind in
            PromotionChoiceView(
                piece: DisplayPiece(color: promotion.color, kind: kind.displayKind),
                squareSize: squareSize
            ) {
                onPromotionChosen?(kind)
            }
            .position(
                x: CGFloat(col) * squareSize + squareSize / 2,
                y: (CGFloat(row) + direction * CGFloat(offset)) * squareSize + squareSize / 2
            )
            .accessibilityIdentifier("promote-to-\(kind.rawValue)")
            .accessibilityLabel("Promote to \(kind.rawValue)")
        }
    }

    /// A center-of-square-to-center-of-square arrow with a triangular head,
    /// the standard chess-analysis-tool move suggestion.
    private func arrowShape(from: BoardSquare, to: BoardSquare, squareSize: CGFloat) -> some Shape {
        let (fromRow, fromCol) = rowCol(for: from)
        let (toRow, toCol) = rowCol(for: to)
        let start = CGPoint(x: CGFloat(fromCol) * squareSize + squareSize / 2, y: CGFloat(fromRow) * squareSize + squareSize / 2)
        let end = CGPoint(x: CGFloat(toCol) * squareSize + squareSize / 2, y: CGFloat(toRow) * squareSize + squareSize / 2)
        return ArrowShape(start: start, end: end, lineWidth: squareSize * 0.16, headLength: squareSize * 0.42, headWidth: squareSize * 0.36)
    }

    private func rowCol(for square: BoardSquare) -> (row: Int, col: Int) {
        let col = flipped ? 7 - square.file : square.file
        let row = flipped ? square.rank : 7 - square.rank
        return (row, col)
    }

    private func square(atRow row: Int, col: Int) -> BoardSquare {
        let file = flipped ? 7 - col : col
        let rank = flipped ? row : 7 - row
        return BoardSquare(file: file, rank: rank)
    }

    private func baseColor(for square: BoardSquare) -> Color {
        let isLight = (square.file + square.rank) % 2 == 0
        return isLight ? theme.lightSquare : theme.darkSquare
    }

    private func isLastMoveSquare(_ square: BoardSquare) -> Bool {
        guard let lastMove else { return false }
        return square == lastMove.from || square == lastMove.to
    }

    /// File letter along the bottom edge, rank number along the left edge -
    /// the standard lichess/chess.com in-square placement, adjusted for
    /// board orientation.
    ///
    /// Sized at 22% of the square rather than the 16% this started at: a
    /// beginner still counting files reads these constantly, and at 16% they
    /// were the smallest text anywhere in the app. The 11pt floor keeps them
    /// legible on a board squeezed into a narrow column, and the opposite
    /// square color plus a bold weight is what carries contrast without
    /// putting a plate behind each glyph.
    @ViewBuilder
    private func coordinateOverlay(for square: BoardSquare, row: Int, col: Int, squareSize: CGFloat) -> some View {
        let font = Font.system(size: max(squareSize * 0.22, 11), weight: .bold)
        let color = baseColor(for: square) == theme.lightSquare ? theme.darkSquare : theme.lightSquare
        VStack {
            HStack {
                Spacer()
                if col == (flipped ? 0 : 7) {
                    Text("\(square.rank + 1)")
                        .font(font)
                        .foregroundStyle(color)
                        .padding(.trailing, 3)
                        .padding(.top, 2)
                }
            }
            Spacer()
            HStack {
                if row == (flipped ? 0 : 7) {
                    Text(String(UnicodeScalar(UInt8(97 + square.file))))
                        .font(font)
                        .foregroundStyle(color)
                        .padding(.leading, 3)
                        .padding(.bottom, 2)
                }
                Spacer()
            }
        }
        // Coordinates are decoration for sighted orientation; VoiceOver
        // already gets each square's name from the button's own label, so
        // announcing them again would read every edge square twice.
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A straight shaft with a triangular arrowhead from `start` to `end`,
/// shortened at both ends so it doesn't cover the piece glyphs it points
/// between.
private struct ArrowShape: Shape {
    let start: CGPoint
    let end: CGPoint
    let lineWidth: CGFloat
    let headLength: CGFloat
    let headWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 1 else { return Path() }
        let unit = CGPoint(x: dx / length, y: dy / length)
        let perpendicular = CGPoint(x: -unit.y, y: unit.x)

        let inset = length * 0.18
        let trueStart = CGPoint(x: start.x + unit.x * inset, y: start.y + unit.y * inset)
        let trueEnd = CGPoint(x: end.x - unit.x * inset, y: end.y - unit.y * inset)
        let shaftEnd = CGPoint(x: trueEnd.x - unit.x * headLength, y: trueEnd.y - unit.y * headLength)

        var path = Path()
        path.move(to: CGPoint(x: trueStart.x + perpendicular.x * lineWidth / 2, y: trueStart.y + perpendicular.y * lineWidth / 2))
        path.addLine(to: CGPoint(x: shaftEnd.x + perpendicular.x * lineWidth / 2, y: shaftEnd.y + perpendicular.y * lineWidth / 2))
        path.addLine(to: CGPoint(x: shaftEnd.x + perpendicular.x * headWidth / 2, y: shaftEnd.y + perpendicular.y * headWidth / 2))
        path.addLine(to: trueEnd)
        path.addLine(to: CGPoint(x: shaftEnd.x - perpendicular.x * headWidth / 2, y: shaftEnd.y - perpendicular.y * headWidth / 2))
        path.addLine(to: CGPoint(x: shaftEnd.x - perpendicular.x * lineWidth / 2, y: shaftEnd.y - perpendicular.y * lineWidth / 2))
        path.addLine(to: CGPoint(x: trueStart.x - perpendicular.x * lineWidth / 2, y: trueStart.y - perpendicular.y * lineWidth / 2))
        path.closeSubpath()
        return path
    }
}

/// One of the four promotion choices: the real piece artwork on a light
/// card, so a cburnett black king-shaped silhouette never has to be read
/// against a dark square. Hover raises the brass ring the rest of the app
/// uses for its interactive accent.
private struct PromotionChoiceView: View {
    let piece: DisplayPiece
    let squareSize: CGFloat
    let onSelect: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            onSelect()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: DesignShape.controlRadius)
                    .fill(DesignColors.surface2)
                RoundedRectangle(cornerRadius: DesignShape.controlRadius)
                    .strokeBorder(
                        isHovering ? DesignColors.accent : DesignColors.hairline,
                        lineWidth: isHovering ? max(squareSize * 0.05, 2) : 1
                    )
                Image(piece.assetNameForTesting)
                    .resizable()
                    .scaledToFit()
                    .frame(width: squareSize * 0.76, height: squareSize * 0.76)
            }
            .frame(width: squareSize * 0.94, height: squareSize * 0.94)
            .contentShape(RoundedRectangle(cornerRadius: DesignShape.controlRadius))
        }
        .buttonStyle(.plain)
        .shadow(color: Color.black.opacity(0.22), radius: 4, y: 1)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
    }
}

private struct PieceView: View {
    let piece: DisplayPiece
    let squareSize: CGFloat

    var body: some View {
        Image(piece.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: squareSize * 0.82, height: squareSize * 0.82)
    }
}

extension DisplayPiece {
    /// Asset catalog names for the cburnett piece set fetched by
    /// `scripts/fetch-pieces.sh` into `App/Resources/Pieces.xcassets`.
    /// Internal (not private) so `PieceAssetsTests` can assert every asset
    /// resolves to a real image.
    var assetNameForTesting: String { assetName }

    fileprivate var assetName: String {
        let colorLetter = color == .white ? "w" : "b"
        let kindLetter: String
        switch kind {
        case .pawn: kindLetter = "P"
        case .knight: kindLetter = "N"
        case .bishop: kindLetter = "B"
        case .rook: kindLetter = "R"
        case .queen: kindLetter = "Q"
        case .king: kindLetter = "K"
        }
        return "cburnett-\(colorLetter)\(kindLetter)"
    }
}

#Preview {
    BoardView(position: .previewStandard)
        .padding()
        .frame(width: 480, height: 480)
}

extension BoardPosition {
    static let previewStandard: BoardPosition = {
        var pieces: [BoardSquare: DisplayPiece] = [:]
        let backRank: [PieceKind] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for file in 0..<8 {
            pieces[BoardSquare(file: file, rank: 0)] = DisplayPiece(color: .white, kind: backRank[file])
            pieces[BoardSquare(file: file, rank: 1)] = DisplayPiece(color: .white, kind: .pawn)
            pieces[BoardSquare(file: file, rank: 6)] = DisplayPiece(color: .black, kind: .pawn)
            pieces[BoardSquare(file: file, rank: 7)] = DisplayPiece(color: .black, kind: backRank[file])
        }
        return BoardPosition(pieces: pieces)
    }()
}
