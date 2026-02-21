import Foundation

enum Constants {
    /// Logging
    static let logSubsystem = "com.vaultype.app"

    /// Remote model registry
    enum Registry {
        static let manifestURL = URL(string: "https://raw.githubusercontent.com/vaultype/VaulType/main/registry/models.json")!
        static let refreshIntervalSeconds: TimeInterval = 24 * 60 * 60 // 24 hours
    }
}
