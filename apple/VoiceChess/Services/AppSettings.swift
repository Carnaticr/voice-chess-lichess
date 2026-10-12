import Foundation
import Observation

/// User preferences, persisted in UserDefaults.
@Observable @MainActor
final class AppSettings {
    private let defaults: UserDefaults

    var announceOpponent: Bool { didSet { save(announceOpponent, "announceOpponent") } }
    var detailedCaptures: Bool { didSet { save(detailedCaptures, "detailedCaptures") } }
    var threatWarnings: Bool { didSet { save(threatWarnings, "threatWarnings") } }
    var echoMyMoves: Bool { didSet { save(echoMyMoves, "echoMyMoves") } }
    var confirmMoves: Bool { didSet { save(confirmMoves, "confirmMoves") } }
    var clockWarnings: Bool { didSet { save(clockWarnings, "clockWarnings") } }
    /// AVSpeechSynthesisVoice identifier; empty = system default.
    var voiceIdentifier: String { didSet { save(voiceIdentifier, "voiceIdentifier") } }
    /// 0...1, AVSpeechUtterance rate scale.
    var speechRate: Double { didSet { save(speechRate, "speechRate") } }
    var boardTheme: BoardTheme { didSet { save(boardTheme.rawValue, "boardTheme") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "announceOpponent": true, "detailedCaptures": true, "threatWarnings": true, "echoMyMoves": true,
            "confirmMoves": false, "clockWarnings": true, "voiceIdentifier": "", "speechRate": 0.5,
            "boardTheme": BoardTheme.brown.rawValue,
        ])
        announceOpponent = defaults.bool(forKey: "announceOpponent")
        detailedCaptures = defaults.bool(forKey: "detailedCaptures")
        threatWarnings = defaults.bool(forKey: "threatWarnings")
        echoMyMoves = defaults.bool(forKey: "echoMyMoves")
        confirmMoves = defaults.bool(forKey: "confirmMoves")
        clockWarnings = defaults.bool(forKey: "clockWarnings")
        voiceIdentifier = defaults.string(forKey: "voiceIdentifier") ?? ""
        speechRate = defaults.double(forKey: "speechRate")
        boardTheme = BoardTheme(rawValue: defaults.string(forKey: "boardTheme") ?? "") ?? .brown
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
