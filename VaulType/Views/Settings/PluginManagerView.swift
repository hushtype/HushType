import AppKit
import SwiftUI

struct PluginManagerView: View {
    let pluginManager: PluginManager

    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        Form {
            // MARK: - Header section

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Extend VaulType with custom plugins. Place .bundle files in ~/Library/Application Support/VaulType/Plugins/ to install them.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            pluginManager.discoverPlugins()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh plugin list")
                        .accessibilityHint("Scans the Plugins folder and loads any new .bundle files found")

                        Button {
                            openPluginsFolder()
                        } label: {
                            Label("Open Plugins Folder", systemImage: "folder")
                        }
                        .accessibilityLabel("Open Plugins folder in Finder")
                        .accessibilityHint("Reveals the ~/Library/Application Support/VaulType/Plugins directory in Finder")
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Plugin Manager")
            }

            // MARK: - Plugin list section

            Section {
                if pluginManager.loadedPlugins.isEmpty {
                    emptyStateView
                } else {
                    ForEach(pluginManager.loadedPlugins, id: \.identifier) { plugin in
                        PluginRow(
                            plugin: plugin,
                            isActive: pluginManager.isActive(identifier: plugin.identifier)
                        ) { shouldActivate in
                            togglePlugin(plugin: plugin, activate: shouldActivate)
                        } onRemove: {
                            removePlugin(plugin: plugin)
                        }
                    }
                }
            } header: {
                Text("Installed Plugins (\(pluginManager.loadedPlugins.count))")
            } footer: {
                if !pluginManager.loadedPlugins.isEmpty {
                    Text("Toggle the switch to activate or deactivate a plugin. Use the trash button to unload a plugin from the current session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .alert("Plugin Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("No Plugins Installed")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Place .bundle plugin files in the Plugins folder, then click Refresh to load them.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                openPluginsFolder()
            } label: {
                Label("Open Plugins Folder", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Open Plugins folder in Finder")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Actions

    private func openPluginsFolder() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let pluginsURL = appSupport.appendingPathComponent("VaulType/Plugins")

        // Ensure the directory exists before opening
        pluginManager.ensurePluginsDirectory()
        NSWorkspace.shared.open(pluginsURL)
    }

    private func togglePlugin(plugin: any VaulTypePlugin, activate: Bool) {
        do {
            if activate {
                try pluginManager.activatePlugin(identifier: plugin.identifier)
            } else {
                try pluginManager.deactivatePlugin(identifier: plugin.identifier)
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func removePlugin(plugin: any VaulTypePlugin) {
        do {
            try pluginManager.removePlugin(identifier: plugin.identifier)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - PluginRow

private struct PluginRow: View {
    let plugin: any VaulTypePlugin
    let isActive: Bool
    let onToggle: (Bool) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(plugin.displayName)
                        .font(.headline)
                    Text("v\(plugin.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !plugin.pluginDescription.isEmpty {
                    Text(plugin.pluginDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(plugin.identifier)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { isActive },
                    set: { newValue in onToggle(newValue) }
                )
            )
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel("\(plugin.displayName) \(isActive ? "active" : "inactive")")
            .accessibilityHint("Toggle to \(isActive ? "deactivate" : "activate") the \(plugin.displayName) plugin")

            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(plugin.displayName)")
            .accessibilityHint("Unloads the \(plugin.displayName) plugin from the current session")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    PluginManagerView(pluginManager: PluginManager())
        .frame(width: 500, height: 600)
}
