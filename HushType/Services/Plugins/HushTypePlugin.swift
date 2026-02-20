import Foundation

/// Current plugin API version. Plugins must declare a compatible version.
let kHushTypePluginAPIVersion = "0.5.0"

/// Base protocol for all HushType plugins.
///
/// Plugins are loadable bundles that extend HushType functionality.
/// Each plugin must conform to this protocol and declare itself as the
/// bundle's principal class.
///
/// Lifecycle:
/// 1. Plugin bundle is discovered and loaded
/// 2. Principal class is instantiated via `init()`
/// 3. `activate()` is called — plugin sets up resources
/// 4. Plugin participates in the pipeline
/// 5. `deactivate()` is called on removal or app quit
protocol HushTypePlugin: AnyObject {
    /// Reverse-DNS identifier unique to this plugin (e.g., "com.example.my-plugin").
    var identifier: String { get }

    /// Human-readable name shown in the plugin manager UI.
    var displayName: String { get }

    /// Semantic version of this plugin (e.g., "1.0.0").
    var version: String { get }

    /// Plugin API version this plugin was built against.
    /// Must match `kHushTypePluginAPIVersion` major version to load.
    var apiVersion: String { get }

    /// Optional description shown in the plugin manager.
    var pluginDescription: String { get }

    /// Called when the plugin is activated. Set up resources here.
    /// - Throws: `PluginError.activationFailed` if setup fails.
    func activate() throws

    /// Called when the plugin is deactivated. Clean up resources here.
    /// - Throws: `PluginError.deactivationFailed` if teardown fails.
    func deactivate() throws
}

// MARK: - Default Implementations

extension HushTypePlugin {
    var apiVersion: String { kHushTypePluginAPIVersion }
    var pluginDescription: String { "" }
}
