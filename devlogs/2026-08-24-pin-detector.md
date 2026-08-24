# Absolute-pin detector

The P4.2 absolute-pin fact slice is implemented on `codex/roadmap-completion`.

## Definition

`ChessGame.absolutePins(in:)` inventories a rook, bishop, or queen that attacks through exactly one same-color non-king piece to that color's king.
The primitive covers both pinned colors and ignores relative pins, skewers, adjacent-king artifacts, same-color attackers, and lines with another blocker.
Results are side-to-move independent and sorted by pinned square, then pinning square.

`ThemeDetector.pin(input:ply:)` reports only one newly created relation after a strictly replay-verified mainline move.
The typed fact records the ply, attacker kind and square, pinned-piece kind and square, and king square.

## ChessKit-backed verification

The primitive removes each candidate blocker from a hypothetical FEN and asks ChessKit's legal-move generator which opposing slider can reach the king.
The original legal-move set must contain a capture of the candidate, which prevents a skewer or an unrelated already-checking slider from being reported as a pin.
No rook, bishop, or queen ray geometry is hand-written.

The detector validates the persisted transition through the repository's replay and FEN continuity checks.
It accepts only the documented transient en-passant normalization and the narrow real en-passant halfmove correction.
It compares pre- and post-move relations by physical attacker, pinned-piece, and king identities rather than by coordinates or kinds.
Promotion retains the pawn identity after its kind changes, castling moves the rook identity, and captures remove ordinary or en-passant identities.
An existing relation therefore survives a piece moving along its line, while a slider move, blocker departure, or interposition can create one new relation.
Ambiguous transitions with more than one new relation return no fact.

## Real-fixture review

The 56-position Magnus Carlsen versus artin10862 fixture was scanned across all 55 played plies.
The hand-reviewed fires are ply 25 with queen d5 pinning the pawn on f7 to king g8, ply 29 with bishop c4 pinning the pawn on f7 to king g8, and ply 31 with bishop e6 pinning the pawn on f7 to king g8.
Every fire survives `FactAuditor` verification.
None of those fires lands on an existing selected key moment, so report and Coach golden resources remain unchanged.

## Validation and non-goals

ChessCore primitive tests cover slider kinds, both colors, malformed positions, blockers, exclusions, ordering, and side-to-move independence.
AnalysisKit tests cover legal fixtures, identity preservation, strict rejection cases, auditing, neutral report text, selector stability, and the all-ply real-fixture scan.
CoachKit tests cover payload propagation, legacy decoding, and restricted prompt language.
The fact does not claim that a piece cannot move, is trapped, loses material, changes evaluation, causes the move classification, or caused any other outcome.
Pins are not selector candidates and do not feed beginner consequence ranking, takeaways, practice generation, or priority rules.
