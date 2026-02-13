Last Updated: 2026-02-13

# Cost Estimation

> Development, infrastructure, and operational costs for building and maintaining HushType.

## Table of Contents

- [Overview](#overview)
- [Development Time Estimates](#development-time-estimates)
- [Infrastructure Costs](#infrastructure-costs)
- [Recurring Costs](#recurring-costs)
- [One-Time Costs](#one-time-costs)
- [Total Cost Summary](#total-cost-summary)
- [Cost Comparison with Alternatives](#cost-comparison-with-alternatives)
- [Next Steps](#next-steps)

---

## Overview

HushType's **local-only architecture** dramatically reduces operational costs compared to cloud-based alternatives. There are no server costs, no API usage fees, and no scaling concerns. The primary costs are development time, Apple Developer Program fees, and CI/CD infrastructure.

```
┌────────────────────────────────────────────────────────────┐
│                   Cost Structure                            │
├────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────┐    ┌───────────────────────────┐     │
│  │  Development      │    │  Infrastructure            │     │
│  │  (Primary cost)   │    │  (Minimal)                 │     │
│  │                   │    │                             │     │
│  │  Developer time   │    │  Apple Dev Program  $99/yr │     │
│  │  per phase        │    │  GitHub Actions     ~Free  │     │
│  │                   │    │  Domain/hosting     ~$20/yr│     │
│  └──────────────────┘    └───────────────────────────┘     │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  NO ongoing server costs (zero-network architecture)  │  │
│  │  NO API fees, NO cloud compute, NO storage costs      │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
└────────────────────────────────────────────────────────────┘
```

---

## Development Time Estimates

### Phase 1 — MVP (v0.1.0)

| Component | Estimated Effort | Notes |
|-----------|-----------------|-------|
| Menu bar app shell | 1-2 weeks | SwiftUI + AppKit, status icons, dropdown |
| Global hotkey system | 1 week | CGEvent tap, push-to-talk, toggle mode |
| Audio capture pipeline | 1-2 weeks | AVAudioEngine, VAD, device selection |
| whisper.cpp integration | 2-3 weeks | C bridging, Metal, model loading |
| Text injection engine | 1-2 weeks | CGEvent, clipboard fallback, preservation |
| Settings UI | 1-2 weeks | SwiftUI tabs, model management |
| Model downloader | 1 week | Hugging Face download, progress UI |
| Testing & polish | 1-2 weeks | Unit tests, bug fixes, edge cases |
| **Phase 1 Total** | **8-14 weeks** | **Solo developer estimate** |

### Phase 2 — LLM Post-Processing (v0.2.0)

| Component | Estimated Effort | Notes |
|-----------|-----------------|-------|
| llama.cpp integration | 2-3 weeks | C bridging, Metal, context management |
| Ollama integration | 1 week | REST API client, model selection |
| Processing modes (6) | 2-3 weeks | Prompt templates, mode switching |
| Prompt template system | 1-2 weeks | Template engine, user editing, import/export |
| Mode selection UI | 1 week | Quick switcher, per-hotkey assignment |
| Testing & polish | 1-2 weeks | Integration tests, performance tuning |
| **Phase 2 Total** | **8-12 weeks** | |

### Phase 3 — Smart Features (v0.3.0)

| Component | Estimated Effort | Notes |
|-----------|-----------------|-------|
| App-aware context | 1-2 weeks | NSWorkspace, per-app profiles |
| Dictation history | 2-3 weeks | SwiftData, search, export |
| Floating overlay | 2-3 weeks | NSPanel, editable text, positioning |
| Custom vocabulary | 1-2 weeks | Dictionary, auto-correction, per-project |
| Multi-language switching | 1 week | Language detection, quick switch |
| Testing & polish | 1-2 weeks | |
| **Phase 3 Total** | **8-13 weeks** | |

### Phase 4 — Voice Commands (v0.4.0)

| Component | Estimated Effort | Notes |
|-----------|-----------------|-------|
| Command engine | 2-3 weeks | Parser, registry, executor |
| App management commands | 1-2 weeks | Open, switch, close, quit |
| Window management | 1-2 weeks | Snap, tile, move between spaces |
| System controls | 1 week | Volume, brightness, DnD |
| Workflow automation | 2-3 weeks | Command chaining, Shortcuts, AppleScript |
| Testing & polish | 1-2 weeks | |
| **Phase 4 Total** | **8-13 weeks** | |

### Phase 5 — Power User & Polish (v0.5.0)

| Component | Estimated Effort | Notes |
|-----------|-----------------|-------|
| Keyboard shortcut chaining | 1-2 weeks | Voice-triggered shortcuts |
| Audio feedback | 1 week | Sound effects, optional TTS |
| Accessibility polish | 1-2 weeks | VoiceOver, high contrast, keyboard nav |
| Performance optimization | 2-3 weeks | Preloading, memory mgmt, battery-aware |
| Plugin system | 3-4 weeks | API design, extension loading |
| Testing & final polish | 2-3 weeks | |
| **Phase 5 Total** | **10-15 weeks** | |

### Total Development Estimate

| Milestone | Weeks (Solo) | Weeks (2 devs) |
|-----------|-------------|-----------------|
| Phase 1 (MVP) | 8-14 | 5-8 |
| Phase 2 (LLM) | 8-12 | 5-7 |
| Phase 3 (Smart) | 8-13 | 5-7 |
| Phase 4 (Voice) | 8-13 | 5-7 |
| Phase 5 (Polish) | 10-15 | 6-9 |
| **Total** | **42-67 weeks** | **26-38 weeks** |

> ⚠️ These are rough estimates for a skilled macOS/Swift developer familiar with the technologies. Actual time may vary based on experience with whisper.cpp, llama.cpp, and low-level macOS APIs.

---

## Infrastructure Costs

### Apple Developer Program

| Item | Cost | Frequency | Required |
|------|------|-----------|----------|
| Apple Developer Program | $99 | Annual | Yes (for code signing & notarization) |

Without this, you cannot:
- Code sign with Developer ID
- Notarize the app (Gatekeeper will block it)
- Distribute outside the App Store

### CI/CD — GitHub Actions

GitHub Actions provides free minutes for public repositories:

| Plan | Minutes/Month | Cost |
|------|--------------|------|
| Free (public repo) | 2,000 | $0 |
| Free (private repo) | 2,000 | $0 |
| Team | 3,000 | $4/user/month |

**Estimated usage per month:**

| Workflow | Runs/Month | Minutes/Run | Total Minutes |
|----------|-----------|-------------|---------------|
| Build (push/PR) | 60 | 5 | 300 |
| Test (push/PR) | 60 | 10 | 600 |
| Release | 2 | 20 | 40 |
| Nightly | 30 | 15 | 450 |
| **Total** | | | **~1,390** |

> 💡 For a public repo, this fits within the free tier. macOS runners consume minutes at a 10x rate on the free plan, so actual billed minutes = ~139 standard minutes.

**If exceeding free tier:**

| Overage | Rate |
|---------|------|
| macOS minutes | $0.08/minute |
| Estimated monthly overage | $0-30 |

### Domain & Hosting

| Item | Cost | Frequency |
|------|------|-----------|
| Domain (hushtype.app) | $14-20 | Annual |
| GitHub Pages (website + appcast) | $0 | Free |
| Alternative: Netlify/Vercel | $0 | Free tier |

### Model Hosting

Models are hosted on Hugging Face (free) and downloaded by users directly. No bandwidth costs for us.

| Item | Cost |
|------|------|
| Hugging Face model hosting | $0 (public models) |
| GitHub Releases (DMG hosting) | $0 (within repo limits) |

---

## Recurring Costs

### Monthly

| Item | Low | High | Notes |
|------|-----|------|-------|
| GitHub Actions (if private repo) | $0 | $30 | Free for public repos |
| **Monthly Total** | **$0** | **$30** | |

### Annual

| Item | Cost |
|------|------|
| Apple Developer Program | $99 |
| Domain name | $14-20 |
| GitHub (if private/Team) | $0-$48 |
| **Annual Total** | **$113-$167** |

---

## One-Time Costs

| Item | Cost | Notes |
|------|------|-------|
| Development hardware (Mac) | $0-$3,000 | Assuming dev already has one |
| External microphone for testing | $50-200 | Optional but recommended |
| Apple Developer enrollment | $99 | First year |
| create-dmg (Homebrew) | $0 | Open source |
| SwiftLint (Homebrew) | $0 | Open source |
| **One-Time Total** | **$99-$3,299** | |

---

## Total Cost Summary

### Year 1 (Development + Launch)

| Category | Low Estimate | High Estimate |
|----------|-------------|---------------|
| Apple Developer Program | $99 | $99 |
| Domain | $14 | $20 |
| CI/CD | $0 | $360 |
| Hardware | $0 | $3,000 |
| External services | $0 | $0 |
| Cloud/server costs | **$0** | **$0** |
| **Year 1 Total** | **$113** | **$3,479** |

### Ongoing Annual (Year 2+)

| Category | Cost |
|----------|------|
| Apple Developer Program | $99 |
| Domain | $14-20 |
| CI/CD | $0-360 |
| Cloud/server costs | **$0** |
| **Annual Total** | **$113-$479** |

### Cost per User

Since HushType has no server costs, the cost per user is effectively **$0** at any scale. Whether 10 users or 100,000 users, the infrastructure cost remains the same.

---

## Cost Comparison with Alternatives

### Building a Cloud-Based Alternative

If HushType used cloud speech recognition and LLM APIs instead:

| Service | Cost | Volume |
|---------|------|--------|
| OpenAI Whisper API | $0.006/min | Per audio minute |
| OpenAI GPT-4o-mini | $0.15/1M tokens | Per processed text |
| Server hosting (AWS) | $50-500/month | Depending on scale |
| **Monthly (1,000 active users)** | **$200-2,000** | |

**HushType's local approach eliminates all of these costs.**

### User Cost Comparison

| Product | User Cost | Model |
|---------|-----------|-------|
| HushType | **Free** | Open source, local AI |
| Superwhisper | $10/month ($120/yr) | Subscription |
| VoiceInk | $30 one-time | Proprietary |
| MacWhisper Pro | $30 one-time | Proprietary |
| Apple Dictation | Free (with macOS) | Cloud-dependent |

### Developer Program ROI

At $99/year for the Apple Developer Program, the break-even vs. alternatives:

| Alternative | Annual Cost (User) | Users Needed to Match $99 |
|------------|-------------------|---------------------------|
| Superwhisper | $120/user/yr | < 1 user |
| Cloud Whisper API | ~$7/user/yr | ~14 users |

Even one person using HushType instead of a paid alternative saves more than the Developer Program fee.

---

## Optional Costs

These are not required but may improve the project:

| Item | Cost | Benefit |
|------|------|---------|
| Sentry crash reporting | $0-26/month | Opt-in crash reports from users |
| Figma (design) | $0-15/month | UI/UX design tool |
| TestFlight (beta testing) | $0 | Included with Apple Developer |
| Localization service | $0.05-0.10/word | Professional translation |
| Security audit | $5,000-20,000 | Third-party code audit |
| Legal review | $500-2,000 | License and privacy policy review |

---

## Next Steps

- [Roadmap](ROADMAP.md) — Development phases and timeline
- [Architecture](../architecture/ARCHITECTURE.md) — Technical foundation
- [Deployment Guide](../deployment/DEPLOYMENT_GUIDE.md) — Build and distribution pipeline
- [Contributing](../contributing/CONTRIBUTING.md) — How to contribute and reduce development time
