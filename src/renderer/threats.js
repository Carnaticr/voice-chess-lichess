// Detects pieces of one side that are newly under threat, for spoken warnings.

export const VALUE = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 100 };

/**
 * Pieces of `color` ('w'|'b') that are attacked by a cheaper piece, or attacked and undefended.
 * Kings (check is already announced) and pawns (too chatty) are skipped.
 */
export function findThreats(chess, color) {
  const opp = color === 'w' ? 'b' : 'w';
  const out = [];
  for (const row of chess.board()) {
    for (const p of row) {
      if (!p || p.color !== color || p.type === 'k' || p.type === 'p') continue;
      const attackers = chess.attackers(p.square, opp);
      if (!attackers.length) continue;
      const cheapest = attackers
        .map((sq) => chess.get(sq).type)
        .sort((a, b) => VALUE[a] - VALUE[b])[0];
      const defended = chess.attackers(p.square, color).length > 0;
      if (VALUE[cheapest] < VALUE[p.type]) out.push({ square: p.square, type: p.type, by: cheapest, kind: 'attacked' });
      else if (!defended) out.push({ square: p.square, type: p.type, by: cheapest, kind: 'hanging' });
    }
  }
  return out.sort((a, b) => VALUE[b.type] - VALUE[a.type]);
}

/** Threats in `after` that were not present (same piece on same square) in `before`. */
export function newThreats(before, after) {
  const key = (t) => `${t.square}${t.type}${t.kind}`;
  const old = new Set(before.map(key));
  return after.filter((t) => !old.has(key(t)));
}
