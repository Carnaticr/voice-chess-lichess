import Foundation
import Observation
import VoiceChessCore

/// Post-game review: navigation plus Lichess' server analysis when available.
struct ReviewState {
    var index: Int
    var judgments: [String?] = []
    var best: [String?] = []
    var evals: [String?] = []
    var mySummary: GameExport.SideAnalysis?
    var opponentSummary: GameExport.SideAnalysis?
    var opening: String?
    var status: String?
    var hasAnalysis: Bool { !judgments.isEmpty }
}

struct PendingPromotion: Equatable {
    let from: Square
    let to: Square
}

@Observable @MainActor
final class GameModel {
    let id: String
    private let client: LichessClient
    private let me: Account
    private let settings: AppSettings
    private let announcer: Announcer

    private(set) var color: PieceColor?
    private(set) var white: LichessPlayer?
    private(set) var black: LichessPlayer?
    private(set) var line = GameLine()
    private(set) var wtime = 0
    private(set) var btime = 0
    private(set) var clockStamp = Date()
    private(set) var status = "created"
    private(set) var opponentOffersDraw = false
    private(set) var statusMessage: String?
    private(set) var review: ReviewState?
    private(set) var sending = false
    var orientation: PieceColor = .white
    var selected: Square?
    var pendingPromotion: PendingPromotion?
    var errorMessage: String?
    /// "Stop listening" is handled by whoever owns the microphone.
    @ObservationIgnored var onStopListening: (() -> Void)?

    @ObservationIgnored private var initial = Position.start
    @ObservationIgnored private var pending: Pending?
    @ObservationIgnored private var voiceMoves: Set<String> = []
    @ObservationIgnored private var myThreats: [Threat] = []
    @ObservationIgnored private var warned: Set<Int> = []
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    private enum Pending { case move(Move), resign }

    init(id: String, client: LichessClient, me: Account, settings: AppSettings, announcer: Announcer) {
        self.id = id
        self.client = client
        self.me = me
        self.settings = settings
        self.announcer = announcer
    }

    // MARK: Derived state

    var isOver: Bool { !["created", "started"].contains(status) }
    var isMyTurn: Bool {
        guard let color, !isOver, review == nil else { return false }
        return line.current.sideToMove == color
    }
    var displayedPosition: Position { review.map { line.positions[$0.index] } ?? line.current }
    var displayedLastMove: Move? {
        if let r = review { return r.index > 0 ? line.moves[r.index - 1] : nil }
        return line.lastMove
    }
    var currentPly: Int { review?.index ?? line.moves.count }
    var selectableTargets: Set<Square> {
        guard let selected, isMyTurn else { return [] }
        return Set(line.current.legalMoves(from: selected).map(\.to))
    }
    var opponent: LichessPlayer? { color == .white ? black : white }

    func player(_ c: PieceColor) -> LichessPlayer? { c == .white ? white : black }

    /// Remaining clock time in ms for `c`, counting down for the side to move.
    func clock(_ c: PieceColor, at now: Date) -> Int {
        let base = c == .white ? wtime : btime
        guard clockRunning == c else { return base }
        return max(0, base - Int(now.timeIntervalSince(clockStamp) * 1000))
    }

    /// Lichess starts the clocks once both sides have moved.
    var clockRunning: PieceColor? {
        guard !isOver, line.moves.count >= 2 else { return nil }
        return line.current.sideToMove
    }

    // MARK: Lifecycle

    func start() {
        streamTask = Task { await runStream() }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.checkClockWarnings()
            }
        }
    }

    func stop() {
        streamTask?.cancel()
        tickTask?.cancel()
    }

    private func runStream() async {
        var delay = 1.0
        while !Task.isCancelled {
            do {
                for try await event in client.gameEvents(gameId: id) {
                    delay = 1
                    statusMessage = nil
                    handle(event)
                }
                return // stream ends when the game is over
            } catch {
                if Task.isCancelled { return }
                if let e = error as? LichessError, let status = e.status, status < 500, status != 429 {
                    errorMessage = e.message
                    return
                }
                statusMessage = String(localized: "Reconnecting…")
            }
            try? await Task.sleep(for: .seconds(delay))
            delay = min(delay * 2, 15)
        }
    }

    // MARK: Lichess events

    private func handle(_ event: GameStreamEvent) {
        switch event {
        case .gameFull(let full): handleFull(full)
        case .gameState(let state): apply(state, full: false)
        case .opponentGone(let gone, let seconds):
            if gone {
                let msg = seconds.map { "Your opponent left. You can claim victory in \($0) seconds." } ?? "Your opponent left the game."
                statusMessage = msg
                announcer.say(msg)
            } else {
                statusMessage = nil
            }
        case .chatLine, .other:
            break
        }
    }

    private func handleFull(_ full: GameFull) {
        white = full.white
        black = full.black
        color = full.white.id == me.id ? .white : .black
        orientation = color ?? .white
        if let fen = full.initialFen, fen != "startpos", let p = Position(fen: fen) { initial = p } else { initial = .start }
        if let variant = full.variant, !["standard", "fromPosition"].contains(variant.key) {
            errorMessage = String(localized: "This variant isn't supported here. Open the game on lichess.org.")
        }
        let fresh = full.state.moves.isEmpty && full.state.status == "started"
        apply(full.state, full: true)
        guard !isOver, let color else { return }
        let opp = opponent?.displayName ?? "your opponent"
        let rating = opponent?.rating.map { ", rated \($0)" } ?? ""
        let opener = fresh ? "New game against \(opp)\(rating). You are \(color.rawValue)." : "Resuming game against \(opp). You are \(color.rawValue)."
        announcer.say(opener + (isMyTurn ? " Your move." : ""), remember: true)
    }

    private func apply(_ state: GameState, full: Bool) {
        let ucis = state.uciMoves
        let known = line.moves.map(\.uci)
        if full || !ucis.starts(with: known) {
            line = GameLine(initial: initial)
        }
        var fresh: [(move: Move, san: String)] = []
        for uci in ucis.dropFirst(line.moves.count) {
            guard line.play(uci: uci), let m = line.lastMove, let san = line.sans.last else { break }
            fresh.append((m, san))
        }
        if !fresh.isEmpty {
            selected = nil
            pending = nil
        }

        wtime = state.wtime
        btime = state.btime
        clockStamp = Date()
        let wasOver = isOver
        status = state.status
        let offeredBefore = opponentOffersDraw
        opponentOffersDraw = color == .white ? (state.bdraw ?? false) : (state.wdraw ?? false)

        let threatsNow = color.map { Threats.find(in: line.current, for: $0) } ?? []
        if !full {
            for f in fresh {
                let text = SpeechText.move(f.move, san: f.san, detailed: settings.detailedCaptures)
                let mine = f.move.piece.color == color
                if !mine && settings.announceOpponent { announcer.say(text, interrupt: true, remember: true) }
                if mine && voiceMoves.contains(f.move.uci) && settings.echoMyMoves { announcer.say(text) }
            }
            if let last = fresh.last, last.move.piece.color != color, settings.threatWarnings, !line.current.isGameOver {
                let warning = Threats.new(before: myThreats, after: threatsNow).prefix(2).map(SpeechText.threat).joined(separator: " ")
                if !warning.isEmpty {
                    announcer.say(warning)
                    announcer.remember(announcer.lastSpoken + " " + warning)
                }
            }
            if opponentOffersDraw && !offeredBefore {
                announcer.say("Your opponent offers a draw. Say accept draw, or decline draw.")
            }
        } else if let last = fresh.last {
            let who = last.move.piece.color == color ? "you played" : "your opponent played"
            announcer.remember("Last move: \(who) \(SpeechText.move(last.move, san: last.san, detailed: settings.detailedCaptures))")
        }
        myThreats = threatsNow

        if isOver && !wasOver {
            let text = resultText(state)
            statusMessage = text
            if !full { announcer.say(text + " Say review to go over the game.", remember: true) }
        }
    }

    private func resultText(_ s: GameState) -> String {
        let youWin = s.winner != nil && s.winner == color?.rawValue
        switch s.status {
        case "mate": return youWin ? "Checkmate. You win." : "Checkmate. You lose."
        case "resign": return youWin ? "Your opponent resigned. You win." : "You resigned."
        case "stalemate": return "Stalemate. The game is a draw."
        case "timeout": return youWin ? "Your opponent left. You win." : "You left the game."
        case "outoftime":
            guard s.winner != nil else { return "Time out. Draw." }
            return youWin ? "Your opponent ran out of time. You win." : "You ran out of time."
        case "draw": return "The game is a draw."
        case "aborted": return "Game aborted."
        case "noStart": return "The game did not start."
        default: return s.winner == nil ? "Game over." : (youWin ? "You win." : "You lose.")
        }
    }

    private func checkClockWarnings() {
        guard settings.clockWarnings, let color, clockRunning == color else { return }
        let ms = clock(color, at: Date())
        for (limit, text) in [(60_000, "One minute left"), (30_000, "30 seconds"), (10_000, "10 seconds")] where ms <= limit {
            guard !warned.contains(limit) else { continue }
            warned.insert(limit)
            // Only speak thresholds crossed during play, not ones the game started below.
            if ms > limit - 5_000 { announcer.say(text) }
        }
    }

    // MARK: Moves

    func tap(_ square: Square) {
        guard isMyTurn, !sending else { return }
        let position = line.current
        if let from = selected {
            let moves = position.legalMoves(from: from).filter { $0.to == square }
            if !moves.isEmpty {
                selected = nil
                if moves.contains(where: { $0.promotion != nil }) {
                    pendingPromotion = PendingPromotion(from: from, to: square)
                } else if let m = moves.first {
                    submit(m, byVoice: false)
                }
                return
            }
        }
        if let piece = position[square], piece.color == position.sideToMove, square != selected {
            selected = square
        } else {
            selected = nil
        }
    }

    func promote(to kind: PieceKind) {
        guard let p = pendingPromotion else { return }
        pendingPromotion = nil
        if let m = line.current.legalMoves(from: p.from).first(where: { $0.to == p.to && $0.promotion == kind }) {
            submit(m, byVoice: false)
        }
    }

    private func submit(_ move: Move, byVoice: Bool) {
        guard isMyTurn else {
            if byVoice { announcer.say("It's not your turn.") }
            return
        }
        let san = line.current.san(move)
        if byVoice { voiceMoves.insert(move.uci) }
        sending = true
        Task {
            defer { sending = false }
            do {
                try await client.move(gameId: id, uci: move.uci)
            } catch {
                errorMessage = "Move \(san) rejected: \(error.localizedDescription)"
                if byVoice { announcer.say("Move \(SpeechText.san(san)) was rejected.") }
            }
        }
    }

    // MARK: Voice

    /// Handles a recognized utterance. Returns true if it was acted on.
    func handleSpeech(_ text: String, isFinal: Bool) -> Bool {
        let result = VoiceParser.parse(text, position: isMyTurn ? line.current : nil, reviewing: review != nil)
        switch result {
        case .command(let command):
            run(command)
            return true
        case .move(let move):
            let san = line.current.san(move)
            if settings.confirmMoves {
                pending = .move(move)
                announcer.say("\(SpeechText.san(san))? Say yes or no.", interrupt: true)
            } else {
                submit(move, byVoice: true)
            }
            return true
        case .ambiguous(let moves):
            let options = moves.prefix(4).map { SpeechText.san(line.current.san($0)) }.joined(separator: ", or ")
            announcer.say("Which one? \(options).", interrupt: true)
            return true
        case .illegal:
            // A pause mid-move ("knight ... f three") shouldn't count as an illegal move yet.
            guard isFinal else { return false }
            announcer.say(isMyTurn ? "That move isn't legal." : "It's not your turn.", interrupt: true)
            return true
        case .none:
            return false
        }
    }

    func run(_ command: VoiceCommand) {
        switch command {
        case .yes:
            let p = pending
            pending = nil
            switch p {
            case .move(let m): submit(m, byVoice: true)
            case .resign: resign(confirmed: true)
            case nil: break
            }
        case .no:
            if pending != nil { pending = nil; announcer.say("Cancelled.", interrupt: true) }
        case .repeatLast:
            if let r = review { announcer.say(describePly(r.index), interrupt: true) }
            else { announcer.say(announcer.lastSpoken.isEmpty ? "No moves yet." : announcer.lastSpoken, interrupt: true) }
        case .time:
            guard let color else { return }
            let now = Date()
            announcer.say("You have \(SpeechText.duration(milliseconds: clock(color, at: now))). Your opponent has \(SpeechText.duration(milliseconds: clock(color.opposite, at: now))).", interrupt: true)
        case .flipBoard:
            orientation = orientation.opposite
        case .help:
            announcer.say(review != nil
                ? "Say next, back, start, end, go to move and a number, next mistake, best move, summary, or exit review."
                : "Say a move like knight f three, e takes d five, or castle short. Commands: repeat, time, offer draw, accept draw, abort, resign, and review after the game.",
                interrupt: true)
        case .stopListening:
            onStopListening?()
            announcer.say("Microphone off.")
        case .review:
            if isOver { startReview() } else { announcer.say("You can review the game after it ends.") }
        case .resign: resign(confirmed: false)
        case .offerDraw: drawAction(accept: true, announce: opponentOffersDraw ? "Draw accepted." : "Draw offered.")
        case .acceptDraw:
            if opponentOffersDraw { drawAction(accept: true, announce: "Draw accepted.") } else { announcer.say("There is no draw offer.") }
        case .declineDraw:
            if opponentOffersDraw { drawAction(accept: false, announce: "Draw declined.") } else { announcer.say("There is no draw offer.") }
        case .abort:
            guard !isOver else { return }
            Task {
                do { try await client.abort(gameId: id) } catch { errorMessage = error.localizedDescription }
            }
        case .next, .back, .start, .end, .summary, .bestMove, .nextMistake, .exitReview, .goToMove:
            runReview(command)
        }
    }

    func resign(confirmed: Bool) {
        guard !isOver else { announcer.say("The game is over."); return }
        guard confirmed else {
            pending = .resign
            announcer.say("Are you sure you want to resign? Say yes or no.", interrupt: true)
            return
        }
        Task {
            do { try await client.resign(gameId: id) } catch { errorMessage = error.localizedDescription }
        }
    }

    private func drawAction(accept: Bool, announce: String) {
        guard !isOver else { announcer.say("The game is over."); return }
        Task {
            do {
                try await client.draw(gameId: id, accept: accept)
                announcer.say(announce)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Review

    func startReview() {
        guard isOver else { return }
        review = ReviewState(index: line.moves.count, status: String(localized: "Loading analysis…"))
        announcer.say("Review mode. Say next or back to step through the moves.", interrupt: true)
        Task { await loadAnalysis() }
    }

    func exitReview() {
        review = nil
    }

    func loadAnalysis() async {
        do {
            let export = try await client.export(gameId: id)
            guard var r = review else { return }
            r.opening = export.opening?.name
            if let plies = export.analysis, plies.count >= line.moves.count {
                r.judgments = plies.prefix(line.moves.count).map { $0.judgment?.name.lowercased() }
                r.best = plies.prefix(line.moves.count).map(\.best)
                r.evals = [nil] + plies.prefix(line.moves.count).map { ply in
                    if let mate = ply.mate { return "#\(mate)" }
                    return ply.eval.map { String(format: "%+.1f", Double($0) / 100) }
                }
                let mine = color == .black ? export.players.black : export.players.white
                let theirs = color == .black ? export.players.white : export.players.black
                r.mySummary = mine.analysis
                r.opponentSummary = theirs.analysis
                r.status = nil
                review = r
                announcer.say(summaryText(), remember: true)
            } else {
                r.status = String(localized: "This game hasn't been analysed on Lichess yet. Request a computer analysis on lichess.org, then reload.")
                review = r
                announcer.say("No computer analysis yet. You can still step through the moves.")
            }
        } catch {
            review?.status = error.localizedDescription
        }
    }

    func reviewGo(to ply: Int, speak: Bool = true) {
        guard review != nil else { return }
        review?.index = max(0, min(line.moves.count, ply))
        if speak, let r = review { announcer.say(describePly(r.index), interrupt: true, remember: true) }
    }

    private func runReview(_ command: VoiceCommand) {
        guard let r = review else {
            announcer.say(isOver ? "Say review to start reviewing." : "You can review the game after it ends.")
            return
        }
        switch command {
        case .next:
            if r.index >= line.moves.count { announcer.say("That was the last move.", interrupt: true) } else { reviewGo(to: r.index + 1) }
        case .back:
            if r.index == 0 { announcer.say("This is the starting position.", interrupt: true) } else { reviewGo(to: r.index - 1) }
        case .start: reviewGo(to: 0)
        case .end: reviewGo(to: line.moves.count)
        case .goToMove(let n):
            // "Go to move 12" shows the position after my 12th move.
            reviewGo(to: 2 * n - (color == .black ? 0 : 1))
        case .summary: announcer.say(summaryText(), interrupt: true)
        case .nextMistake:
            guard r.hasAnalysis else { announcer.say("There's no analysis for this game yet."); return }
            let mine = line.moves.indices.first { i in
                i + 1 > r.index && r.judgments[i] != nil && line.moves[i].piece.color == color
            }
            if let i = mine { reviewGo(to: i + 1) } else { announcer.say("No more mistakes after this point.", interrupt: true) }
        case .bestMove:
            let i = r.index
            if i > 0, r.hasAnalysis, let best = r.best[i - 1], let alt = line.positions[i - 1].move(uci: best) {
                announcer.say("Instead of that move, better was \(SpeechText.san(line.positions[i - 1].san(alt))).", interrupt: true)
            } else if i > 0, r.hasAnalysis {
                announcer.say("That move was fine.", interrupt: true)
            } else {
                announcer.say("No engine suggestion is available here.", interrupt: true)
            }
        case .exitReview:
            exitReview()
            announcer.say("Review closed.")
        default: break
        }
    }

    func describePly(_ ply: Int) -> String {
        guard ply > 0 else { return "Starting position." }
        let move = line.moves[ply - 1]
        let san = line.sans[ply - 1]
        var text = "Move \((ply + 1) / 2), \(move.piece.color.rawValue): \(SpeechText.move(move, san: san, detailed: true))."
        if let r = review, r.hasAnalysis, let judgment = r.judgments[ply - 1] {
            text += " \(judgment.capitalized)."
            if let best = r.best[ply - 1], let alt = line.positions[ply - 1].move(uci: best) {
                text += " Better was \(SpeechText.san(line.positions[ply - 1].san(alt)))."
            }
        }
        return text
    }

    func summaryText() -> String {
        guard let r = review, let me = r.mySummary, let them = r.opponentSummary else {
            return review?.status ?? "The analysis is not ready yet."
        }
        func errors(_ s: GameExport.SideAnalysis) -> String {
            var parts: [String] = []
            if s.blunder > 0 { parts.append("\(s.blunder) blunder\(s.blunder == 1 ? "" : "s")") }
            if s.mistake > 0 { parts.append("\(s.mistake) mistake\(s.mistake == 1 ? "" : "s")") }
            if s.inaccuracy > 0 { parts.append("\(s.inaccuracy) \(s.inaccuracy == 1 ? "inaccuracy" : "inaccuracies")") }
            return parts.isEmpty ? "no mistakes" : parts.joined(separator: ", ")
        }
        var text = "Analysis from Lichess."
        if let opening = r.opening { text += " Opening: \(opening)." }
        text += " You made \(errors(me))" + (me.accuracy.map { ", with \($0) percent accuracy." } ?? ".")
        text += " Your opponent made \(errors(them))" + (them.accuracy.map { ", with \($0) percent accuracy." } ?? ".")
        if me.blunder + me.mistake + me.inaccuracy > 0 { text += " Say next mistake to jump to your mistakes." }
        return text
    }
}
