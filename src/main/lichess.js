// Minimal Lichess Board API client (runs in the Electron main process).
// Docs: https://lichess.org/api#tag/Board

const BASE = 'https://lichess.org';

class LichessError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

class Lichess {
  constructor(token) {
    this.token = token;
  }

  headers(extra = {}) {
    return { Authorization: `Bearer ${this.token}`, ...extra };
  }

  async request(method, path, form) {
    const opts = { method, headers: this.headers() };
    if (form) {
      opts.headers['Content-Type'] = 'application/x-www-form-urlencoded';
      opts.body = new URLSearchParams(form).toString();
    }
    const res = await fetch(BASE + path, opts);
    const text = await res.text();
    let body;
    try { body = text ? JSON.parse(text) : {}; } catch { body = { raw: text }; }
    if (!res.ok) {
      const msg = body.error || body.raw || `HTTP ${res.status}`;
      throw new LichessError(typeof msg === 'string' ? msg : JSON.stringify(msg), res.status);
    }
    return body;
  }

  account() { return this.request('GET', '/api/account'); }

  async tokenScopes() {
    const res = await fetch(BASE + '/api/token/test', { method: 'POST', body: this.token });
    const body = await res.json();
    const info = body[this.token];
    return info ? (info.scopes || '').split(',').filter(Boolean) : null;
  }

  /** Game export as JSON, including Lichess' server analysis when it exists. */
  async exportGame(gameId) {
    const res = await fetch(`${BASE}/game/export/${gameId}?evals=true&accuracy=true&opening=true&clocks=false`, {
      headers: this.headers({ Accept: 'application/json' }),
    });
    if (!res.ok) throw new LichessError(`Export failed (HTTP ${res.status})`, res.status);
    return res.json();
  }

  move(gameId, uci) { return this.request('POST', `/api/board/game/${gameId}/move/${uci}`); }
  resign(gameId) { return this.request('POST', `/api/board/game/${gameId}/resign`); }
  abort(gameId) { return this.request('POST', `/api/board/game/${gameId}/abort`); }
  draw(gameId, accept) { return this.request('POST', `/api/board/game/${gameId}/draw/${accept ? 'yes' : 'no'}`); }

  challengeAi({ level, limit, increment, color }) {
    return this.request('POST', '/api/challenge/ai', {
      level: String(level),
      'clock.limit': String(limit),
      'clock.increment': String(increment),
      color,
    });
  }

  /**
   * Streams a newline-delimited JSON endpoint, calling onMessage per object.
   * Resolves when the server closes the stream; rejects on HTTP/network error.
   */
  async stream(path, { method = 'GET', form, signal, onMessage }) {
    const opts = { method, headers: this.headers(), signal };
    if (form) {
      opts.headers['Content-Type'] = 'application/x-www-form-urlencoded';
      opts.body = new URLSearchParams(form).toString();
    }
    const res = await fetch(BASE + path, opts);
    if (!res.ok) {
      let msg = `HTTP ${res.status}`;
      try {
        const body = await res.json();
        msg = typeof body.error === 'string' ? body.error : JSON.stringify(body.error || body);
      } catch { /* keep generic message */ }
      throw new LichessError(msg, res.status);
    }
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      let nl;
      while ((nl = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, nl).trim();
        buffer = buffer.slice(nl + 1);
        if (!line) continue; // keep-alive
        try { onMessage(JSON.parse(line)); } catch (e) { console.error('Bad ndjson line', line, e); }
      }
    }
  }

  /** Real-time seek. Stays open until a game starts (gameStart arrives on the event stream). */
  seek({ time, increment, rated, color, signal }) {
    return this.stream('/api/board/seek', {
      method: 'POST',
      form: { time: String(time), increment: String(increment), rated: String(rated), color, variant: 'standard' },
      signal,
      onMessage: () => {},
    });
  }
}

module.exports = { Lichess, LichessError };
