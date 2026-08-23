# 2026-08-24

## Coach entry points clarity (P2.5)

Executed `handoffs/NEXT-SESSION-COACH-ENTRY-POINTS.md` to resolve ambiguity between the three entry points into the Coach panel (header toggle, board control button, and move/moment context menus) and make the active mode ("following board" vs "pinned position") visually and behaviorally obvious.

## Live diagnosis of current behavior

Before altering source code, built the unsigned Release binary (`scripts/release-build.sh`) and exercised all three entry points in a running app against an isolated database copy using `scripts/axprobe.swift` and `scripts/axclick.swift`.

1. **Compositing check**: Executed `scripts/capture-window.swift` and `screencapture -x -o -l<windowid>`. Window capture was refused with `could not create image from window` due to non-interactive agent execution lacking OS Screen Recording permissions, matching previous sessions' findings. Verification proceeded via direct AX-tree and synthesized event introspection.
2. **Header toggle retention bug verified**: Opening the Coach via the pane-header toggle is intended to follow the board. In the pre-existing code, if `pinnedChatIndex` was previously set by a context menu or button action, toggling the Coach open preserved the stale pin. Stepping the board forward left the Coach discussing the old ply rather than tracking the board.
3. **Subtle caption line**: The only distinction between modes was a tiny 6pt icon (`circle.fill` vs `pin.fill`) and a single 11pt secondary caption ("Following board · Move X" vs "Pinned to Move X").
4. **Action/state confusion on unpin button**: When pinned, the button was labeled "Pinned" with a `pin.slash` icon, naming the state rather than the action ("Follow board" or "Unpin").
5. **No indicator on move list or report**: Stepping the board away from a pinned move highlighted the board's current ply with standard selection styling, but provided zero visual or accessibility indication on the scoresheet or report regarding which move the Coach was actually anchored to.

## Design decisions and rationale

Applied `ui-ux-pro-max` and `frontend-design` principles while strictly adhering to the app's established warm-neutral and brass visual identity (no new colors, no dark-mode overrides, layout preserved):

1. **Two distinct mode banners in `ChatView`**:
   - **Following mode**: Renders a neutral `surface0` card bounded by a subtle hairline stroke. It displays an uppercase muted section badge ("FOLLOWING BOARD") with `dot.radiowaves.left.and.right`, the live board move in medium body text, helper copy ("Questions and suggestions track the board move by move."), and an explicit "Pin position" button.
   - **Pinned mode**: Renders a warm-brass card with a subtle selection background tint (`DesignColors.selection.opacity(0.55)`), a 1px brass border, and a prominent 3px solid brass (`DesignColors.accent`) left accent bar. It displays an uppercase brass badge ("PINNED POSITION") with `pin.fill`, the pinned move in semibold primary text, and an explicit action button: "Follow board" (`arrow.triangle.2.circlepath`), which clearly communicates the unpin action.
2. **Contextual board delta note and jump button**:
   - When the Coach is pinned to move X and the user steps the board to move Y, `ChatView`'s pinned card displays a live delta note: "Board is at Move Y" alongside a dedicated "View pinned move" button.
   - Clicking "View pinned move" jumps the board back to the pinned ply (`viewModel.jumpToPinnedPosition()`), bridging board state and Coach discussion.
3. **State transition integrity**:
   - Opening the Coach via the header toggle (`coachToggleButton`) now explicitly unpins (`viewModel.unpinChat()`), ensuring the primary top toggle always follows the board as expected.
   - Opening via "Ask Coach" in board controls, `CoachStageView`, or context menus explicitly pins to the targeted ply.
4. **Persistent pin badges on move rows and key moments**:
   - In `MoveListView`, whatever move is pinned displays a brass pin badge (`pin.fill` in `DesignColors.accent`) and includes `", pinned in Coach"` in its accessibility label.
   - In `GameReportView`, a pinned key moment card renders a brass `Pinned in Coach` capsule chip and includes `"pinned in Coach"` in its accessibility description.
5. **Standardized action copy**:
   - Move cell context menu: "Ask Coach about this move" (standardized from "Ask the coach about this move").
   - Key moment context menu: "Ask Coach about this moment" (standardized from "Ask the coach about this moment").
   - Board controls: "Ask Coach" with accessibility label "Ask Coach about current position (pins position)".

## Visual and accessibility confirmation

- **Verified via AX tree in running app**:
  - Following mode header renders `FOLLOWING BOARD` title and `Pin Coach to current board position` button.
  - Stepping board forward updates live move in header (`Following board · Move 1. d4`).
  - Clicking "Ask Coach" transitions Coach header to `PINNED POSITION` with `Unpin and follow board` button.
  - Stepping board away from pinned move renders `Board is at Move 2. e4` and `Jump board to pinned position: Move 1. d4` button.
  - `MoveListView` move cell for pinned move announces `Pawn d 4, Book, pinned in Coach`.
  - Clicking `Jump board to pinned position` aligns board and Coach back on `Move 1. d4`.
  - Clicking `Unpin and follow board` returns Coach header to `FOLLOWING BOARD`.
  - Closing Coach and reopening via header toggle opens in `FOLLOWING BOARD` mode.
  - Selecting key moment 9... and clicking "Ask Coach" pins to `Move 9... cxd5`, and key moment card in Review tab announces `pinned in Coach`.
- **Visual rendering notes**:
  - As noted above, native window compositing / screenshots were refused by macOS in this non-interactive agent environment; all verification was completed via direct Accessibility tree inspection, synthesized mouse events, and unit tests.

## Data safety verification

- Live sandbox database at `~/Library/Containers/com.chessanto.app/Data/Library/Application Support/Chessanto/chessanto.sqlite` was backed up before QA.
- QA ran strictly against a temporary disposable database copy under both required environment variables (`CHESSANTO_ENABLE_QA_DATABASE_OVERRIDE=1` and `CHESSANTO_DATABASE_PATH`).
- After completing all QA and unit tests, the live database was verified unchanged at SHA-256 `173a3693267582696c9ce2415d83cf6d3e158089fab9116d6fe550a5ca72c133`.
- The temporary QA directory was deleted.

## Validation results

1. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build` completed with `** BUILD SUCCEEDED **`.
2. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test` completed with `** TEST SUCCEEDED **` (175 tests across 34 suites passed, up from 174 baseline).
