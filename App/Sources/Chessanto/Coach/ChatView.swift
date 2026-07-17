import AnalysisKit
import CoachKit
import Persistence
import SwiftUI

/// The "Chat" tab of the game replay pane (M7 PLAN.md's Position chat):
/// legality precheck, engine-tool loop, and `CoachVerifier` gate all happen
/// in `CoachChat`/`CoachService` - this view is purely presentation. A
/// `List`-based message view (M5's AX lesson: `List` rows expose text where
/// bare `ScrollView`/`VStack` did not); every interactive element is a real
/// native control.
struct ChatView: View {
    @ObservedObject var viewModel: GameReplayViewModel
    @EnvironmentObject private var engineService: EngineService
    @EnvironmentObject private var coachService: CoachService
    let store: GameStore

    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(viewModel.chatPositionLabel)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if !coachService.chatMessages.isEmpty {
                    Button("Clear") {
                        Task { await clearChat() }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            if isCoachAvailable {
                messageList
                starterChips
                if coachService.isSendingChatMessage {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Coach is thinking…").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                }
                inputBar
            } else {
                offlineState
            }
        }
        .task(id: viewModel.id) {
            await loadChatIfNeeded()
        }
        .task {
            if coachService.health == .unknown {
                await coachService.checkHealth()
            }
        }
    }

    // MARK: - Availability

    private var isCoachEnabled: Bool {
        viewModel.userProfile()?.coachEnabled == true
    }

    private var isCoachAvailable: Bool {
        guard isCoachEnabled, !coachService.isIntel else { return false }
        if case .reachable = coachService.health { return true }
        return false
    }

    @ViewBuilder
    private var offlineState: some View {
        VStack(alignment: .leading, spacing: 8) {
            if coachService.isIntel {
                Text("Position chat needs the AI coach, which defaults to off on Intel Macs.")
            } else if !isCoachEnabled {
                Text("Turn on the AI coach in Settings to chat about this position.")
            } else if case .unreachable = coachService.health {
                Text("Ollama isn't reachable, so the coach is offline. Unlike the report, chat has no rule-based fallback - honesty means saying it's offline rather than faking a degraded mode.")
            } else {
                Text("Checking the coach's connection…")
            }
            Button("Check again") {
                Task { await coachService.checkHealth() }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Messages

    private var messageList: some View {
        List(coachService.chatMessages, id: \.id) { message in
            messageRow(message)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessageRecord) -> some View {
        let isUser = message.role == "user"
        VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
            Text(message.content)
                .font(.callout)
                .padding(8)
                .background(isUser ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 6) {
                if let source = message.source {
                    Text(sourceCaption(source))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button("at move \(moveLabel(plyIndex: message.plyIndex))") {
                    jump(toPly: message.plyIndex)
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("chat-jump-\(message.id ?? 0)")
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isUser ? "You" : "Coach"): \(message.content)")
    }

    private func sourceCaption(_ source: String) -> String {
        switch source {
        case "coach": return "Coach"
        case "fallback": return "Couldn't verify"
        case "precheck": return "Move check"
        default: return source
        }
    }

    private func moveLabel(plyIndex: Int) -> String {
        guard plyIndex > 0 else { return "start" }
        let moveNumber = (plyIndex + 1) / 2
        return plyIndex % 2 == 1 ? "\(moveNumber)" : "\(moveNumber)…"
    }

    private func jump(toPly ply: Int) {
        guard ply < viewModel.moveIndices.count else { return }
        viewModel.jump(to: viewModel.moveIndices[ply])
    }

    // MARK: - Starter questions

    @ViewBuilder
    private var starterChips: some View {
        let chips = starterQuestions()
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { chip in
                        Button(chip) { send(chip) }
                            .font(.caption)
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(.vertical, 4)
        }
    }

    private func starterQuestions() -> [String] {
        var chips: [String] = []
        if let moment = viewModel.currentKeyMoment {
            chips.append("Why was \(moment.evalSwing.playedSAN) a \(moment.evalSwing.classification.rawValue)?")
            if let betterMove = moment.betterMove {
                chips.append("What was the idea behind \(betterMove.bestMoveSAN)?")
            }
        }
        if coachService.chatMessages.isEmpty {
            chips.append("How should \(sideToMoveLabel()) continue here?")
        }
        return chips
    }

    private func sideToMoveLabel() -> String {
        guard let fen = viewModel.currentFEN else { return "the player to move" }
        let fields = fen.split(separator: " ")
        guard fields.count > 1 else { return "the player to move" }
        return fields[1] == "w" ? "White" : "Black"
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack {
            TextField("Ask about this position…", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .disabled(coachService.isSendingChatMessage)
                .onSubmit { send(inputText) }
            Button("Send") { send(inputText) }
                .disabled(coachService.isSendingChatMessage || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(8)
    }

    // MARK: - Actions

    private func loadChatIfNeeded() async {
        guard let gameId = viewModel.id else { return }
        await coachService.loadChat(gameId: gameId, store: store)
    }

    private func clearChat() async {
        guard let gameId = viewModel.id else { return }
        await coachService.clearChat(gameId: gameId, store: store)
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !coachService.isSendingChatMessage,
            let gameId = viewModel.id, let profile = viewModel.userProfile(),
            let context = viewModel.chatContext()
        else { return }
        inputText = ""
        let plyIndex = viewModel.currentGraphPly
        Task {
            await coachService.sendChatMessage(
                text: question, gameId: gameId, plyIndex: plyIndex, context: context,
                userProfile: profile, userRating: viewModel.userRatingInThisGame,
                executor: engineService, store: store
            )
        }
    }
}
