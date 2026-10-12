/// An immutable-by-convention chess position with legal move generation.
public struct Position: Hashable, Sendable {
    public private(set) var board: [Piece?]
    public private(set) var sideToMove: PieceColor
    public private(set) var castling: CastlingRights
    public private(set) var enPassant: Square?
    public private(set) var halfmoveClock: Int
    public private(set) var fullmoveNumber: Int

    public static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    public static let start = Position(trustedFEN: startFEN)

    public subscript(square: Square) -> Piece? { board[square.index] }

    // MARK: FEN

    public init?(fen: String) {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 2 else { return nil }
        var board = [Piece?](repeating: nil, count: 64)
        let rows = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard rows.count == 8 else { return nil }
        for (i, row) in rows.enumerated() {
            let rank = 7 - i
            var file = 0
            for ch in row {
                if let n = ch.wholeNumberValue {
                    file += n
                } else {
                    guard let piece = Piece(fenChar: ch), let sq = Square(file: file, rank: rank) else { return nil }
                    board[sq.index] = piece
                    file += 1
                }
            }
            guard file == 8 else { return nil }
        }
        self.board = board
        switch fields[1] {
        case "w": sideToMove = .white
        case "b": sideToMove = .black
        default: return nil
        }
        var rights: CastlingRights = []
        if fields.count > 2 {
            for ch in fields[2] {
                switch ch {
                case "K": rights.insert(.whiteKingside)
                case "Q": rights.insert(.whiteQueenside)
                case "k": rights.insert(.blackKingside)
                case "q": rights.insert(.blackQueenside)
                default: break
                }
            }
        }
        castling = rights
        enPassant = fields.count > 3 ? Square(fields[3]) : nil
        halfmoveClock = fields.count > 4 ? Int(fields[4]) ?? 0 : 0
        fullmoveNumber = fields.count > 5 ? Int(fields[5]) ?? 1 : 1
    }

    private init(trustedFEN: String) {
        guard let p = Position(fen: trustedFEN) else { preconditionFailure("invalid built-in FEN") }
        self = p
    }

    public var fen: String {
        var rows: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var row = ""
            var empty = 0
            for file in 0..<8 {
                if let p = board[rank * 8 + file] {
                    if empty > 0 { row += String(empty); empty = 0 }
                    row.append(p.fenChar)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { row += String(empty) }
            rows.append(row)
        }
        var castle = ""
        if castling.contains(.whiteKingside) { castle += "K" }
        if castling.contains(.whiteQueenside) { castle += "Q" }
        if castling.contains(.blackKingside) { castle += "k" }
        if castling.contains(.blackQueenside) { castle += "q" }
        return [
            rows.joined(separator: "/"),
            sideToMove == .white ? "w" : "b",
            castle.isEmpty ? "-" : castle,
            enPassant?.name ?? "-",
            String(halfmoveClock),
            String(fullmoveNumber),
        ].joined(separator: " ")
    }

    // MARK: Attacks

    static let knightOffsets = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
    static let kingOffsets = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
    static let rookDirections = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    static let bishopDirections = [(1, 1), (1, -1), (-1, 1), (-1, -1)]

    /// Squares holding pieces of `color` that attack `square` (regardless of pins).
    public func attackers(of square: Square, by color: PieceColor) -> [Square] {
        var result: [Square] = []
        // A pawn of `color` attacks diagonally forward, so look one rank "behind" the target.
        let back = color == .white ? -1 : 1
        for df in [-1, 1] {
            if let s = square.offset(file: df, rank: back), self[s] == Piece(.pawn, color) { result.append(s) }
        }
        for (df, dr) in Self.knightOffsets {
            if let s = square.offset(file: df, rank: dr), self[s] == Piece(.knight, color) { result.append(s) }
        }
        for (df, dr) in Self.kingOffsets {
            if let s = square.offset(file: df, rank: dr), self[s] == Piece(.king, color) { result.append(s) }
        }
        for (dirs, kinds) in [(Self.rookDirections, [PieceKind.rook, .queen]), (Self.bishopDirections, [.bishop, .queen])] {
            for (df, dr) in dirs {
                var cur = square.offset(file: df, rank: dr)
                while let s = cur {
                    if let p = self[s] {
                        if p.color == color && kinds.contains(p.kind) { result.append(s) }
                        break
                    }
                    cur = s.offset(file: df, rank: dr)
                }
            }
        }
        return result
    }

    public func isAttacked(_ square: Square, by color: PieceColor) -> Bool {
        !attackers(of: square, by: color).isEmpty
    }

    public func kingSquare(_ color: PieceColor) -> Square? {
        board.firstIndex(of: Piece(.king, color)).map { Square(index: $0) }
    }

    public var inCheck: Bool {
        guard let k = kingSquare(sideToMove) else { return false }
        return isAttacked(k, by: sideToMove.opposite)
    }

    // MARK: Move generation

    public func legalMoves() -> [Move] {
        let us = sideToMove
        return pseudoLegalMoves().filter { move in
            let after = applying(move)
            guard let k = after.kingSquare(us) else { return false }
            return !after.isAttacked(k, by: us.opposite)
        }
    }

    public func legalMoves(from square: Square) -> [Move] {
        legalMoves().filter { $0.from == square }
    }

    private func pseudoLegalMoves() -> [Move] {
        let us = sideToMove
        var moves: [Move] = []
        for sq in Square.all {
            guard let piece = self[sq], piece.color == us else { continue }
            switch piece.kind {
            case .pawn: addPawnMoves(from: sq, piece: piece, into: &moves)
            case .knight: addStepMoves(from: sq, piece: piece, offsets: Self.knightOffsets, into: &moves)
            case .king:
                addStepMoves(from: sq, piece: piece, offsets: Self.kingOffsets, into: &moves)
                addCastling(from: sq, piece: piece, into: &moves)
            case .bishop: addSlides(from: sq, piece: piece, directions: Self.bishopDirections, into: &moves)
            case .rook: addSlides(from: sq, piece: piece, directions: Self.rookDirections, into: &moves)
            case .queen: addSlides(from: sq, piece: piece, directions: Self.rookDirections + Self.bishopDirections, into: &moves)
            }
        }
        return moves
    }

    private func addPawnMoves(from sq: Square, piece: Piece, into moves: inout [Move]) {
        let dir = piece.color == .white ? 1 : -1
        let startRank = piece.color == .white ? 1 : 6
        let promoRank = piece.color == .white ? 7 : 0
        func add(_ to: Square, captured: PieceKind?, enPassant: Bool = false) {
            if to.rank == promoRank {
                for promo in [PieceKind.queen, .rook, .bishop, .knight] {
                    moves.append(Move(from: sq, to: to, piece: piece, captured: captured, promotion: promo))
                }
            } else {
                moves.append(Move(from: sq, to: to, piece: piece, captured: captured, isEnPassant: enPassant))
            }
        }
        if let one = sq.offset(file: 0, rank: dir), self[one] == nil {
            add(one, captured: nil)
            if sq.rank == startRank, let two = sq.offset(file: 0, rank: 2 * dir), self[two] == nil {
                add(two, captured: nil)
            }
        }
        for df in [-1, 1] {
            guard let to = sq.offset(file: df, rank: dir) else { continue }
            if let target = self[to], target.color != piece.color {
                add(to, captured: target.kind)
            } else if to == enPassant {
                add(to, captured: .pawn, enPassant: true)
            }
        }
    }

    private func addStepMoves(from sq: Square, piece: Piece, offsets: [(Int, Int)], into moves: inout [Move]) {
        for (df, dr) in offsets {
            guard let to = sq.offset(file: df, rank: dr) else { continue }
            if let target = self[to] {
                if target.color != piece.color { moves.append(Move(from: sq, to: to, piece: piece, captured: target.kind)) }
            } else {
                moves.append(Move(from: sq, to: to, piece: piece))
            }
        }
    }

    private func addSlides(from sq: Square, piece: Piece, directions: [(Int, Int)], into moves: inout [Move]) {
        for (df, dr) in directions {
            var cur = sq.offset(file: df, rank: dr)
            while let to = cur {
                if let target = self[to] {
                    if target.color != piece.color { moves.append(Move(from: sq, to: to, piece: piece, captured: target.kind)) }
                    break
                }
                moves.append(Move(from: sq, to: to, piece: piece))
                cur = to.offset(file: df, rank: dr)
            }
        }
    }

    private func addCastling(from sq: Square, piece: Piece, into moves: inout [Move]) {
        let us = piece.color
        let them = us.opposite
        let rank = us == .white ? 0 : 7
        guard sq == Square(file: 4, rank: rank), !isAttacked(sq, by: them) else { return }
        let rook = Piece(.rook, us)
        func at(_ file: Int) -> Square { Square(index: rank * 8 + file) }
        if castling.contains(.kingside(us)), self[at(7)] == rook, self[at(5)] == nil, self[at(6)] == nil,
           !isAttacked(at(5), by: them), !isAttacked(at(6), by: them) {
            moves.append(Move(from: at(4), to: at(6), piece: piece, castle: .kingside))
        }
        if castling.contains(.queenside(us)), self[at(0)] == rook, self[at(1)] == nil, self[at(2)] == nil, self[at(3)] == nil,
           !isAttacked(at(3), by: them), !isAttacked(at(2), by: them) {
            moves.append(Move(from: at(4), to: at(2), piece: piece, castle: .queenside))
        }
    }

    // MARK: Making moves

    public func applying(_ move: Move) -> Position {
        var next = self
        let us = move.piece.color
        next.board[move.from.index] = nil
        if move.isEnPassant, let victim = Square(file: move.to.file, rank: move.from.rank) {
            next.board[victim.index] = nil
        }
        next.board[move.to.index] = move.promotion.map { Piece($0, us) } ?? move.piece
        if let side = move.castle {
            let rank = move.from.rank
            let (rookFrom, rookTo) = side == .kingside ? (7, 5) : (0, 3)
            next.board[rank * 8 + rookFrom] = nil
            next.board[rank * 8 + rookTo] = Piece(.rook, us)
        }

        if move.piece.kind == .king {
            next.castling.subtract([.kingside(us), .queenside(us)])
        }
        // Moving from or capturing on a rook's home square removes that right.
        for sq in [move.from, move.to] {
            switch sq.index {
            case 0: next.castling.remove(.whiteQueenside)
            case 7: next.castling.remove(.whiteKingside)
            case 56: next.castling.remove(.blackQueenside)
            case 63: next.castling.remove(.blackKingside)
            default: break
            }
        }

        if move.piece.kind == .pawn, abs(move.to.rank - move.from.rank) == 2 {
            next.enPassant = Square(file: move.from.file, rank: (move.from.rank + move.to.rank) / 2)
        } else {
            next.enPassant = nil
        }
        next.halfmoveClock = (move.piece.kind == .pawn || move.captured != nil) ? 0 : halfmoveClock + 1
        if us == .black { next.fullmoveNumber += 1 }
        next.sideToMove = us.opposite
        return next
    }

    /// Finds the legal move for a UCI string such as "e2e4" or "e7e8q".
    public func move(uci: String) -> Move? {
        let lower = uci.lowercased()
        return legalMoves().first { $0.uci == lower }
    }

    // MARK: Game state

    public var isCheckmate: Bool { inCheck && legalMoves().isEmpty }
    public var isStalemate: Bool { !inCheck && legalMoves().isEmpty }
    public var isInsufficientMaterial: Bool {
        let pieces = board.compactMap { $0 }.filter { $0.kind != .king }
        if pieces.isEmpty { return true }
        return pieces.count == 1 && (pieces[0].kind == .bishop || pieces[0].kind == .knight)
    }
    public var isGameOver: Bool { legalMoves().isEmpty || isInsufficientMaterial || halfmoveClock >= 100 }
}
