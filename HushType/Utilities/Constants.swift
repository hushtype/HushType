import Foundation

enum Constants {
    /// Logging
    static let logSubsystem = "com.hushtype.app"

    /// Remote model registry
    enum Registry {
        static let manifestURL = URL(string: "https://raw.githubusercontent.com/hushtype/HushType/main/registry/models.json")!
        static let refreshIntervalSeconds: TimeInterval = 24 * 60 * 60 // 24 hours
    }
}
