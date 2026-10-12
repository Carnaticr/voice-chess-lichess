import Testing
@testable import VoiceChessCore

private func perft(_ p: Position, _ depth: Int) -> Int {
    if depth == 0 { return 1 }
    let moves = p.legalMoves()
    if depth == 1 { return moves.count }
    return moves.reduce(0) { $0 + perft(p.applying($1), depth - 1) }
}

private func pos(_ fen: String) throws -> Position {
    try #require(Position(fen: fen))
}

@Suite("Move generation (perft)")
struct PerftTests {
    @Test func startPosition() {
        #expect(perft(.start, 1) == 20)
        #expect(perft(.start, 2) == 400)
        #expect(perft(.start, 3) == 8902)
    }

    @Test func kiwipeteCastlingAndPins() throws {
        let p = try pos("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
        #expect(perft(p, 1) == 48)
        #expect(perft(p, 2) == 2039)
    }

    @Test func enPassantAndDiscoveredChecks() throws {
        let p = try pos("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1")
        #expect(perft(p, 1) == 14)
        #expect(perft(p, 2) == 191)
        #expect(perft(p, 3) == 2812)
    }

    @Test func promotions() throws {
        let p = try pos("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1")
        #expect(perft(p, 1) == 6)
        #expect(perft(p, 2) == 264)
        #expect(perft(p, 3) == 9467)
    }
}

@Suite("Positions and notation")
struct NotationTests {
    @Test func fenRoundTrip() throws {
        let fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
        #expect(try pos(fen).fen == fen)
        #expect(Position.start.fen == Position.startFEN)
    }

    @Test func sanBasics() throws {
        var line = GameLine()
        for uci in ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6", "b5c6", "d7c6", "e1g1"] {
            #expect(line.play(uci: uci))
        }
        #expect(line.sans == ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Bxc6", "dxc6", "O-O"])
        #expect(line.play(uci: "e1e2") == false)
    }

    @Test func sanDisambiguationCheckAndMate() throws {
        let knights = try pos("4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1")
        let nbd2 = try #require(knights.move(uci: "b1d2"))
        #expect(knights.san(nbd2) == "Nbd2")

        let rooks = try pos("4k3/8/8/R7/8/8/8/R3K3 w - - 0 1") // rooks a1 + a5 both reach a3
        #expect(rooks.san(try #require(rooks.move(uci: "a1a3"))) == "R1a3")

        let mate = try pos("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")
        #expect(mate.san(try #require(mate.move(uci: "a1a8"))) == "Ra8#")
        #expect(mate.applying(try #require(mate.move(uci: "a1a8"))).isCheckmate)

        let promo = try pos("8/4P3/8/8/8/8/k7/4K3 w - - 0 1")
        #expect(promo.san(try #require(promo.move(uci: "e7e8q"))) == "e8=Q")
        #expect(promo.move(san: "e8=N")?.promotion == .knight)
    }

    @Test func squareColors() {
        #expect(Square("a1")?.isLight == false)
        #expect(Square("h1")?.isLight == true)
        #expect(Square("e4")?.isLight == true)
    }
}
