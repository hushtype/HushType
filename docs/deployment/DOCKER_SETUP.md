# Docker Setup

> **Last Updated: 2026-02-20**

> **HushType** — Privacy-first, macOS-native speech-to-text application

---

## Not Applicable

HushType is a **native macOS application**. Docker is not used and does not apply to this project.

HushType requires macOS-specific system APIs that cannot run in any container environment:

- **Metal GPU** — whisper.cpp and llama.cpp use Apple Metal for hardware-accelerated inference
- **AVFoundation / Core Audio** — microphone capture requires macOS audio hardware
- **Accessibility API** — text injection via `AXUIElement` and `CGEvent` requires the macOS window server
- **SwiftUI / AppKit** — the UI requires the macOS display server

All builds, tests, and releases run on macOS runners (GitHub Actions `macos-15`). There are no Linux containers, no Docker images, and no containerized CI tasks in this project.

## CI/CD

See [CI_CD.md](CI_CD.md) for the actual GitHub Actions workflows:

- `build.yml` — builds Debug and Release on `macos-15`
- `test.yml` — runs unit tests on `macos-15`
- `lint.yml` — runs SwiftLint and SwiftFormat on `macos-14`

## Related Documentation

- [CI_CD.md](CI_CD.md) — GitHub Actions pipeline
- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) — DMG packaging, notarization, distribution
