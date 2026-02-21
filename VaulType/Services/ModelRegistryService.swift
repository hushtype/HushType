import Foundation
import SwiftData
import os

/// Fetches the remote model manifest and reconciles it with local SwiftData records.
///
/// Follows the `HistoryCleanupService` pattern: `@MainActor`, `@Observable`,
/// requires `modelContainer` to be set before use.
///
/// Usage:
/// ```swift
/// let registry = ModelRegistryService(modelContainer: container)
/// await registry.refreshIfNeeded()
/// ```
@MainActor
@Observable
final class ModelRegistryService {
    // MARK: - Dependencies

    var modelContainer: ModelContainer?

    // MARK: - State

    private(set) var isRefreshing: Bool = false
    private(set) var lastRefreshError: String?
    private(set) var lastRefreshDate: Date?

    // MARK: - Initialization

    init(modelContainer: ModelContainer? = nil) {
        self.modelContainer = modelContainer
        self.lastRefreshDate = UserDefaults.standard.object(
            forKey: UserDefaultsKey.lastModelRegistryUpdate
        ) as? Date
    }

    // MARK: - Public API

    /// Refreshes the model registry if the refresh interval has elapsed.
    func refreshIfNeeded() async {
        if let lastRefresh = lastRefreshDate {
            let elapsed = Date().timeIntervalSince(lastRefresh)
            guard elapsed >= Constants.Registry.refreshIntervalSeconds else {
                Logger.models.debug("ModelRegistryService: skipping refresh (\(Int(elapsed))s since last)")
                return
            }
        }
        await refresh()
    }

    /// Force-fetches the remote manifest and reconciles with local records.
    func refresh() async {
        guard modelContainer != nil else {
            Logger.models.warning("ModelRegistryService.refresh: no ModelContainer — skipping")
            return
        }

        isRefreshing = true
        lastRefreshError = nil

        do {
            let manifest = try await fetchManifest()
            applyManifest(manifest)

            let now = Date()
            lastRefreshDate = now
            UserDefaults.standard.set(now, forKey: UserDefaultsKey.lastModelRegistryUpdate)

            Logger.models.info("ModelRegistryService: refresh complete (\(manifest.models.count) models in manifest)")
        } catch {
            lastRefreshError = error.localizedDescription
            Logger.models.warning("ModelRegistryService: refresh failed — \(error.localizedDescription)")
        }

        isRefreshing = false
    }

    /// Applies a manifest directly (for testing). In production, use `refresh()`.
    func applyManifestForTesting(_ manifest: ModelManifest) {
        applyManifest(manifest)
    }

    // MARK: - Private

    /// Fetches and decodes the remote manifest JSON.
    private func fetchManifest() async throws -> ModelManifest {
        let (data, response) = try await URLSession.shared.data(from: Constants.Registry.manifestURL)

        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                throw RegistryError.httpError(httpResponse.statusCode)
            }
        }

        let decoder = JSONDecoder()
        return try decoder.decode(ModelManifest.self, from: data)
    }

    /// Reconciles the remote manifest with local SwiftData records (merge-only).
    private func applyManifest(_ manifest: ModelManifest) {
        guard let container = modelContainer else { return }

        let context = ModelContext(container)

        let existing: [ModelInfo]
        do {
            existing = try context.fetch(FetchDescriptor<ModelInfo>())
        } catch {
            Logger.models.error("ModelRegistryService: failed to fetch local models — \(error.localizedDescription)")
            return
        }

        let existingByFileName = Dictionary(uniqueKeysWithValues: existing.map { ($0.fileName, $0) })
        var updatedCount = 0
        var insertedCount = 0

        for entry in manifest.models {
            if let local = existingByFileName[entry.fileName] {
                // Update mutable fields, preserve local state
                if let urlString = entry.downloadURLs.first, let url = URL(string: urlString) {
                    local.downloadURL = url
                }
                local.mirrorURLs = Array(entry.downloadURLs.dropFirst())
                local.sha256 = entry.sha256
                local.name = entry.name
                local.fileSize = entry.fileSize
                local.isDefault = entry.isDefault
                local.isDeprecated = entry.deprecated
                local.registryNotes = entry.notes
                updatedCount += 1
            } else {
                // Insert new model from manifest
                guard let modelType = ModelType(rawValue: entry.type) else {
                    Logger.models.warning("ModelRegistryService: unknown model type '\(entry.type)' for \(entry.fileName) — skipping")
                    continue
                }

                let primaryURL = entry.downloadURLs.first.flatMap { URL(string: $0) }
                let model = ModelInfo(
                    name: entry.name,
                    type: modelType,
                    fileName: entry.fileName,
                    fileSize: entry.fileSize,
                    downloadURL: primaryURL,
                    isDefault: entry.isDefault,
                    sha256: entry.sha256,
                    mirrorURLs: Array(entry.downloadURLs.dropFirst()),
                    isDeprecated: entry.deprecated,
                    registryNotes: entry.notes
                )
                context.insert(model)
                insertedCount += 1
            }
        }

        do {
            try context.save()
            Logger.models.info("ModelRegistryService: applied manifest — \(updatedCount) updated, \(insertedCount) inserted")
        } catch {
            Logger.models.error("ModelRegistryService: failed to save — \(error.localizedDescription)")
        }
    }
}

// MARK: - Errors

enum RegistryError: LocalizedError {
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .httpError(let code):
            "Registry fetch failed (HTTP \(code))"
        }
    }
}
