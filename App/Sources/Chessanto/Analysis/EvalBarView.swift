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
            }
            .overlay(alignment: (eval.map { isWhiteBetter($0) } ?? true) ? .bottom : .top) {
                if let eval {
                    Text(eval.label)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(isWhiteBetter(eval) ? .black : .white)
                        .padding(.vertical, 2)
                }
            }
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.4)))
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
