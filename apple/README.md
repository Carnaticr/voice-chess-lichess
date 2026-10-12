# Voice Chess — SwiftUI (macOS, iPhone, iPad)

Native version of Voice Chess for Lichess: hear your opponent's moves, speak your own.

- **SwiftUI** app for macOS 14+ and iOS/iPadOS 17+, one multiplatform target.
- **VoiceChessCore** Swift package with the testable logic: chess rules (legal moves, SAN, FEN; verified with perft),
  the voice parser, speech text, threat detection and the Lichess Board API client.
- Speech uses Apple's frameworks: `SFSpeechRecognizer` (on-device when supported) for input,
  `AVSpeechSynthesizer` for announcements. Speech heard while the app is talking is ignored.

## Build

Requires Xcode 16 or newer and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
cd apple
xcodegen generate
open VoiceChess.xcodeproj
```

Choose the **VoiceChess** scheme with a Mac or iOS destination. To run on a device, set your team under
Signing & Capabilities (the bundle id is `io.github.carnaticr.voicechess`; change it if needed).

Core tests: `cd apple/VoiceChessCore && swift test`. CI builds both platforms on every push (`.github/workflows/apple.yml`).

## Speaking

Moves: "e four", "knight f three", "night to f3", "e takes d five", "bishop takes knight on c6", "knight b d two",
"g one f three", "castle short", "e eight queen" (promotion defaults to a queen). Commands: repeat, time, offer draw,
accept/decline draw, abort, resign (asks yes/no), flip board, help, stop listening, review.
Review: next, back, start, end, go to move twelve, next mistake, best move, summary, exit review.

## Differences from the Windows app

- Review uses Lichess' server analysis. If a game hasn't been analysed, request a computer analysis on
  lichess.org and tap **Reload analysis**. (No embedded Stockfish yet.)
- Speech recognition is free-form (Apple doesn't support fixed grammars), so the parser tolerates common
  mishearings ("night", "for", "see", "rock"…) and only accepts legal moves.
