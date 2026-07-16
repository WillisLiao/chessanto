import SwiftUI
import ChessCore
import Persistence

struct GameReplayView: View {
    @StateObject private var viewModel: GameReplayViewModel
    private let game: GameRecord

    init(game: GameRecord) {
        self.game = game
        _viewModel = StateObject(wrappedValue: GameReplayViewModel(record: game))
    }

    var body: some View {
        HSplitView {
            VStack {
                BoardView(position: viewModel.position)
                    .padding()
                controls
            }
            .frame(minWidth: 420)

            MoveListView(viewModel: viewModel)
                .frame(minWidth: 260, maxWidth: 340)
        }
        .navigationTitle("\(game.white) vs \(game.black)")
        .alert("Load error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.loadError ?? "")
        }
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .right: viewModel.stepForward()
            case .left: viewModel.stepBackward()
            default: break
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.stepBackward()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!viewModel.canStepBackward)
            .accessibilityLabel("Previous move")

            Button {
                viewModel.stepForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!viewModel.canStepForward)
            .accessibilityLabel("Next move")
        }
        .buttonStyle(.bordered)
        .padding(.bottom)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.loadError != nil },
            set: { if !$0 { viewModel.loadError = nil } }
        )
    }
}

private struct MoveListView: View {
    @ObservedObject var viewModel: GameReplayViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(Array(viewModel.moveIndices.enumerated()), id: \.element) { position, index in
                    if let san = viewModel.san(at: index) {
                        Button {
                            viewModel.jump(to: index)
                        } label: {
                            HStack {
                                if position % 2 == 1 {
                                    Text("\(position / 2 + 1).")
                                        .foregroundStyle(.secondary)
                                }
                                Text(san)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .background(index == viewModel.currentIndex ? Color.accentColor.opacity(0.2) : .clear)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            position % 2 == 1 ? "Move \(position / 2 + 1), \(san)" : san
                        )
                    }
                }
            }
            .padding()
        }
    }
}
