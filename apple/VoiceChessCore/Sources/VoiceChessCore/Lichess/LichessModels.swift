// Subset of the Lichess API payloads this app uses. https://lichess.org/api

public struct Account: Decodable, Sendable, Equatable {
    public let id: String
    public let username: String
}

public struct LichessPlayer: Decodable, Sendable, Equatable {
    public let id: String?
    public let name: String?
    public let rating: Int?
    public let provisional: Bool?
    public let aiLevel: Int?

    public var displayName: String {
        if let aiLevel { return "Stockfish level \(aiLevel)" }
        return name ?? id ?? "Anonymous"
    }
}

public struct GameState: Decodable, Sendable, Equatable {
    public let moves: String
    public let wtime: Int
    public let btime: Int
    public let status: String
    public let winner: String?
    public let wdraw: Bool?
    public let bdraw: Bool?

    public var uciMoves: [String] { moves.split(separator: " ").map(String.init) }
    public var isOver: Bool { !["created", "started"].contains(status) }
}

public struct GameFull: Decodable, Sendable, Equatable {
    public struct Variant: Decodable, Sendable, Equatable { public let key: String; public let name: String }
    public let id: String
    public let white: LichessPlayer
    public let black: LichessPlayer
    public let initialFen: String?
    public let rated: Bool?
    public let speed: String?
    public let variant: Variant?
    public let state: GameState
}

public enum GameStreamEvent: Decodable, Sendable, Equatable {
    case gameFull(GameFull)
    case gameState(GameState)
    case chatLine(username: String, text: String, room: String)
    case opponentGone(gone: Bool, claimWinInSeconds: Int?)
    case other

    private enum Keys: String, CodingKey { case type, username, text, room, gone, claimWinInSeconds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decodeIfPresent(String.self, forKey: .type) {
        case "gameFull": self = .gameFull(try GameFull(from: decoder))
        case "gameState": self = .gameState(try GameState(from: decoder))
        case "chatLine":
            self = .chatLine(username: try c.decode(String.self, forKey: .username),
                             text: try c.decode(String.self, forKey: .text),
                             room: try c.decodeIfPresent(String.self, forKey: .room) ?? "player")
        case "opponentGone":
            self = .opponentGone(gone: try c.decode(Bool.self, forKey: .gone),
                                 claimWinInSeconds: try c.decodeIfPresent(Int.self, forKey: .claimWinInSeconds))
        default: self = .other
        }
    }
}

public enum AccountEvent: Decodable, Sendable, Equatable {
    case gameStart(gameId: String)
    case gameFinish(gameId: String)
    case challenge(from: String, toMe: Bool)
    case other

    private enum Keys: String, CodingKey { case type, game, challenge }
    private struct Game: Decodable { let gameId: String?; let id: String? }
    private struct Challenge: Decodable {
        struct User: Decodable { let id: String?; let name: String? }
        let challenger: User?
        let destUser: User?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decodeIfPresent(String.self, forKey: .type) {
        case "gameStart", "gameFinish":
            let g = try c.decode(Game.self, forKey: .game)
            let id = g.gameId ?? g.id ?? ""
            self = try c.decode(String.self, forKey: .type) == "gameStart" ? .gameStart(gameId: id) : .gameFinish(gameId: id)
        case "challenge":
            let ch = try c.decode(Challenge.self, forKey: .challenge)
            self = .challenge(from: ch.challenger?.name ?? "someone", toMe: ch.destUser != nil)
        default:
            self = .other
        }
    }
}

/// /game/export with evals: Lichess' server analysis, when the game has been analysed.
public struct GameExport: Decodable, Sendable {
    public struct Opening: Decodable, Sendable { public let name: String }
    public struct Judgment: Decodable, Sendable { public let name: String }
    public struct PlyAnalysis: Decodable, Sendable {
        public let eval: Int?
        public let mate: Int?
        public let best: String?
        public let judgment: Judgment?
    }
    public struct SideAnalysis: Decodable, Sendable, Equatable {
        public let inaccuracy: Int
        public let mistake: Int
        public let blunder: Int
        public let accuracy: Int?
    }
    public struct Side: Decodable, Sendable { public let analysis: SideAnalysis? }
    public struct Players: Decodable, Sendable { public let white: Side; public let black: Side }

    public let opening: Opening?
    public let analysis: [PlyAnalysis]?
    public let players: Players
}

struct TokenTestResult: Decodable { let scopes: String? }
