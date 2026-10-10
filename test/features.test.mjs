import test from 'node:test';
import assert from 'node:assert/strict';
import { Chess } from '../node_modules/chess.js/dist/esm/chess.js';
import { moveToSpeech, numberWords } from '../src/renderer/voice.js';
import { findThreats, newThreats } from '../src/renderer/threats.js';
import { analyzeGame, winPercent, judge } from '../src/renderer/analysis.js';

test('detailed capture speech', () => {
  const c = new Chess('r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 2 3');
  assert.equal(moveToSpeech(c.move('Bxc6'), { detailed: true }), 'Bishop takes knight on see 6');
  const d = new Chess('rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2');
  assert.equal(moveToSpeech(d.move('exd5'), { detailed: true }), 'Ee pawn takes pawn on dee 5');
  assert.equal(moveToSpeech(new Chess().move('Nf3'), { detailed: true }), 'Knight eff 3');
});

test('number words', () => {
  assert.equal(numberWords(7), 'seven');
  assert.equal(numberWords(42), 'forty two');
  assert.equal(numberWords(120), 'one hundred twenty');
});

test('threats: attacked by cheaper piece, hanging, defended', () => {
  // Black knight on c6 attacks the white queen on d4.
  const c = new Chess('r1bqkb1r/pppp1ppp/2n2n2/8/3Q4/8/PPP2PPP/RNB1KBNR w KQkq - 0 1');
  const t = findThreats(c, 'w');
  assert.deepEqual(t.map((x) => [x.type, x.square, x.kind, x.by]), [['q', 'd4', 'attacked', 'n']]);
  // Undefended white knight on e5 attacked by a black queen on e7.
  const h = new Chess('4k3/4q3/8/4N3/8/8/8/K7 w - - 0 1');
  assert.deepEqual(findThreats(h, 'w').map((x) => x.kind), ['hanging']);
  // Same knight defended by a pawn on d4: no warning.
  const ok = new Chess('4k3/4q3/8/4N3/3P4/8/8/K7 w - - 0 1');
  assert.equal(findThreats(ok, 'w').length, 0);
  assert.equal(newThreats(t, t).length, 0);
  assert.equal(newThreats([], t).length, 1);
});

test('analysis judgments and accuracy', () => {
  assert.equal(Math.round(winPercent(0)), 50);
  assert.equal(judge(35), 'blunder');
  // White keeps +0.3, black blunders a piece (+3.5), then white throws it back to 0.
  const evals = [{ cp: 30 }, { cp: 30 }, { cp: 350 }, { cp: 0 }];
  const r = analyzeGame(evals, ['e2e4', 'e7e5', 'g1f3', 'b1c3']);
  assert.equal(r.moves[0].judgment, null);
  assert.equal(r.moves[1].judgment, 'blunder');
  assert.equal(r.moves[1].best, 'e7e5');
  assert.equal(r.moves[2].judgment, 'blunder');
  assert.equal(r.summary.black.blunder, 1);
  assert.ok(r.summary.white.accuracy > 0 && r.summary.white.accuracy < 70);
  // Mate scores are handled.
  const m = analyzeGame([{ cp: 0 }, { mate: 3 }], ['e2e4', null]);
  assert.equal(m.moves[0].judgment, null);
});
