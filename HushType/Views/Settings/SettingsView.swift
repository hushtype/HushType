import SwiftUI
import SwiftData
import os

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear.circle")
                }
                .tag(0)

            AudioSettingsTab()
                .tabItem {
                    Label("Audio", systemImage: "waveform.circle")
                }
                .tag(1)

            ProcessingSettingsTab()
                .tabItem {
                    Label("Processing", systemImage: "sparkles")
                }
                .tag(2)

            ModelManagementView()
                .tabItem {
                    Label("Models", systemImage: "arrow.down.circle")
                }
                .tag(3)

            AppProfilesSettingsTab()
                .tabItem {
                    Label("App Profiles", systemImage: "apps.iphone")
                }
                .tag(4)

            VocabularySettingsTab()
                .tabItem {
                    Label("Vocabulary", systemImage: "textformat.abc")
                }
                .tag(5)

            LanguageSettingsTab()
                .tabItem {
                    Label("Language", systemImage: "globe")
                }
                .tag(6)

            HistorySettingsTab()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(7)

            CommandSettingsTab()
                .tabItem {
                    Label("Commands", systemImage: "command")
                }
                .tag(8)

            PluginManagerView(pluginManager: appState.pluginManager)
                .tabItem {
                    Label("Plugins", systemImage: "puzzlepiece.extension")
                }
                .tag(9)
        }
        .frame(minWidth: 500, minHeight: 700)
        .onAppear {
            selectedTab = 0
            Logger.ui.info("Settings window opened")
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
        .modelContainer(for: [
            UserSettings.self, ModelInfo.self, PromptTemplate.self,
            AppProfile.self, VocabularyEntry.self, DictationEntry.self,
            CustomCommand.self
        ], inMemory: true)
}
