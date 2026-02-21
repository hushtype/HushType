import Foundation
import os

/// Manages discovery, loading, activation, and lifecycle of VaulType plugins.
///
/// Plugins are `.bundle` files placed in:
/// `~/Library/Application Support/VaulType/Plugins/`
///
/// Each plugin bundle must:
/// - Declare a `NSPrincipalClass` in its `Info.plist`
/// - Have that class be an `NSObject` subclass with a no-argument `init()`
/// - Conform to `VaulTypePlugin` (and optionally `ProcessingPlugin` or `CommandPlugin`)
///
/// Usage:
/// ```swift
/// let manager = PluginManager()
/// manager.discoverPlugins()
/// try manager.activatePlugin(identifier: "com.example.my-plugin")
/// ```
@Observable
final class PluginManager {

    // MARK: - Published State

    /// All successfully loaded plugins (active and inactive).
    private(set) var loadedPlugins: [any VaulTypePlugin] = []

    /// Active processing plugins, sorted by priority (lower value = runs first).
    private(set) var activeProcessingPlugins: [any ProcessingPlugin] = []

    /// Active command plugins.
    private(set) var activeCommandPlugins: [any CommandPlugin] = []

    // MARK: - Private

    private let pluginsDirectory: URL
    private let logger = Logger.general

    // MARK: - Init

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.pluginsDirectory = appSupport.appendingPathComponent("VaulType/Plugins")
    }

    // MARK: - Directory Management

    /// Creates the plugins directory if it does not exist.
    func ensurePluginsDirectory() {
        do {
            try FileManager.default.createDirectory(
                at: pluginsDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            logger.error("Failed to create plugins directory: \(error.localizedDescription)")
        }
    }

    // MARK: - Discovery

    /// Scans the plugins directory and loads all `.bundle` files found.
    ///
    /// Bundles that fail to load are logged and skipped — they do not prevent
    /// other plugins from loading.
    func discoverPlugins() {
        ensurePluginsDirectory()
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: pluginsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            logger.warning("Cannot read plugins directory: \(self.pluginsDirectory.path)")
            return
        }

        let bundles = contents.filter { $0.pathExtension == "bundle" }
        logger.info("Plugin discovery: found \(bundles.count) bundle(s) in \(self.pluginsDirectory.path)")

        for url in bundles {
            do {
                try loadPlugin(at: url)
            } catch {
                logger.error("Failed to load plugin at \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Loading

    /// Loads a single plugin bundle and registers it.
    ///
    /// - Parameter url: URL of the `.bundle` file to load.
    /// - Throws: `PluginError.loadFailed` if the bundle cannot be opened, loaded, or
    ///   if the principal class does not conform to `VaulTypePlugin`.
    ///   `PluginError.incompatibleVersion` if the API major version does not match.
    ///   `PluginError.duplicateIdentifier` if a plugin with the same identifier is already registered.
    ///
    /// - Note: The principal class **must** be an `NSObject` subclass with a no-argument
    ///   `init()`. This is required because `Bundle.principalClass` returns `AnyClass`
    ///   (i.e., `AnyObject.Type`) and Swift protocols cannot mandate an initializer on
    ///   existential metatypes without an `NSObject` base.
    func loadPlugin(at url: URL) throws {
        guard let bundle = Bundle(url: url) else {
            throw PluginError.loadFailed(path: url.path, reason: "Failed to create bundle")
        }

        guard bundle.load() else {
            throw PluginError.loadFailed(path: url.path, reason: "Bundle.load() returned false")
        }

        // Retrieve the principal class. It must be an NSObject subclass so we can call init().
        guard let principalClass = bundle.principalClass else {
            throw PluginError.loadFailed(path: url.path, reason: "No NSPrincipalClass declared in Info.plist")
        }

        guard let pluginClass = principalClass as? NSObject.Type else {
            throw PluginError.loadFailed(
                path: url.path,
                reason: "Principal class '\(principalClass)' is not an NSObject subclass"
            )
        }

        let instance = pluginClass.init()

        guard let plugin = instance as? any VaulTypePlugin else {
            throw PluginError.loadFailed(
                path: url.path,
                reason: "Principal class '\(principalClass)' does not conform to VaulTypePlugin"
            )
        }

        // Verify API major version compatibility
        let requiredMajor = kVaulTypePluginAPIVersion.split(separator: ".").first.map(String.init) ?? "0"
        let pluginMajor = plugin.apiVersion.split(separator: ".").first.map(String.init) ?? "0"
        guard requiredMajor == pluginMajor else {
            throw PluginError.incompatibleVersion(
                identifier: plugin.identifier,
                required: kVaulTypePluginAPIVersion,
                found: plugin.apiVersion
            )
        }

        // Guard against duplicate identifiers
        guard !loadedPlugins.contains(where: { $0.identifier == plugin.identifier }) else {
            throw PluginError.duplicateIdentifier(plugin.identifier)
        }

        loadedPlugins.append(plugin)
        logger.info("Loaded plugin: \(plugin.displayName) v\(plugin.version) (\(plugin.identifier))")
    }

    // MARK: - Activation

    /// Activates a loaded plugin by identifier.
    ///
    /// - Parameter identifier: The reverse-DNS identifier of the plugin to activate.
    /// - Throws: `PluginError.notFound` if the plugin is not loaded.
    ///   Re-throws any error raised by `plugin.activate()`.
    func activatePlugin(identifier: String) throws {
        guard let plugin = loadedPlugins.first(where: { $0.identifier == identifier }) else {
            throw PluginError.notFound(identifier: identifier)
        }

        try plugin.activate()

        if let processingPlugin = plugin as? any ProcessingPlugin {
            activeProcessingPlugins.append(processingPlugin)
            activeProcessingPlugins.sort { $0.priority < $1.priority }
        }

        if let commandPlugin = plugin as? any CommandPlugin {
            activeCommandPlugins.append(commandPlugin)
        }

        logger.info("Activated plugin: \(plugin.displayName) (\(identifier))")
    }

    // MARK: - Deactivation

    /// Deactivates an active plugin by identifier.
    ///
    /// - Parameter identifier: The reverse-DNS identifier of the plugin to deactivate.
    /// - Throws: `PluginError.notFound` if the plugin is not loaded.
    ///   Re-throws any error raised by `plugin.deactivate()`.
    func deactivatePlugin(identifier: String) throws {
        guard let plugin = loadedPlugins.first(where: { $0.identifier == identifier }) else {
            throw PluginError.notFound(identifier: identifier)
        }

        try plugin.deactivate()
        activeProcessingPlugins.removeAll { $0.identifier == identifier }
        activeCommandPlugins.removeAll { $0.identifier == identifier }
        logger.info("Deactivated plugin: \(plugin.displayName) (\(identifier))")
    }

    // MARK: - Removal

    /// Removes a plugin from the manager. Deactivates it first if currently active.
    ///
    /// - Parameter identifier: The reverse-DNS identifier of the plugin to remove.
    /// - Throws: `PluginError.notFound` if the plugin is not loaded.
    ///   Re-throws any error raised by `deactivatePlugin` if the plugin was active.
    func removePlugin(identifier: String) throws {
        guard loadedPlugins.contains(where: { $0.identifier == identifier }) else {
            throw PluginError.notFound(identifier: identifier)
        }

        // Deactivate first if currently active
        if isActive(identifier: identifier) {
            try deactivatePlugin(identifier: identifier)
        }

        loadedPlugins.removeAll { $0.identifier == identifier }
        logger.info("Removed plugin: \(identifier)")
    }

    // MARK: - Bulk Operations

    /// Deactivates all active plugins and clears all loaded plugin state.
    func deactivateAll() {
        for plugin in loadedPlugins {
            do {
                try plugin.deactivate()
            } catch {
                logger.error("Error deactivating plugin \(plugin.identifier): \(error.localizedDescription)")
            }
        }
        activeProcessingPlugins.removeAll()
        activeCommandPlugins.removeAll()
        loadedPlugins.removeAll()
    }

    // MARK: - Queries

    /// Returns whether the plugin with the given identifier is currently active.
    ///
    /// A plugin is considered active if it appears in either `activeProcessingPlugins`
    /// or `activeCommandPlugins`.
    func isActive(identifier: String) -> Bool {
        activeProcessingPlugins.contains { $0.identifier == identifier }
            || activeCommandPlugins.contains { $0.identifier == identifier }
    }

    // MARK: - Pipeline Integration

    /// Applies all active processing plugins to the given text in priority order.
    ///
    /// Each plugin receives the output of the previous one. If a plugin throws, the
    /// error is logged and processing continues with the text as it was before that
    /// plugin ran (fallback behaviour).
    ///
    /// Plugins whose `applicableModes` is empty are applied to every mode.
    ///
    /// - Parameters:
    ///   - text: The input text (e.g., raw transcription output).
    ///   - context: Metadata about the current dictation session.
    /// - Returns: The text after all applicable plugins have been applied.
    func applyProcessingPlugins(text: String, context: ProcessingContext) async throws -> String {
        var result = text
        for plugin in activeProcessingPlugins {
            guard plugin.applicableModes.isEmpty || plugin.applicableModes.contains(context.mode) else {
                continue
            }
            do {
                result = try await plugin.process(text: result, context: context)
            } catch {
                logger.error(
                    "Processing plugin \(plugin.identifier) failed: \(error.localizedDescription) — using input text as fallback"
                )
                // result retains the value from before this plugin ran
            }
        }
        return result
    }
}
