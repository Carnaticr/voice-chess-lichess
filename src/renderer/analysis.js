// Turns per-position engine evaluations into move judgments and an accuracy score,
// following the formulas Lichess publishes.

/** Win percentage (0..100) for white from a centipawn score (white's perspective). */
export function winPercent(cp) {
  const c = Math.max(-1000, Math.min(1000, cp));
  return 50 + 50 * (2 / (1 + Math.exp(-0.00368208 * c)) - 1);
}

/** Normalize an eval {cp} | {mate} (white perspective) to centipawns. */
export function evalToCp(ev) {
  if (!ev) return 0;
  if (ev.mate !== undefined && ev.mate !== null) {
    if (ev.mate === 0) return 0;
    return ev.mate > 0 ? 10000 - ev.mate : -10000 - ev.mate;
  }
  return ev.cp ?? 0;
}

export function moveAccuracy(winDrop) {
  const a = 103.1668 * Math.exp(-0.04354 * Math.max(0, winDrop)) - 3.1669;
  return Math.max(0, Math.min(100, a));
}

// Lichess judges on "winning chances" (-1..1) deltas of .3/.2/.1, i.e. 15/10/5 win-percent points.
export function judge(winDrop) {
  if (winDrop >= 15) return 'blunder';
  if (winDrop >= 10) return 'mistake';
  if (winDrop >= 5) return 'inaccuracy';
  return null;
}

/**
 * evals: N+1 evals (white perspective) for the positions before move 0 .. after move N-1.
 * best:  N+1 best-move UCIs; best[i] is what the engine preferred instead of move i.
 */
export function analyzeGame(evals, best) {
  const n = evals.length - 1;
  const moves = [];
  const sides = {
    white: { inaccuracy: 0, mistake: 0, blunder: 0, acc: [] },
    black: { inaccuracy: 0, mistake: 0, blunder: 0, acc: [] },
  };
  for (let i = 0; i < n; i++) {
    const white = i % 2 === 0;
    const before = winPercent(evalToCp(evals[i]));
    const after = winPercent(evalToCp(evals[i + 1]));
    const drop = white ? before - after : after - before;
    const j = judge(drop);
    const side = sides[white ? 'white' : 'black'];
    side.acc.push(moveAccuracy(drop));
    if (j) side[j]++;
    moves.push({ judgment: j, drop, best: j ? best[i] : null, eval: evals[i + 1] });
  }
  const summary = {};
  for (const [color, s] of Object.entries(sides)) {
    summary[color] = {
      inaccuracy: s.inaccuracy,
      mistake: s.mistake,
      blunder: s.blunder,
      accuracy: s.acc.length ? Math.round(s.acc.reduce((a, b) => a + b, 0) / s.acc.length) : null,
    };
  }
  return { moves, summary };
}
