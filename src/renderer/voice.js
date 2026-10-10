// Voice helpers: turn legal moves into spoken phrases (for the recognizer grammar)
// and SAN into natural speech (for announcing moves).

const FILE_LETTER = { a: 'a', b: 'b', c: 'c', d: 'd', e: 'e', f: 'f', g: 'g', h: 'h' };
const FILE_NATO = { a: 'alpha', b: 'bravo', c: 'charlie', d: 'delta', e: 'echo', f: 'foxtrot', g: 'golf', h: 'hotel' };
const RANK_WORD = { 1: 'one', 2: 'two', 3: 'three', 4: 'four', 5: 'five', 6: 'six', 7: 'seven', 8: 'eight' };
const PIECE_WORDS = { n: ['knight', 'horse'], b: ['bishop'], r: ['rook'], q: ['queen'], k: ['king'] };
const PIECE_NAME = { n: 'knight', b: 'bishop', r: 'rook', q: 'queen', k: 'king', p: 'pawn' };

// How the synthesizer should pronounce files (single letters are read inconsistently).
const FILE_SPOKEN = { a: 'ay', b: 'bee', c: 'see', d: 'dee', e: 'ee', f: 'eff', g: 'gee', h: 'aitch' };

const KINGSIDE = ['castle kingside', 'castles kingside', 'castle king side', 'castle short', 'castles short',
  'short castle', 'kingside castle', 'king side castle', 'castle', 'castles', 'o o'];
const QUEENSIDE = ['castle queenside', 'castles queenside', 'castle queen side', 'castle long', 'castles long',
  'long castle', 'queenside castle', 'queen side castle', 'castle', 'castles', 'o o o'];

const STYLES = [FILE_LETTER, FILE_NATO];

function sq(square, files) {
  return `${files[square[0]]} ${RANK_WORD[square[1]]}`;
}

function disambiguation(san) {
  const m = san.replace(/[+#]/g, '').match(/^[NBRQK]([a-h]?[1-8]?)x?[a-h][1-8]/);
  return m ? m[1] : '';
}

function disambPhrase(d, files) {
  if (!d) return '';
  if (d.length === 2) return sq(d, files);
  return /[a-h]/.test(d) ? files[d] : RANK_WORD[d];
}

/** All phrases that should map to one move (chess.js verbose move). */
export function phrasesForMove(move) {
  const out = new Set();
  const capture = !!move.captured;
  const conns = capture ? ['takes', 'captures', 'x', ''] : ['to', ''];
  const join = (...parts) => parts.filter(Boolean).join(' ');

  if (move.flags.includes('k')) KINGSIDE.forEach((p) => out.add(p));
  if (move.flags.includes('q')) QUEENSIDE.forEach((p) => out.add(p));

  for (const files of STYLES) {
    const to = sq(move.to, files);
    const from = sq(move.from, files);

    // Coordinate form works for every move: "g one f three", "g one to f three".
    const promoSuffixes = move.promotion
      ? PIECE_WORDS[move.promotion].flatMap((w) => [w, `promote to ${w}`, `promotes to ${w}`, `equals ${w}`])
      : [''];
    for (const suf of promoSuffixes) {
      out.add(join(from, to, suf));
      out.add(join(from, 'to', to, suf));
    }

    if (move.piece === 'p') {
      for (const suf of promoSuffixes) {
        if (capture) {
          const ff = files[move.from[0]];
          for (const c of conns) {
            out.add(join(ff, c, to, suf));
            out.add(join('pawn', c, to, suf));
            if (c) out.add(join(ff, c, files[move.to[0]], suf)); // "e takes d"
          }
        } else {
          out.add(join(to, suf));
          out.add(join('pawn', to, suf));
          out.add(join('pawn', 'to', to, suf));
        }
      }
    } else {
      const d = disambPhrase(disambiguation(move.san), files);
      for (const word of PIECE_WORDS[move.piece]) {
        for (const c of conns) {
          out.add(join(word, d, c, to));
          // Also the under-specified form, so "knight d two" maps to "ambiguous" rather than to a wrong move.
          if (d) out.add(join(word, c, to));
          // "knight on b one to d two"
          out.add(join(word, 'on', from, c || 'to', to));
        }
      }
    }
  }
  return [...out];
}

/**
 * Build grammar items for all legal moves. Phrases that would match more than one move are
 * mapped to "amb:<uci,uci>" so the app can ask the player to be more specific.
 */
export function buildMoveGrammar(moves) {
  const map = new Map();
  for (const m of moves) {
    const uci = m.from + m.to + (m.promotion || '');
    for (const p of phrasesForMove(m)) {
      if (!map.has(p)) map.set(p, new Set());
      map.get(p).add(uci);
    }
  }
  const items = [];
  for (const [phrase, set] of map) {
    const ucis = [...set];
    // Ambiguous promotion without a piece named is not worth asking about; skip.
    if (ucis.length > 1 && ucis.every((u) => u.length === 5 && u.slice(0, 4) === ucis[0].slice(0, 4))) continue;
    items.push({ phrase, value: ucis.length === 1 ? ucis[0] : `amb:${ucis.join(',')}` });
  }
  return items;
}

function squareSpoken(square) {
  return `${FILE_SPOKEN[square[0]]} ${square[1]}`;
}

/** "Nbxd2+" -> "Knight bee takes dee 2, check" */
export function sanToSpeech(san) {
  let suffix = '';
  if (san.endsWith('#')) suffix = ', checkmate';
  else if (san.endsWith('+')) suffix = ', check';
  const s = san.replace(/[+#!?]/g, '');
  if (s === 'O-O') return `Castles kingside${suffix}`;
  if (s === 'O-O-O') return `Castles queenside${suffix}`;

  const m = s.match(/^([NBRQK])?([a-h])?([1-8])?(x)?([a-h][1-8])(?:=([NBRQ]))?$/);
  if (!m) return san;
  const [, piece, dFile, dRank, x, dest, promo] = m;
  const parts = [];
  if (piece) parts.push(PIECE_NAME[piece.toLowerCase()]);
  if (dFile) parts.push(FILE_SPOKEN[dFile]);
  if (dRank) parts.push(dRank);
  if (x) parts.push('takes');
  parts.push(squareSpoken(dest));
  if (promo) parts.push(`promotes to ${PIECE_NAME[promo.toLowerCase()]}`);
  const text = parts.join(' ');
  return text.charAt(0).toUpperCase() + text.slice(1) + suffix;
}

export function describeSquareForSpeech(square) {
  return squareSpoken(square);
}

export const PIECE_NAMES = PIECE_NAME;

/**
 * Speak a chess.js verbose move. With detailed=true captures name the victim:
 * "Bishop takes knight on see 6", "Ee pawn takes pawn on dee 5".
 */
export function moveToSpeech(move, { detailed = false } = {}) {
  if (!detailed || !move.captured) return sanToSpeech(move.san);
  let suffix = '';
  if (move.san.endsWith('#')) suffix = ', checkmate';
  else if (move.san.endsWith('+')) suffix = ', check';
  const parts = [];
  if (move.piece === 'p') parts.push(FILE_SPOKEN[move.from[0]], 'pawn');
  else {
    parts.push(PIECE_NAME[move.piece]);
    const d = disambiguation(move.san);
    if (d) parts.push(...d.split('').map((ch) => FILE_SPOKEN[ch] || ch));
  }
  parts.push('takes', PIECE_NAME[move.captured], 'on', squareSpoken(move.to));
  if (move.flags.includes('e')) parts.push('en passant');
  if (move.promotion) parts.push(`and promotes to ${PIECE_NAME[move.promotion]}`);
  const text = parts.join(' ');
  return text.charAt(0).toUpperCase() + text.slice(1) + suffix;
}

const ONES = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven',
  'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
const TENS = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];

/** 0..199 as words, for "go to move forty two". */
export function numberWords(n) {
  if (n < 20) return ONES[n];
  if (n < 100) return TENS[Math.floor(n / 10)] + (n % 10 ? ` ${ONES[n % 10]}` : '');
  const rest = n % 100;
  return `one hundred${rest ? ` ${numberWords(rest)}` : ''}`;
}
