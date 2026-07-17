import Foundation

/// White-perspective eval label formatting, shared by the live eval bar
/// (`GameReplayViewModel`) and the coaching report templates so both speak
/// the same convention (`+1.2`, `-M3`, `1-0`/`0-1` for the terminal-mate
/// sentinel).
public enum EvalLabel {
    /// `|mateIn| == 99` is the terminal-mate-sentinel convention (a
    /// synthesized final-ply record for a game that ended in checkmate),
    /// not a literal "mate in 99" - see the M5 handoff's verified fact 1.
    public static func isTerminalSentinel(mateIn: Int?) -> Bool {
        guard let mateIn else { return false }
        return abs(mateIn) == 99
    }

    public static func format(scoreCentipawns: Int?, mateIn: Int?) -> String {
        if isTerminalSentinel(mateIn: mateIn) {
            return mateIn! > 0 ? "1-0" : "0-1"
        }
        if let mateIn {
            return mateIn > 0 ? "M\(mateIn)" : "-M\(abs(mateIn))"
        }
        if let cp = scoreCentipawns {
            return String(format: "%+.1f", Double(cp) / 100)
        }
        return "--"
    }
}
