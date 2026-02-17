import SwiftUI
import SwiftData
import os

struct AppProfileEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppProfile.appName) private var profiles: [AppProfile]
    @State private var selectedProfile: AppProfile?

    var body: some View {
        NavigationSplitView {
            List(profiles, selection: $selectedProfile) { profile in
                HStack {
                    VStack(alignment: .leading) {
                        Text(profile.appName).font(.body)
                        Text(profile.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let mode = profile.defaultMode {
                        Image(systemName: mode.iconName).foregroundStyle(.secondary)
                    }
                }
                .tag(profile)
            }
            .navigationTitle("App Profiles")
        } detail: {
            if let profile = selectedProfile {
                AppProfileDetailView(profile: profile)
            } else {
                ContentUnavailableView("No Profile Selected", systemImage: "apps.iphone", description: Text("Select a profile to edit"))
            }
        }
    }
}

private struct AppProfileDetailView: View {
    @Bindable var profile: AppProfile
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section("Application") {
                LabeledContent("Name", value: profile.appName)
                LabeledContent("Bundle ID", value: profile.bundleIdentifier)
                Toggle("Enabled", isOn: $profile.isEnabled)
            }

            Section("Processing") {
                Picker("Default Mode", selection: modeBinding) {
                    Text("Use Global Default").tag(ProcessingMode?.none)
                    ForEach(ProcessingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(ProcessingMode?.some(mode))
                    }
                }
            }

            Section("Language") {
                TextField("Preferred Language (e.g., en, tr)", text: languageBinding)
                    .textFieldStyle(.roundedBorder)
                Text("Leave empty to use global default").font(.caption).foregroundStyle(.secondary)
            }

            Section("Injection") {
                Picker("Method", selection: $profile.injectionMethod) {
                    ForEach(InjectionMethod.allCases, id: \.self) { method in
                        Text(method.rawValue.capitalized).tag(method)
                    }
                }
            }

            Section {
                Button("Delete Profile", role: .destructive) {
                    modelContext.delete(profile)
                    try? modelContext.save()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(profile.appName)
        .onChange(of: profile.isEnabled) { _, _ in try? modelContext.save() }
        .onChange(of: profile.injectionMethod) { _, _ in try? modelContext.save() }
    }

    // Use computed bindings since AppProfile uses optional types
    private var modeBinding: Binding<ProcessingMode?> {
        Binding(
            get: { profile.defaultMode },
            set: { profile.defaultMode = $0; try? modelContext.save() }
        )
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { profile.preferredLanguage ?? "" },
            set: { profile.preferredLanguage = $0.isEmpty ? nil : $0; try? modelContext.save() }
        )
    }
}

#Preview {
    AppProfileEditorView()
        .modelContainer(for: [AppProfile.self, VocabularyEntry.self], inMemory: true)
}
