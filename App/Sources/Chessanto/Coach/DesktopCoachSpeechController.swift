import AVFoundation
import CompanionDomain
import Foundation

@MainActor
final class DesktopCoachSpeechController: NSObject, ObservableObject {
    @Published private(set) var phase: CoachSpeechPhase = .idle
    @Published private(set) var activeText: String?

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return }

        synthesizer.stopSpeaking(at: .immediate)
        activeText = normalized

        let utterance = AVSpeechUtterance(string: normalized)
        utterance.voice = preferredSageVoice()
        utterance.rate = 0.42
        utterance.pitchMultiplier = 0.82
        utterance.volume = 0.95
        utterance.preUtteranceDelay = 0.08
        utterance.postUtteranceDelay = 0.12
        phase = .speaking
        synthesizer.speak(utterance)
    }

    func pause() {
        guard synthesizer.isSpeaking else { return }
        if synthesizer.pauseSpeaking(at: .word) {
            phase = .paused
        }
    }

    func resume() {
        guard synthesizer.isPaused else { return }
        if synthesizer.continueSpeaking() {
            phase = .speaking
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        phase = .idle
        activeText = nil
    }

    private func preferredSageVoice() -> AVSpeechSynthesisVoice? {
        let englishVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
        let preferredNames = ["Arthur", "Daniel", "Oliver", "Rishi"]
        for name in preferredNames {
            if let voice = englishVoices.first(where: {
                $0.name.localizedCaseInsensitiveContains(name)
            }) {
                return voice
            }
        }
        return englishVoices.first(where: { $0.language == "en-GB" })
            ?? AVSpeechSynthesisVoice(language: "en-GB")
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}

extension DesktopCoachSpeechController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            phase = .idle
            activeText = nil
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            phase = .idle
            activeText = nil
        }
    }
}
