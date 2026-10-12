import Foundation
import Testing
@testable import VoiceChessCore

private func pos(_ fen: String) throws -> Position {
    try #require(Position(fen: fen))
}

private func uci(_ text: String, _ p: Position) -> String? {
    if case .move(let m) = VoiceParser.parse(text, position: p) { return m.uci }
    return nil
}

@Suite("Voice parser")
struct VoiceParserTests {
    let start = Position.start

    @Test(arguments: [
        ("e four", "e2e4"), ("E4", "e2e4"), ("echo four", "e2e4"), ("pawn to e4", "e2e4"), ("e 4", "e2e4"),
        ("knight f3", "g1f3"), ("Knight to F3.", "g1f3"), ("night f three", "g1f3"), ("horse to foxtrot three", "g1f3"),
        ("g1 f3", "g1f3"), ("g one to f three", "g1f3"), ("Nf3", "g1f3"), ("e2e4", "e2e4"), ("knight c3", "b1c3"),
        ("d for", "d2d4"), ("pawn d4 check", "d2d4"),
    ])
    func startPositionMoves(text: String, expected: String) {
        #expect(uci(text, start) == expected)
    }

    @Test func capturesAndPieces() throws {
        let p = try pos("rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2")
        #expect(uci("e takes d5", p) == "e4d5")
        #expect(uci("pawn takes d five", p) == "e4d5")
        #expect(uci("e takes d", p) == "e4d5")
        #expect(uci("exd5", p) == "e4d5")
        let bxc6 = try pos("r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 2 3")
        #expect(uci("bishop takes c6", bxc6) == "b5c6")
        #expect(uci("bishop takes knight on see six", bxc6) == "b5c6")
    }

    @Test func disambiguation() throws {
        let p = try pos("4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1")
        #expect(uci("knight b d2", p) == "b1d2")
        #expect(uci("knight on f3 to d2", p) == "f3d2")
        if case .ambiguous(let moves) = VoiceParser.parse("knight d2", position: p) {
            #expect(Set(moves.map(\.uci)) == ["b1d2", "f3d2"])
        } else {
            Issue.record("expected ambiguity")
        }
        let rooks = try pos("4k3/8/8/8/8/8/8/R4RK1 w - - 0 1")
        #expect(uci("rook a d1", rooks) == "a1d1")
    }

    @Test func castlingAndPromotion() throws {
        let p = try pos("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        #expect(uci("castle short", p) == "e1g1")
        #expect(uci("castles kingside", p) == "e1g1")
        #expect(uci("long castle", p) == "e1c1")
        #expect(uci("O-O-O", p) == "e1c1")
        #expect(uci("castle queen side", p) == "e1c1")
        if case .ambiguous = VoiceParser.parse("castle", position: p) {} else { Issue.record("castle should be ambiguous") }

        let promo = try pos("8/4P3/8/8/8/8/k7/4K3 w - - 0 1")
        #expect(uci("e8 queen", promo) == "e7e8q")
        #expect(uci("e eight promote to knight", promo) == "e7e8n")
        #expect(uci("e8", promo) == "e7e8q") // auto-queen
    }

    @Test func illegalAndNoise() {
        #expect(VoiceParser.parse("knight e5", position: start) == .illegal)
        #expect(VoiceParser.parse("what a nice day", position: start) == .none)
        #expect(VoiceParser.parse("", position: start) == .none)
    }

    @Test func commands() {
        #expect(VoiceParser.parse("I resign", position: start) == .command(.resign))
        #expect(VoiceParser.parse("offer a draw", position: start) == .command(.offerDraw))
        #expect(VoiceParser.parse("Yes", position: start) == .command(.yes))
        #expect(VoiceParser.parse("say again", position: start) == .command(.repeatLast))
        #expect(VoiceParser.parse("how much time", position: start) == .command(.time))
        #expect(VoiceParser.parse("next", position: nil, reviewing: true) == .command(.next))
        #expect(VoiceParser.parse("go to move twelve", position: nil, reviewing: true) == .command(.goToMove(12)))
        #expect(VoiceParser.parse("move 42", position: nil, reviewing: true) == .command(.goToMove(42)))
        #expect(VoiceParser.parse("next mistake", position: nil, reviewing: true) == .command(.nextMistake))
        #expect(VoiceParser.parse("next move", position: nil, reviewing: true) == .command(.next))
    }
}

@Suite("Speech text")
struct SpeechTextTests {
    @Test func sanToSpeech() {
        #expect(SpeechText.san("Nbxd2+") == "Knight bee takes dee 2, check")
        #expect(SpeechText.san("e4") == "Ee 4")
        #expect(SpeechText.san("exd5") == "Ee takes dee 5")
        #expect(SpeechText.san("O-O-O#") == "Castles queenside, checkmate")
        #expect(SpeechText.san("e8=Q+") == "Ee 8 promotes to queen, check")
        #expect(SpeechText.san("R1a3") == "Rook 1 ay 3")
    }

    @Test func detailedCaptures() throws {
        let p = try pos("r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 2 3")
        let m = try #require(p.move(uci: "b5c6"))
        #expect(SpeechText.move(m, san: p.san(m), detailed: true) == "Bishop takes knight on see 6")
        let q = try pos("rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2")
        let exd5 = try #require(q.move(uci: "e4d5"))
        #expect(SpeechText.move(exd5, san: q.san(exd5), detailed: true) == "Ee pawn takes pawn on dee 5")
    }

    @Test func durations() {
        #expect(SpeechText.duration(milliseconds: 597_000) == "9 minutes 57 seconds")
        #expect(SpeechText.duration(milliseconds: 60_000) == "1 minute")
        #expect(SpeechText.duration(milliseconds: 900) == "0 seconds")
    }
}

@Suite("Threats")
struct ThreatTests {
    @Test func attackedHangingDefended() throws {
        let queen = try pos("r1bqkb1r/pppp1ppp/2n2n2/8/3Q4/8/PPP2PPP/RNB1KBNR w KQkq - 0 1")
        let t = Threats.find(in: queen, for: .white)
        #expect(t.map(\.square.name) == ["d4"])
        #expect(t.first?.attacker == .knight && t.first?.kind == .attacked)
        #expect(SpeechText.threat(try #require(t.first)) == "Your queen on dee 4 is attacked by a knight.")

        let hanging = try pos("4k3/4q3/8/4N3/8/8/8/K7 w - - 0 1")
        #expect(Threats.find(in: hanging, for: .white).first?.kind == .hanging)

        let defended = try pos("4k3/4q3/8/4N3/3P4/8/8/K7 w - - 0 1")
        #expect(Threats.find(in: defended, for: .white).isEmpty)

        #expect(Threats.new(before: t, after: t).isEmpty)
        #expect(Threats.new(before: [], after: t).count == 1)
    }
}

@Suite("Lichess payloads")
struct LichessModelTests {
    @Test func decodesGameStream() throws {
        let full = """
        {"type":"gameFull","id":"abc12345","rated":false,"speed":"rapid","variant":{"key":"standard","name":"Standard"},
         "white":{"id":"me","name":"Me","rating":1500},"black":{"aiLevel":3},"initialFen":"startpos",
         "state":{"type":"gameState","moves":"e2e4 e7e5","wtime":600000,"btime":598000,"status":"started"}}
        """
        guard case .gameFull(let g) = try JSONDecoder().decode(GameStreamEvent.self, from: Data(full.utf8)) else {
            Issue.record("not gameFull"); return
        }
        #expect(g.black.displayName == "Stockfish level 3")
        #expect(g.state.uciMoves == ["e2e4", "e7e5"])
        #expect(g.state.isOver == false)

        let chat = #"{"type":"chatLine","username":"opp","text":"gl","room":"player"}"#
        #expect(try JSONDecoder().decode(GameStreamEvent.self, from: Data(chat.utf8)) == .chatLine(username: "opp", text: "gl", room: "player"))
    }

    @Test func decodesAccountEvents() throws {
        let start = #"{"type":"gameStart","game":{"gameId":"xyz98765","color":"white"}}"#
        #expect(try JSONDecoder().decode(AccountEvent.self, from: Data(start.utf8)) == .gameStart(gameId: "xyz98765"))
        let other = #"{"type":"challengeDeclined","challenge":{}}"#
        #expect(try JSONDecoder().decode(AccountEvent.self, from: Data(other.utf8)) == .other)
    }

    @Test func formEncoding() {
        #expect(LichessClient.formBody(["clock.limit": "600", "color": "random"]) == "clock.limit=600&color=random")
    }
}
