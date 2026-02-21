import Foundation

/// Remote model registry manifest, fetched from GitHub.
struct ModelManifest: Codable {
    let version: Int
    let updatedAt: String
    let models: [ModelManifestEntry]
}

/// A single model entry in the remote manifest.
struct ModelManifestEntry: Codable {
    let fileName: String
    let name: String
    let type: String
    let fileSize: Int64
    let isDefault: Bool
    let sha256: String?
    let downloadURLs: [String]
    let deprecated: Bool
    let notes: String?
}
