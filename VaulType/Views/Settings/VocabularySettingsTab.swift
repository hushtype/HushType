import SwiftUI
import SwiftData

struct VocabularySettingsTab: View {
    var body: some View {
        VocabularyEditorView()
            .frame(minHeight: 400)
    }
}

#Preview {
    VocabularySettingsTab()
        .modelContainer(for: [VocabularyEntry.self, AppProfile.self], inMemory: true)
}
