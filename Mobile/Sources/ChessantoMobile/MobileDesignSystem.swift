#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

enum MobileColors {
    static let paper = Color.dynamic(
        light: UIColor(hex: "#FAF9F6"),
        dark: UIColor(hex: "#1C1A17")
    )
    static let paperRaised = Color.dynamic(
        light: UIColor(hex: "#FFFFFF"),
        dark: UIColor(hex: "#2D2A26")
    )
    static let parchment = Color.dynamic(
        light: UIColor(hex: "#F3F0E9"),
        dark: UIColor(hex: "#252220")
    )
    static let graphite = Color.dynamic(
        light: UIColor(hex: "#26231F"),
        dark: UIColor(hex: "#E8E2D6")
    )
    static let graphiteSoft = Color.dynamic(
        light: UIColor(hex: "#625E57"),
        dark: UIColor(hex: "#A09A8E")
    )
    static let brass = Color.dynamic(
        light: UIColor(hex: "#A6791F"),
        dark: UIColor(hex: "#C9A04A")
    )
    static let brassWash = Color.dynamic(
        light: UIColor(hex: "#F2E8D2"),
        dark: UIColor(hex: "#3A3220")
    )
    static let hairline = Color.dynamic(
        light: UIColor(hex: "#DDD8CE"),
        dark: UIColor(hex: "#3D3A35")
    )
    static let success = Color.dynamic(
        light: UIColor(hex: "#2D6E49"),
        dark: UIColor(hex: "#4EAA74")
    )
    static let danger = Color.dynamic(
        light: UIColor(hex: "#B42318"),
        dark: UIColor(hex: "#E55A4F")
    )
}

#if canImport(UIKit)
extension UIColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

extension Color {
    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? dark : light
        })
    }
}
#endif

enum MobileClassificationStyle {
    static func color(for classification: String) -> Color {
        switch classification.lowercased() {
        case "best", "excellent":
            return Color.dynamic(
                light: UIColor(hex: "#6F9E4C"),
                dark: UIColor(hex: "#82B859")
            )
        case "brilliant":
            return Color.dynamic(
                light: UIColor(hex: "#26C1B6"),
                dark: UIColor(hex: "#3AD5CA")
            )
        case "good":
            return Color.dynamic(
                light: UIColor(hex: "#8C8C8C"),
                dark: UIColor(hex: "#A0A0A0")
            )
        case "inaccuracy":
            return Color.dynamic(
                light: UIColor(hex: "#E0A93B"),
                dark: UIColor(hex: "#F0BD55")
            )
        case "mistake":
            return Color.dynamic(
                light: UIColor(hex: "#E0803B"),
                dark: UIColor(hex: "#F09555")
            )
        case "blunder":
            return Color.dynamic(
                light: UIColor(hex: "#D14B4B"),
                dark: UIColor(hex: "#E56363")
            )
        case "missedwin", "missed win":
            return Color.dynamic(
                light: UIColor(hex: "#9B6FD1"),
                dark: UIColor(hex: "#B087E6")
            )
        case "book", "forced":
            return MobileColors.graphiteSoft
        default:
            return MobileColors.graphiteSoft
        }
    }

    static func label(for classification: String) -> String {
        switch classification.lowercased() {
        case "missedwin", "missed win":
            return "Missed Win"
        case "best":
            return "Best"
        case "brilliant":
            return "Brilliant"
        case "excellent":
            return "Excellent"
        case "good":
            return "Good"
        case "inaccuracy":
            return "Inaccuracy"
        case "mistake":
            return "Mistake"
        case "blunder":
            return "Blunder"
        case "book":
            return "Book"
        case "forced":
            return "Forced"
        default:
            return classification.capitalized
        }
    }

    static func compactMark(for classification: String) -> String? {
        switch classification.lowercased() {
        case "best": return "★"
        case "brilliant": return "!!"
        case "inaccuracy": return "?!"
        case "mistake": return "?"
        case "blunder": return "??"
        default: return nil
        }
    }
}

struct MobileClassificationChip: View {
    let classification: String

    var body: some View {
        let color = MobileClassificationStyle.color(for: classification)
        let label = MobileClassificationStyle.label(for: classification)
        let mark = MobileClassificationStyle.compactMark(for: classification)
        HStack(spacing: 3) {
            if let mark {
                Text(mark)
                    .font(.caption.weight(.bold))
            }
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

struct ScorebookCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.vertical, 16)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                VStack(spacing: 0) {
                    Divider()
                    Spacer()
                    Divider()
                }
                .foregroundStyle(MobileColors.hairline)
            }
    }
}

struct StatusPill: View {
    let text: String
    var color: Color = MobileColors.brass

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.11))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(color)
                    .frame(height: 1)
            }
    }
}

extension View {
    func companionBackground() -> some View {
        background(MobileColors.paper.ignoresSafeArea())
            .tint(MobileColors.brass)
            .foregroundStyle(MobileColors.graphite)
    }
}
