public enum PieceColor: String, Sendable, Hashable, Codable {
    case white, black

    public var opposite: PieceColor { self == .white ? .black : .white }
}

public enum PieceKind: Character, Sendable, Hashable, CaseIterable {
    case pawn = "p", knight = "n", bishop = "b", rook = "r", queen = "q", king = "k"

    /// Letter used in SAN ("" for pawns).
    public var sanLetter: String { self == .pawn ? "" : String(rawValue).uppercased() }

    public var name: String {
        switch self {
        case .pawn: "pawn"
        case .knight: "knight"
        case .bishop: "bishop"
        case .rook: "rook"
        case .queen: "queen"
        case .king: "king"
        }
    }

    /// Conventional material value; the king is effectively priceless.
    public var value: Int {
        switch self {
        case .pawn: 1
        case .knight, .bishop: 3
        case .rook: 5
        case .queen: 9
        case .king: 100
        }
    }

    public init?(letter: Character) {
        guard let kind = PieceKind(rawValue: Character(letter.lowercased())) else { return nil }
        self = kind
    }
}

public struct Piece: Hashable, Sendable {
    public let kind: PieceKind
    public let color: PieceColor

    public init(_ kind: PieceKind, _ color: PieceColor) {
        self.kind = kind
        self.color = color
    }

    init?(fenChar: Character) {
        guard let kind = PieceKind(letter: fenChar) else { return nil }
        self.init(kind, fenChar.isUppercase ? .white : .black)
    }

    var fenChar: Character {
        color == .white ? Character(String(kind.rawValue).uppercased()) : kind.rawValue
    }

    /// Asset name such as "wN" / "bQ".
    public var assetName: String {
        (color == .white ? "w" : "b") + String(kind.rawValue).uppercased()
    }
}

/// Board square, 0 = a1 ... 63 = h8.
public struct Square: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let index: Int

    public init(index: Int) {
        precondition((0..<64).contains(index), "square index out of range")
        self.index = index
    }

    /// Zero-based file (0 = a) and rank (0 = rank 1).
    public init?(file: Int, rank: Int) {
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        self.index = rank * 8 + file
    }

    public init?(_ name: some StringProtocol) {
        let chars = Array(name.lowercased())
        guard chars.count == 2,
              let f = chars[0].asciiValue, let r = chars[1].asciiValue,
              (97...104).contains(f), (49...56).contains(r) else { return nil }
        self.index = Int(r - 49) * 8 + Int(f - 97)
    }

    public var file: Int { index % 8 }
    public var rank: Int { index / 8 }
    public var fileLetter: Character { Character(UnicodeScalar(UInt8(97 + file))) }
    public var rankNumber: Int { rank + 1 }
    public var name: String { "\(fileLetter)\(rankNumber)" }
    public var description: String { name }
    /// a1 is a dark square.
    public var isLight: Bool { (file + rank) % 2 == 1 }

    public func offset(file df: Int, rank dr: Int) -> Square? {
        Square(file: file + df, rank: rank + dr)
    }

    public static let all: [Square] = (0..<64).map { Square(index: $0) }

    public static func < (lhs: Square, rhs: Square) -> Bool { lhs.index < rhs.index }
}

public enum CastleSide: Sendable, Hashable {
    case kingside, queenside
}

public struct Move: Hashable, Sendable, CustomStringConvertible {
    public let from: Square
    public let to: Square
    public let piece: Piece
    public let captured: PieceKind?
    public let promotion: PieceKind?
    public let isEnPassant: Bool
    public let castle: CastleSide?

    public init(from: Square, to: Square, piece: Piece, captured: PieceKind? = nil,
                promotion: PieceKind? = nil, isEnPassant: Bool = false, castle: CastleSide? = nil) {
        self.from = from
        self.to = to
        self.piece = piece
        self.captured = captured
        self.promotion = promotion
        self.isEnPassant = isEnPassant
        self.castle = castle
    }

    public var uci: String { from.name + to.name + (promotion.map { String($0.rawValue) } ?? "") }
    public var description: String { uci }
}

public struct CastlingRights: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let whiteKingside = CastlingRights(rawValue: 1)
    public static let whiteQueenside = CastlingRights(rawValue: 2)
    public static let blackKingside = CastlingRights(rawValue: 4)
    public static let blackQueenside = CastlingRights(rawValue: 8)
    public static let all: CastlingRights = [.whiteKingside, .whiteQueenside, .blackKingside, .blackQueenside]

    static func kingside(_ c: PieceColor) -> CastlingRights { c == .white ? .whiteKingside : .blackKingside }
    static func queenside(_ c: PieceColor) -> CastlingRights { c == .white ? .whiteQueenside : .blackQueenside }
}
