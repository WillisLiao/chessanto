import SwiftUI
import AnalysisKit

/// Full-game strip showing White's win probability per ply, with a marker at
/// the current position. Dragging maps x to the nearest ply and jumps there.
struct EvalGraphView: View {
    /// White win probability per ply (index 0 = start); `nil` for unanalyzed plies.
    let series: [Double?]
    let currentPly: Int
    /// Report key moments to mark on the strip, colored by classification.
    let keyMoments: [KeyMoment]
    let onScrub: (Int) -> Void

    @State private var hoverPly: Int?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let count = max(series.count - 1, 1)

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(DesignColors.surface1)

                Path { path in
                    guard !series.isEmpty else { return }
                    path.move(to: point(forPly: 0, width: width, height: height, count: count))
                    for ply in series.indices {
                        path.addLine(to: point(forPly: ply, width: width, height: height, count: count))
                    }
                    path.addLine(to: CGPoint(x: width, y: height / 2))
                    path.addLine(to: CGPoint(x: 0, y: height / 2))
                    path.closeSubpath()
                }
                .fill(DesignColors.textPrimary.opacity(0.82))

                // Baseline at the 50% win-probability mark.
                Rectangle()
                    .fill(DesignColors.hairline)
                    .frame(height: 1)
                    .position(x: width / 2, y: height / 2)

                ForEach(keyMoments, id: \.ply) { moment in
                    Circle()
                        .fill(moment.evalSwing.classification.color)
                        .frame(width: 6, height: 6)
                        .position(point(forPly: moment.ply, width: width, height: height, count: count))
                }

                if !series.isEmpty {
                    Rectangle()
                        .fill(DesignColors.accent)
                        .frame(width: 2)
                        .position(x: CGFloat(currentPly) / CGFloat(count) * width, y: height / 2)
                }

                if let hoverPly, hoverPly < series.count {
                    Rectangle()
                        .fill(DesignColors.textSecondary)
                        .frame(width: 1)
                        .position(x: CGFloat(hoverPly) / CGFloat(count) * width, y: height / 2)

                    hoverReadout(ply: hoverPly, width: width)
                }
            }
            .overlay(Rectangle().stroke(DesignColors.hairline, lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(max(value.location.x / width, 0), 1)
                        onScrub(Int((fraction * CGFloat(count)).rounded()))
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let fraction = min(max(location.x / width, 0), 1)
                    hoverPly = Int((fraction * CGFloat(count)).rounded())
                case .ended:
                    hoverPly = nil
                }
            }
        }
        .frame(height: 60)
    }

    private func hoverReadout(ply: Int, width: CGFloat) -> some View {
        let evalText: String
        if let probability = series[ply] {
            evalText = "\(Int(probability.rounded()))% white"
        } else {
            evalText = "unanalyzed"
        }
        let label = "Ply \(ply) · \(evalText)"
        let fraction = CGFloat(ply) / CGFloat(max(series.count - 1, 1))
        return Text(label)
            .font(.dsSecondary)
            .padding(.horizontal, DesignSpacing.xs)
            .padding(.vertical, 2)
            .background(DesignColors.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(DesignColors.hairline, lineWidth: 1))
            .position(x: min(max(fraction * width, 40), width - 40), y: 12)
    }

    private func point(forPly ply: Int, width: CGFloat, height: CGFloat, count: Int) -> CGPoint {
        let x = CGFloat(ply) / CGFloat(count) * width
        let whiteWinP = series[ply] ?? 50
        // Invert so 100 (White winning) is at the top.
        let y = height * (1 - whiteWinP / 100)
        return CGPoint(x: x, y: y)
    }
}

#Preview {
    EvalGraphView(series: [50, 55, 60, 45, 30, 70, 90], currentPly: 3, keyMoments: []) { _ in }
        .padding()
}
