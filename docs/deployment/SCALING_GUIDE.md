# Scaling Guide

> **Last Updated: 2026-02-20**

> **HushType** — Privacy-first, macOS-native speech-to-text application

---

## Not Applicable

HushType is a **single-user desktop application**. It runs entirely on the user's Mac with no server-side components. Concepts like horizontal scaling, load balancing, database replication, or infrastructure scaling do not apply.

## Single-User Desktop Architecture

All processing runs locally on the user's machine:

- **whisper.cpp** — on-device speech-to-text, accelerated by Apple Metal GPU
- **llama.cpp** — on-device LLM post-processing, accelerated by Apple Metal GPU
- **SwiftData** — local on-device database for history, profiles, and vocabulary
- **No network** — zero outbound connections for core functionality

The only "scaling" concerns for HushType are hardware-specific performance tuning for a single user:

- **Model selection** — choose whisper/LLM model size appropriate for the Mac's RAM and chip
- **Memory management** — concurrent vs. sequential model loading based on available unified memory
- **Battery awareness** — `PowerManagementService` reduces thread count and model tier on battery power
- **Thermal management** — throttle inference when `ProcessInfo.thermalState` is critical

These are documented in [PERFORMANCE_OPTIMIZATION.md](../reference/PERFORMANCE_OPTIMIZATION.md).

## Distribution

HushType is distributed as a signed, notarized DMG. There is no server to deploy. See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for the release process.

## Related Documentation

- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) — DMG packaging, notarization, Sparkle auto-updates
- [CI_CD.md](CI_CD.md) — GitHub Actions pipeline
- [../reference/PERFORMANCE_OPTIMIZATION.md](../reference/PERFORMANCE_OPTIMIZATION.md) — hardware tuning, model selection, memory budgets
