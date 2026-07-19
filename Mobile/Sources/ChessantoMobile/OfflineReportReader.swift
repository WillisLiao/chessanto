import AVFoundation
import CompanionDomain
import SwiftUI

struct OfflineReportReader: View {
    @EnvironmentObject private var model: MobileAppModel
    let report: PortableAnalysisReport
    @State private var selectedPly = 0
    @State private var linePreview: OfflineBetterLinePreview?
    @State private var linePreviewIndex = 0
    @State private var linePlaybackTask: Task<Void, Never>?
    @StateObject private var speech = CoachSpeechController()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                header
                boardSection
                if let moment = currentMoment {
                    coachSection(moment)
                }
                keyMoments
                scoreSheet
                takeaways
            }
            .padding(16)
        }
        .navigationTitle("Game report")
        .navigationBarTitleDisplayMode(.inline)
        .companionBackground()
        .onDisappear {
            stopLinePreview()
            speech.stop()
        }
    }

    private var header: some View {
        ScorebookCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(report.metadata.white) vs \(report.metadata.black)")
                    .font(.title2.weight(.semibold))
                HStack {
                    Text(report.metadata.result)
                        .font(.headline.monospacedDigit())
                    Spacer()
                    StatusPill(
                        text: "Saved for offline reading",
                        color: MobileColors.success
                    )
                }
                HStack {
                    Text(report.analysisQuality.rawValue.capitalized)
                    if let opening = report.opening {
                        Text("·")
                        Text("\(opening.eco) \(opening.name)")
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(MobileColors.graphiteSoft)
            }
        }
    }

    private var boardSection: some View {
        VStack(spacing: 12) {
            CompanionBoardView(fen: displayedFEN)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Chess position after ply \(selectedPly)")
            if let linePreview {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Better line")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MobileColors.brass)
                        Text(
                            linePreview.frames[linePreviewIndex].san
                                ?? "Starting position"
                        )
                        .font(.headline.monospaced())
                    }
                    Spacer()
                    Text(
                        "\(linePreviewIndex) of \(linePreview.frames.count - 1)"
                    )
                    .font(.caption.monospacedDigit())
                    Button("Done") {
                        stopLinePreview()
                    }
                    .frame(minHeight: 44)
                }
                .padding(.horizontal, 4)
            }
            HStack {
                Button {
                    select(ply: max(0, selectedPly - 1))
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                }
                .disabled(selectedPly == 0)
                Spacer()
                VStack(spacing: 2) {
                    Text(moveLabel)
                        .font(.headline)
                    Text(evaluationLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(MobileColors.graphiteSoft)
                }
                Spacer()
                Button {
                    select(ply: min(
                        report.positions.count - 1,
                        selectedPly + 1
                    ))
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                }
                .disabled(selectedPly >= report.positions.count - 1)
            }
        }
    }

    private func coachSection(_ moment: PortableKeyMoment) -> some View {
        ScorebookCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(coachImageName(moment.narration?.mood))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 104)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Coach")
                            .font(.headline)
                        Text(
                            moment.narration?.text ?? moment.summary
                        )
                        .font(.body)
                        Text(narrationSource(moment))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MobileColors.graphiteSoft)
                    }
                }
                CoachSpeechControls(
                    speech: speech,
                    text: moment.narration?.text ?? moment.summary
                )
            }
        }
    }

    @ViewBuilder
    private var keyMoments: some View {
        if !report.keyMoments.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Key moments")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 0) {
                    ForEach(report.keyMoments, id: \.ply) { moment in
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                select(ply: moment.ply)
                            } label: {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(
                                        formatted(moment.canonicalPlayedSAN)
                                    )
                                    .font(.headline)
                                    Spacer()
                                    Text(
                                        moment.classification
                                            .replacingOccurrences(
                                                of: "missedWin",
                                                with: "missed win"
                                            )
                                            .capitalized
                                    )
                                    .font(.caption)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .padding(.horizontal, 10)
                                .background(
                                    selectedPly == moment.ply
                                        ? MobileColors.brassWash
                                        : Color.clear
                                )
                            }
                            .buttonStyle(.plain)
                            if selectedPly == moment.ply,
                                !moment.betterLineSAN.isEmpty
                            {
                                Text(
                                    "Better: "
                                        + moment.betterLineSAN.joined(
                                            separator: " "
                                        )
                                )
                                .font(.caption.monospaced())
                                .foregroundStyle(MobileColors.graphiteSoft)
                                Button {
                                    playBetterLine(for: moment)
                                } label: {
                                    Label(
                                        "Show better line",
                                        systemImage: "play.fill"
                                    )
                                    .frame(minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var scoreSheet: some View {
        ScorebookCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Score sheet")
                    .font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(moveRows, id: \.number) { row in
                        GridRow {
                            Text("\(row.number).")
                                .foregroundStyle(MobileColors.graphiteSoft)
                                .frame(width: 30, alignment: .trailing)
                            moveButton(row.white)
                            moveButton(row.black)
                        }
                    }
                }
                .font(.body.monospaced())
            }
        }
    }

    private var takeaways: some View {
        ScorebookCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Takeaways")
                    .font(.headline)
                ForEach(Array(report.takeaways.enumerated()), id: \.offset) {
                    _, takeaway in
                    Label(takeaway, systemImage: "checkmark.circle")
                        .foregroundStyle(MobileColors.graphiteSoft)
                }
            }
        }
    }

    @ViewBuilder
    private func moveButton(_ move: MoveCell?) -> some View {
        if let move {
            Button {
                select(ply: move.ply)
            } label: {
                Text(formatted(move.san))
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .padding(.horizontal, 8)
                    .background(
                        selectedPly == move.ply
                            ? MobileColors.brassWash
                            : Color.clear
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ply \(move.ply), \(move.san)")
        } else {
            Color.clear.frame(height: 36)
        }
    }

    private var currentPosition: PortablePosition? {
        report.positions.first { $0.ply == selectedPly }
    }

    private var currentMoment: PortableKeyMoment? {
        report.keyMoments.first { $0.ply == selectedPly }
    }

    private var displayedFEN: String? {
        if let linePreview {
            return linePreview.frames[linePreviewIndex].fen
        }
        return currentPosition?.fen
    }

    private var evaluationLabel: String {
        guard
            let evaluation = report.evaluations.first(where: {
                $0.ply == selectedPly
            })
        else {
            return "No evaluation"
        }
        if let mate = evaluation.mateIn {
            return mate > 0 ? "White mates in \(mate)" : "Black mates in \(-mate)"
        }
        guard let centipawns = evaluation.scoreCentipawns else {
            return "Even"
        }
        return String(format: "%+.2f", Double(centipawns) / 100)
    }

    private var moveLabel: String {
        if let linePreview {
            return linePreview.frames[linePreviewIndex].san
                ?? "Better line"
        }
        guard let san = currentPosition?.playedSAN else {
            return "Starting position"
        }
        return formatted(san)
    }

    private var moveRows: [MoveRow] {
        let moves = report.positions.dropFirst().compactMap { position -> MoveCell? in
            guard let san = position.playedSAN else { return nil }
            return MoveCell(ply: position.ply, san: san)
        }
        var result: [MoveRow] = []
        for start in stride(from: 0, to: moves.count, by: 2) {
            result.append(
                MoveRow(
                    number: start / 2 + 1,
                    white: moves[start],
                    black: start + 1 < moves.count ? moves[start + 1] : nil
                )
            )
        }
        return result
    }

    private func formatted(_ san: String) -> String {
        guard model.notationStyle == .pieceNames else { return san }
        let names: [Character: String] = [
            "K": "King ",
            "Q": "Queen ",
            "R": "Rook ",
            "B": "Bishop ",
            "N": "Knight ",
        ]
        guard let first = san.first, let name = names[first] else {
            return san
        }
        return name + san.dropFirst()
    }

    private func coachImageName(_ mood: CoachEmotion?) -> String {
        guard let mood else { return "coach-comic" }
        return "coach-\(mood.rawValue)"
    }

    private func narrationSource(_ moment: PortableKeyMoment) -> String {
        switch moment.narration?.source {
        case .verifiedCoach:
            return "Verified local Coach"
        case .engineVerifiedFallback:
            return "Engine-verified fallback"
        case .deterministicPrecheck:
            return "Deterministic report"
        case nil:
            return "Deterministic report"
        }
    }

    private func select(ply: Int) {
        stopLinePreview()
        selectedPly = ply
    }

    private func playBetterLine(for moment: PortableKeyMoment) {
        stopLinePreview()
        guard let preview = OfflineBetterLinePreview(
            report: report,
            moment: moment
        ) else {
            return
        }
        linePreview = preview
        linePreviewIndex = 0
        linePlaybackTask = Task { @MainActor in
            for index in preview.frames.indices.dropFirst() {
                do {
                    try await Task.sleep(for: .milliseconds(850))
                } catch {
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                linePreviewIndex = index
            }
        }
    }

    private func stopLinePreview() {
        linePlaybackTask?.cancel()
        linePlaybackTask = nil
        linePreview = nil
        linePreviewIndex = 0
    }
}

private struct MoveCell {
    let ply: Int
    let san: String
}

private struct MoveRow {
    let number: Int
    let white: MoveCell?
    let black: MoveCell?
}

private struct CompanionBoardView: View {
    let fen: String?

    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width / 8
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { rank in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { file in
                            ZStack {
                                ((rank + file).isMultiple(of: 2)
                                    ? Color(red: 0.91, green: 0.87, blue: 0.77)
                                    : Color(red: 0.45, green: 0.36, blue: 0.24))
                                if let piece = pieces[rank * 8 + file] {
                                    Image(piece)
                                        .resizable()
                                        .scaledToFit()
                                        .padding(side * 0.08)
                                }
                            }
                            .frame(width: side, height: side)
                        }
                    }
                }
            }
        }
    }

    private var pieces: [String?] {
        guard let board = fen?.split(separator: " ").first else {
            return Array(repeating: nil, count: 64)
        }
        var result: [String?] = []
        for character in board {
            if character == "/" {
                continue
            }
            if let empty = character.wholeNumberValue {
                result.append(contentsOf: Array(repeating: nil, count: empty))
            } else {
                let color = character.isUppercase ? "w" : "b"
                let symbol = character.uppercased()
                result.append("cburnett-\(color)\(symbol)")
            }
        }
        if result.count < 64 {
            result.append(contentsOf: Array(repeating: nil, count: 64 - result.count))
        }
        return Array(result.prefix(64))
    }
}

@MainActor
final class CoachSpeechController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var phase: CoachSpeechPhase = .idle
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = preferredVoice()
        utterance.rate = 0.42
        utterance.pitchMultiplier = 0.82
        utterance.preUtteranceDelay = 0.08
        synthesizer.speak(utterance)
        phase = .speaking
    }

    func pause() {
        guard synthesizer.pauseSpeaking(at: .word) else { return }
        phase = .paused
    }

    func resume() {
        guard synthesizer.continueSpeaking() else { return }
        phase = .speaking
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        phase = .idle
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in phase = .idle }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in phase = .idle }
    }

    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices().first {
            $0.language.hasPrefix("en-GB")
                && $0.name.localizedCaseInsensitiveContains("male")
        } ?? AVSpeechSynthesisVoice(language: "en-GB")
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}

private struct CoachSpeechControls: View {
    @ObservedObject var speech: CoachSpeechController
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            switch speech.phase {
            case .idle:
                Button {
                    speech.speak(text)
                } label: {
                    Label("Hear Coach", systemImage: "speaker.wave.2.fill")
                        .frame(minHeight: 44)
                }
            case .speaking:
                Button {
                    speech.pause()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .frame(minHeight: 44)
                }
                Button {
                    speech.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(minHeight: 44)
                }
            case .paused:
                Button {
                    speech.resume()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .frame(minHeight: 44)
                }
                Button {
                    speech.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(minHeight: 44)
                }
            }
        }
        .buttonStyle(.bordered)
        .accessibilityElement(children: .contain)
    }
}
