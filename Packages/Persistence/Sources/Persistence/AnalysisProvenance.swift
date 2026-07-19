import Foundation

public enum AnalysisQualityProvenance: String, Codable, CaseIterable, Sendable {
    case fast
    case standard
    case deep

    fileprivate var strength: Int {
        switch self {
        case .fast: return 0
        case .standard: return 1
        case .deep: return 2
        }
    }
}

public enum AnalysisProvenance {
    public static func canReuse(
        storedQuality: AnalysisQualityProvenance?,
        requestedQuality: AnalysisQualityProvenance
    ) -> Bool {
        guard let storedQuality else {
            return false
        }
        return storedQuality.strength >= requestedQuality.strength
    }
}
