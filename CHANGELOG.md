# Changelog

Last Updated: 2026-02-13

All notable changes to VaulType will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!-- Release checklist:
     1. Move items from [Unreleased] into a new version section
     2. Update comparison links at the bottom of this file
     3. Set the release date in the new version heading
     4. Tag the commit: git tag -a v0.x.0 -m "Release 0.x.0"
-->

## [Unreleased]

### Added

### Changed
- Renamed project from HushType to VaulType (all source, configs, CI/CD, docs, and distribution)

### Deprecated

### Removed

### Fixed

### Security

<!-- Template for new entries — copy this block when cutting a release:

## [X.Y.Z] — YYYY-MM-DD

### Added
- New features

### Changed
- Changes in existing functionality

### Deprecated
- Soon-to-be removed features

### Removed
- Removed features

### Fixed
- Bug fixes

### Security
- Vulnerability fixes
-->

## [0.1.0-alpha] — 2026-02-13

Initial alpha release of VaulType — a privacy-first, macOS-native speech-to-text
application. All transcription runs locally on-device; no audio data ever leaves
the machine.

### Added

#### Menu Bar Application
- macOS menu bar application shell with native SwiftUI interface
- Lightweight, always-accessible menu bar icon with status indicators
- SwiftUI settings window for configuring all application preferences
- Launch at login support via the Login Items framework

#### Hotkey & Activation
- Global hotkey system for hands-free transcription control
- Push-to-talk mode: hold the hotkey to record, release to transcribe
- Toggle mode: press once to start recording, press again to stop and transcribe
- Hotkey registration works system-wide, including over fullscreen applications

#### Audio Capture
- Audio capture pipeline built on AVAudioEngine
- Configurable audio input device selection from system audio sources
- Real-time audio level monitoring during recording

#### Transcription Engine
- Local speech-to-text powered by whisper.cpp with Metal GPU acceleration
- Support for multiple Whisper model sizes:
  - `tiny` and `tiny.en` — fastest, lowest resource usage
  - `base` and `base.en` — balanced speed and accuracy
  - `small` and `small.en` — improved accuracy
  - `medium` and `medium.en` — high accuracy
  - `large-v3` — highest accuracy, largest model
- Built-in model downloader with progress tracking
- Automatic model file management in the application support directory

#### Text Output
- CGEvent-based text injection engine for typing transcribed text into any app
- Clipboard-paste fallback for applications that block synthetic keyboard events
- Clipboard preservation: original clipboard contents are saved and restored
  after paste-based insertion

---

*This is a pre-release version. APIs, configuration formats, and behaviors may
change between alpha releases without notice.*

## Links

[Unreleased]: https://github.com/anthropics/vaultype/compare/v0.1.0-alpha...HEAD
[0.1.0-alpha]: https://github.com/anthropics/vaultype/releases/tag/v0.1.0-alpha

<!-- When cutting a new release, add a comparison link:
[X.Y.Z]: https://github.com/anthropics/vaultype/compare/vPREVIOUS...vX.Y.Z
-->
