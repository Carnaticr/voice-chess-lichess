import AVFoundation
import Observation
import Speech

/// Continuous speech recognition with Apple's Speech framework.
///
/// Each utterance is delivered once it is final, or once the partial transcript has been
/// stable for a moment (people pause after "knight f three"). Transcripts heard while the
/// app itself is speaking are discarded so announcements are never mistaken for moves.
@Observable @MainActor
final class VoiceInput {
    enum State: Equatable {
        case off, starting, listening
        case unavailable(String)
    }

    private(set) var state: State = .off
    private(set) var transcript = ""
    /// Receives (text, isFinal); return true if the text was acted on, which starts a fresh utterance.
    @ObservationIgnored var onUtterance: ((String, Bool) -> Bool)?
    /// Hints that bias recognition toward chess vocabulary.
    @ObservationIgnored var contextualStrings: [String] = VoiceInput.chessVocabulary

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let sink = BufferSink()
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var stableTimer: Task<Void, Never>?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var paused = false

    static let chessVocabulary = [
        "knight", "bishop", "rook", "queen", "king", "pawn", "takes", "castle", "kingside", "queenside",
        "short castle", "long castle", "promote", "resign", "offer draw", "accept draw", "decline draw",
        "repeat", "next", "back", "best move", "summary", "next mistake",
        "a1", "b2", "c3", "d4", "e4", "e5", "f3", "f6", "g5", "h7",
    ]

    var isOn: Bool { state == .listening || state == .starting }

    func toggle() async {
        if isOn { stop() } else { await start() }
    }

    func start() async {
        guard !isOn else { return }
        state = .starting
        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable(String(localized: "Speech recognition isn't available right now."))
            return
        }
        guard await Self.requestPermissions() else {
            state = .unavailable(String(localized: "Allow microphone and speech recognition access in Settings."))
            return
        }
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            let sink = sink
            // @Sendable: this runs on the realtime audio thread, not the main actor.
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
                sink.append(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            state = .unavailable(error.localizedDescription)
            return
        }
        state = .listening
        beginUtterance()
    }

    func stop() {
        generation += 1
        stableTimer?.cancel()
        watchdog?.cancel()
        sink.set(nil)
        task?.cancel()
        task = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        transcript = ""
        if case .unavailable = state { return }
        state = .off
    }

    /// While paused (the app is speaking) nothing is delivered; resuming starts a clean utterance.
    func setPaused(_ paused: Bool) {
        self.paused = paused
        if !paused && state == .listening { beginUtterance() }
    }

    private func beginUtterance() {
        guard state == .listening, let recognizer else { return }
        generation += 1
        let gen = generation
        stableTimer?.cancel()
        task?.cancel()
        transcript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .confirmation
        request.contextualStrings = contextualStrings
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        sink.set(request)

        task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in self?.received(text: text, isFinal: isFinal, failed: failed, generation: gen) }
        }

        // Recognition requests are limited to about a minute; recycle well before that.
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled, let self, self.generation == gen else { return }
            self.beginUtterance()
        }
    }

    private func received(text: String?, isFinal: Bool, failed: Bool, generation gen: Int) {
        guard gen == generation, state == .listening else { return }
        if paused { return }
        if let text, !text.isEmpty {
            transcript = text
            stableTimer?.cancel()
            if isFinal {
                _ = onUtterance?(text, true)
                beginUtterance()
                return
            }
            stableTimer = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled, let self, self.generation == gen, self.transcript == text else { return }
                if self.onUtterance?(text, false) == true { self.beginUtterance() }
            }
        } else if isFinal || failed {
            beginUtterance()
        }
    }

    private static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        #if os(iOS)
        return await AVAudioApplication.requestRecordPermission()
        #else
        return await AVCaptureDevice.requestAccess(for: .audio)
        #endif
    }
}

/// Hands audio buffers from the realtime audio thread to the current recognition request.
private final class BufferSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request?.endAudio()
        self.request = request
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        request?.append(buffer)
        lock.unlock()
    }
}
