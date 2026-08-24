import ChessCore
import Persistence
import Testing
@testable import Chessanto

@MainActor
struct GameReplayViewModelPGNHardeningTests {
    private let hikaruVsCasablancaPGN = """
    [Event "Live Chess"]
    [Site "Chess.com"]
    [Date "2026.07.17"]
    [Round "-"]
    [White "Hikaru"]
    [Black "Casablanca"]
    [Result "1-0"]
    [CurrentPosition "1r6/1PR5/8/3B4/1k2P2p/p2K3P/8/8 b - - 0 57"]
    [Timezone "UTC"]
    [ECO "D27"]
    [ECOUrl "https://www.chess.com/openings/Queens-Gambit-Accepted-Classical-Main-Line-Furman-Variation...9.Ne5-Ke7-10.Be2-Nbd7"]
    [UTCDate "2026.07.17"]
    [UTCTime "01:26:46"]
    [WhiteElo "3445"]
    [BlackElo "2900"]
    [TimeControl "180"]
    [Termination "Hikaru won by resignation"]
    [StartTime "01:26:46"]
    [EndDate "2026.07.17"]
    [EndTime "01:31:58"]
    [Link "https://www.chess.com/game/live/171673575376"]

    1. d4 {[%clk 0:03:00]} 1... d5 {[%clk 0:03:00]} 2. Nf3 {[%clk 0:02:59.9]} 2... Nf6 {[%clk 0:02:59]} 3. c4 {[%clk 0:02:59.2]} 3... dxc4 {[%clk 0:02:58.2]} 4. e3 {[%clk 0:02:58.2]} 4... a6 {[%clk 0:02:56.8]} 5. Bxc4 {[%clk 0:02:56.3]} 5... e6 {[%clk 0:02:56.1]} 6. O-O {[%clk 0:02:54.6]} 6... c5 {[%clk 0:02:55.5]} 7. dxc5 {[%clk 0:02:54.2]} 7... Bxc5 {[%clk 0:02:54.8]} 8. Qxd8+ {[%clk 0:02:52.8]} 8... Kxd8 {[%clk 0:02:54.7]} 9. Be2 {[%clk 0:02:49.1]} 9... Ke7 {[%clk 0:02:50.7]} 10. Ne5 {[%clk 0:02:43.2]} 10... Nbd7 {[%clk 0:02:48.6]} 11. Nd3 {[%clk 0:02:42.7]} 11... Bd6 {[%clk 0:02:47.6]} 12. Nd2 {[%clk 0:02:41.2]} 12... b5 {[%clk 0:02:40.9]} 13. Nb3 {[%clk 0:02:32.6]} 13... Bb7 {[%clk 0:02:36.3]} 14. Na5 {[%clk 0:02:31.5]} 14... Bd5 {[%clk 0:02:35.7]} 15. f3 {[%clk 0:02:31.1]} 15... Rhc8 {[%clk 0:02:14.7]} 16. Bd2 {[%clk 0:02:20.4]} 16... Ne5 {[%clk 0:02:00]} 17. Nb4 {[%clk 0:02:17.3]} 17... Nc4 {[%clk 0:01:46.1]} 18. Nxd5+ {[%clk 0:02:06.1]} 18... exd5 {[%clk 0:01:46]} 19. Nxc4 {[%clk 0:02:01.5]} 19... dxc4 {[%clk 0:01:43.6]} 20. e4 {[%clk 0:01:55.3]} 20... Bc5+ {[%clk 0:01:42.4]} 21. Kh1 {[%clk 0:01:54.7]} 21... Rd8 {[%clk 0:01:41.8]} 22. Bc3 {[%clk 0:01:53]} 22... Bd4 {[%clk 0:01:34.2]} 23. Bb4+ {[%clk 0:01:52.5]} 23... Ke6 {[%clk 0:01:33.7]} 24. Rab1 {[%clk 0:01:52.4]} 24... a5 {[%clk 0:01:32.1]} 25. Be1 {[%clk 0:01:51.1]} 25... Nd7 {[%clk 0:01:27.5]} 26. a4 {[%clk 0:01:49.4]} 26... Nc5 {[%clk 0:01:11]} 27. axb5 {[%clk 0:01:47.9]} 27... Nd3 {[%clk 0:01:10.3]} 28. b3 {[%clk 0:01:41.1]} 28... Bc5 {[%clk 0:01:03.7]} 29. bxc4 {[%clk 0:01:37.4]} 29... Nxe1 {[%clk 0:01:03.1]} 30. Rfxe1 {[%clk 0:01:36.6]} 30... g5 {[%clk 0:00:58.9]} 31. b6 {[%clk 0:01:33.3]} 31... Bb4 {[%clk 0:00:53.6]} 32. Rec1 {[%clk 0:01:30.6]} 32... Rac8 {[%clk 0:00:51.9]} 33. c5 {[%clk 0:01:19.5]} 33... Rxc5 {[%clk 0:00:49.3]} 34. Rxc5 {[%clk 0:01:18.9]} 34... Bxc5 {[%clk 0:00:49.2]} 35. b7 {[%clk 0:01:18.1]} 35... Rb8 {[%clk 0:00:48]} 36. Bc4+ {[%clk 0:01:17.2]} 36... Ke7 {[%clk 0:00:46.3]} 37. Rb5 {[%clk 0:01:14.6]} 37... Bb4 {[%clk 0:00:44.4]} 38. g3 {[%clk 0:01:12.9]} 38... f6 {[%clk 0:00:40.5]} 39. Bd5 {[%clk 0:01:11.7]} 39... Kd6 {[%clk 0:00:33.6]} 40. Rb6+ {[%clk 0:01:10.7]} 40... Kc5 {[%clk 0:00:32.8]} 41. Ra6 {[%clk 0:01:04.9]} 41... Kb5 {[%clk 0:00:29.1]} 42. Ra8 {[%clk 0:01:04.2]} 42... Bd6 {[%clk 0:00:28.7]} 43. Kg2 {[%clk 0:01:03.8]} 43... a4 {[%clk 0:00:27.5]} 44. Kf2 {[%clk 0:01:03.2]} 44... a3 {[%clk 0:00:25.3]} 45. Ke2 {[%clk 0:01:02.7]} 45... Kb4 {[%clk 0:00:24.4]} 46. Kd3 {[%clk 0:01:00.9]} 46... h5 {[%clk 0:00:22.9]} 47. Ke3 {[%clk 0:00:58.1]} 47... Bc5+ {[%clk 0:00:20.7]} 48. Ke2 {[%clk 0:00:56.8]} 48... Bd6 {[%clk 0:00:20.6]} 49. Kd3 {[%clk 0:00:56.1]} 49... h4 {[%clk 0:00:19.4]} 50. gxh4 {[%clk 0:00:54]} 50... gxh4 {[%clk 0:00:19.3]} 51. h3 {[%clk 0:00:53.5]} 51... Bf4 {[%clk 0:00:18.9]} 52. Ra6 {[%clk 0:00:51.2]} 52... Be5 {[%clk 0:00:16.1]} 53. f4 {[%clk 0:00:50.5]} 53... Bxf4 {[%clk 0:00:15]} 54. Rxf6 {[%clk 0:00:50.1]} 54... Bc7 {[%clk 0:00:14.5]} 55. Ra6 {[%clk 0:00:49.3]} 55... Kc5 {[%clk 0:00:13.2]} 56. Rc6+ {[%clk 0:00:48.2]} 56... Kb4 {[%clk 0:00:12.4]} 57. Rxc7 {[%clk 0:00:48.1]} 1-0
    """

    @Test func gameReplayViewModelLoadsGameWithDisambiguatedCaptureCleanly() throws {
        let store = try GameStore()
        let record = GameRecord(
            id: 42,
            source: .chessCom,
            pgn: hikaruVsCasablancaPGN,
            white: "Hikaru",
            black: "Casablanca",
            result: "1-0"
        )
        let viewModel = GameReplayViewModel(record: record, store: store)

        #expect(viewModel.loadError == nil)
        #expect(viewModel.chessGame != nil)
        #expect(viewModel.moveIndices.count == 114)
        #expect(viewModel.fens.count == 114)
        #expect(viewModel.fens.last == "1r6/1PR5/8/3B4/1k2P2p/p2K3P/8/8 b - - 0 57")
    }

    @Test func reportBuildingInputConstructsSuccessfullyFromFailingGame() throws {
        let record = GameRecord(
            id: 42,
            source: .chessCom,
            pgn: hikaruVsCasablancaPGN,
            white: "Hikaru",
            black: "Casablanca",
            result: "1-0"
        )
        let reportInput = buildReportInput(record: record, analyses: [])
        #expect(reportInput != nil)
        #expect(reportInput?.plies.count == 114)
        #expect(reportInput?.whiteName == "Hikaru")
        #expect(reportInput?.blackName == "Casablanca")
    }
}
