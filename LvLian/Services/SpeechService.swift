import AVFAudio

@MainActor
final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    private var activated = false
    func speak(_ text: String) {
        if !activated {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                try session.setActive(true)
                activated = true
            } catch { return }
        }
        // Never replay an old instruction after the movement has already changed.
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = 0.55
        synthesizer.speak(utterance)
    }
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        if activated { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        activated = false
    }
}
