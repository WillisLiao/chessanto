import EngineKit
import Foundation

// Live smoke run for AnalysisEngine + in-process Stockfish 17.
//
//     swift run --package-path Packages/EngineKit engine-smoke
//
// Exits 0 only if a real search produced real evaluations with the expected
// side-to-move sign convention and mate detection. Run this after touching
// EngineKit or bumping chesskit-engine.
//
// Three chesskit-engine facts shape everything here (verified against its
// source, 0.7.0):
//
// - `Engine.start()` dup2()s the process's stdout into the engine's read
//   pipe, so print() stops reaching the terminal once the engine is up.
//   All output below goes to stderr.
// - Engine output arrives via NSFileHandle run-loop notifications scheduled
//   on the main thread, so the main thread must sit in a running run loop;
//   all engine work happens off it in a detached task. (XCTest doesn't
//   guarantee this, which is why upstream's own Stockfish tests are
//   disabled - hence an executable, not a test.)
// - Stockfish is compiled with NNUE_EMBEDDING_OFF and auto-loads networks
//   only from Bundle.main, which a CLI binary doesn't have. Searching with
//   no network loaded makes Stockfish exit() the whole process, so the
//   networks are passed explicitly via `setoption` below.

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func fail(_ message: String) -> Never {
    log("FAIL: \(message)")
    exit(1)
}

// #filePath = <repo>/Packages/EngineKit/Sources/engine-smoke/main.swift
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let netsDir = repoRoot.appendingPathComponent("App/Resources")
let bigNet = netsDir.appendingPathComponent("nn-1111cefa1111.nnue")
let smallNet = netsDir.appendingPathComponent("nn-37f18f62d772.nnue")

// Watchdog: the three shallow searches below finish in seconds even in a
// debug build; anything near this limit means the run loop plumbing broke.
Task.detached {
    try? await Task.sleep(for: .seconds(300))
    fail("timed out after 300s - engine responses are not arriving")
}

Task.detached {
    for net in [bigNet, smallNet] where !FileManager.default.fileExists(atPath: net.path) {
        fail("missing \(net.path) - run scripts/fetch-nnue.sh first")
    }

    let engine = AnalysisEngine()
    var iterator = engine.updates.makeAsyncIterator()

    await engine.start(multipv: 3)
    log("engine started")

    await engine.setOption(name: "EvalFile", value: bigNet.path)
    await engine.setOption(name: "EvalFileSmall", value: smallNet.path)
    await engine.setOption(name: "Hash", value: "256")

    struct SearchResult {
        var rank1Info: AnalysisEngine.EngineInfo?
        var bestMove: String
    }

    func search(fen: String, depth: Int) async -> SearchResult {
        let generation = await engine.setPosition(fen: fen)
        await engine.go(depth: depth)
        var rank1Info: AnalysisEngine.EngineInfo?
        while let update = await iterator.next() {
            switch update {
            case let .info(info):
                guard info.generation == generation,
                    info.multiPVRank ?? 1 == 1,
                    info.scoreCentipawns != nil || info.mateIn != nil
                else { continue }
                rank1Info = info
            case let .bestMove(gen, move):
                guard gen == generation else { continue }
                return SearchResult(rank1Info: rank1Info, bestMove: move)
            }
        }
        fail("updates stream ended before bestmove arrived")
    }

    // 1. Start position: a sane, roughly balanced eval and a real PV.
    let startpos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    let r1 = await search(fen: startpos, depth: 15)
    guard let i1 = r1.rank1Info, let cp1 = i1.scoreCentipawns, let d1 = i1.depth else {
        fail("startpos: no scored rank-1 info received")
    }
    log(
        "startpos: depth \(d1), cp \(cp1), pv \(i1.principalVariation.prefix(6).joined(separator: " ")), bestmove \(r1.bestMove)"
    )
    guard abs(cp1) < 150 else { fail("startpos eval \(cp1)cp is not a sane opening eval") }
    guard !i1.principalVariation.isEmpty else { fail("startpos: empty PV") }

    // 2. White to move without his queen: the reported score must be
    //    strongly negative, which pins down the side-to-move (not
    //    white-perspective) sign convention everything in M2 relies on.
    let queenOdds = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNB1KBNR w KQkq - 0 1"
    let r2 = await search(fen: queenOdds, depth: 12)
    guard let i2 = r2.rank1Info, let cp2 = i2.scoreCentipawns else {
        fail("queen-odds: no scored rank-1 info received")
    }
    log("queen-odds (white to move, no white queen): cp \(cp2)")
    guard cp2 < -300 else {
        fail("queen-odds eval \(cp2) should be clearly negative for the side to move")
    }

    // 3. Black to move, mate in one (fool's mate): a mate score - positive,
    //    because the side to move is the one mating - and the mating move.
    let foolsMate = "rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq g3 0 2"
    let r3 = await search(fen: foolsMate, depth: 10)
    guard let i3 = r3.rank1Info else { fail("fools-mate: no rank-1 info received") }
    log("fools-mate (black to move): mateIn \(i3.mateIn.map(String.init) ?? "nil"), bestmove \(r3.bestMove)")
    guard i3.mateIn == 1 else { fail("expected mateIn 1, got \(i3.mateIn.map(String.init) ?? "nil")") }
    guard r3.bestMove == "d8h4" else { fail("expected bestmove d8h4 (Qh4#), got \(r3.bestMove)") }

    // 4. go(movetimeMilliseconds:): a fixed-time search still produces a
    //    scored rank-1 info and a terminating bestmove.
    let generation4 = await engine.setPosition(fen: startpos)
    await engine.go(movetimeMilliseconds: 300)
    var movetimeInfo: AnalysisEngine.EngineInfo?
    var movetimeBestMove: String?
    searchLoop: while let update = await iterator.next() {
        switch update {
        case let .info(info):
            guard info.generation == generation4,
                info.multiPVRank ?? 1 == 1,
                info.scoreCentipawns != nil || info.mateIn != nil
            else { continue }
            movetimeInfo = info
        case let .bestMove(gen, move):
            guard gen == generation4 else { continue }
            movetimeBestMove = move
            break searchLoop
        }
    }
    guard movetimeInfo != nil, movetimeBestMove != nil else {
        fail("go(movetimeMilliseconds:) did not produce a scored info + bestmove")
    }
    log("go(movetime: 300ms): cp \(movetimeInfo?.scoreCentipawns.map(String.init) ?? "nil"), bestmove \(movetimeBestMove!)")

    await engine.shutdown()
    log("OK: live Stockfish verified - real evals, side-to-move sign convention, mate scores, generation tags")
    exit(0)
}

RunLoop.main.run()
