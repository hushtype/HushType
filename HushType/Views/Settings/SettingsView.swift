import SwiftUI
import SwiftData
import os

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
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
        .modelContainer(for: [UserSettings.self, ModelInfo.self, PromptTemplate.self], inMemory: true)
}
