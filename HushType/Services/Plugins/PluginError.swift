import Foundation

/// Errors that can occur during plugin operations.
enum PluginError: LocalizedError {
    case loadFailed(path: String, reason: String)
    case activationFailed(identifier: String, reason: String)
    case deactivationFailed(identifier: String, reason: String)
    case incompatibleVersion(identifier: String, required: String, found: String)
    case duplicateIdentifier(String)
    case notFound(identifier: String)

    var errorDescription: String? {
        switch self {
        case .loadFailed(let path, let reason):
            "Failed to load plugin at \(path): \(reason)"
        case .activationFailed(let id, let reason):
            "Failed to activate plugin '\(id)': \(reason)"
        case .deactivationFailed(let id, let reason):
            "Failed to deactivate plugin '\(id)': \(reason)"
        case .incompatibleVersion(let id, let required, let found):
            "Plugin '\(id)' requires API version \(required), found \(found)"
        case .duplicateIdentifier(let id):
            "Plugin with identifier '\(id)' is already registered"
        case .notFound(let id):
            "Plugin '\(id)' not found"
        }
    }
}
