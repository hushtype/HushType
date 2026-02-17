import SwiftUI
import SwiftData

struct AppProfilesSettingsTab: View {
    var body: some View {
        AppProfileEditorView()
            .frame(minHeight: 400)
    }
}

#Preview {
    AppProfilesSettingsTab()
        .modelContainer(for: [AppProfile.self, VocabularyEntry.self], inMemory: true)
}
