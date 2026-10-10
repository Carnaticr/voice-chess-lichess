# Voice Chess for Lichess

Desktop Lichess client for Windows that **reads your opponent's moves aloud** and lets you **speak your own moves**.

- Electron app; plays through the official [Lichess Board API](https://lichess.org/api#tag/Board).
- Speech uses the Windows built‑in System.Speech engine (offline, no API keys) via `speech/speech-host.ps1`.
- On your turn the recognizer listens only for your **legal moves** (plus a few commands), so accuracy is high.

## Run

```
npm install
npm start
```

Build an installer locally: `npm run dist` → `dist/VoiceChess-Setup-<version>.exe`.
Tests: `npm test`.

## Install & updates

Download `VoiceChess-Setup-<version>.exe` from [Releases](https://github.com/Carnaticr/voice-chess-lichess/releases/latest).
The installed app checks GitHub Releases at startup and every 4 hours, downloads updates in the background and shows
**Restart to update** in the top bar (otherwise the update installs when you quit). Settings → *Check for updates* checks on demand.
The installer isn't code-signed, so Windows SmartScreen may warn on first install ("More info" → "Run anyway").

### Publishing a new version

1. Bump `version` in `package.json` (e.g. `0.1.1`) and commit.
2. `GH_TOKEN=$(gh auth token) npm run release` — builds and uploads the installer, `latest.yml` and blockmap to a GitHub release `v<version>`.

Installed copies pick it up on their next check.

## First launch

Click the token link, create a Lichess personal token (`board:play`, `challenge:write`), paste it in.
The token is encrypted with Windows DPAPI (`safeStorage`) under `%APPDATA%\voice-chess-lichess`.

## Speaking

Toggle the mic with the button or **M**, or switch to push‑to‑talk (hold **Space**) in Settings.

| Say | Plays |
| --- | --- |
| "e four", "echo four", "pawn to e four" | e4 |
| "knight f three", "horse to foxtrot three" | Nf3 |
| "e takes d five", "pawn takes d five" | exd5 |
| "knight b d two", "knight on b one to d two" | Nbd2 |
| "castle short" / "long castle" | O‑O / O‑O‑O |
| "e eight queen", "e eight promote to knight" | e8=Q / e8=N |
| "g one f three" | any move, from‑to |

Commands: *repeat*, *time*, *offer draw*, *accept draw*, *decline draw*, *abort*, *resign* (asks yes/no), *flip board*, *help*, *stop listening*, *review* (after the game).

If a phrase fits two moves (e.g. "knight d two") the app asks which one. Settings include voice, rate, confidence threshold,
optional yes/no confirmation before each spoken move, read‑back of your moves and low‑clock warnings.

## Announcements

- Captures name the piece taken: "Bishop takes knight on c6".
- After the opponent moves, you're warned about **newly** attacked pieces: "Your queen on h5 is attacked by a pawn" / "Your knight on f3 is hanging".

## Post-game review

Click **Review game** or say "review". The game is analysed with Lichess' server analysis if it exists, otherwise locally
with Stockfish 19 (lite WASM, runs inside the app). You get a spoken summary (accuracy, blunders/mistakes/inaccuracies,
your worst move and what was better), marks in the move list (?!, ?, ??), and navigation by voice or keys:
"next" / "back" (←/→), "start" / "end" (Home/End), "go to move twelve", "next mistake", "best move", "summary", "exit review".

## Appearance

Settings → Board theme (brown, blue, green, purple, grey, high contrast) and pieces (Lichess classic SVGs or simple glyphs).

## Notes / limits

- Open seeks through the Board API are limited to rapid and classical; games vs. Stockfish can use faster clocks.
- Standard chess only.
- Windows must allow desktop apps to use the microphone (Settings → Privacy & security → Microphone).
- Anything recognized while the app is speaking is ignored so it doesn't hear its own announcements.
- Licensing: Stockfish.js and chessground (piece artwork) are GPL‑3.0, so distributed builds of this app are GPL‑3.0 too.
