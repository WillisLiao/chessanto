import AVFoundation
import CompanionDomain
import Foundation

@MainActor
final class DesktopCoachSpeechController: NSObject, ObservableObject {
    @Published private(set) var phase: CoachSpeechPhase = .idle
    @Published private(set) var activeText: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var currentTask: Task<Void, Never>?

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

        // Stop any active speech
        stop()

        activeText = normalized
        phase = .speaking

        // First, check health, then attempt to speak via local Kokoro TTS server
        currentTask = Task {
            let isHealthy = await checkKokoroHealth()
            guard !Task.isCancelled else { return }

            if isHealthy {
                if let audioData = await fetchKokoroSpeech(text: normalized) {
                    guard !Task.isCancelled else { return }
                    playAudioData(audioData)
                    return
                }
            }

            guard !Task.isCancelled else { return }
            // Fallback to system synthesizer
            speakFallback(normalized)
        }
    }

    private func checkKokoroHealth() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:8888/health") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 0.5 // Ultra fast check

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }
            return true
        } catch {
            return false
        }
    }

    private func fetchKokoroSpeech(text: String) async -> Data? {
        guard let url = URL(string: "http://127.0.0.1:8888/tts") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20.0 // Allow ample time for local synthesis

        let payload: [String: Any] = [
            "text": text,
            "voice": "bm_george",
            "speed": 0.95
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            return data
        } catch {
            return nil // Fallback silently
        }
    }

    private func playAudioData(_ data: Data) {
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.audioPlayer = player
        } catch {
            // If audio player initialization/playback fails, fallback
            if let activeText {
                speakFallback(activeText)
            }
        }
    }

    private func speakFallback(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = preferredSageVoice()
        utterance.rate = 0.42
        utterance.pitchMultiplier = 0.82
        utterance.volume = 0.95
        utterance.preUtteranceDelay = 0.08
        utterance.postUtteranceDelay = 0.12
        synthesizer.speak(utterance)
    }

    func pause() {
        if let audioPlayer, audioPlayer.isPlaying {
            audioPlayer.pause()
            phase = .paused
        } else if synthesizer.isSpeaking {
            if synthesizer.pauseSpeaking(at: .word) {
                phase = .paused
            }
        }
    }

    func resume() {
        if let audioPlayer {
            audioPlayer.play()
            phase = .speaking
        } else if synthesizer.isPaused {
            if synthesizer.continueSpeaking() {
                phase = .speaking
            }
        }
    }

    func stop() {
        currentTask?.cancel()
        currentTask = nil

        audioPlayer?.stop()
        audioPlayer = nil

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

extension DesktopCoachSpeechController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor in
            phase = .idle
            activeText = nil
            audioPlayer = nil
        }
    }
}
