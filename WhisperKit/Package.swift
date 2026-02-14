// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WhisperKit", targets: ["WhisperKit"]),
    ],
    targets: [
        // C target wrapping the whisper.cpp static library.
        // Requires: run `scripts/setup-whisper.sh` first to build libwhisper.a
        // and copy headers into WhisperKit/Sources/CWhisper/.
        .systemLibrary(
            name: "CWhisper",
            path: "Sources/CWhisper",
            pkgConfig: nil,
            providers: []
        ),
        // Swift wrapper providing a safe, async-friendly API.
        .target(
            name: "WhisperKit",
            dependencies: ["CWhisper"],
            path: "Sources/WhisperKit"
        ),
    ]
)
