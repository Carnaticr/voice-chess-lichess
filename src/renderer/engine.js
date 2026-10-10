// Stockfish 19 (lite, single-threaded WASM) in a Web Worker.

const ENGINE_URL = '../../node_modules/stockfish/bin/stockfish-19-lite-single.js';

export class Engine {
  constructor() {
    this.worker = null;
    this.listeners = new Set();
    this.readyPromise = null;
  }

  start() {
    if (this.readyPromise) return this.readyPromise;
    this.worker = new Worker(ENGINE_URL);
    this.worker.onmessage = (e) => { for (const l of [...this.listeners]) l(String(e.data)); };
    this.readyPromise = this.waitFor('uci', (l) => l === 'uciok')
      .then(() => this.waitFor('isready', (l) => l === 'readyok'));
    return this.readyPromise;
  }

  waitFor(cmd, done, onLine) {
    return new Promise((resolve) => {
      const l = (line) => {
        if (onLine) onLine(line);
        if (done(line)) { this.listeners.delete(l); resolve(line); }
      };
      this.listeners.add(l);
      this.worker.postMessage(cmd);
    });
  }

  /**
   * Evaluate a position. Returns { cp | mate (white's perspective), best (uci) }.
   */
  async evaluate(fen, { depth = 12, movetime = 500 } = {}) {
    await this.start();
    this.worker.postMessage(`position fen ${fen}`);
    const whiteToMove = fen.split(' ')[1] === 'w';
    let score = null;
    const last = await this.waitFor(`go depth ${depth} movetime ${movetime}`, (l) => l.startsWith('bestmove'), (line) => {
      const m = line.match(/ score (cp|mate) (-?\d+)/);
      if (m && !line.includes(' upperbound') && !line.includes(' lowerbound')) score = { type: m[1], v: Number(m[2]) };
    });
    const best = last.split(' ')[1];
    const sign = whiteToMove ? 1 : -1;
    const ev = { best: best && best !== '(none)' ? best : null };
    if (score?.type === 'mate') ev.mate = sign * score.v;
    else ev.cp = sign * (score?.v ?? 0);
    return ev;
  }

  newGame() {
    if (this.worker) this.worker.postMessage('ucinewgame');
  }
}
