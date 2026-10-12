import SwiftUI

struct TimeControl: Hashable, Identifiable {
    let minutes: Int
    let increment: Int
    var id: String { "\(minutes)+\(increment)" }
    var label: String { "\(minutes) + \(increment)" }

    static let computer = [TimeControl(minutes: 5, increment: 3), TimeControl(minutes: 10, increment: 0),
                           TimeControl(minutes: 10, increment: 5), TimeControl(minutes: 15, increment: 10),
                           TimeControl(minutes: 30, increment: 0)]
    // The Board API only allows rapid and classical open seeks.
    static let seek = [TimeControl(minutes: 10, increment: 0), TimeControl(minutes: 10, increment: 5),
                       TimeControl(minutes: 15, increment: 10), TimeControl(minutes: 30, increment: 0),
                       TimeControl(minutes: 30, increment: 20)]
}

struct LobbyView: View {
    @Environment(AppModel.self) private var model
    @State private var level = 3
    @State private var aiTime = TimeControl(minutes: 10, increment: 5)
    @State private var color = "random"
    @State private var seekTime = TimeControl(minutes: 10, increment: 5)
    @State private var rated = false

    var body: some View {
        Form {
            Section("Play the computer") {
                Picker("Strength", selection: $level) {
                    ForEach(1...8, id: \.self) { Text("Level \($0)").tag($0) }
                }
                Picker("Time control", selection: $aiTime) {
                    ForEach(TimeControl.computer) { Text($0.label).tag($0) }
                }
                Picker("Your color", selection: $color) {
                    Text("Random").tag("random")
                    Text("White").tag("white")
                    Text("Black").tag("black")
                }
                Button {
                    Task { await model.playComputer(level: level, minutes: aiTime.minutes, increment: aiTime.increment, color: color) }
                } label: {
                    Label("Play computer", systemImage: "cpu")
                }
                .disabled(model.busy)
            }

            Section {
                Picker("Time control", selection: $seekTime) {
                    ForEach(TimeControl.seek) { Text($0.label).tag($0) }
                }
                Toggle("Rated", isOn: $rated)
                if model.seeking {
                    HStack {
                        ProgressView()
                        Text("Looking for an opponent…")
                        Spacer()
                        Button("Cancel", role: .cancel) { model.cancelSeek() }
                    }
                } else {
                    Button {
                        model.seek(minutes: seekTime.minutes, increment: seekTime.increment, rated: rated)
                    } label: {
                        Label("Find opponent", systemImage: "person.2")
                    }
                }
            } header: {
                Text("Play a person")
            } footer: {
                Text("The Board API supports rapid and classical games for open seeks.")
            }

            Section("Speaking your moves") {
                VoiceHelp()
            }

            Section {
                Button("Log out", role: .destructive) { model.logout() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Voice Chess")
    }
}

struct VoiceHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Turn the microphone on in a game, then say a move:")
            Group {
                Text("“e four” · “pawn to e four” · “knight f three”")
                Text("“e takes d five” · “bishop takes c six”")
                Text("“knight b d two” · “rook on a one to d one”")
                Text("“castle short” · “long castle” · “e eight queen”")
            }
            .foregroundStyle(.secondary)
            Text("Commands: repeat, time, offer draw, accept draw, decline draw, abort, resign, flip board, help. After a game: review, next, back, go to move twelve, next mistake, best move, summary.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack { LobbyView() }
        .environment(AppModel())
}
