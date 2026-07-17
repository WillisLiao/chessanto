import Foundation

/// The RAM-based model picker table (PLAN.md's Model Picker, revised per
/// fact 11's gemma3-has-no-tools deviation). Pure data - the App layer
/// does chip/RAM detection (`sysctl`) and combines this with `/api/tags`
/// for the installed-models list.
public enum CoachModelCatalog {
    public struct Recommendation: Sendable, Equatable {
        public let defaultModel: String
        public let alternativeModel: String
    }

    /// Hardcoded from fact 6's real registry manifest sizes - labeled
    /// "approx." wherever shown, never fetched at runtime.
    public static let approxDownloadSizeGB: [String: Double] = [
        "qwen3:4b": 2.5,
        "llama3.2:3b": 2.0,
        "qwen3:8b": 5.2,
        "qwen2.5:14b": 9.0,
        "qwen3:32b": 20.2,
        "qwen2.5:32b": 19.9,
        "qwen3:0.6b": 0.5,
    ]

    /// `nil` on non-Apple-Silicon (Intel defaults to rule-based-only with a
    /// slow-inference warning, per PLAN.md - still enableable).
    public static func recommendation(physicalMemoryGB: Int, isAppleSilicon: Bool) -> Recommendation? {
        guard isAppleSilicon else { return nil }
        if physicalMemoryGB < 16 {
            return Recommendation(defaultModel: "qwen3:4b", alternativeModel: "llama3.2:3b")
        }
        if physicalMemoryGB < 32 {
            return Recommendation(defaultModel: "qwen3:8b", alternativeModel: "qwen2.5:14b")
        }
        return Recommendation(defaultModel: "qwen3:32b", alternativeModel: "qwen2.5:32b")
    }
}
