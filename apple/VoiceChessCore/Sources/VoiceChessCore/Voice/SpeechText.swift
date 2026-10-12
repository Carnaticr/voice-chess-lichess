/// Natural-language text for announcing moves and positions with a speech synthesizer.
public enum SpeechText {
    /// Files spelled phonetically; single letters are read inconsistently by synthesizers.
    static let fileSpoken: [Character: String] = [
        "a": "ay", "b": "bee", "c": "see", "d": "dee", "e": "ee", "f": "eff", "g": "gee", "h": "aitch",
    ]

    public static func square(_ sq: Square) -> String {
        "\(fileSpoken[sq.fileLetter] ?? String(sq.fileLetter)) \(sq.rankNumber)"
    }

    /// "Nbxd2+" -> "Knight bee takes dee 2, check"
    public static func san(_ san: String) -> String {
        var suffix = ""
        if san.hasSuffix("#") { suffix = ", checkmate" } else if san.hasSuffix("+") { suffix = ", check" }
        let s = String(san.filter { !"+#!?".contains($0) })
        if s == "O-O" { return "Castles kingside" + suffix }
        if s == "O-O-O" { return "Castles queenside" + suffix }

        var chars = Array(s)
        var parts: [String] = []
        var promo: PieceKind?
        if let eq = chars.firstIndex(of: "=") {
            promo = chars.count > eq + 1 ? PieceKind(letter: chars[eq + 1]) : nil
            chars = Array(chars[..<eq])
        }
        guard chars.count >= 2, let dest = Square(String(chars.suffix(2))) else { return san }
        var head = chars.dropLast(2)
        if let first = head.first, first.isUppercase, let kind = PieceKind(letter: first) {
            parts.append(kind.name)
            head = head.dropFirst()
        }
        var capture = false
        for ch in head {
            if ch == "x" { capture = true } else if let spoken = fileSpoken[ch] { parts.append(spoken) } else { parts.append(String(ch)) }
        }
        if capture { parts.append("takes") }
        parts.append(square(dest))
        if let promo { parts.append("promotes to \(promo.name)") }
        return capitalized(parts.joined(separator: " ")) + suffix
    }

    /// Announces a move; with `detailed` captures name the victim ("Bishop takes knight on see 6").
    public static func move(_ move: Move, san sanText: String, detailed: Bool) -> String {
        guard detailed, let captured = move.captured else { return san(sanText) }
        var suffix = ""
        if sanText.hasSuffix("#") { suffix = ", checkmate" } else if sanText.hasSuffix("+") { suffix = ", check" }
        var parts: [String] = []
        if move.piece.kind == .pawn {
            parts += [fileSpoken[move.from.fileLetter] ?? "", "pawn"]
        } else {
            parts.append(move.piece.kind.name)
            // Keep SAN disambiguation ("Nbxd2" -> "knight bee").
            let core = sanText.dropFirst().prefix { $0 != "x" }
            for ch in core { parts.append(fileSpoken[ch] ?? String(ch)) }
        }
        parts += ["takes", captured.name, "on", square(move.to)]
        if move.isEnPassant { parts.append("en passant") }
        if let promo = move.promotion { parts.append("and promotes to \(promo.name)") }
        return capitalized(parts.joined(separator: " ")) + suffix
    }

    public static func threat(_ t: Threat) -> String {
        switch t.kind {
        case .hanging: "Your \(t.piece.name) on \(square(t.square)) is hanging."
        case .attacked: "Your \(t.piece.name) on \(square(t.square)) is attacked by a \(t.attacker.name)."
        }
    }

    /// "9 minutes 57 seconds"
    public static func duration(milliseconds ms: Int) -> String {
        let total = max(0, ms / 1000)
        let m = total / 60
        let s = total % 60
        var parts: [String] = []
        if m > 0 { parts.append("\(m) minute\(m == 1 ? "" : "s")") }
        if s > 0 || m == 0 { parts.append("\(s) second\(s == 1 ? "" : "s")") }
        return parts.joined(separator: " ")
    }

    static func capitalized(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}
