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

    // 4b. A depth-limited search terminates having reported either the depth
    //     it was asked for or one less, and waiting longer does not change
    //     that.
    //
    //     The tolerance is a measured property of Stockfish under MultiPV 3
    //     with multiple threads, not slack. It is deliberately pinned here
    //     because it was originally misdiagnosed: seeing depth 11 for a
    //     depth-12 request looks exactly like chesskit-engine's unordered
    //     response dispatch losing the last `info` behind the terminating
    //     `bestmove`. It is not. The drain below flushes everything still in
    //     flight by running a second search and consuming to its own
    //     bestmove; the depth never improves, so the missing line was never
    //     emitted, and no amount of waiting on the consumer side can
    //     recover it.
    //
    //     Consequence for callers: budget by depth for reproducibility, and
    //     report the depth actually reached rather than the depth asked for.
    //     Do not add a grace period waiting for the final iteration.
    //
    //     Do not "improve" this by sending depth and movetime in one `go`
    //     either: with both limits Stockfish reports one iteration fewer
    //     again. EngineService bounds a depth search with an explicit `stop`
    //     instead, which 4c covers.
    // A depth-limited search terminates, and the depth it reports by the
    // time the bestmove is seen is at most the depth requested and never
    // more than one short of it.
    //
    // The "one short" allowance is not slack, it is a measured property of
    // the transport: Stockfish always completes the requested iteration,
    // but chesskit-engine dispatches every response through its own
    // unstructured `Task`, so that iteration's `info` lines and the
    // terminating `bestmove` race. Eight runs at depth 12 here reported
    // [11, 11, 11, 12, 12, 11, 12, 11].
    //
    // A consumer that resolves on the bestmove alone therefore stores a
    // nondeterministically shallower evaluation, which is precisely what
    // depth budgeting exists to prevent. `BoundedSearchSession` closes that
    // window by staying open until the requested depth lands (bounded by
    // `EngineService.finalDepthGraceMilliseconds`); `BoundedSearchTests`
    // covers it deterministically, since a live engine cannot be driven
    // under XCTest.
    let requestedDepth = 12
    var observedDepths: [Int] = []
    var drainedDepths: [Int] = []
    for _ in 1...8 {
        let generation = await engine.setPosition(fen: startpos)
        await engine.go(depth: requestedDepth)
        var atBestMove = 0
        var afterDrain = 0
        var sawBestMove = false
        drainLoop: while let update = await iterator.next() {
            switch update {
            case let .info(info):
                guard info.generation == generation, info.multiPVRank ?? 1 == 1 else { continue }
                if sawBestMove {
                    afterDrain = max(afterDrain, info.depth ?? 0)
                } else {
                    atBestMove = max(atBestMove, info.depth ?? 0)
                    afterDrain = atBestMove
                }
            case let .bestMove(gen, _):
                guard gen == generation else {
                    // A stale bestmove from the flush search below.
                    break drainLoop
                }
                sawBestMove = true
                // Flush anything still in flight for this generation by
                // running a trivial search and consuming up to its own
                // terminating bestmove.
                _ = await engine.setPosition(fen: startpos)
                await engine.go(depth: 1)
            }
        }
        observedDepths.append(atBestMove)
        drainedDepths.append(afterDrain)
    }
    log("go(depth: \(requestedDepth)) x8 depth at bestmove:  \(observedDepths)")
    log("go(depth: \(requestedDepth)) x8 depth after drain:  \(drainedDepths)")
    guard observedDepths.allSatisfy({ $0 == requestedDepth || $0 == requestedDepth - 1 }) else {
        fail("go(depth: \(requestedDepth)) reported depths outside [\(requestedDepth - 1), \(requestedDepth)]: \(observedDepths)")
    }
    guard drainedDepths == observedDepths else {
        fail(
            "draining after bestmove changed the reported depth (\(observedDepths) -> \(drainedDepths)) - the final iteration IS delivered late, so EngineService should wait for it after all"
        )
    }
    guard observedDepths.allSatisfy({ $0 == requestedDepth || $0 == requestedDepth - 1 }) else {
        fail(
            "go(depth: \(requestedDepth)) reported unexpected depths \(observedDepths) - the depth limit is not being honoured"
        )
    }
    guard observedDepths.contains(requestedDepth) else {
        fail(
            "go(depth: \(requestedDepth)) never once delivered the requested depth across 8 runs \(observedDepths) - Stockfish is not completing the iteration at all, and the grace window cannot rescue it"
        )
    }

    // 4c. `stop` during a deep search still terminates with a real bestmove
    //     and leaves the partial lines usable. This is the mechanism
    //     EngineService's movetime ceiling relies on: it starts a
    //     depth-limited search and sends `stop` if the ceiling elapses
    //     first, so a pathological position degrades to a shallower real
    //     evaluation rather than to a thrown error.
    let generation4c = await engine.setPosition(fen: startpos)
    await engine.go(depth: 60)
    var stoppedDepth = 0
    var stoppedBestMove: String?
    var stopSent = false
    stoppedLoop: while let update = await iterator.next() {
        switch update {
        case let .info(info):
            guard info.generation == generation4c, info.multiPVRank ?? 1 == 1 else { continue }
            stoppedDepth = max(stoppedDepth, info.depth ?? 0)
            if !stopSent, stoppedDepth >= 10 {
                stopSent = true
                await engine.stop()
            }
        case let .bestMove(gen, move):
            guard gen == generation4c else { continue }
            stoppedBestMove = move
            break stoppedLoop
        }
    }
    guard let stoppedBestMove else {
        fail("stop() during a depth-60 search never produced a terminating bestmove")
    }
    guard stoppedDepth >= 10, stoppedDepth < 60 else {
        fail("stop() during a depth-60 search ended at depth \(stoppedDepth), expected a partial depth")
    }
    log("stop() mid-search: terminated at depth \(stoppedDepth), bestmove \(stoppedBestMove)")

    // 5. Generation isolation under rapid position switching: run a normal
    //    midgame search immediately followed by a bounded search on a
    //    stalemate position with no legal moves. F2 diagnosis: the listener
    //    task stamps updates with the generation current at *delivery* time,
    //    not the generation the search *started* under, so a trailing info
    //    from the midgame search can arrive after `setPosition` has already
    //    bumped the generation for the stalemate search and get misattributed
    //    to it. Repeated because this is timing-dependent (the diagnosis
    //    session saw contamination in two of three runs).
    let midgame = "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"
    let stalemate = "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"

    for iteration in 1...5 {
        let midGeneration = await engine.setPosition(fen: midgame)
        await engine.go(movetimeMilliseconds: 500)
        var midDone = false
        while !midDone {
            guard let update = await iterator.next() else {
                fail("iteration \(iteration): updates stream ended during midgame search")
            }
            if case let .bestMove(gen, _) = update, gen == midGeneration {
                midDone = true
            }
        }

        let stalemateGeneration = await engine.setPosition(fen: stalemate)
        await engine.go(movetimeMilliseconds: 500)
        var stalemateBestMove: String?
        var contaminated: AnalysisEngine.EngineInfo?
        while stalemateBestMove == nil {
            guard let update = await iterator.next() else {
                fail("iteration \(iteration): updates stream ended during stalemate search")
            }
            switch update {
            case let .info(info):
                guard info.generation == stalemateGeneration else { continue }
                // A position with no legal moves can legitimately produce a
                // terminal "score cp 0, empty PV" summary line from Stockfish
                // itself (verified live in isolation, no preceding search).
                // Real contamination carries an actual PV or a mate score,
                // neither of which this position can produce.
                if info.mateIn != nil || !info.principalVariation.isEmpty {
                    contaminated = info
                }
            case let .bestMove(gen, move):
                guard gen == stalemateGeneration else { continue }
                stalemateBestMove = move
            }
        }

        if let bad = contaminated {
            fail(
                "iteration \(iteration): stalemate search (no legal moves) received a scored info "
                    + "cp=\(bad.scoreCentipawns.map(String.init) ?? "nil") mate=\(bad.mateIn.map(String.init) ?? "nil") "
                    + "pv=\(bad.principalVariation.prefix(4).joined(separator: " ")) - cross-position contamination (F2)"
            )
        }
        guard stalemateBestMove == "(none)" else {
            fail("iteration \(iteration): stalemate bestmove was \(stalemateBestMove ?? "nil"), expected (none)")
        }
        log("iteration \(iteration): stalemate search clean, bestmove (none), no scored info leaked")
    }

    await engine.shutdown()
    log("OK: live Stockfish verified - real evals, side-to-move sign convention, mate scores, generation tags")
    exit(0)
}

RunLoop.main.run()
