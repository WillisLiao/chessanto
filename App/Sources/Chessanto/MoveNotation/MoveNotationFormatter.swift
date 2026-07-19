import Foundation
import SwiftUI

enum MoveNotationStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case standard
    case pieceNames

    var id: String { rawValue }

    var settingsLabel: String {
        switch self {
        case .standard:
            "Standard chess notation"
        case .pieceNames:
            "Full piece names"
        }
    }

    var settingsExample: String {
        switch self {
        case .standard:
            "Nf3"
        case .pieceNames:
            "Knight f3"
        }
    }
}

struct RenderedMoveNotation: Equatable, Sendable {
    let visual: String
    let spoken: String
}

struct MoveNotationFormatter: Equatable, Sendable {
    let style: MoveNotationStyle

    init(style: MoveNotationStyle = .standard) {
        self.style = style
    }

    func move(_ san: String) -> RenderedMoveNotation {
        guard let parsed = ParsedMove(san: san) else {
            return RenderedMoveNotation(visual: san, spoken: san)
        }

        return RenderedMoveNotation(
            visual: style == .standard ? san : parsed.readable,
            spoken: parsed.spoken
        )
    }

    func line(_ sans: [String]) -> String {
        sans.map { move($0).visual }.joined(separator: " ")
    }

    /// Formats complete SAN tokens embedded in trusted, app-generated prose.
    /// User-authored text should remain verbatim and should not pass through
    /// this method.
    func text(_ source: String) -> String {
        guard style == .pieceNames else { return source }

        var result = source
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        for match in Self.sanTokenRegex.matches(in: source, range: range).reversed() {
            guard let swiftRange = Range(match.range, in: result) else { continue }
            let token = String(result[swiftRange])
            let rendered = move(token).visual
            guard rendered != token else { continue }
            result.replaceSubrange(swiftRange, with: rendered)
        }
        return result
    }

    func accessibilityText(_ source: String) -> String {
        var result = source
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        for match in Self.sanTokenRegex.matches(in: source, range: range).reversed() {
            guard let swiftRange = Range(match.range, in: result) else { continue }
            let token = String(result[swiftRange])
            let rendered = move(token).spoken
            guard rendered != token else { continue }
            result.replaceSubrange(swiftRange, with: rendered)
        }
        return result
    }

    private static let sanTokenRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9])(?:(?:O-O-O|O-O|0-0-0|0-0)[+#]?[!?]{0,2}|[KQRBN](?:[a-h][1-8]|[a-h1-8])?x?[a-h][1-8](?:=[QRBN])?[+#]?[!?]{0,2}|(?:[a-h]x[a-h][1-8]|[a-h][18]=[QRBN])[+#]?[!?]{0,2})(?![A-Za-z0-9])"#
    )
}

private struct ParsedMove {
    let readable: String
    let spoken: String

    init?(san: String) {
        guard !san.isEmpty else { return nil }

        var core = san
        let annotation = Self.takeSuffix(from: &core, allowed: "!?")
        let checkSuffix: String
        if core.hasSuffix("#") {
            core.removeLast()
            checkSuffix = "checkmate"
        } else if core.hasSuffix("+") {
            core.removeLast()
            checkSuffix = "check"
        } else {
            checkSuffix = ""
        }

        let normalizedCastle = core.replacingOccurrences(of: "0", with: "O")
        if normalizedCastle == "O-O" || normalizedCastle == "O-O-O" {
            let side = normalizedCastle == "O-O" ? "kingside" : "queenside"
            let base = "Castle \(side)"
            readable = Self.withSuffixes(base, check: checkSuffix, annotation: annotation)
            spoken = Self.withSuffixes(base, check: checkSuffix, annotation: annotation)
            return
        }

        let promotion: String?
        if core.count >= 2,
           core[core.index(core.endIndex, offsetBy: -2)] == "=",
           let promotedPiece = Self.pieceName(for: core.last!) {
            promotion = promotedPiece
            core.removeLast(2)
        } else {
            promotion = nil
        }

        guard core.count >= 2 else { return nil }
        let destinationStart = core.index(core.endIndex, offsetBy: -2)
        let destination = String(core[destinationStart...])
        guard Self.isSquare(destination) else { return nil }

        var prefix = String(core[..<destinationStart])
        let piece: String
        let isPawn: Bool
        if let first = prefix.first, let pieceName = Self.pieceName(for: first) {
            piece = pieceName
            isPawn = false
            prefix.removeFirst()
        } else {
            piece = "Pawn"
            isPawn = true
        }

        let isCapture = prefix.contains("x")
        prefix.removeAll(where: { $0 == "x" })
        guard prefix.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              prefix.count <= 2 else {
            return nil
        }

        let base: String
        if isPawn {
            if isCapture {
                guard prefix.count == 1, let file = prefix.first, ("a"..."h").contains(String(file)) else {
                    return nil
                }
                base = "\(file)-pawn takes \(destination)"
            } else {
                guard prefix.isEmpty else { return nil }
                base = "Pawn \(destination)"
            }
        } else if isCapture {
            base = prefix.isEmpty
                ? "\(piece) takes \(destination)"
                : "\(piece) \(prefix) takes \(destination)"
        } else {
            base = prefix.isEmpty
                ? "\(piece) \(destination)"
                : "\(piece) \(prefix) to \(destination)"
        }

        let promoted = promotion.map { "\(base), promotes to \($0)" } ?? base
        readable = Self.withSuffixes(promoted, check: checkSuffix, annotation: annotation)

        let spokenBase = base
            .replacingOccurrences(of: " takes ", with: " captures ")
            .replacingOccurrences(
                of: destination,
                with: "\(destination.first!) \(destination.last!)"
            )
        let spokenPromotion = promotion.map { "\(spokenBase), promotes to \($0)" } ?? spokenBase
        spoken = Self.withSuffixes(spokenPromotion, check: checkSuffix, annotation: annotation)
    }

    private static func takeSuffix(from value: inout String, allowed: String) -> String {
        var suffix = ""
        while let last = value.last, allowed.contains(last) {
            suffix.insert(last, at: suffix.startIndex)
            value.removeLast()
        }
        return suffix
    }

    private static func withSuffixes(_ base: String, check: String, annotation: String) -> String {
        var parts = [base]
        if !check.isEmpty {
            parts[0] += ", \(check)"
        }
        if !annotation.isEmpty {
            parts.append(annotation)
        }
        return parts.joined(separator: " ")
    }

    private static func pieceName(for symbol: Character) -> String? {
        switch symbol {
        case "K": "King"
        case "Q": "Queen"
        case "R": "Rook"
        case "B": "Bishop"
        case "N": "Knight"
        default: nil
        }
    }

    private static func isSquare(_ value: String) -> Bool {
        guard value.count == 2,
              let file = value.first,
              let rank = value.last else {
            return false
        }
        return ("a"..."h").contains(String(file)) && ("1"..."8").contains(String(rank))
    }
}

private struct MoveNotationEnvironmentKey: EnvironmentKey {
    static let defaultValue = MoveNotationFormatter()
}

extension EnvironmentValues {
    var moveNotation: MoveNotationFormatter {
        get { self[MoveNotationEnvironmentKey.self] }
        set { self[MoveNotationEnvironmentKey.self] = newValue }
    }
}
