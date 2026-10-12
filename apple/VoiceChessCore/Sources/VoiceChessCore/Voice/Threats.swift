public struct Threat: Hashable, Sendable {
    public enum Kind: Sendable { case attacked, hanging }
    public let square: Square
    public let piece: PieceKind
    public let attacker: PieceKind
    public let kind: Kind
}

public enum Threats {
    /// Pieces of `color` attacked by a cheaper piece, or attacked and undefended. Kings (check is
    /// announced anyway) and pawns (too chatty) are skipped. Most valuable first.
    public static func find(in position: Position, for color: PieceColor) -> [Threat] {
        var out: [Threat] = []
        for sq in Square.all {
            guard let p = position[sq], p.color == color, p.kind != .king, p.kind != .pawn else { continue }
            let attackers = position.attackers(of: sq, by: color.opposite).compactMap { position[$0]?.kind }
            guard let cheapest = attackers.min(by: { $0.value < $1.value }) else { continue }
            let defended = !position.attackers(of: sq, by: color).isEmpty
            if cheapest.value < p.kind.value {
                out.append(Threat(square: sq, piece: p.kind, attacker: cheapest, kind: .attacked))
            } else if !defended {
                out.append(Threat(square: sq, piece: p.kind, attacker: cheapest, kind: .hanging))
            }
        }
        return out.sorted { $0.piece.value > $1.piece.value }
    }

    /// Threats in `after` that were not already present in `before`.
    public static func new(before: [Threat], after: [Threat]) -> [Threat] {
        let old = Set(before.map { "\($0.square.index)\($0.piece.rawValue)\($0.kind)" })
        return after.filter { !old.contains("\($0.square.index)\($0.piece.rawValue)\($0.kind)") }
    }
}
