extension Position {
    /// Standard Algebraic Notation for a legal move in this position, e.g. "Nbxd2+", "e8=Q#", "O-O".
    public func san(_ move: Move) -> String {
        var s: String
        if let side = move.castle {
            s = side == .kingside ? "O-O" : "O-O-O"
        } else if move.piece.kind == .pawn {
            s = move.captured != nil ? "\(move.from.fileLetter)x\(move.to.name)" : move.to.name
            if let promo = move.promotion { s += "=" + promo.sanLetter }
        } else {
            let rivals = legalMoves().filter { $0.piece == move.piece && $0.to == move.to && $0.from != move.from }
            var disambiguation = ""
            if !rivals.isEmpty {
                let sameFile = rivals.contains { $0.from.file == move.from.file }
                let sameRank = rivals.contains { $0.from.rank == move.from.rank }
                if !sameFile {
                    disambiguation = String(move.from.fileLetter)
                } else if !sameRank {
                    disambiguation = String(move.from.rankNumber)
                } else {
                    disambiguation = move.from.name
                }
            }
            s = move.piece.kind.sanLetter + disambiguation + (move.captured != nil ? "x" : "") + move.to.name
        }
        let after = applying(move)
        if after.inCheck { s += after.legalMoves().isEmpty ? "#" : "+" }
        return s
    }

    /// Finds the legal move matching a SAN string (check marks and annotations are ignored).
    public func move(san: String) -> Move? {
        let wanted = Self.stripSAN(san)
        return legalMoves().first { Self.stripSAN(self.san($0)) == wanted }
    }

    static func stripSAN(_ san: String) -> String {
        String(san.compactMap { ch -> Character? in
            if "+#!?".contains(ch) { return nil }
            return ch == "0" ? "O" : ch // "0-0" is a common way to write castling
        })
    }
}

/// A game as a list of positions and moves, built from Lichess' space-separated UCI move list.
public struct GameLine: Sendable {
    public private(set) var positions: [Position]
    public private(set) var moves: [Move]
    public private(set) var sans: [String]

    public init(initial: Position = .start) {
        positions = [initial]
        moves = []
        sans = []
    }

    public var current: Position { positions[positions.count - 1] }
    public var lastMove: Move? { moves.last }

    /// Appends a move given in UCI. Returns false (and changes nothing) if it is illegal.
    @discardableResult
    public mutating func play(uci: String) -> Bool {
        guard let m = current.move(uci: uci) else { return false }
        play(m)
        return true
    }

    public mutating func play(_ move: Move) {
        sans.append(current.san(move))
        positions.append(current.applying(move))
        moves.append(move)
    }
}
