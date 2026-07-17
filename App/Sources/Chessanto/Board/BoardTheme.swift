import SwiftUI

/// A chess board is not system-appearance-inverted - these are fixed
/// palettes, not adaptive colors. Persisted (raw value) in
/// `userProfile.boardTheme`.
enum BoardTheme: String, CaseIterable, Identifiable {
    case classic
    case green
    case blue

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: return "Classic"
        case .green: return "Green"
        case .blue: return "Blue"
        }
    }

    var lightSquare: Color {
        switch self {
        case .classic: return Color(red: 0.93, green: 0.87, blue: 0.77)
        case .green: return Color(red: 0.93, green: 0.93, blue: 0.82)
        case .blue: return Color(red: 0.88, green: 0.91, blue: 0.95)
        }
    }

    var darkSquare: Color {
        switch self {
        case .classic: return Color(red: 0.55, green: 0.39, blue: 0.29)
        case .green: return Color(red: 0.46, green: 0.59, blue: 0.34)
        case .blue: return Color(red: 0.36, green: 0.50, blue: 0.66)
        }
    }

    var highlight: Color {
        switch self {
        case .classic: return Color.yellow.opacity(0.35)
        case .green: return Color.yellow.opacity(0.4)
        case .blue: return Color.yellow.opacity(0.4)
        }
    }

    var selected: Color { Color.blue.opacity(0.35) }
    var destination: Color { Color.green.opacity(0.35) }

    /// Coordinate label color, legible against both square shades in this theme.
    var coordinateColor: Color {
        switch self {
        case .classic: return Color(red: 0.55, green: 0.39, blue: 0.29)
        case .green: return Color(red: 0.46, green: 0.59, blue: 0.34)
        case .blue: return Color(red: 0.36, green: 0.50, blue: 0.66)
        }
    }
}
