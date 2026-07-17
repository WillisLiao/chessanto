import Foundation

/// Builds the system/user messages sent to Ollama. Layer 1 of the Verified
/// Coach design: a quality aid, not the safety mechanism (`CoachVerifier`
/// is). States the two rules the verifier enforces mechanically so the
/// model has the best chance of writing prose that survives the gate on
/// the first try.
public enum CoachPrompt {
    private static let groundingRules = """
        Rules you must follow exactly:
        1. Only cite moves or lines that appear in the JSON data below, or that you obtain by calling the `evaluate` tool. Never invent a move or a line.
        2. Whenever you cite a line, put its evaluation in parentheses immediately after it, using the same format as the data (e.g. "(+0.5)" or "(M3)").
        Write natural, encouraging coaching prose. Do not restate these rules to the user.
        """

    public static func systemPrompt(register: RatingRegister) -> String {
        let registerText: String
        switch register {
        case .beginner:
            registerText = "The player is a beginner. Avoid jargon; explain basic tactical/positional ideas in plain language (e.g. explain what a fork or a hanging piece is rather than assuming it's known)."
        case .intermediate:
            registerText = "The player is an intermediate club player. You can use standard chess terminology (fork, pin, outpost, weak square) without defining it, but keep explanations concrete and move-focused."
        case .advanced:
            registerText = "The player is an advanced/expert player. Be concise and precise; you can discuss deeper strategic and calculation nuance without over-explaining basics."
        }
        return """
            You are a chess coach reviewing a game with a student. \(registerText)

            \(groundingRules)
            """
    }

    public static func momentUserMessage(payload: CoachMomentPayload) throws -> String {
        let json = try encode(payload)
        return """
            Here is the data for one key moment in the game:
            \(json)

            Write a short coaching explanation (2-4 sentences) of what happened at this moment: why the played move (\(payload.playedSAN)) was a problem (or, if it was a good move, why it worked), and what the better idea was if one is given in the data.
            """
    }

    public static func summaryUserMessage(payload: CoachSummaryPayload) throws -> String {
        let json = try encode(payload)
        return """
            Here is the data for the whole game:
            \(json)

            Write a short whole-game summary (2-3 takeaways) highlighting any recurring patterns across the key moments listed above.
            """
    }

    public static func regenerationUserMessage(violations: [CoachVerifier.Violation]) -> String {
        let bulletedViolations = violations.map { "- \($0.description)" }.joined(separator: "\n")
        return """
            Your previous answer had problems that must be fixed:
            \(bulletedViolations)

            Rewrite your answer. Only cite moves/lines that appear in the data provided or that you obtain via the `evaluate` tool, and make sure every eval you state matches the data exactly.
            """
    }

    public static let evaluateToolSchema = OllamaTool(function: .init(
        name: "evaluate",
        description: "Evaluate a chess position with the engine. Provide the starting FEN and, optionally, a sequence of UCI moves to play from it before evaluating.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "fen": .object(["type": .string("string"), "description": .string("The starting position in FEN notation.")]),
                "moves": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("UCI moves (e.g. \"e2e4\") to play from the FEN before evaluating. Optional."),
                ]),
            ]),
            "required": .array([.string("fen")]),
        ])
    ))

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
