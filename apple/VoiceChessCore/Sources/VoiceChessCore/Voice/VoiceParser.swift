/// Things the player can say besides moves.
public enum VoiceCommand: Hashable, Sendable {
    case resign, offerDraw, acceptDraw, declineDraw, abort
    case repeatLast, time, yes, no, flipBoard, help, stopListening, review
    // Review mode
    case next, back, start, end, summary, bestMove, nextMistake, exitReview
    case goToMove(Int)
}

public enum VoiceResult: Equatable, Sendable {
    case move(Move)
    case ambiguous([Move])
    case command(VoiceCommand)
    /// Understood as a move, but no legal move matches.
    case illegal
    case none
}

/// Turns free-form speech-recognizer text ("Knight takes E5", "night to f3", "castle short")
/// into a legal move or a command. Recognizers mishear chess terms in predictable ways,
/// so common homophones are folded in before parsing.
public enum VoiceParser {
    public static func parse(_ text: String, position: Position?, reviewing: Bool = false) -> VoiceResult {
        let tokens = normalize(text)
        guard !tokens.isEmpty else { return .none }
        let phrase = tokens.joined(separator: " ")

        if let cmd = command(phrase, tokens: tokens, reviewing: reviewing) { return .command(cmd) }
        guard !reviewing, let position else { return .none }
        let legal = position.legalMoves()

        // Literal SAN / UCI said or transcribed as one word ("nf3", "exd5", "e2e4").
        for t in tokens where t.count >= 2 {
            if let m = legal.first(where: { Position.stripSAN(position.san($0)).lowercased() == t || $0.uci == t }) {
                return .move(m)
            }
        }
        return matchMove(tokens: tokens, legal: legal)
    }

    // MARK: Normalization

    static let fileWords: [String: Int] = [
        "a": 0, "ay": 0, "alpha": 0, "alfa": 0,
        "b": 1, "be": 1, "bee": 1, "bravo": 1,
        "c": 2, "see": 2, "sea": 2, "si": 2, "charlie": 2,
        "d": 3, "dee": 3, "delta": 3,
        "e": 4, "ee": 4, "echo": 4,
        "f": 5, "eff": 5, "ef": 5, "foxtrot": 5,
        "g": 6, "gee": 6, "ji": 6, "golf": 6,
        "h": 7, "aitch": 7, "age": 7, "hotel": 7,
    ]
    static let rankWords: [String: Int] = [
        "1": 0, "one": 0, "won": 0,
        "2": 1, "two": 1, "to": 1, "too": 1,
        "3": 2, "three": 2, "tree": 2,
        "4": 3, "four": 3, "for": 3, "fore": 3,
        "5": 4, "five": 4,
        "6": 5, "six": 5,
        "7": 6, "seven": 6,
        "8": 7, "eight": 7, "ate": 7,
    ]
    static let pieceWords: [String: PieceKind] = [
        "knight": .knight, "night": .knight, "nite": .knight, "horse": .knight, "knights": .knight,
        "bishop": .bishop, "bishops": .bishop,
        "rook": .rook, "rock": .rook, "ruck": .rook, "brook": .rook, "rooks": .rook,
        "queen": .queen, "queens": .queen,
        "king": .king,
        "pawn": .pawn, "pond": .pawn, "prawn": .pawn, "pawns": .pawn,
    ]
    static let captureWords: Set = ["takes", "take", "x", "captures", "capture", "takes on", "by"]
    static let fillerWords: Set = ["on", "move", "moves", "goes", "from", "the", "please", "play", "check", "checkmate", "mate", "and"]

    /// Lowercases, strips punctuation, splits "e4"/"nf3"-style tokens and merges two-word terms.
    static func normalize(_ text: String) -> [String] {
        var s = text.lowercased()
        for (from, to) in [("o-o-o", " castle queenside "), ("0-0-0", " castle queenside "),
                           ("o-o", " castle kingside "), ("0-0", " castle kingside "),
                           ("king side", "kingside"), ("queen side", "queenside"),
                           ("king's side", "kingside"), ("queen's side", "queenside")] {
            s = s.replacing(from, with: to)
        }
        let cleaned = String(s.map { $0.isLetter || $0.isNumber || $0 == "=" ? $0 : " " })
        var tokens: [String] = []
        for raw in cleaned.split(separator: " ") {
            tokens.append(contentsOf: splitCompact(String(raw)))
        }
        // "oh oh" / "o o o" for castling.
        var merged: [String] = []
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if ["o", "oh", "0"].contains(t) {
                var n = 0
                while i + n < tokens.count, ["o", "oh", "0"].contains(tokens[i + n]) { n += 1 }
                if n >= 2 { merged += ["castle", n >= 3 ? "queenside" : "kingside"]; i += n; continue }
            }
            merged.append(t)
            i += 1
        }
        return merged
    }

    /// Splits "e4" -> ["e","4"], "e2e4" stays (UCI), "exd5"/"nf3" stay (SAN), "f3." handled by caller.
    static func splitCompact(_ t: String) -> [String] {
        let chars = Array(t)
        if chars.count == 2, let f = chars.first, ("a"..."h").contains(f), let r = chars.last, ("1"..."8").contains(r) {
            return [String(f), String(r)]
        }
        return [t]
    }

    // MARK: Commands

    static let commandPhrases: [(String, VoiceCommand)] = [
        ("offer draw", .offerDraw), ("offer a draw", .offerDraw), ("accept draw", .acceptDraw), ("accept the draw", .acceptDraw),
        ("decline draw", .declineDraw), ("decline the draw", .declineDraw), ("i resign", .resign),
        ("abort game", .abort), ("abort the game", .abort), ("say again", .repeatLast), ("repeat", .repeatLast),
        ("last move", .repeatLast), ("how much time", .time), ("flip board", .flipBoard), ("flip the board", .flipBoard),
        ("what can i say", .help), ("stop listening", .stopListening), ("microphone off", .stopListening),
        ("review game", .review), ("review the game", .review), ("analyze the game", .review),
    ]
    static let singleWordCommands: [String: VoiceCommand] = [
        "resign": .resign, "draw": .offerDraw, "accept": .acceptDraw, "decline": .declineDraw, "abort": .abort,
        "repeat": .repeatLast, "time": .time, "clock": .time, "yes": .yes, "yeah": .yes, "confirm": .yes,
        "no": .no, "nope": .no, "cancel": .no, "help": .help, "review": .review, "analyze": .review,
    ]
    static let reviewPhrases: [(String, VoiceCommand)] = [
        ("next mistake", .nextMistake), ("next blunder", .nextMistake), ("next error", .nextMistake),
        ("next move", .next), ("previous move", .back), ("go back", .back), ("go to start", .start),
        ("go to the start", .start), ("go to the beginning", .start), ("go to end", .end), ("go to the end", .end),
        ("final position", .end), ("best move", .bestMove), ("what was better", .bestMove),
        ("what should i have played", .bestMove), ("read summary", .summary), ("how did i do", .summary),
        ("exit review", .exitReview), ("stop review", .exitReview), ("say again", .repeatLast),
        ("flip board", .flipBoard), ("stop listening", .stopListening), ("what can i say", .help),
    ]
    static let reviewWords: [String: VoiceCommand] = [
        "next": .next, "forward": .next, "back": .back, "previous": .back, "start": .start, "beginning": .start,
        "end": .end, "summary": .summary, "done": .exitReview, "repeat": .repeatLast, "help": .help,
    ]

    static func command(_ phrase: String, tokens: [String], reviewing: Bool) -> VoiceCommand? {
        if reviewing {
            if let n = goToMove(tokens) { return .goToMove(n) }
            if let c = reviewPhrases.first(where: { phrase.contains($0.0) })?.1 { return c }
            if tokens.count == 1, let c = reviewWords[tokens[0]] { return c }
            return nil
        }
        if let c = commandPhrases.first(where: { phrase.contains($0.0) })?.1 { return c }
        if tokens.count <= 2, let c = singleWordCommands[tokens[0]] { return c }
        return nil
    }

    /// "go to move twelve", "move 12".
    static func goToMove(_ tokens: [String]) -> Int? {
        guard let idx = tokens.firstIndex(of: "move"), idx + 1 < tokens.count else { return nil }
        if idx > 0 && !["to", "go"].contains(tokens[idx - 1]) { return nil }
        return NumberWords.parse(Array(tokens[(idx + 1)...]))
    }

    // MARK: Moves

    enum Coord: Equatable { case square(Square), file(Int), rank(Int) }

    static func matchMove(tokens: [String], legal: [Move]) -> VoiceResult {
        var piece: PieceKind?
        var capture = false
        var castle: CastleSide?
        var wantsCastle = false
        var promotion: PieceKind?
        var coords: [Coord] = []

        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if let file = fileWords[t] {
                // A file followed by a rank is a square. "to"/"too" only counts as a rank right after a file.
                if i + 1 < tokens.count, let rank = rankWords[tokens[i + 1]], let sq = Square(file: file, rank: rank) {
                    coords.append(.square(sq))
                    i += 2
                    continue
                }
                // "a" alone is usually the article, not the a-file.
                if t != "a" || piece != nil || !coords.isEmpty { coords.append(.file(file)) }
            } else if t != "to", t != "too", let rank = rankWords[t] {
                coords.append(.rank(rank))
            } else if let kind = pieceWords[t] {
                if coords.contains(where: { if case .square = $0 { return true } else { return false } }), kind != .pawn, kind != .king {
                    promotion = kind // "e eight queen"
                } else if piece == nil {
                    piece = kind
                }
            } else if captureWords.contains(t) {
                capture = true
            } else if ["castle", "castles", "castling"].contains(t) {
                wantsCastle = true
            } else if ["kingside", "short"].contains(t) {
                castle = .kingside
            } else if ["queenside", "long"].contains(t) {
                castle = .queenside
            } else if ["promote", "promotes", "promotion", "equals", "="].contains(t) {
                // the next piece word sets the promotion
            } else if t.hasPrefix("="), let kind = PieceKind(letter: t.dropFirst().first ?? " ") {
                promotion = kind
            }
            i += 1
        }

        if wantsCastle || castle != nil {
            let castles = legal.filter { $0.castle != nil && (castle == nil || $0.castle == castle) }
            if castles.count == 1 { return .move(castles[0]) }
            if castles.count > 1 { return .ambiguous(castles) }
            if wantsCastle { return .illegal }
        }

        // Target: the last square, or for "e takes d" the last bare file.
        var target: Coord?
        var hints: [Coord] = []
        if let idx = coords.lastIndex(where: { if case .square = $0 { return true } else { return false } }) {
            target = coords[idx]
            hints = Array(coords[..<idx])
        } else if capture, coords.count >= 2, case .file = coords[coords.count - 1] {
            target = coords[coords.count - 1]
            hints = Array(coords.dropLast())
        }
        guard let target else { return piece == nil && !capture ? .none : .illegal }

        var candidates = legal.filter { m in
            switch target {
            case .square(let sq): return m.to == sq
            case .file(let f): return m.to.file == f && m.captured != nil
            case .rank: return false
            }
        }
        let fromSquareGiven = hints.contains { if case .square = $0 { return true } else { return false } }
        for h in hints {
            switch h {
            case .square(let sq): candidates = candidates.filter { $0.from == sq }
            case .file(let f): candidates = candidates.filter { $0.from.file == f }
            case .rank(let r): candidates = candidates.filter { $0.from.rank == r }
            }
        }
        if let piece {
            candidates = candidates.filter { $0.piece.kind == piece }
        } else if !fromSquareGiven {
            // "e four" / "e takes d five" mean pawn moves; "g one f three" can be any piece.
            let hasFileHint = hints.contains { if case .file = $0 { return true } else { return false } }
            let pawns = candidates.filter { $0.piece.kind == .pawn }
            if !pawns.isEmpty || hasFileHint { candidates = pawns }
        }
        if capture {
            let captures = candidates.filter { $0.captured != nil }
            if !captures.isEmpty { candidates = captures }
        }
        if candidates.contains(where: { $0.promotion != nil }) {
            let wanted = promotion ?? .queen // auto-queen unless something else is named
            candidates = candidates.filter { $0.promotion == wanted }
        }

        switch candidates.count {
        case 0: return .illegal
        case 1: return .move(candidates[0])
        default: return .ambiguous(candidates)
        }
    }
}

public enum NumberWords {
    static let ones = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                       "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
    static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    /// Parses "12", "twelve", "forty two", "one hundred five" (and "to"/"for" homophones).
    public static func parse(_ tokens: [String]) -> Int? {
        if let first = tokens.first, let n = Int(first) { return n }
        var total = 0
        var found = false
        for t in tokens {
            let word = ["to": "two", "too": "two", "for": "four", "won": "one", "ate": "eight"][t] ?? t
            if let n = ones.firstIndex(of: word) { total += n; found = true }
            else if let n = tens.firstIndex(of: word), n >= 2 { total += n * 10; found = true }
            else if word == "hundred" { total = max(total, 1) * 100; found = true }
            else if word == "and" { continue }
            else if found { break }
        }
        return found ? total : nil
    }
}
