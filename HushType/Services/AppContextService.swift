import AppKit
import Foundation
import SwiftData
import os

// MARK: - AppContextService

/// Monitors the frontmost macOS application and resolves per-app profiles from SwiftData.
///
/// Observes `NSWorkspace.didActivateApplicationNotification` for app-switch events and
/// keeps `currentBundleIdentifier`, `currentAppName`, and `currentProfile` up to date.
/// Call `resolveProfile(in:)` after an app switch to hydrate `currentProfile` from the
/// persistent store, auto-creating a new ``AppProfile`` with smart defaults when none exists.
@Observable
@MainActor
final class AppContextService {
    // MARK: - Public State

    /// Bundle identifier of the currently frontmost application (e.g. `"com.apple.dt.Xcode"`).
    private(set) var currentBundleIdentifier: String?

    /// Localized display name of the currently frontmost application (e.g. `"Xcode"`).
    private(set) var currentAppName: String?

    /// The resolved SwiftData profile for the frontmost application.
    /// `nil` until `resolveProfile(in:)` is called or the profile cannot be determined.
    private(set) var currentProfile: AppProfile?

    // MARK: - Private

    /// Token returned by `NotificationCenter.addObserver` — retained to remove later.
    /// `nonisolated(unsafe)` so `deinit` (which is nonisolated) can access it.
    nonisolated(unsafe) private var observer: (any NSObjectProtocol)?

    // MARK: - Smart Default Mappings

    /// Static mapping from well-known bundle identifiers to a `(mode, language)` tuple.
    /// `language` follows BCP-47 conventions and is `nil` when the global default should apply.
    private static let defaultModes: [String: (mode: ProcessingMode, language: String?)] = [
        "com.apple.dt.Xcode":        (.code,      nil),
        "com.apple.mail":            (.clean,     nil),
        "com.apple.Terminal":        (.raw,       nil),
        "com.microsoft.VSCode":      (.code,      nil),
        "com.apple.Notes":           (.structure, nil),
        "com.apple.Safari":          (.clean,     nil),
        "com.google.Chrome":         (.clean,     nil),
        "com.apple.TextEdit":        (.clean,     nil),
        "com.tinyspeck.slackmacgap": (.clean,     nil),
        "com.apple.iWork.Pages":     (.structure, nil),
        "com.microsoft.Word":        (.structure, nil),
        "com.apple.MobileSMS":       (.clean,     nil),
    ]

    // MARK: - Initialization

    init() {
        startObserving()

        // Seed the current frontmost app without waiting for a notification.
        if let app = NSWorkspace.shared.frontmostApplication {
            updateCurrentApp(app)
        }

        Logger.general.info("AppContextService initialized")
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Notification Observation

    private func startObserving() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }

            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication

            Task { @MainActor [weak self] in
                guard let self else { return }
                if let app {
                    self.updateCurrentApp(app)
                } else {
                    self.clearCurrentApp()
                }
            }
        }
    }

    // MARK: - App State Updates

    private func updateCurrentApp(_ app: NSRunningApplication) {
        let bundleID = app.bundleIdentifier
        let appName  = app.localizedName

        currentBundleIdentifier = bundleID
        currentAppName          = appName
        // Profile is cleared until `resolveProfile(in:)` is called by the caller.
        currentProfile = nil

        Logger.general.info(
            "App switched — bundle: \(bundleID ?? "nil"), name: \(appName ?? "nil")"
        )
    }

    private func clearCurrentApp() {
        currentBundleIdentifier = nil
        currentAppName          = nil
        currentProfile          = nil
        Logger.general.debug("No frontmost application")
    }

    // MARK: - Profile Resolution

    /// Fetches or auto-creates the ``AppProfile`` for the currently active application.
    ///
    /// - Parameter context: The `ModelContext` used for persistence operations.
    ///
    /// The method:
    /// 1. Looks up an existing `AppProfile` by `bundleIdentifier`.
    /// 2. If none exists, creates one using smart defaults (``defaultModes``) and inserts it.
    /// 3. Saves the context after creation.
    /// 4. Updates `currentProfile` with the result.
    ///
    /// Does nothing when `currentBundleIdentifier` is `nil`.
    func resolveProfile(in context: ModelContext) {
        guard let bundleID = currentBundleIdentifier else {
            Logger.general.debug("resolveProfile called with no currentBundleIdentifier — skipping")
            return
        }

        do {
            let profile = try fetchOrCreateProfile(
                bundleID: bundleID,
                appName: currentAppName ?? bundleID,
                in: context
            )
            currentProfile = profile
            Logger.general.info(
                "Profile resolved for \(bundleID) — mode: \(profile.defaultMode?.rawValue ?? "global default")"
            )
        } catch {
            Logger.general.error(
                "Failed to resolve profile for \(bundleID): \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Private Helpers

    /// Fetches an existing `AppProfile` or creates one with smart defaults.
    private func fetchOrCreateProfile(
        bundleID: String,
        appName: String,
        in context: ModelContext
    ) throws -> AppProfile {
        let descriptor = FetchDescriptor<AppProfile>(
            predicate: #Predicate { $0.bundleIdentifier == bundleID }
        )

        let results = try context.fetch(descriptor)

        if let existing = results.first {
            Logger.general.debug("Found existing AppProfile for \(bundleID)")
            return existing
        }

        // No existing profile — create one with smart defaults.
        let defaults = Self.defaultModes[bundleID]
        let profile = AppProfile(
            bundleIdentifier: bundleID,
            appName: appName,
            defaultMode: defaults?.mode,
            preferredLanguage: defaults?.language
        )

        context.insert(profile)

        do {
            try context.save()
            Logger.general.info(
                "Auto-created AppProfile for \(bundleID) (mode: \(defaults?.mode.rawValue ?? "nil"), language: \(defaults?.language ?? "nil"))"
            )
        } catch {
            Logger.general.error(
                "Failed to save auto-created AppProfile for \(bundleID): \(error.localizedDescription)"
            )
            // Propagate so callers can handle persistence failures appropriately.
            throw error
        }

        return profile
    }
}
