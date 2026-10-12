import SwiftUI

@main
struct VoiceChessApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.restore() }
                #if os(macOS)
                .frame(minWidth: 820, minHeight: 600)
                #endif
        }
        #if os(macOS)
        Settings {
            SettingsView()
                .environment(model)
                .frame(width: 460, height: 560)
        }
        #endif
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            content
                .toolbar { toolbar }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 460, minHeight: 560)
            #endif
        }
        .alert("Voice Chess", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .restoring:
            ProgressView("Connecting to Lichess…")
        case .loggedOut:
            LoginView()
        case .lobby:
            LobbyView()
        case .game:
            if let game = model.game {
                GameView(game: game)
            } else {
                LobbyView()
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            if let account = model.account {
                Label {
                    Text(account.username)
                } icon: {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(model.connected ? .green : .orange)
                        .imageScale(.small)
                }
                .labelStyle(.titleAndIcon)
                .accessibilityLabel(model.connected ? "Connected as \(account.username)" : "Reconnecting")
            }
        }
        ToolbarItem(placement: .automatic) {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}
