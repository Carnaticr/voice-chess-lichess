import SwiftUI
import VoiceChessCore

struct GameView: View {
    @Environment(AppModel.self) private var app
    @Bindable var game: GameModel

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height * 1.15 {
                HStack(alignment: .top, spacing: 20) {
                    board
                    sidePanel.frame(width: min(360, geo.size.width * 0.38))
                }
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        PlayerBar(game: game, color: game.orientation.opposite)
                        board.frame(height: min(geo.size.width - 24, geo.size.height * 0.62))
                        PlayerBar(game: game, color: game.orientation)
                        controls
                    }
                    .padding(12)
                }
            }
        }
        .navigationTitle(game.opponent.map { "vs \($0.displayName)" } ?? "Game")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog("Promote to", isPresented: promotionBinding, titleVisibility: .visible) {
            ForEach([PieceKind.queen, .rook, .bishop, .knight], id: \.self) { kind in
                Button(kind.name.capitalized) { game.promote(to: kind) }
            }
        }
        .alert("Voice Chess", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(game.errorMessage ?? "")
        }
        .onKeyPress(.leftArrow) { reviewKey(-1) }
        .onKeyPress(.rightArrow) { reviewKey(1) }
    }

    private var board: some View {
        BoardView(
            position: game.displayedPosition,
            orientation: game.orientation,
            lastMove: game.displayedLastMove,
            selected: game.selected,
            targets: game.selectableTargets,
            theme: app.settings.boardTheme,
            onTap: game.tap
        )
    }

    private var sidePanel: some View {
        VStack(spacing: 10) {
            PlayerBar(game: game, color: game.orientation.opposite)
            MoveList(game: game)
            PlayerBar(game: game, color: game.orientation)
            controls
        }
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 10) {
            if let message = game.statusMessage {
                Text(message).font(.headline).multilineTextAlignment(.center)
            }
            if game.review != nil {
                ReviewPanel(game: game)
            } else {
                GameActions(game: game, onLeave: app.leaveGame)
            }
            VoiceBar()
            SpokenLog(lines: app.spokenLog)
        }
    }

    private func reviewKey(_ delta: Int) -> KeyPress.Result {
        guard let r = game.review else { return .ignored }
        game.reviewGo(to: r.index + delta)
        return .handled
    }

    private var promotionBinding: Binding<Bool> {
        Binding(get: { game.pendingPromotion != nil }, set: { if !$0 { game.pendingPromotion = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { game.errorMessage != nil }, set: { if !$0 { game.errorMessage = nil } })
    }
}

struct PlayerBar: View {
    let game: GameModel
    let color: PieceColor

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(game.player(color)?.displayName ?? "…")
                    .font(.headline)
                    .lineLimit(1)
                if let rating = game.player(color)?.rating {
                    Text("\(rating)\(game.player(color)?.provisional == true ? "?" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let ms = game.clock(color, at: context.date)
                let running = game.clockRunning == color
                Text(Self.format(ms))
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(running ? (ms < 20_000 ? Color.red : Color.accentColor) : Color.secondary.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(running ? Color.white : Color.primary)
                    .accessibilityLabel("\(color.rawValue) clock \(SpeechText.duration(milliseconds: ms))")
            }
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    static func format(_ ms: Int) -> String {
        let total = ms / 1000
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        if ms < 10_000 { return String(format: "%d:%02d.%d", m, s, (ms % 1000) / 100) }
        return String(format: "%d:%02d", m, s)
    }
}

struct MoveList: View {
    let game: GameModel

    private static let marks = ["inaccuracy": "?!", "mistake": "?", "blunder": "??"]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.fixed(36)), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                    ForEach(Array(stride(from: 0, to: game.line.sans.count, by: 2)), id: \.self) { i in
                        Text("\(i / 2 + 1).").foregroundStyle(.secondary)
                        cell(i)
                        cell(i + 1)
                    }
                }
                .padding(8)
            }
            .onChange(of: game.currentPly) { _, ply in
                withAnimation { proxy.scrollTo(max(0, ply - 1), anchor: .center) }
            }
        }
        .frame(minHeight: 120)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private func cell(_ i: Int) -> some View {
        if i < game.line.sans.count {
            let judgment = game.review.flatMap { $0.judgments.indices.contains(i) ? $0.judgments[i] : nil }
            let current = i == game.currentPly - 1
            Button {
                game.reviewGo(to: i + 1, speak: false)
            } label: {
                Text(game.line.sans[i] + (judgment.flatMap { Self.marks[$0] } ?? ""))
                    .fontWeight(current ? .bold : .regular)
                    .foregroundStyle(color(for: judgment, current: current))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(game.review == nil)
            .id(i)
        } else {
            Color.clear.frame(height: 1)
        }
    }

    private func color(for judgment: String?, current: Bool) -> Color {
        switch judgment {
        case "blunder": .red
        case "mistake": .orange
        case "inaccuracy": .blue
        default: current ? .accentColor : .primary
        }
    }
}

struct GameActions: View {
    let game: GameModel
    let onLeave: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if game.opponentOffersDraw && !game.isOver {
                HStack {
                    Text("Your opponent offers a draw")
                    Spacer()
                    Button("Accept") { game.run(.acceptDraw) }.buttonStyle(.borderedProminent)
                    Button("Decline") { game.run(.declineDraw) }
                }
                .padding(8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Button { game.run(.flipBoard) } label: { Label("Flip", systemImage: "arrow.up.arrow.down") }
                if game.isOver {
                    Button { game.startReview() } label: { Label("Review game", systemImage: "list.bullet.clipboard") }
                        .buttonStyle(.borderedProminent)
                    Button("New game", action: onLeave)
                } else {
                    if game.line.moves.count < 2 {
                        Button("Abort") { game.run(.abort) }
                    }
                    Button("Offer draw") { game.run(.offerDraw) }
                    Button("Resign", role: .destructive) { game.resign(confirmed: true) }
                }
            }
            .buttonStyle(.bordered)
            if game.isOver, let url = LichessClient.gameURL(game.id) {
                Link("Open on lichess.org", destination: url).font(.footnote)
            }
        }
    }
}

struct ReviewPanel: View {
    let game: GameModel

    var body: some View {
        let r = game.review
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(positionLabel).font(.headline)
                Spacer()
                if let r, r.evals.indices.contains(r.index), let eval = r.evals[r.index] {
                    Text(eval)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        .accessibilityLabel("Evaluation \(eval)")
                }
            }
            HStack {
                navButton("backward.end.fill", "Start") { game.reviewGo(to: 0, speak: false) }
                navButton("chevron.backward", "Back") { game.run(.back) }
                navButton("chevron.forward", "Next") { game.run(.next) }
                navButton("forward.end.fill", "End") { game.reviewGo(to: game.line.moves.count, speak: false) }
            }
            if let status = r?.status {
                Text(status).font(.callout).foregroundStyle(.secondary)
                if r?.hasAnalysis == false {
                    Button("Reload analysis") { Task { await game.loadAnalysis() } }
                }
            } else if let me = r?.mySummary {
                Text("You: \(me.accuracy.map { "\($0)% accuracy · " } ?? "")\(me.blunder) blunders, \(me.mistake) mistakes, \(me.inaccuracy) inaccuracies")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Best move") { game.run(.bestMove) }
                Button("Summary") { game.run(.summary) }
                Spacer()
                Button("Exit review") { game.exitReview() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var positionLabel: String {
        let ply = game.currentPly
        guard ply > 0 else { return String(localized: "Start") }
        return "Move \((ply + 1) / 2)\(ply % 2 == 0 ? "…" : "") / \((game.line.moves.count + 1) / 2)"
    }

    private func navButton(_ icon: String, _ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon).labelStyle(.iconOnly).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

struct VoiceBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let voice = app.voice
        HStack(spacing: 12) {
            Button {
                Task { await voice.toggle() }
            } label: {
                Image(systemName: voice.isOn ? "mic.fill" : "mic.slash")
                    .font(.title2)
                    .frame(width: 48, height: 48)
                    .background(voice.isOn ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                    .foregroundStyle(voice.isOn ? Color.white : Color.primary)
                    .symbolEffect(.pulse, isActive: voice.state == .listening)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("m", modifiers: [])
            .accessibilityLabel(voice.isOn ? "Turn microphone off" : "Turn microphone on")

            VStack(alignment: .leading, spacing: 2) {
                Text(stateText(voice.state)).font(.headline)
                if !voice.transcript.isEmpty {
                    Text("“\(voice.transcript)”")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func stateText(_ state: VoiceInput.State) -> String {
        switch state {
        case .off: String(localized: "Mic off")
        case .starting: String(localized: "Starting…")
        case .listening: String(localized: "Listening…")
        case .unavailable(let reason): reason
        }
    }
}

struct SpokenLog: View {
    let lines: [String]

    var body: some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.prefix(4).enumerated()), id: \.offset) { _, line in
                    Label(line, systemImage: "speaker.wave.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true) // already spoken aloud
        }
    }
}
