import Foundation
import Observation
import VoiceChessCore

/// App-wide state: authentication, the Lichess event stream, and the current game.
@Observable @MainActor
final class AppModel {
    enum Phase: Equatable { case restoring, loggedOut, lobby, game }

    private(set) var phase: Phase = .restoring
    private(set) var account: Account?
    private(set) var game: GameModel?
    private(set) var seeking = false
    private(set) var connected = false
    private(set) var spokenLog: [String] = []
    var errorMessage: String?
    var loginError: String?
    var busy = false

    let settings: AppSettings
    let voice: VoiceInput
    @ObservationIgnored let announcer: Announcer
    @ObservationIgnored private var client: LichessClient?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var seekTask: Task<Void, Never>?

    init() {
        let settings = AppSettings()
        let voice = VoiceInput()
        let announcer = Announcer()
        self.settings = settings
        self.voice = voice
        self.announcer = announcer
        announcer.onSpeakingChanged = { [weak voice] speaking in voice?.setPaused(speaking) }
        announcer.onSay = { [weak self] text in
            guard let self else { return }
            self.spokenLog.insert(text, at: 0)
            if self.spokenLog.count > 30 { self.spokenLog.removeLast() }
        }
        voice.onUtterance = { [weak self] text, isFinal in
            self?.game?.handleSpeech(text, isFinal: isFinal) ?? false
        }
        applyVoiceSettings()
    }

    func applyVoiceSettings() {
        announcer.voiceIdentifier = settings.voiceIdentifier
        announcer.rate = settings.speechRate
    }

    // MARK: Auth

    func restore() async {
        guard let token = KeychainStore.load() else { phase = .loggedOut; return }
        do {
            try await connect(token: token)
        } catch {
            loginError = String(localized: "Couldn't reconnect: \(error.localizedDescription)")
            phase = .loggedOut
        }
    }

    func login(token raw: String) async {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { loginError = String(localized: "Paste a token first."); return }
        busy = true
        defer { busy = false }
        do {
            try await connect(token: token)
            KeychainStore.save(token)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
    }

    private func connect(token: String) async throws {
        let c = LichessClient(token: token)
        let acc = try await c.account()
        client = c
        account = acc
        phase = .lobby
        if let scopes = try? await c.scopes(), !scopes.contains("board:play") {
            errorMessage = String(localized: "This token is missing the board:play scope. Create a new token from the login screen.")
        }
        eventsTask?.cancel()
        eventsTask = Task { await runEvents() }
    }

    func logout() {
        eventsTask?.cancel()
        seekTask?.cancel()
        game?.stop()
        game = nil
        voice.stop()
        client = nil
        account = nil
        connected = false
        KeychainStore.delete()
        phase = .loggedOut
    }

    // MARK: Events

    private func runEvents() async {
        var delay = 1.0
        while !Task.isCancelled, let client {
            do {
                connected = true
                for try await event in client.accountEvents() {
                    delay = 1
                    handle(event)
                }
            } catch {
                if Task.isCancelled { return }
                if let e = error as? LichessError, e.status == 401 {
                    connected = false
                    errorMessage = String(localized: "Lichess rejected the token. Please log in again.")
                    logout()
                    return
                }
            }
            connected = false
            try? await Task.sleep(for: .seconds(delay))
            delay = min(delay * 2, 30)
        }
    }

    private func handle(_ event: AccountEvent) {
        switch event {
        case .gameStart(let id):
            if game == nil || game?.isOver == true {
                cancelSeek()
                openGame(id)
            } else if game?.id != id {
                errorMessage = String(localized: "Another game is in progress (\(id)).")
            }
        case .challenge(let from, let toMe) where toMe:
            errorMessage = String(localized: "Challenge from \(from). Accept it on lichess.org to play it here.")
        default:
            break
        }
    }

    // MARK: Games

    func openGame(_ id: String) {
        guard let client, let account, game?.id != id else { return }
        game?.stop()
        let g = GameModel(id: id, client: client, me: account, settings: settings, announcer: announcer)
        g.onStopListening = { [weak self] in self?.voice.stop() }
        game = g
        g.start()
        phase = .game
    }

    func leaveGame() {
        game?.stop()
        game = nil
        voice.stop()
        phase = .lobby
    }

    func playComputer(level: Int, minutes: Int, increment: Int, color: String) async {
        guard let client else { return }
        busy = true
        defer { busy = false }
        do {
            let id = try await client.challengeAI(level: level, limitSeconds: minutes * 60, increment: increment, color: color)
            openGame(id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func seek(minutes: Int, increment: Int, rated: Bool) {
        guard let client else { return }
        seekTask?.cancel()
        seeking = true
        seekTask = Task {
            defer { seeking = false }
            do {
                try await client.seek(minutes: minutes, increment: increment, rated: rated)
            } catch is CancellationError {
            } catch let e as URLError where e.code == .cancelled {
            } catch {
                errorMessage = String(localized: "Seek failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelSeek() {
        seekTask?.cancel()
        seekTask = nil
        seeking = false
    }
}
