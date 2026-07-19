import SwiftUI

/// Vertical eval bar, filled from the bottom with White's win probability.
struct EvalBarView: View {
    let eval: EvalDisplay?

    private let width: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let whiteFraction = (eval?.whiteWinProbability ?? 50) / 100
            ZStack(alignment: .bottom) {
                Color.black
                Color.white
                    .frame(height: proxy.size.height * whiteFraction)
                    .animation(.easeInOut(duration: 0.25), value: whiteFraction)
                // The advantage cap: a thin brass tick at the black/white
                // boundary, so the side currently ahead reads at a glance
                // instead of requiring a careful compare of the two fills.
                Rectangle()
                    .fill(DesignColors.accent)
                    .frame(height: 3)
                    .offset(y: -proxy.size.height * whiteFraction)
                    .animation(.easeInOut(duration: 0.25), value: whiteFraction)
            }
            .overlay(alignment: (eval.map { isWhiteBetter($0) } ?? true) ? .bottom : .top) {
                if let eval {
                    Text(eval.label)
                        .font(.dsNotation)
                        .foregroundStyle(isWhiteBetter(eval) ? .black : .white)
                        .padding(.vertical, 3)
                }
            }
        }
        .frame(width: width)
        .overlay(Rectangle().stroke(DesignColors.hairline, lineWidth: 1))
        .accessibilityLabel(accessibilityLabel)
    }

    private func isWhiteBetter(_ eval: EvalDisplay) -> Bool {
        eval.whiteWinProbability >= 50
    }

    private var accessibilityLabel: String {
        guard let eval else { return "Evaluation unavailable" }
        return "Evaluation \(eval.label), White win probability \(Int(eval.whiteWinProbability)) percent"
    }
}

#Preview {
    EvalBarView(eval: EvalDisplay(whiteWinProbability: 65, label: "+0.8", isLive: false, depth: 18, isGameOver: false))
        .frame(height: 400)
        .padding()
}
