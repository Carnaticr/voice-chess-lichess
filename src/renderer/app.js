import { Chess } from '../../node_modules/chess.js/dist/esm/chess.js';
import { Board } from './board.js';
import { buildMoveGrammar, sanToSpeech, moveToSpeech, numberWords, PIECE_NAMES, describeSquareForSpeech } from './voice.js';
import { findThreats, newThreats } from './threats.js';
import { analyzeGame, evalToCp } from './analysis.js';
import { Engine } from './engine.js';

const api = window.api;
const $ = (sel) => document.querySelector(sel);

const COMMANDS = {
  resign: ['resign', 'i resign'],
  draw: ['offer draw', 'offer a draw', 'draw'],
  acceptDraw: ['accept draw', 'accept the draw', 'accept'],
  declineDraw: ['decline draw', 'decline the draw', 'decline'],
  abort: ['abort', 'abort game', 'abort the game'],
  repeat: ['repeat', 'say again', 'say that again', 'last move', 'what was the last move', 'repeat last move'],
  time: ['time', 'clock', 'how much time', 'my time', 'what is the time'],
  yes: ['yes', 'confirm', 'yes please', 'do it'],
  no: ['no', 'cancel', 'never mind'],
  flip: ['flip board', 'flip the board'],
  help: ['help', 'what can i say'],
  micOff: ['stop listening', 'microphone off'],
  review: ['review', 'review game', 'review the game', 'analyze', 'analyze the game'],
};

// Only active while reviewing a finished game.
const REVIEW_COMMANDS = {
  next: ['next', 'forward', 'next move'],
  back: ['back', 'previous', 'go back', 'previous move'],
  start: ['start', 'beginning', 'go to start', 'go to the beginning'],
  end: ['end', 'go to end', 'go to the end', 'final position'],
  summary: ['summary', 'read summary', 'how did i do'],
  best: ['best move', 'what was better', 'what is best', 'what should i have played'],
  nextMistake: ['next mistake', 'next blunder', 'next error'],
  exit: ['exit review', 'stop review', 'done'],
  help: ['help', 'what can i say'],
  repeat: ['repeat', 'say again'],
  flip: ['flip board', 'flip the board'],
  micOff: ['stop listening', 'microphone off'],
};

const JUDGMENT_MARK = { inaccuracy: '?!', mistake: '?', blunder: '??' };

// ---------------- state ----------------
const state = {
  me: null,
  settings: null,
  voices: [],
  game: null, // see newGame()
  micOn: false,
  pttHeld: false,
  speechAvailable: true,
  pending: null, // { kind: 'move', uci, san } | { kind: 'resign' }
  lastSpoken: '',
  voiceUcis: new Set(), // moves I made by voice (to read back)
  tickTimer: null,
  review: null, // { index, fens, moves, analysis, status }
};

const engine = new Engine();

const board = new Board($('#board'), { onMove: (uci) => submitMove(uci, 'mouse') });

// ---------------- helpers ----------------
function show(view) {
  for (const v of ['login', 'lobby', 'game']) $(`#view-${v}`).classList.toggle('hidden', v !== view);
}

let toastTimer;
function toast(msg, isError = false) {
  const t = $('#toast');
  t.textContent = msg;
  t.classList.toggle('error', isError);
  t.classList.remove('hidden');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.add('hidden'), 4500);
}

function logVoice(kind, text, bad = false) {
  const li = document.createElement('li');
  li.className = kind + (bad ? ' bad' : '');
  li.textContent = text;
  const ol = $('#voice-log');
  ol.prepend(li);
  while (ol.children.length > 30) ol.lastChild.remove();
}

function say(text, { interrupt = false, remember = false } = {}) {
  if (!text) return;
  if (remember) state.lastSpoken = text;
  api.speech.say(text, interrupt);
  logVoice('say', text);
}

function fmtClock(ms) {
  ms = Math.max(0, ms);
  const total = Math.floor(ms / 1000);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  if (ms < 10000) return `${m}:${String(s).padStart(2, '0')}.${Math.floor((ms % 1000) / 100)}`;
  return `${m}:${String(s).padStart(2, '0')}`;
}

function speakDuration(ms) {
  const total = Math.max(0, Math.floor(ms / 1000));
  const m = Math.floor(total / 60);
  const s = total % 60;
  const parts = [];
  if (m) parts.push(`${m} minute${m === 1 ? '' : 's'}`);
  if (s || !m) parts.push(`${s} second${s === 1 ? '' : 's'}`);
  return parts.join(' ');
}

async function call(promise, errPrefix) {
  const res = await promise;
  if (!res.ok) {
    toast(`${errPrefix}: ${res.error}`, true);
    return null;
  }
  return res.data ?? true;
}

// ---------------- auth ----------------
async function afterLogin(info) {
  state.me = info;
  $('#user').textContent = info.username;
  $('#btn-logout').classList.remove('hidden');
  if (info.scopes && !info.scopes.includes('board:play')) {
    toast('This token is missing the board:play scope. Create a new token with the link on the login page.', true);
  }
  if (!state.game) show('lobby');
}

$('#btn-token-page').addEventListener('click', () => api.auth.openTokenPage());
$('#login-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  $('#login-error').textContent = '';
  const res = await api.auth.login($('#token').value);
  if (!res.ok) { $('#login-error').textContent = res.error; return; }
  $('#token').value = '';
  afterLogin(res.data);
});
$('#btn-logout').addEventListener('click', async () => {
  await api.auth.logout();
  state.me = null;
  state.game = null;
  setMic(false);
  $('#user').textContent = '';
  $('#btn-logout').classList.add('hidden');
  setConn(false);
  show('login');
});

function setConn(ok, text) {
  const c = $('#conn');
  c.classList.toggle('ok', ok === true);
  c.classList.toggle('warn', ok === 'warn');
  $('#conn-text').textContent = text || (ok ? 'Connected' : 'Offline');
}

api.on.lichessStatus((s) => {
  if (s.connected) setConn(true);
  else if (s.reconnecting) setConn('warn', 'Reconnecting…');
  else { setConn(false); if (s.error) toast(s.error, true); }
});

// ---------------- lobby ----------------
$('#btn-ai').addEventListener('click', async () => {
  const [limit, increment] = $('#ai-time').value.split('+').map(Number);
  $('#btn-ai').disabled = true;
  const res = await call(api.game.challengeAi({
    level: Number($('#ai-level').value), limit, increment, color: $('#ai-color').value,
  }), 'Could not start game');
  $('#btn-ai').disabled = false;
  if (res && res.id) { state.awaitingGameId = res.id; openGame(res.id); }
});

$('#btn-seek').addEventListener('click', async () => {
  const [time, increment] = $('#seek-time').value.split('+').map(Number);
  await call(api.game.seek({ time, increment, rated: $('#seek-rated').value === 'true', color: 'random' }), 'Seek failed');
});
$('#btn-cancel-seek').addEventListener('click', () => api.game.cancelSeek());
api.on.seekStatus((s) => {
  $('#seeking').classList.toggle('hidden', !s.active);
  $('#btn-seek').disabled = s.active;
  if (s.error) toast(`Seek failed: ${s.error}`, true);
});

// ---------------- lichess events ----------------
api.on.lichessEvent((ev) => {
  if (ev.type === 'gameStart') {
    const id = ev.game.gameId || ev.game.id;
    const current = state.game;
    if (!current || current.over || current.id === id) {
      if (!current || current.id !== id) {
        api.game.cancelSeek();
        openGame(id);
      }
    } else {
      toast(`Another game is in progress: ${id}`);
    }
  } else if (ev.type === 'challenge' && ev.challenge && ev.challenge.destUser && state.me
    && ev.challenge.destUser.id === state.me.id) {
    toast(`Challenge from ${ev.challenge.challenger?.name || 'someone'} — accept it on lichess.org to play it here.`);
  }
});

function openGame(id) {
  if (state.game && state.game.id === id) return;
  state.game = {
    id,
    color: null,
    chess: new Chess(),
    initialFen: null,
    sans: [],
    ucis: [],
    lastMove: null,
    wtime: 0, btime: 0, stamp: performance.now(),
    status: 'created',
    over: false,
    white: null, black: null,
    oppDraw: false,
    warned: new Set(),
  };
  state.pending = null;
  state.review = null;
  state.voiceUcis.clear();
  $('#voice-log').innerHTML = '';
  $('#moves').innerHTML = '';
  $('#game-status').textContent = 'Connecting…';
  show('game');
  api.game.watch(id);
}

api.on.gameEvent((ev) => {
  const g = state.game;
  if (!g || ev.gameId !== g.id) return;
  switch (ev.type) {
    case 'gameFull': onGameFull(ev); break;
    case 'gameState': applyState(ev, false); break;
    case 'opponentGone':
      if (ev.gone) {
        const msg = ev.claimWinInSeconds ? `Opponent left. You can claim victory in ${ev.claimWinInSeconds} seconds.` : 'Your opponent left the game.';
        $('#game-status').textContent = msg;
        say(msg);
      } else {
        $('#game-status').textContent = '';
      }
      break;
    case 'chatLine':
      if (ev.username !== 'lichess' && ev.room === 'player') logVoice('chat', `${ev.username}: ${ev.text}`);
      break;
    case 'streamError':
      toast(`Game stream: ${ev.message}`, true);
      break;
    default: break;
  }
});

function playerLabel(p) {
  if (!p) return { name: '?', rating: '' };
  if (p.aiLevel) return { name: `Stockfish level ${p.aiLevel}`, rating: '' };
  return { name: p.name || p.id || 'Anonymous', rating: p.rating ? `${p.rating}${p.provisional ? '?' : ''}` : '' };
}

function onGameFull(ev) {
  const g = state.game;
  g.white = ev.white;
  g.black = ev.black;
  g.color = ev.white?.id === state.me?.id ? 'white' : 'black';
  g.initialFen = ev.initialFen && ev.initialFen !== 'startpos' ? ev.initialFen : null;
  g.rated = ev.rated;
  g.variant = ev.variant?.key;
  g.speed = ev.speed;
  board.set({ orientation: g.color });

  const opp = playerLabel(g.color === 'white' ? g.black : g.white);
  if (g.variant && g.variant !== 'standard' && g.variant !== 'fromPosition') {
    toast(`Variant "${ev.variant.name}" is not supported by this client; open it on lichess.org.`, true);
  }
  const fresh = !ev.state.moves && ev.state.status === 'started';
  applyState(ev.state, true);
  if (fresh || !g.over) {
    const opener = fresh
      ? `New game against ${opp.name}${opp.rating ? `, rated ${opp.rating}` : ''}. You are ${g.color}.`
      : `Resuming game against ${opp.name}. You are ${g.color}.`;
    say(`${opener} ${isMyTurn() ? 'Your move.' : ''}`, { remember: true });
  }
}

function isMyTurn() {
  const g = state.game;
  return !!g && !g.over && g.color && g.chess.turn() === g.color[0];
}

function applyState(s, isFull) {
  const g = state.game;
  const ucis = s.moves ? s.moves.split(' ') : [];
  const fresh = [];

  const prefixMatches = g.ucis.length <= ucis.length && g.ucis.every((u, i) => u === ucis[i]);
  if (isFull || !prefixMatches) {
    g.chess = g.initialFen ? new Chess(g.initialFen) : new Chess();
    g.sans = [];
    g.ucis = [];
    g.lastMove = null;
  }
  for (let i = g.ucis.length; i < ucis.length; i++) {
    const u = ucis[i];
    let mv;
    try { mv = g.chess.move({ from: u.slice(0, 2), to: u.slice(2, 4), promotion: u[4] }); }
    catch { console.error('Illegal move from server?', u); break; }
    g.sans.push(mv.san);
    g.ucis.push(u);
    g.lastMove = { from: mv.from, to: mv.to };
    fresh.push({ uci: u, san: mv.san, move: mv, mine: mv.color === g.color?.[0] });
  }

  g.wtime = s.wtime ?? g.wtime;
  g.btime = s.btime ?? g.btime;
  g.stamp = performance.now();
  g.status = s.status;
  const prevOppDraw = g.oppDraw;
  g.oppDraw = g.color === 'white' ? !!s.bdraw : !!s.wdraw;

  // Announce
  const detailed = state.settings.detailedCaptures;
  const myThreats = g.color ? findThreats(g.chess, g.color[0]) : [];
  if (!isFull) {
    for (const f of fresh) {
      const text = moveToSpeech(f.move, { detailed });
      if (!f.mine && state.settings.announceOpponent) say(text, { remember: true, interrupt: true });
      if (f.mine && state.voiceUcis.has(f.uci) && state.settings.echoMyMoves) say(text);
    }
    const oppJustMoved = fresh.length && !fresh[fresh.length - 1].mine;
    if (oppJustMoved && state.settings.threatWarnings && !g.chess.isGameOver()) {
      const added = newThreats(g.myThreats || [], myThreats).slice(0, 2);
      const warn = added.map(threatText).join(' ');
      if (warn) say(warn);
      if (warn) state.lastSpoken += ` ${warn}`;
    }
    if (g.oppDraw && !prevOppDraw) say('Your opponent offers a draw. Say accept draw, or decline draw.');
  } else if (fresh.length) {
    const last = fresh[fresh.length - 1];
    state.lastSpoken = `Last move: ${last.mine ? 'you played' : 'opponent played'} ${moveToSpeech(last.move, { detailed })}`;
  }
  g.myThreats = myThreats;
  if (fresh.length) state.pending = null;

  const wasOver = g.over;
  g.over = !['created', 'started'].includes(s.status);
  if (g.over && !wasOver) {
    const msg = resultText(s);
    $('#game-status').textContent = msg;
    if (!isFull) say(msg, { remember: true });
    else $('#game-status').textContent = msg;
  } else if (!g.over && $('#game-status').textContent === 'Connecting…') {
    $('#game-status').textContent = '';
  }

  render();
  updateGrammar();
}

function threatText(t) {
  const where = describeSquareForSpeech(t.square);
  return t.kind === 'hanging'
    ? `Your ${PIECE_NAMES[t.type]} on ${where} is hanging.`
    : `Your ${PIECE_NAMES[t.type]} on ${where} is attacked by a ${PIECE_NAMES[t.by]}.`;
}

function resultText(s) {
  const g = state.game;
  const youWin = s.winner && s.winner === g.color;
  const winnerWord = s.winner ? (youWin ? 'You win' : 'You lose') : '';
  switch (s.status) {
    case 'mate': return `Checkmate. ${winnerWord}.`;
    case 'resign': return youWin ? 'Your opponent resigned. You win.' : 'You resigned.';
    case 'stalemate': return 'Stalemate. The game is a draw.';
    case 'timeout': return youWin ? 'Your opponent left. You win.' : 'You left the game. You lose.';
    case 'outoftime': return s.winner ? (youWin ? 'Your opponent ran out of time. You win.' : 'You ran out of time.') : 'Time out. Draw.';
    case 'draw': return 'The game is a draw.';
    case 'aborted': return 'Game aborted.';
    case 'noStart': return 'The game did not start.';
    default: return winnerWord ? `${winnerWord}.` : `Game over (${s.status}).`;
  }
}

// ---------------- rendering ----------------
function render() {
  const g = state.game;
  if (!g) return;
  const r = state.review;
  if (r) {
    const prev = r.moves[r.index - 1];
    board.set({ chess: new Chess(r.fens[r.index]), lastMove: prev ? { from: prev.from, to: prev.to } : null, interactive: false });
  } else {
    board.set({ chess: g.chess, lastMove: g.lastMove, interactive: isMyTurn() });
  }

  const top = board.orientation === 'white' ? 'black' : 'white';
  const bottom = top === 'white' ? 'black' : 'white';
  for (const [slot, color] of [['top', top], ['bottom', bottom]]) {
    const p = playerLabel(g[color]);
    const el = $(`#player-${slot}`);
    el.querySelector('.pname').textContent = `${color === 'white' ? '○' : '●'} ${p.name}`;
    el.querySelector('.prating').textContent = p.rating;
    el.dataset.color = color;
  }

  const moves = $('#moves');
  moves.innerHTML = '';
  for (let i = 0; i < g.sans.length; i += 2) {
    const n = document.createElement('span');
    n.className = 'n';
    n.textContent = `${i / 2 + 1}.`;
    moves.append(n);
    for (const j of [i, i + 1]) {
      const m = document.createElement('span');
      const currentPly = r ? r.index - 1 : g.sans.length - 1;
      const judgment = r?.analysis?.moves[j]?.judgment;
      m.className = 'm' + (j === currentPly ? ' current' : '') + (judgment ? ` ${judgment}` : '');
      m.textContent = (g.sans[j] || '') + (judgment ? JUDGMENT_MARK[judgment] : '');
      if (r && g.sans[j]) {
        m.dataset.ply = j + 1;
        m.addEventListener('click', () => reviewGoto(j + 1));
      }
      moves.append(m);
    }
  }
  const cur = moves.querySelector('.current');
  if (r && cur) cur.scrollIntoView({ block: 'nearest' });
  else moves.scrollTop = moves.scrollHeight;

  const started = g.ucis.length >= 2;
  $('#btn-abort').classList.toggle('hidden', started || g.over);
  $('#btn-draw').classList.toggle('hidden', g.over);
  $('#btn-resign').classList.toggle('hidden', g.over);
  $('#draw-offer').classList.toggle('hidden', !g.oppDraw || g.over);
  $('#after-game').classList.toggle('hidden', !g.over || !!r);
  $('#review').classList.toggle('hidden', !r);
  $('#moves').classList.toggle('reviewing', !!r);
  if (r) renderReviewPanel();
  renderClocks();
}

function currentClocks() {
  const g = state.game;
  const running = !g.over && g.ucis.length >= 2 ? g.chess.turn() : null;
  const elapsed = performance.now() - g.stamp;
  return {
    white: g.wtime - (running === 'w' ? elapsed : 0),
    black: g.btime - (running === 'b' ? elapsed : 0),
    running,
  };
}

function renderClocks() {
  const g = state.game;
  if (!g || !g.color) return;
  const c = currentClocks();
  for (const slot of ['top', 'bottom']) {
    const el = $(`#player-${slot}`);
    const color = el.dataset.color;
    const clock = el.querySelector('.clock');
    clock.textContent = fmtClock(c[color]);
    clock.classList.toggle('running', c.running === color[0]);
    clock.classList.toggle('low', c[color] < 20000 && c.running === color[0]);
  }
  if (state.settings?.clockWarnings && c.running === g.color[0]) {
    const mine = c[g.color];
    for (const [limit, text] of [[60000, 'One minute left'], [30000, '30 seconds'], [10000, '10 seconds']]) {
      if (mine <= limit && mine > limit - 5000 && !g.warned.has(limit)) {
        // Only warn if we crossed the threshold during play (not if the game started below it).
        g.warned.add(limit);
        say(text);
      } else if (mine <= limit) {
        g.warned.add(limit);
      }
    }
  }
}

state.tickTimer = setInterval(renderClocks, 100);

// ---------------- moves & commands ----------------
async function submitMove(uci, source) {
  const g = state.game;
  if (!isMyTurn()) { if (source === 'voice') say("It's not your turn."); return; }
  // Optimistic update so the board feels instant.
  let mv;
  try { mv = g.chess.move({ from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci[4] }); }
  catch { if (source === 'voice') say('That move is not legal.'); return; }
  g.chess.undo();
  if (source === 'voice') state.voiceUcis.add(uci);
  board.set({ interactive: false });
  const ok = await call(api.game.move(g.id, uci), `Move ${mv.san} rejected`);
  if (!ok) {
    if (source === 'voice') say(`Move ${sanToSpeech(mv.san)} was rejected.`);
    render();
  }
}

function sanFor(uci) {
  const g = state.game;
  try {
    const mv = g.chess.move({ from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci[4] });
    g.chess.undo();
    return mv.san;
  } catch { return uci; }
}

function updateGrammar() {
  const items = [];
  const r = state.review;
  if (r) {
    for (const [cmd, phrases] of Object.entries(REVIEW_COMMANDS)) for (const p of phrases) items.push({ phrase: p, value: `rev:${cmd}` });
    for (let n = 1; n <= Math.ceil(r.moves.length / 2); n++) {
      items.push({ phrase: `go to move ${numberWords(n)}`, value: `rev:goto:${n}` });
      items.push({ phrase: `move ${numberWords(n)}`, value: `rev:goto:${n}` });
    }
    api.speech.setGrammar(items);
    return;
  }
  for (const [cmd, phrases] of Object.entries(COMMANDS)) for (const p of phrases) items.push({ phrase: p, value: `cmd:${cmd}` });
  if (isMyTurn()) items.push(...buildMoveGrammar(state.game.chess.moves({ verbose: true })));
  api.speech.setGrammar(items);
}

function handleHeard(msg) {
  const g = state.game;
  const value = msg.value || '';
  $('#heard').textContent = `“${msg.text}” · ${Math.round(msg.confidence * 100)}%`;
  logVoice('hear', `${msg.text} (${Math.round(msg.confidence * 100)}%)`);
  if (!g) return;

  if (value.startsWith('rev:')) return runReviewCommand(value.slice(4));
  if (value.startsWith('cmd:')) return runCommand(value.slice(4));

  if (value.startsWith('amb:')) {
    const options = value.slice(4).split(',').map((u) => sanToSpeech(sanFor(u)));
    say(`Which one? ${options.join(', or ')}. Say the starting square too, for example ${'knight on b one to d two'}.`, { interrupt: true });
    return;
  }

  if (/^[a-h][1-8][a-h][1-8][qrbn]?$/.test(value)) {
    if (!isMyTurn()) { say("It's not your turn."); return; }
    const san = sanFor(value);
    if (state.settings.confirmMoves) {
      state.pending = { kind: 'move', uci: value, san };
      say(`${sanToSpeech(san)}? Say yes or no.`, { interrupt: true });
    } else {
      submitMove(value, 'voice');
    }
  }
}

async function runCommand(cmd) {
  const g = state.game;
  switch (cmd) {
    case 'yes': {
      const p = state.pending;
      state.pending = null;
      if (!p) return;
      if (p.kind === 'move') submitMove(p.uci, 'voice');
      if (p.kind === 'resign') { await call(api.game.resign(g.id), 'Resign failed'); }
      return;
    }
    case 'no':
      if (state.pending) { state.pending = null; say('Cancelled.', { interrupt: true }); }
      return;
    case 'repeat':
      say(state.lastSpoken || (g.sans.length ? `Last move ${sanToSpeech(g.sans[g.sans.length - 1])}` : 'No moves yet.'), { interrupt: true });
      return;
    case 'time': {
      const c = currentClocks();
      const opp = g.color === 'white' ? 'black' : 'white';
      say(`You have ${speakDuration(c[g.color])}. Opponent has ${speakDuration(c[opp])}.`, { interrupt: true });
      return;
    }
    case 'flip': board.flip(); render(); return;
    case 'help':
      say('Say a move like knight f three, or e takes d five, or castle short. Commands: repeat, time, offer draw, accept draw, abort, resign.', { interrupt: true });
      return;
    case 'micOff': setMic(false); say('Microphone off.'); return;
    case 'review':
      if (g.over) startReview();
      else say('You can review the game after it ends.');
      return;
    default: break;
  }
  if (g.over) { say('The game is over. Say review to go over it.'); return; }
  switch (cmd) {
    case 'resign':
      state.pending = { kind: 'resign' };
      say('Are you sure you want to resign? Say yes or no.', { interrupt: true });
      break;
    case 'draw':
      if (await call(api.game.draw(g.id, true), 'Draw offer failed')) say(g.oppDraw ? 'Draw accepted.' : 'Draw offered.');
      break;
    case 'acceptDraw':
      if (!g.oppDraw) { say('There is no draw offer.'); break; }
      if (await call(api.game.draw(g.id, true), 'Accept draw failed')) say('Draw accepted.');
      break;
    case 'declineDraw':
      if (!g.oppDraw) { say('There is no draw offer.'); break; }
      if (await call(api.game.draw(g.id, false), 'Decline draw failed')) say('Draw declined.');
      break;
    case 'abort':
      if (await call(api.game.abort(g.id), 'Abort failed')) say('Aborting.');
      break;
    default: break;
  }
}

// ---------------- post-game review ----------------
function uciToMove(fen, uci) {
  if (!uci) return null;
  try { return new Chess(fen).move({ from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci[4] }); }
  catch { return null; }
}

function plural(n, word) { return `${n} ${word}${n === 1 ? '' : 's'}`; }

function errorsText(s) {
  const parts = [];
  if (s.blunder) parts.push(plural(s.blunder, 'blunder'));
  if (s.mistake) parts.push(plural(s.mistake, 'mistake'));
  if (s.inaccuracy) parts.push(plural(s.inaccuracy, 'inaccuracy').replace('inaccuracys', 'inaccuracies'));
  if (!parts.length) return 'no mistakes';
  return parts.length === 1 ? parts[0] : `${parts.slice(0, -1).join(', ')} and ${parts[parts.length - 1]}`;
}

function formatEval(ev) {
  if (!ev) return '';
  if (ev.mate !== undefined && ev.mate !== null) return ev.mate === 0 ? 'Mate' : `#${ev.mate}`;
  const cp = ev.cp ?? 0;
  return `${cp >= 0 ? '+' : ''}${(cp / 100).toFixed(1)}`;
}

function speakEval(ev) {
  if (!ev) return '';
  if (ev.mate) return `${ev.mate > 0 ? 'White' : 'Black'} has mate in ${Math.abs(ev.mate)}.`;
  const cp = evalToCp(ev);
  if (Math.abs(cp) >= 10000) return `${cp > 0 ? 'White' : 'Black'} has delivered checkmate.`;
  if (Math.abs(cp) < 30) return 'The position is about equal.';
  return `${cp > 0 ? 'White' : 'Black'} is better by ${(Math.abs(cp) / 100).toFixed(1)} pawns.`;
}

function startReview() {
  const g = state.game;
  if (!g || !g.over) return;
  const chess = g.initialFen ? new Chess(g.initialFen) : new Chess();
  const fens = [chess.fen()];
  const moves = [];
  for (const u of g.ucis) {
    moves.push(chess.move({ from: u.slice(0, 2), to: u.slice(2, 4), promotion: u[4] }));
    fens.push(chess.fen());
  }
  const r = { index: moves.length, fens, moves, analysis: null, evals: [], status: 'Starting analysis…' };
  state.review = r;
  render();
  updateGrammar();
  say('Review mode. Analyzing the game. Say next or back to step through the moves.', { interrupt: true });
  runAnalysis(r);
}

async function runAnalysis(r) {
  const g = state.game;
  // Prefer Lichess' own server analysis if it exists for this game.
  try {
    const res = await api.game.exportGame(g.id);
    const data = res.ok ? res.data : null;
    if (data?.opening?.name) r.opening = data.opening.name;
    if (data?.analysis && data.analysis.length >= r.moves.length && data.players?.white?.analysis) {
      const pick = (p) => ({ ...p.analysis });
      r.analysis = {
        source: 'lichess',
        moves: data.analysis.slice(0, r.moves.length).map((a) => ({
          judgment: a.judgment ? a.judgment.name.toLowerCase() : null,
          best: a.best || null,
          drop: a.judgment ? ({ Blunder: 30, Mistake: 20, Inaccuracy: 10 }[a.judgment.name] || 0) : 0,
        })),
        summary: { white: pick(data.players.white), black: pick(data.players.black) },
      };
      r.evals = [null, ...data.analysis.slice(0, r.moves.length).map((a) => ('mate' in a ? { mate: a.mate } : { cp: a.eval }))];
      return finishAnalysis(r);
    }
  } catch { /* fall back to the local engine */ }

  try {
    const evals = [];
    const best = [];
    engine.newGame();
    for (let i = 0; i < r.fens.length; i++) {
      if (state.review !== r) return; // review was closed
      const pos = new Chess(r.fens[i]);
      let ev;
      if (pos.isCheckmate()) ev = { cp: pos.turn() === 'w' ? -10000 : 10000, best: null };
      else if (pos.isDraw() || pos.isStalemate()) ev = { cp: 0, best: null };
      else ev = await engine.evaluate(r.fens[i], { depth: 12, movetime: 400 });
      evals.push(ev);
      best.push(ev.best);
      r.status = `Analyzing with Stockfish… ${Math.round(((i + 1) / r.fens.length) * 100)}%`;
      if (i % 4 === 0) renderReviewPanel();
    }
    r.evals = evals;
    r.analysis = { source: 'local', ...analyzeGame(evals, best) };
    finishAnalysis(r);
  } catch (e) {
    r.status = `Analysis failed: ${e.message}`;
    renderReviewPanel();
  }
}

function finishAnalysis(r) {
  if (state.review !== r) return;
  r.status = '';
  render();
  say(summaryText(r), { remember: true });
}

function summaryText(r) {
  const g = state.game;
  if (!r.analysis) return r.status || 'The analysis is not ready yet.';
  const me = r.analysis.summary[g.color];
  const opp = r.analysis.summary[g.color === 'white' ? 'black' : 'white'];
  const parts = [`Analysis ${r.analysis.source === 'lichess' ? 'from Lichess' : 'by Stockfish'}.`];
  if (r.opening) parts.push(`Opening: ${r.opening}.`);
  parts.push(`You made ${errorsText(me)}${me.accuracy != null ? `, with ${me.accuracy} percent accuracy` : ''}.`);
  parts.push(`Your opponent made ${errorsText(opp)}${opp.accuracy != null ? `, with ${opp.accuracy} percent accuracy` : ''}.`);
  // Worst move of mine.
  let worst = -1;
  r.analysis.moves.forEach((m, i) => {
    if (r.moves[i].color !== g.color[0] || !m.judgment) return;
    if (worst < 0 || m.drop > r.analysis.moves[worst].drop) worst = i;
  });
  if (worst >= 0) {
    const mv = r.moves[worst];
    const better = uciToMove(r.fens[worst], r.analysis.moves[worst].best);
    parts.push(`Your biggest ${r.analysis.moves[worst].judgment} was move ${Math.floor(worst / 2) + 1}, ${moveToSpeech(mv, { detailed: true })}.`
      + (better ? ` Better was ${sanToSpeech(better.san)}.` : ''));
    parts.push('Say next mistake to jump to your mistakes.');
  }
  return parts.join(' ');
}

function describePly(i) {
  const r = state.review;
  if (i === 0) return 'Starting position.';
  const mv = r.moves[i - 1];
  let text = `Move ${Math.floor((i - 1) / 2) + 1}, ${mv.color === 'w' ? 'white' : 'black'}: ${moveToSpeech(mv, { detailed: true })}.`;
  const a = r.analysis?.moves[i - 1];
  if (a?.judgment) {
    text += ` ${a.judgment.charAt(0).toUpperCase()}${a.judgment.slice(1)}.`;
    const better = uciToMove(r.fens[i - 1], a.best);
    if (better) text += ` Better was ${sanToSpeech(better.san)}.`;
  }
  return text;
}

function reviewGoto(i, { speak = true } = {}) {
  const r = state.review;
  if (!r) return;
  r.index = Math.max(0, Math.min(r.moves.length, i));
  render();
  if (speak) say(describePly(r.index), { interrupt: true, remember: true });
}

function renderReviewPanel() {
  const r = state.review;
  if (!r) return;
  const ev = r.evals[r.index];
  $('#rv-eval').textContent = ev ? formatEval(ev) : '';
  $('#rv-eval').className = 'rv-eval' + (ev && evalToCp(ev) < 0 ? ' black-better' : '');
  const g = state.game;
  let status = r.status;
  if (!status && r.analysis) {
    const me = r.analysis.summary[g.color];
    status = `You: ${me.accuracy != null ? `${me.accuracy}% accuracy · ` : ''}${errorsText(me)}`;
  }
  $('#rv-status').textContent = status;
  $('#rv-pos').textContent = r.index === 0 ? 'Start' : `Move ${Math.floor((r.index - 1) / 2) + 1}${r.index % 2 ? '' : '…'} / ${Math.ceil(r.moves.length / 2)}`;
}

function exitReview() {
  state.review = null;
  render();
  updateGrammar();
}

async function runReviewCommand(cmd) {
  const r = state.review;
  if (!r) return;
  if (cmd.startsWith('goto:')) {
    const n = Number(cmd.slice(5));
    const g = state.game;
    // "go to move 12" shows the position after my 12th move.
    reviewGoto(2 * n - (g.color === 'white' ? 1 : 0));
    return;
  }
  switch (cmd) {
    case 'next':
      if (r.index >= r.moves.length) say('That was the last move.', { interrupt: true });
      else reviewGoto(r.index + 1);
      break;
    case 'back':
      if (r.index === 0) say('This is the starting position.', { interrupt: true });
      else reviewGoto(r.index - 1);
      break;
    case 'start': reviewGoto(0); break;
    case 'end': reviewGoto(r.moves.length); break;
    case 'summary': say(summaryText(r), { interrupt: true }); break;
    case 'nextMistake': {
      if (!r.analysis) { say('The analysis is not ready yet.'); break; }
      const myColor = state.game.color[0];
      const idx = r.analysis.moves.findIndex((m, i) => i + 1 > r.index && m.judgment && r.moves[i].color === myColor);
      if (idx < 0) say('No more mistakes after this point.', { interrupt: true });
      else reviewGoto(idx + 1);
      break;
    }
    case 'best': {
      const fen = r.fens[r.index];
      const pos = new Chess(fen);
      if (pos.isGameOver()) { say('The game is over in this position.', { interrupt: true }); break; }
      const ev = await engine.evaluate(fen, { depth: 16, movetime: 1500 });
      const mv = uciToMove(fen, ev.best);
      say(`${mv ? `Best here is ${sanToSpeech(mv.san)}. ` : ''}${speakEval(ev)}`, { interrupt: true });
      break;
    }
    case 'exit': exitReview(); say('Review closed.'); break;
    case 'help':
      say('Say next, back, start, end, go to move and a number, next mistake, best move, summary, or exit review.', { interrupt: true });
      break;
    case 'repeat': say(state.lastSpoken || describePly(r.index), { interrupt: true }); break;
    case 'flip': board.flip(); render(); break;
    case 'micOff': setMic(false); say('Microphone off.'); break;
    default: break;
  }
}

$('#rv-start').addEventListener('click', () => reviewGoto(0, { speak: false }));
$('#rv-back').addEventListener('click', () => runReviewCommand('back'));
$('#rv-next').addEventListener('click', () => runReviewCommand('next'));
$('#rv-end').addEventListener('click', () => reviewGoto(state.review.moves.length, { speak: false }));
$('#rv-summary').addEventListener('click', () => runReviewCommand('summary'));
$('#rv-best').addEventListener('click', () => runReviewCommand('best'));
$('#rv-exit').addEventListener('click', exitReview);
$('#btn-review').addEventListener('click', startReview);

// ---------------- game buttons ----------------
$('#btn-flip').addEventListener('click', () => { board.flip(); render(); });
$('#btn-draw').addEventListener('click', () => runCommand('draw'));
$('#btn-abort').addEventListener('click', () => runCommand('abort'));
$('#btn-resign').addEventListener('click', async () => {
  if (confirm('Resign this game?')) await call(api.game.resign(state.game.id), 'Resign failed');
});
$('#btn-draw-yes').addEventListener('click', () => runCommand('acceptDraw'));
$('#btn-draw-no').addEventListener('click', () => runCommand('declineDraw'));
$('#btn-lobby').addEventListener('click', () => { state.review = null; state.game = null; setMic(false); show('lobby'); });
$('#btn-open-web').addEventListener('click', () => api.game.openInBrowser(state.game.id));

// ---------------- microphone ----------------
function setMic(on) {
  state.micOn = on;
  api.speech.listen(on);
  renderMic(on);
}

function renderMic(on) {
  const b = $('#btn-mic');
  b.setAttribute('aria-pressed', String(on));
  const ptt = state.settings?.micMode === 'ptt';
  $('#mic-state').textContent = !state.speechAvailable ? 'Speech recognition unavailable'
    : on ? 'Listening…' : ptt ? 'Hold Space to talk' : 'Mic off — press M';
}

$('#btn-mic').addEventListener('click', () => setMic(!state.micOn));

function typingInField(e) {
  const t = e.target;
  return t && (t.tagName === 'INPUT' || t.tagName === 'SELECT' || t.tagName === 'TEXTAREA');
}

document.addEventListener('keydown', (e) => {
  if (typingInField(e) || $('#settings').open) return;
  if (state.settings?.micMode === 'ptt' && e.code === 'Space') {
    e.preventDefault();
    if (!e.repeat && !state.pttHeld) { state.pttHeld = true; setMic(true); }
  } else if (state.review && ['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(e.key)) {
    e.preventDefault();
    const r = state.review;
    const to = { ArrowLeft: r.index - 1, ArrowRight: r.index + 1, Home: 0, End: r.moves.length }[e.key];
    reviewGoto(to, { speak: e.key.startsWith('Arrow') });
  } else if (e.code === 'KeyM' && !e.repeat) {
    setMic(!state.micOn);
  }
});
document.addEventListener('keyup', (e) => {
  if (e.code === 'Space' && state.pttHeld) {
    state.pttHeld = false;
    // Give the recognizer a moment to finish the phrase in progress.
    setTimeout(() => { if (!state.pttHeld) setMic(false); }, 600);
  }
});

api.on.speechEvent((msg) => {
  switch (msg.type) {
    case 'ready':
      state.voices = msg.voices || [];
      state.speechAvailable = !!msg.recognizer;
      fillVoices();
      $('#speech-status').textContent = msg.recognizer
        ? `Speech recognizer: ${msg.recognizer}.`
        : 'Speech recognition is not available on this PC (announcements still work).';
      updateGrammar();
      if (state.micOn) api.speech.listen(true);
      break;
    case 'heard': handleHeard(msg); break;
    case 'rejected':
      if (msg.text) {
        $('#heard').textContent = `Not sure: “${msg.text}” · ${Math.round(msg.confidence * 100)}%`;
        logVoice('hear', `? ${msg.text} (${Math.round(msg.confidence * 100)}%)`, true);
      }
      break;
    case 'speechDetected':
      $('#btn-mic').classList.add('hearing');
      setTimeout(() => $('#btn-mic').classList.remove('hearing'), 700);
      break;
    case 'listening':
      if (!msg.on && state.micOn && !state.pttHeld) { state.micOn = false; }
      renderMic(msg.on);
      break;
    case 'error':
      toast(msg.message, true);
      break;
    default: break;
  }
});

// ---------------- settings dialog ----------------
function applyAppearance() {
  board.setAppearance({ theme: state.settings.boardTheme, pieceSet: state.settings.pieceSet });
}

function fillVoices() {
  const sel = $('#set-voice');
  sel.innerHTML = '<option value="">System default</option>'
    + state.voices.map((v) => `<option>${v.replace(/</g, '&lt;')}</option>`).join('');
  sel.value = state.settings?.voice || '';
}

function loadSettingsForm() {
  const s = state.settings;
  $('#set-voice').value = s.voice || '';
  $('#set-rate').value = s.rate;
  $('#set-volume').value = s.volume;
  $('#set-threshold').value = s.threshold;
  $('#set-threshold-val').textContent = `${Math.round(s.threshold * 100)}%`;
  document.querySelector(`input[name=micMode][value=${s.micMode}]`).checked = true;
  $('#set-announce').checked = s.announceOpponent;
  $('#set-echo').checked = s.echoMyMoves;
  $('#set-confirm').checked = s.confirmMoves;
  $('#set-clock').checked = s.clockWarnings;
  $('#set-detailed').checked = s.detailedCaptures;
  $('#set-threats').checked = s.threatWarnings;
  $('#set-theme').value = s.boardTheme;
  $('#set-pieces').value = s.pieceSet;
}

async function saveSettingsForm() {
  const patch = {
    voice: $('#set-voice').value,
    rate: Number($('#set-rate').value),
    volume: Number($('#set-volume').value),
    threshold: Number($('#set-threshold').value),
    micMode: document.querySelector('input[name=micMode]:checked').value,
    announceOpponent: $('#set-announce').checked,
    echoMyMoves: $('#set-echo').checked,
    confirmMoves: $('#set-confirm').checked,
    clockWarnings: $('#set-clock').checked,
    detailedCaptures: $('#set-detailed').checked,
    threatWarnings: $('#set-threats').checked,
    boardTheme: $('#set-theme').value,
    pieceSet: $('#set-pieces').value,
  };
  Object.assign(state.settings, patch);
  applyAppearance();
  await api.settings.set(patch);
  renderMic(state.micOn);
}

$('#btn-settings').addEventListener('click', () => { loadSettingsForm(); $('#settings').showModal(); });
$('#settings').addEventListener('input', () => {
  $('#set-threshold-val').textContent = `${Math.round(Number($('#set-threshold').value) * 100)}%`;
  saveSettingsForm();
});
$('#btn-test-voice').addEventListener('click', async () => {
  await saveSettingsForm();
  say('Knight takes ee 5, check.', { interrupt: true });
});

// ---------------- boot ----------------
(async function boot() {
  state.settings = await api.settings.get();
  applyAppearance();
  if (state.settings.speechReady) {
    state.voices = state.settings.speechReady.voices || [];
    state.speechAvailable = !!state.settings.speechReady.recognizer;
  }
  fillVoices();
  renderMic(false);
  const res = await api.auth.restore();
  if (res.ok && res.data) afterLogin(res.data);
  else {
    if (!res.ok) $('#login-error').textContent = `Could not reconnect: ${res.error}`;
    show('login');
  }
})();

// ---------------- updates ----------------
function renderUpdate(s) {
  if (!s) return;
  $('#app-version').textContent = `v${s.version}`;
  const text = {
    idle: '',
    disabled: 'Updates are checked in the installed app (not when run with npm start).',
    checking: 'Checking for updates…',
    current: 'You have the latest version.',
    downloading: `Downloading v${s.newVersion}… ${s.percent ?? 0}%`,
    ready: `Version ${s.newVersion} is ready to install.`,
    error: `Update check failed: ${s.error}`,
  }[s.state] ?? '';
  $('#update-text').textContent = text;
  $('#btn-check-update').disabled = s.state === 'checking' || s.state === 'downloading' || s.state === 'disabled';
  const banner = $('#update-banner');
  banner.classList.toggle('hidden', s.state !== 'ready');
  banner.textContent = `Restart to update to v${s.newVersion}`;
}

api.on.updateStatus(renderUpdate);
api.update.status().then(renderUpdate);
$('#btn-check-update').addEventListener('click', () => api.update.check());
$('#update-banner').addEventListener('click', () => {
  const g = state.game;
  if (g && !g.over && !confirm('A game is in progress. Restart now? (The game continues on Lichess and resumes when the app reopens.)')) return;
  api.update.install();
});

// Debug hook for automated UI checks (simulating Lichess events without an account). Dev runs only.
if (api.dev) window.__vc = { state, openGame, onGameFull, applyState, handleHeard, updateGrammar };
