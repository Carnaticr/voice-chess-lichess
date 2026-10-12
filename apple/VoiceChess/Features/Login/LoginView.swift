import SwiftUI
import VoiceChessCore

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var token = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "mic.and.signal.meter")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Connect your Lichess account")
                    .font(.title2.bold())
                Text("Voice Chess plays through the official Lichess Board API with a personal access token. The token is stored in your keychain on this device.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    if let url = LichessClient.tokenPage {
                        Link(destination: url) {
                            Label("Create a token on lichess.org", systemImage: "arrow.up.right.square")
                        }
                    }
                    Text("The board:play and challenge:write scopes are preselected. Tap Create, copy the token and paste it below.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                SecureField("lip_…", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(connect)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .accessibilityLabel("Lichess token")

                Button(action: connect) {
                    if model.busy { ProgressView() } else { Text("Connect").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.busy || token.isEmpty)

                if let error = model.loginError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Voice Chess")
    }

    private func connect() {
        let t = token
        Task {
            await model.login(token: t)
            if model.loginError == nil { token = "" }
        }
    }
}

#Preview {
    NavigationStack { LoginView() }
        .environment(AppModel())
}
