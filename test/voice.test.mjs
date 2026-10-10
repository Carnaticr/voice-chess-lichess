import test from 'node:test';
import assert from 'node:assert/strict';
import { Chess } from '../node_modules/chess.js/dist/esm/chess.js';
import { buildMoveGrammar, sanToSpeech } from '../src/renderer/voice.js';

const lookup = (fen, phrase) => {
  const c = new Chess(fen);
  const items = buildMoveGrammar(c.moves({ verbose: true }));
  return items.find((i) => i.phrase === phrase)?.value;
};

test('start position phrases', () => {
  const start = new Chess().fen();
  assert.equal(lookup(start, 'e four'), 'e2e4');
  assert.equal(lookup(start, 'echo four'), 'e2e4');
  assert.equal(lookup(start, 'knight f three'), 'g1f3');
  assert.equal(lookup(start, 'horse to foxtrot three'), 'g1f3');
  assert.equal(lookup(start, 'g one f three'), 'g1f3');
  assert.equal(lookup(start, 'knight takes e five'), undefined);
});

test('disambiguation and captures', () => {
  // Knights on b1 and f3 can both reach d2.
  const fen = 'rnbqkb1r/pppppppp/5n2/8/3P4/5N2/PPP1PPPP/RNBQKB1R w KQkq - 0 1';
  const c = new Chess(fen);
  c.remove('d2'); c.remove('c1'); c.remove('e2'); // free d2
  const items = buildMoveGrammar(c.moves({ verbose: true }));
  const v = (p) => items.find((i) => i.phrase === p)?.value;
  assert.equal(v('knight b d two'), 'b1d2');
  assert.equal(v('knight f d two'), 'f3d2');
  assert.match(v('knight d two'), /^amb:/);
  assert.equal(v('knight on b one to d two'), 'b1d2');
});

test('pawn capture, castling, promotion', () => {
  assert.equal(lookup('rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2', 'e takes d five'), 'e4d5');
  assert.equal(lookup('rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2', 'pawn takes d five'), 'e4d5');
  const castle = 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1';
  assert.equal(lookup(castle, 'castle short'), 'e1g1');
  assert.equal(lookup(castle, 'long castle'), 'e1c1');
  assert.match(lookup(castle, 'castle'), /^amb:/);
  const promo = '8/4P3/8/8/8/8/k7/4K3 w - - 0 1';
  assert.equal(lookup(promo, 'e eight queen'), 'e7e8q');
  assert.equal(lookup(promo, 'e eight promote to knight'), 'e7e8n');
  assert.equal(lookup(promo, 'e eight'), undefined);
});

test('san to speech', () => {
  assert.equal(sanToSpeech('Nbxd2+'), 'Knight bee takes dee 2, check');
  assert.equal(sanToSpeech('e4'), 'Ee 4');
  assert.equal(sanToSpeech('exd5'), 'Ee takes dee 5');
  assert.equal(sanToSpeech('O-O-O#'), 'Castles queenside, checkmate');
  assert.equal(sanToSpeech('e8=Q+'), 'Ee 8 promotes to queen, check');
});

test('grammar size is reasonable', () => {
  const items = buildMoveGrammar(new Chess('r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4').moves({ verbose: true }));
  assert.ok(items.length < 1500, `items=${items.length}`);
  console.log('phrases for a middlegame position:', items.length);
});
