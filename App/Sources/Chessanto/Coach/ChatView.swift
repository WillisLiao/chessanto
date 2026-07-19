import AnalysisKit
import CoachKit
import Persistence
import SwiftUI

/// The Coach slide-over panel (UI/UX redesign step 11, replacing M7's
/// third-tab "Chat"): legality precheck, engine-tool loop, and
/// `CoachVerifier` gate all happen in `CoachChat`/`CoachService` - this view
/// is purely presentation. A `List`-based message view (M5's AX lesson:
/// `List` rows expose text where bare `ScrollView`/`VStack` did not); every
/// interactive element is a real native control.
struct ChatView: View {
    @ObservedObject var viewModel: GameReplayViewModel
    @EnvironmentObject private var engineService: EngineService
    @EnvironmentObject private var coachService: CoachService
    let store: GameStore
    var onClose: (() -> Void)?

    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            if isCoachAvailable {
                messageList
                starterChips
                if coachService.isSendingChatMessage {
                    HStack(spacing: DesignSpacing.xs) {
                        ProgressView().controlSize(.mini)
                        Text("Coach is thinking…").font(.dsSecondary).foregroundStyle(DesignColors.textSecondary)
                    }
                    .padding(.horizontal, DesignSpacing.sm)
                }
                inputBar
            } else {
                offlineState
            }
        }
        .background(DesignColors.surface0)
        .task(id: viewModel.id) {
            await loadChatIfNeeded()
        }
        .task {
            if coachService.health == .unknown {
                await coachService.checkHealth()
            }
        }
    }

    // MARK: - Header (position control)

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            HStack {
                Text("Coach").font(.dsSectionHeader).foregroundStyle(DesignColors.textPrimary)
                Spacer()
                if let onClose {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DesignColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close Coach panel")
                }
            }

            HStack(spacing: DesignSpacing.xs) {
                Image(systemName: viewModel.isChatPinned ? "pin.fill" : "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(viewModel.isChatPinned ? DesignColors.accent : DesignColors.textSecondary)
                Text(
                    viewModel.isChatPinned
                        ? "Pinned to \(viewModel.chatPositionLabel)"
                        : "Following board · \(viewModel.chatPositionLabel)"
                )
                    .font(.dsSecondary)
                    .foregroundStyle(DesignColors.textSecondary)
                Spacer()
                Button {
                    if viewModel.isChatPinned {
                        viewModel.unpinChat()
                    } else {
                        viewModel.pinChat(to: viewModel.currentIndex)
                    }
                } label: {
                    Label(viewModel.isChatPinned ? "Pinned" : "Pin", systemImage: viewModel.isChatPinned ? "pin.slash" : "pin")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(viewModel.isChatPinned ? "Unpin position" : "Pin to current position")
            }

            if !coachService.chatMessages.isEmpty {
                Button("Clear chat") {
                    Task { await clearChat() }
                }
                .font(.dsSecondary)
                .buttonStyle(.plain)
                .foregroundStyle(DesignColors.textSecondary)
            }
        }
        .padding(DesignSpacing.sm)
        .background(DesignColors.surface1)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignColors.hairline).frame(height: 1)
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
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
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
        .font(.dsBody)
        .foregroundStyle(DesignColors.textSecondary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Messages

    private var messageList: some View {
        List(coachService.chatMessages, id: \.id) { message in
            messageRow(message)
                .listRowSeparator(.hidden)
                .listRowBackground(DesignColors.surface0)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DesignColors.surface0)
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessageRecord) -> some View {
        let isUser = message.role == "user"
        VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
            markdownText(message.content)
                .font(.dsBody)
                .padding(isUser ? DesignSpacing.sm : 0)
                .background(isUser ? DesignColors.selection : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: isUser ? DesignShape.controlRadius : 0))
            HStack(spacing: DesignSpacing.xs) {
                if let source = message.source {
                    Text(sourceCaption(source))
                        .font(.dsSecondary)
                        .foregroundStyle(DesignColors.textSecondary)
                }
                Button("at move \(moveLabel(plyIndex: message.plyIndex))") {
                    jump(toPly: message.plyIndex)
                }
                .font(.dsSecondary)
                .buttonStyle(.plain)
                .foregroundStyle(DesignColors.accentText)
                .accessibilityIdentifier("chat-jump-\(message.id ?? 0)")
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isUser ? "You" : "Coach"): \(message.content)")
    }

    /// Renders `**bold**`/lists rather than showing literal asterisks
    /// (fact 4) - `AttributedString(markdown:)` handles the coach's actual
    /// output shape (bold emphasis, simple line-based lists) without a
    /// hand-rolled parser.
    private func markdownText(_ content: String) -> Text {
        if let attributed = try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(content)
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
            HStack {
                Menu("Suggested questions") {
                    ForEach(chips, id: \.self) { chip in
                        Button(chip) { send(chip) }
                    }
                }
                .font(.dsSecondary)
                Spacer()
            }
            .padding(.horizontal, DesignSpacing.sm)
            .padding(.vertical, DesignSpacing.xs)
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
                .buttonStyle(.dsPrimary)
                .disabled(coachService.isSendingChatMessage || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(DesignSpacing.sm)
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
        let plyIndex = viewModel.chatSubjectGraphPly
        Task {
            await coachService.sendChatMessage(
                text: question, gameId: gameId, plyIndex: plyIndex, context: context,
                userProfile: profile, userRating: viewModel.userRatingInThisGame,
                executor: engineService, store: store
            )
        }
    }
}
