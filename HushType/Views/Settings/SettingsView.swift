import SwiftUI
import SwiftData
import os

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
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

            ModelsSettingsTab()
                .tabItem {
                    Label("Models", systemImage: "arrow.down.circle")
                }
                .tag(2)
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            Logger.ui.info("Settings window opened")
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [UserSettings.self, ModelInfo.self], inMemory: true)
}
