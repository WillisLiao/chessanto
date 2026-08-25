# Devlog: Play vs Engine Core (2026-08-24)

## Public API Reference for UI Session

### 1. `LiveGameSession` (`App/Sources/Chessanto/Play/LiveGameSession.swift`)
State machine managing a live interactive game against an engine opponent.

```swift
@MainActor
final class LiveGameSession: ObservableObject {
    enum LiveGameStatus: Equatable, Sendable {
        case notStarted
        case userTurn
        case engineThinking
        case completed(GameOutcome)

        var isTerminal: Bool
    }

    let userSideSelection: PlayerSideSelection
    let userColor: ChessCore.PieceColor
    let engineColor: ChessCore.PieceColor
    let engineStrength: EngineStrength
    let engineOpponent: any EngineOpponent
    let store: GameStore
    let userProfile: UserProfileRecord?
    let startedAt: Date

    @Published private(set) var status: LiveGameStatus
    @Published private(set) var currentFEN: String
    @Published private(set) var position: BoardPosition
    @Published private(set) var lastMove: (from: BoardSquare, to: BoardSquare)?
    @Published private(set) var playedMovesSAN: [String]
    @Published private(set) var playedMovesUCI: [String]
    @Published private(set) var isCheck: Bool
    @Published private(set) var outcome: GameOutcome?
    @Published private(set) var persistedRecord: GameRecord?
    @Published private(set) var errorMessage: String?

    var isGameOver: Bool
    var isEngineThinking: Bool
    var moveCount: Int
    var sanAtCurrent: String?

    init(
        userSideSelection: PlayerSideSelection = .white,
        engineStrength: EngineStrength = .intermediate,
        engineOpponent: any EngineOpponent,
        store: GameStore,
        userProfile: UserProfileRecord? = nil,
        startedAt: Date = Date(),
        fixedColor: ChessCore.PieceColor? = nil
    )

    func start() async
    func playUserMove(from start: SquareCoordinate, to end: SquareCoordinate, promotion: PromotionKind = .queen) async -> Bool
    func playUserMove(uci: String) async -> Bool
    func playUserMove(san: String) async -> Bool
    func resign()
    func claimDraw() -> Bool
    func legalDestinations(from square: SquareCoordinate) -> [SquareCoordinate]
    func isPromotion(from start: SquareCoordinate, to end: SquareCoordinate) -> Bool
}
```

### 2. `EngineStrength` (`Packages/EngineKit/Sources/EngineKit/EngineStrength.swift`)
Maps difficulty presets to Stockfish UCI `Skill Level` (0-20), search depth cap, movetime cap, and estimated Elo.

```swift
public struct EngineStrength: Hashable, Sendable, Identifiable, Codable {
    public let id: String
    public let name: String
    public let skillLevel: Int
    public let depth: Int
    public let movetimeCeilingMilliseconds: Int
    public let estimatedElo: Int?

    public static let beginner: EngineStrength     // Skill 0, depth 3, 500ms, Elo ~600
    public static let casual: EngineStrength       // Skill 4, depth 5, 750ms, Elo ~1000
    public static let intermediate: EngineStrength // Skill 9, depth 8, 1000ms, Elo ~1400
    public static let advanced: EngineStrength     // Skill 14, depth 12, 1500ms, Elo ~1800
    public static let master: EngineStrength       // Skill 20, depth 18, 2500ms, Elo ~2400
    public static let allCases: [EngineStrength]
}
```

### 3. `EngineOpponent` (`Packages/EngineKit/Sources/EngineKit/EngineOpponent.swift`)
Protocol for opponent move generation, implemented by `EngineService`:

```swift
public protocol EngineOpponent: Sendable {
    func generateMove(in fen: String, strength: EngineStrength) async throws -> String
}
```

`EngineService.shared` conforms to `EngineOpponent` via `generateOpponentMove(in:strength:)`.

### 4. Game End & Outcome Primitives (`Packages/ChessCore/Sources/ChessCore/ChessGame.swift`)
```swift
public enum GameOutcome: Hashable, Sendable, Codable {
    case checkmate(winner: PieceColor)
    case stalemate
    case repetition
    case fiftyMoveRule
    case insufficientMaterial
    case resignation(resignedBy: PieceColor)

    public var resultString: String           // "1-0", "0-1", "1/2-1/2"
    public var isDraw: Bool
    public var winner: PieceColor?
    public var terminationDescription: String // e.g. "White won by checkmate"
}

public enum PlayerSideSelection: String, CaseIterable, Sendable, Codable {
    case white
    case black
    case random

    public func resolveColor() -> PieceColor
}
```

### 5. `GameSource.vsEngine` (`Packages/Persistence/Sources/Persistence/GameRecord.swift`)
```swift
public enum GameSource: String, Codable, Sendable {
    case chessCom
    case pgnImport
    case vsEngine
}
```

---

## Design Choices & Architecture

1. **Strict Move Legality Validation:**
   - Both user moves and engine moves are validated through `ChessGame.playMove(uci:at:)` and `Board(position:)`. No moves bypass legal validation.

2. **Skill Level Degradation with Safe Recovery:**
   - Opponent searches configure UCI `setoption name Skill Level value <N>` for degraded play and cap depth/movetime.
   - Searches serialize through `EngineService.runOnFIFOTail`.
   - `Skill Level` is safely restored to `20` immediately after search completion so coaching and batch analysis remain at full strength.

3. **Complete Game-End Detection:**
   - Detects checkmate, stalemate, insufficient material (K vs K, KN vs K, KB vs K, KB vs KB with same-colored bishops), fifty-move rule, and threefold repetition.
   - Resignation by either player awards the win to the opponent.

4. **Seamless Downstream Replay & Analysis:**
   - Finished games are automatically serialized to standard PGN with full metadata headers (`[Event "Play vs Engine"]`, `[Site "Chessanto"]`, `[Date "..."]`, `[White "..."]`, `[Black "..."]`, `[Result "..."]`, `[Termination "..."]`).
   - Saved as `GameRecord` with `source: .vsEngine` into `GameStore`.
   - Verified that saved games can be loaded directly into `GameReplayViewModel`, visualized, and analyzed through the standard analysis pipeline without modification.

---

## Verification

- `swift test --package-path Packages/ChessCore`: 67 tests passed.
- `swift test --package-path Packages/EngineKit`: 4 tests passed.
- `swift test --package-path Packages/Persistence`: 45 tests passed.
- `xcodebuild test -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS'`: 210 tests in 37 suites passed.
