// Lightweight click-to-move chessboard rendered with DOM squares.
// Pieces are the Lichess "cburnett" SVGs (via chessground's CSS) or Unicode glyphs.

const GLYPH = { k: '♚', q: '♛', r: '♜', b: '♝', n: '♞', p: '♟' };
const VS15 = '︎'; // force text (not emoji) presentation
const FILES = 'abcdefgh';
const ROLE = { k: 'king', q: 'queen', r: 'rook', b: 'bishop', n: 'knight', p: 'pawn' };

function pieceHtml(set, type, color) {
  if (set === 'glyphs') return `<span class="pc ${color}">${GLYPH[type]}${VS15}</span>`;
  return `<piece class="${ROLE[type]} ${color}"></piece>`;
}

export class Board {
  constructor(el, { onMove }) {
    this.el = el;
    this.onMove = onMove;
    this.orientation = 'white';
    this.chess = null;
    this.interactive = false;
    this.selected = null;
    this.lastMove = null;
    this.squares = new Map();
    this.promo = null;
    this.pieceSet = 'cburnett';
    this.build();
  }

  build() {
    this.el.classList.add('board', 'cg-wrap');
    this.el.innerHTML = '';
    for (let i = 0; i < 64; i++) {
      const div = document.createElement('div');
      div.className = 'sq';
      div.addEventListener('click', () => this.clickSquare(div.dataset.square));
      this.el.appendChild(div);
    }
    this.promoEl = document.createElement('div');
    this.promoEl.className = 'promo hidden';
    this.el.appendChild(this.promoEl);
  }

  setAppearance({ theme, pieceSet }) {
    if (theme) this.el.dataset.theme = theme;
    if (pieceSet) this.pieceSet = pieceSet;
    this.render();
  }

  set({ chess, orientation, lastMove, interactive }) {
    if (chess) this.chess = chess;
    if (orientation) this.orientation = orientation;
    if (lastMove !== undefined) this.lastMove = lastMove;
    if (interactive !== undefined) this.interactive = interactive;
    if (!this.interactive) this.selected = null;
    this.render();
  }

  flip() {
    this.orientation = this.orientation === 'white' ? 'black' : 'white';
    this.render();
  }

  squareAt(index) {
    const row = Math.floor(index / 8);
    const col = index % 8;
    const file = this.orientation === 'white' ? col : 7 - col;
    const rank = this.orientation === 'white' ? 8 - row : row + 1;
    return FILES[file] + rank;
  }

  render() {
    if (!this.chess) return;
    const dests = this.selected
      ? new Set(this.chess.moves({ square: this.selected, verbose: true }).map((m) => m.to))
      : new Set();
    const checkSq = this.chess.inCheck() ? this.kingSquare(this.chess.turn()) : null;
    const children = this.el.querySelectorAll('.sq');
    children.forEach((div, i) => {
      const square = this.squareAt(i);
      div.dataset.square = square;
      const fileIdx = FILES.indexOf(square[0]);
      const rank = Number(square[1]);
      const light = (fileIdx + rank) % 2 === 0; // a1 (0+1) is dark
      const piece = this.chess.get(square);
      const cls = ['sq', light ? 'light' : 'dark'];
      if (this.lastMove && (this.lastMove.from === square || this.lastMove.to === square)) cls.push('last');
      if (this.selected === square) cls.push('selected');
      if (dests.has(square)) cls.push(piece ? 'capture-dest' : 'dest');
      if (checkSq === square) cls.push('check');
      div.className = cls.join(' ');

      let html = '';
      if (piece) html += pieceHtml(this.pieceSet, piece.type, piece.color === 'w' ? 'white' : 'black');
      const row = Math.floor(i / 8);
      const col = i % 8;
      if (col === 0) html += `<span class="coord rank">${rank}</span>`;
      if (row === 7) html += `<span class="coord file">${square[0]}</span>`;
      div.innerHTML = html;
      div.setAttribute('aria-label', piece ? `${square} ${piece.color === 'w' ? 'white' : 'black'} ${piece.type}` : square);
    });
  }

  kingSquare(color) {
    for (const row of this.chess.board()) for (const p of row) if (p && p.type === 'k' && p.color === color) return p.square;
    return null;
  }

  clickSquare(square) {
    if (!this.interactive || !this.chess) return;
    this.hidePromo();
    const piece = this.chess.get(square);
    if (this.selected) {
      const moves = this.chess.moves({ square: this.selected, verbose: true }).filter((m) => m.to === square);
      if (moves.length) {
        const from = this.selected;
        this.selected = null;
        if (moves.some((m) => m.promotion)) this.showPromo(from, square);
        else { this.render(); this.onMove(from + square); }
        return;
      }
    }
    this.selected = piece && piece.color === this.chess.turn() && square !== this.selected ? square : null;
    this.render();
  }

  showPromo(from, to) {
    const color = this.chess.turn() === 'w' ? 'white' : 'black';
    this.promoEl.innerHTML = '';
    for (const t of ['q', 'r', 'b', 'n']) {
      const b = document.createElement('button');
      b.innerHTML = pieceHtml(this.pieceSet, t, color);
      b.title = { q: 'Queen', r: 'Rook', b: 'Bishop', n: 'Knight' }[t];
      b.addEventListener('click', (e) => { e.stopPropagation(); this.hidePromo(); this.onMove(from + to + t); });
      this.promoEl.appendChild(b);
    }
    this.promoEl.classList.remove('hidden');
    this.render();
  }

  hidePromo() { this.promoEl.classList.add('hidden'); }
}
