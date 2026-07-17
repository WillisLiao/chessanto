import Testing
@testable import AnalysisKit

struct EvalLabelTests {
    @Test func positiveScoreFormatsWithPlusSign() {
        #expect(EvalLabel.format(scoreCentipawns: 120, mateIn: nil) == "+1.2")
    }

    @Test func negativeScoreFormatsWithMinusSign() {
        #expect(EvalLabel.format(scoreCentipawns: -120, mateIn: nil) == "-1.2")
    }

    @Test func smallNegativeScoreDoesNotRenderAsNegativeZero() {
        // -4...-1 cp all round to 0.0 pawns; "%+.1f" alone renders this as
        // "-0.0", a real eval-string bug fixed in M8.
        for cp in -4...(-1) {
            #expect(EvalLabel.format(scoreCentipawns: cp, mateIn: nil) == "0.0", "cp=\(cp)")
        }
    }

    @Test func exactZeroFormatsAsZero() {
        #expect(EvalLabel.format(scoreCentipawns: 0, mateIn: nil) == "0.0")
    }

    @Test func smallPositiveScoreRoundsToZeroWithoutPlusSign() {
        // +1...+4 cp also round to 0.0 pawns and should not show a spurious "+".
        for cp in 1...4 {
            #expect(EvalLabel.format(scoreCentipawns: cp, mateIn: nil) == "0.0", "cp=\(cp)")
        }
    }

    @Test func mateInFormatsWithMPrefix() {
        #expect(EvalLabel.format(scoreCentipawns: nil, mateIn: 3) == "M3")
        #expect(EvalLabel.format(scoreCentipawns: nil, mateIn: -3) == "-M3")
    }

    @Test func terminalSentinelFormatsAsResult() {
        #expect(EvalLabel.format(scoreCentipawns: nil, mateIn: 99) == "1-0")
        #expect(EvalLabel.format(scoreCentipawns: nil, mateIn: -99) == "0-1")
    }

    @Test func nilValuesFormatAsDashes() {
        #expect(EvalLabel.format(scoreCentipawns: nil, mateIn: nil) == "--")
    }
}
