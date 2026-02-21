import Foundation
import SwiftData
import os

// MARK: - HistoryCleanupService

/// Manages history retention cleanup for DictationEntry records.
///
/// Extracted from `DictationController.enforceHistoryLimits()` with bug fixes:
/// - Count-based cleanup now respects the `isFavorite` flag (favorites are never auto-deleted).
/// - Age-based cleanup now respects the `isFavorite` flag (favorites are never auto-expired).
///
/// Usage:
/// ```swift
/// let cleanup = HistoryCleanupService()
/// cleanup.modelContainer = sharedContainer
/// await cleanup.runCleanup()
/// ```
@MainActor
@Observable
final class HistoryCleanupService {
    // MARK: - Dependencies

    /// The SwiftData model container. Must be set before calling any cleanup methods.
    var modelContainer: ModelContainer?

    // MARK: - Initialization

    init(modelContainer: ModelContainer? = nil) {
        self.modelContainer = modelContainer
        Logger.general.info("HistoryCleanupService initialized")
    }

    // MARK: - Public API

    /// Enforces history count and age limits while preserving favorited entries.
    ///
    /// - Count-based: keeps the `maxHistoryEntries` most-recent non-favorite entries;
    ///   entries beyond that limit are deleted only if `isFavorite == false`.
    /// - Age-based: deletes entries whose `timestamp` is older than `historyRetentionDays`
    ///   only if `isFavorite == false`.
    ///
    /// Settings are read from the `UserSettings` singleton. If no settings record exists,
    /// defaults (5000 entries / 90 days) are used.
    func runCleanup() {
        guard let container = modelContainer else {
            Logger.general.warning("HistoryCleanupService.runCleanup: no ModelContainer — skipping")
            return
        }

        let context = ModelContext(container)

        let settings = try? UserSettings.shared(in: context)
        let maxEntries = settings?.maxHistoryEntries ?? 5000
        let retentionDays = settings?.historyRetentionDays ?? 90

        Logger.general.info(
            "HistoryCleanupService: running cleanup (maxEntries=\(maxEntries), retentionDays=\(retentionDays))"
        )

        do {
            var totalDeleted = 0

            // -- Count-based cleanup --
            // Only enforce when a positive limit is configured.
            if maxEntries > 0 {
                totalDeleted += try enforceCountLimit(maxEntries: maxEntries, in: context)
            }

            // -- Age-based cleanup --
            // Only enforce when a positive retention window is configured.
            if retentionDays > 0 {
                totalDeleted += try enforceAgeLimit(retentionDays: retentionDays, in: context)
            }

            if totalDeleted > 0 {
                try context.save()
                Logger.general.info("HistoryCleanupService: cleanup complete, \(totalDeleted) entries deleted")
            } else {
                Logger.general.info("HistoryCleanupService: cleanup complete, no entries deleted")
            }
        } catch {
            Logger.general.error("HistoryCleanupService.runCleanup failed: \(error.localizedDescription)")
        }
    }

    /// Deletes ALL DictationEntry records unconditionally, including favorites.
    ///
    /// This is a destructive, irreversible operation. Callers should present a
    /// confirmation dialog before invoking this method.
    func clearAllHistory() {
        guard let container = modelContainer else {
            Logger.general.warning("HistoryCleanupService.clearAllHistory: no ModelContainer — skipping")
            return
        }

        let context = ModelContext(container)

        do {
            let allDescriptor = FetchDescriptor<DictationEntry>()
            let all = try context.fetch(allDescriptor)

            for entry in all {
                context.delete(entry)
            }

            try context.save()
            Logger.general.info("HistoryCleanupService.clearAllHistory: deleted \(all.count) entries")
        } catch {
            Logger.general.error("HistoryCleanupService.clearAllHistory failed: \(error.localizedDescription)")
        }
    }

    /// Performs a full factory reset of persistent user data:
    /// 1. Deletes all `DictationEntry` records (including favorites).
    /// 2. Deletes all `AppProfile` records.
    /// 3. Deletes all `VocabularyEntry` records.
    /// 4. Resets `UserSettings` to default values.
    ///
    /// This operation is irreversible. Callers should present a strong confirmation
    /// dialog before invoking this method.
    func factoryReset() {
        guard let container = modelContainer else {
            Logger.general.warning("HistoryCleanupService.factoryReset: no ModelContainer — skipping")
            return
        }

        let context = ModelContext(container)

        do {
            // 1. Delete all DictationEntry records.
            let allEntries = try context.fetch(FetchDescriptor<DictationEntry>())
            for entry in allEntries {
                context.delete(entry)
            }
            Logger.general.info("HistoryCleanupService.factoryReset: deleted \(allEntries.count) DictationEntry records")

            // 2. Delete all AppProfile records.
            // VocabularyEntry records with a cascade delete rule on AppProfile
            // are automatically removed along with their parent profiles.
            let allProfiles = try context.fetch(FetchDescriptor<AppProfile>())
            for profile in allProfiles {
                context.delete(profile)
            }
            Logger.general.info("HistoryCleanupService.factoryReset: deleted \(allProfiles.count) AppProfile records")

            // 3. Delete orphaned VocabularyEntry records (global entries not linked to an AppProfile).
            let orphanDescriptor = FetchDescriptor<VocabularyEntry>(
                predicate: #Predicate { $0.appProfile == nil }
            )
            let orphanedVocab = try context.fetch(orphanDescriptor)
            for entry in orphanedVocab {
                context.delete(entry)
            }
            if !orphanedVocab.isEmpty {
                Logger.general.info(
                    "HistoryCleanupService.factoryReset: deleted \(orphanedVocab.count) orphaned VocabularyEntry records"
                )
            }

            // 4. Reset UserSettings to defaults by replacing the singleton.
            let settingsDescriptor = FetchDescriptor<UserSettings>(
                predicate: #Predicate { $0.id == "default" }
            )
            if let existingSettings = try context.fetch(settingsDescriptor).first {
                context.delete(existingSettings)
            }
            let freshSettings = UserSettings()
            context.insert(freshSettings)
            Logger.general.info("HistoryCleanupService.factoryReset: UserSettings reset to defaults")

            try context.save()
            Logger.general.info("HistoryCleanupService.factoryReset: complete")
        } catch {
            Logger.general.error("HistoryCleanupService.factoryReset failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    /// Deletes non-favorite entries that exceed `maxEntries` when sorted newest-first.
    ///
    /// - Returns: The number of entries deleted.
    private func enforceCountLimit(maxEntries: Int, in context: ModelContext) throws -> Int {
        // Fetch all entries sorted newest → oldest.
        let allDescriptor = FetchDescriptor<DictationEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let all = try context.fetch(allDescriptor)

        guard all.count > maxEntries else {
            return 0
        }

        // Candidates are every entry beyond the `maxEntries` head.
        // Only delete those that are NOT favorited.
        let candidates = all.dropFirst(maxEntries)
        let toDelete = candidates.filter { !$0.isFavorite }

        for entry in toDelete {
            context.delete(entry)
        }

        let skipped = candidates.count - toDelete.count
        if !toDelete.isEmpty {
            Logger.general.info(
                "HistoryCleanupService: count-limit purge — deleted \(toDelete.count) entries (skipped \(skipped) favorites, limit=\(maxEntries))"
            )
        }

        return toDelete.count
    }

    /// Deletes non-favorite entries whose timestamp is older than `retentionDays` days ago.
    ///
    /// - Returns: The number of entries deleted.
    private func enforceAgeLimit(retentionDays: Int, in context: ModelContext) throws -> Int {
        guard let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -retentionDays,
            to: Date()
        ) else {
            Logger.general.error("HistoryCleanupService: could not compute age cutoff date")
            return 0
        }

        // The predicate excludes favorites — they are exempt from age-based expiry.
        let expiredDescriptor = FetchDescriptor<DictationEntry>(
            predicate: #Predicate { $0.timestamp < cutoff && !$0.isFavorite }
        )
        let expired = try context.fetch(expiredDescriptor)

        for entry in expired {
            context.delete(entry)
        }

        if !expired.isEmpty {
            Logger.general.info(
                "HistoryCleanupService: age-limit purge — deleted \(expired.count) entries (retention=\(retentionDays) days, cutoff=\(cutoff))"
            )
        }

        return expired.count
    }
}
