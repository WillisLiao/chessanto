import SwiftUI

enum MobileColors {
    static let paper = Color(red: 0.98, green: 0.976, blue: 0.965)
    static let paperRaised = Color.white
    static let parchment = Color(red: 0.953, green: 0.941, blue: 0.914)
    static let graphite = Color(red: 0.149, green: 0.137, blue: 0.122)
    static let graphiteSoft = Color(red: 0.384, green: 0.369, blue: 0.341)
    static let brass = Color(red: 0.651, green: 0.475, blue: 0.122)
    static let brassWash = Color(red: 0.949, green: 0.91, blue: 0.824)
    static let hairline = Color(red: 0.867, green: 0.847, blue: 0.808)
    static let success = Color(red: 0.176, green: 0.431, blue: 0.286)
    static let danger = Color(red: 0.706, green: 0.137, blue: 0.094)
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
