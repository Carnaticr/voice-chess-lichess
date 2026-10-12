import AVFoundation

/// Speaks announcements with the system speech synthesizer.
@MainActor
final class Announcer: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var lastSpoken = ""
    /// Called when speech starts/stops, so the microphone can ignore our own voice.
    var onSpeakingChanged: ((Bool) -> Void)?
    var voiceIdentifier = ""
    var rate: Double = 0.5
    /// Log of everything said, newest first (shown in the voice panel).
    var onSay: ((String) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    static var englishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { ($0.language, $0.name) < ($1.language, $1.name) }
    }

    func say(_ text: String, interrupt: Bool = false, remember: Bool = false) {
        guard !text.isEmpty else { return }
        if remember { lastSpoken = text }
        if interrupt { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        if !voiceIdentifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        // Map the 0...1 setting onto the synthesizer's usable range.
        let minRate = Double(AVSpeechUtteranceMinimumSpeechRate)
        let maxRate = Double(AVSpeechUtteranceMaximumSpeechRate)
        utterance.rate = Float(minRate + (maxRate - minRate) * (0.25 + rate * 0.5))
        synthesizer.speak(utterance)
        onSay?(text)
    }

    func remember(_ text: String) { lastSpoken = text }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onSpeakingChanged?(true) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if !self.synthesizer.isSpeaking { self.onSpeakingChanged?(false) }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if !self.synthesizer.isSpeaking { self.onSpeakingChanged?(false) }
        }
    }
}
