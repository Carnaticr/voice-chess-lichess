import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Board") {
                Picker("Theme", selection: $settings.boardTheme) {
                    ForEach(BoardTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
            }

            Section("Announcements") {
                Toggle("Announce opponent moves", isOn: $settings.announceOpponent)
                Toggle("Name captured pieces", isOn: $settings.detailedCaptures)
                Toggle("Warn when my pieces are newly attacked or hanging", isOn: $settings.threatWarnings)
                Toggle("Read back my spoken moves", isOn: $settings.echoMyMoves)
                Toggle("Warn at 1 minute, 30 and 10 seconds", isOn: $settings.clockWarnings)
            }

            Section("Voice") {
                Picker("Announcer voice", selection: $settings.voiceIdentifier) {
                    Text("System default").tag("")
                    ForEach(Announcer.englishVoices, id: \.identifier) { voice in
                        Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                    }
                }
                VStack(alignment: .leading) {
                    Text("Speaking rate")
                    Slider(value: $settings.speechRate, in: 0...1) {
                        Text("Speaking rate")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise").accessibilityLabel("Slower")
                    } maximumValueLabel: {
                        Image(systemName: "hare").accessibilityLabel("Faster")
                    }
                }
                Button("Test voice") {
                    model.applyVoiceSettings()
                    model.announcer.say("Knight takes ee 5, check.", interrupt: true)
                }
            }

            Section {
                Toggle("Ask “yes or no” before sending a spoken move", isOn: $settings.confirmMoves)
            } header: {
                Text("Voice input")
            } footer: {
                Text("Recognition runs on this device when supported. Anything heard while the app is speaking is ignored.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: settings.voiceIdentifier) { model.applyVoiceSettings() }
        .onChange(of: settings.speechRate) { model.applyVoiceSettings() }
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(AppModel())
}
