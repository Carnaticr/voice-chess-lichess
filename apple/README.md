# Voice Chess — SwiftUI (macOS, iPhone, iPad)

Native version of Voice Chess for Lichess: hear your opponent's moves, speak your own.

- **SwiftUI** app for macOS 14+ and iOS/iPadOS 17+, one multiplatform target.
- **VoiceChessCore** Swift package with the testable logic: chess rules (legal moves, SAN, FEN; verified with perft),
  the voice parser, speech text, threat detection and the Lichess Board API client.
- Speech uses Apple's frameworks: `SFSpeechRecognizer` (on-device when supported) for input,
  `AVSpeechSynthesizer` for announcements. Speech heard while the app is talking is ignored.

## Build

Requires a Mac with Xcode 16 or newer (CI uses Xcode 26).

1. Open `apple/VoiceChess.xcodeproj` in Xcode (no other tools needed).
2. Pick the **VoiceChess** scheme and a destination: **My Mac**, an iPhone/iPad simulator, or a connected device.
3. For a device (or a signed Mac build), select the VoiceChess target → **Signing & Capabilities**, choose your team,
   and change the bundle identifier (`io.github.carnaticr.voicechess`) to one you own if needed.
4. Run (⌘R). Grant microphone and speech-recognition access when asked.

Core logic tests: in Xcode open `apple/VoiceChessCore/Package.swift` and press ⌘U, or run `swift test` in that folder.

The committed `VoiceChess.xcodeproj` is the source of truth; edit it in Xcode as usual. `project.yml` is the
[XcodeGen](https://github.com/yonaskolb/XcodeGen) spec it was generated from (`xcodegen generate` recreates it,
discarding manual project edits). CI (`.github/workflows/apple.yml`) runs the core tests and builds both platforms.

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
