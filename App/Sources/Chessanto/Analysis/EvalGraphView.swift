import SwiftUI

/// Full-game strip showing White's win probability per ply, with a marker at
/// the current position. Dragging maps x to the nearest ply and jumps there.
struct EvalGraphView: View {
    /// White win probability per ply (index 0 = start); `nil` for unanalyzed plies.
    let series: [Double?]
    let currentPly: Int
    let onScrub: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let count = max(series.count - 1, 1)

            ZStack(alignment: .topLeading) {
                Rectangle().fill(.black.opacity(0.85))

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
                .fill(.white.opacity(0.9))

                Rectangle()
                    .fill(.secondary.opacity(0.4))
                    .frame(height: 1)
                    .position(x: width / 2, y: height / 2)

                if !series.isEmpty {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2)
                        .position(x: CGFloat(currentPly) / CGFloat(count) * width, y: height / 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(max(value.location.x / width, 0), 1)
                        onScrub(Int((fraction * CGFloat(count)).rounded()))
                    }
            )
        }
        .frame(height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
    EvalGraphView(series: [50, 55, 60, 45, 30, 70, 90], currentPly: 3) { _ in }
        .padding()
}
