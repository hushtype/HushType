import SwiftUI
import SwiftData
import os

struct AppProfileEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppProfile.appName) private var profiles: [AppProfile]
    @State private var selectedProfile: AppProfile?
    @State private var showNewProfileSheet = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        showNewProfileSheet = true
                    } label: {
                        Label("Add Profile", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

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
            }
            .frame(maxWidth: .infinity)

            Divider()

            Group {
                if let profile = selectedProfile {
                    AppProfileDetailView(profile: profile, onDelete: {
                        selectedProfile = nil
                    })
                } else {
                    ContentUnavailableView("No Profile Selected", systemImage: "apps.iphone", description: Text("Select a profile to edit"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showNewProfileSheet) {
            NewProfileSheet { bundleID, appName in
                createProfile(bundleID: bundleID, appName: appName)
                showNewProfileSheet = false
            }
        }
    }

    private func createProfile(bundleID: String, appName: String) {
        let profile = AppProfile(
            bundleIdentifier: bundleID,
            appName: appName
        )
        modelContext.insert(profile)
        do {
            try modelContext.save()
            selectedProfile = profile
            Logger.ui.info("Created app profile: \(appName) (\(bundleID))")
        } catch {
            Logger.ui.error("Failed to create app profile: \(error.localizedDescription)")
        }
    }
}

// MARK: - Detail View

private struct AppProfileDetailView: View {
    @Bindable var profile: AppProfile
    @Environment(\.modelContext) private var modelContext
    var onDelete: () -> Void

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
                    onDelete()
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: profile.isEnabled) { _, _ in try? modelContext.save() }
        .onChange(of: profile.injectionMethod) { _, _ in try? modelContext.save() }
    }

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

// MARK: - New Profile Sheet

private struct NewProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String, String) -> Void

    @State private var bundleID = ""
    @State private var appName = ""

    private var canSave: Bool {
        !bundleID.trimmingCharacters(in: .whitespaces).isEmpty &&
        !appName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("New App Profile")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                Section("Application") {
                    TextField("Bundle ID (e.g., com.example.app)", text: $bundleID)
                        .textFieldStyle(.roundedBorder)
                    TextField("App Name", text: $appName)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    onSave(
                        bundleID.trimmingCharacters(in: .whitespaces),
                        appName.trimmingCharacters(in: .whitespaces)
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding()
        .frame(width: 400, height: 280)
    }
}

#Preview {
    AppProfileEditorView()
        .modelContainer(for: [AppProfile.self, VocabularyEntry.self], inMemory: true)
}
