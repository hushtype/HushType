# Cost Estimation

> **Last Updated: 2026-02-20**

> **VaulType** — Privacy-first, macOS-native speech-to-text application

---

## Zero Operational Cost

VaulType's **local-only architecture** means there are no ongoing server costs, no API usage fees, and no cloud compute expenses. All inference runs on the user's Mac hardware.

## For Users

VaulType is **free to use** with zero runtime costs:

- No subscription fees
- No API usage charges (whisper.cpp and llama.cpp run locally)
- No cloud storage costs (all data stays on the user's device)
- No telemetry or data collection

The only user cost is downloading model files (75 MB to 3.1 GB depending on the chosen whisper model, plus optional LLM models). These are one-time downloads stored in `~/Library/Application Support/VaulType/Models/`.

## For Developers / Maintainers

Minimal ongoing costs for project maintenance:

| Cost | Amount | Notes |
|------|--------|-------|
| Apple Developer Program | $99/year | Required for code signing and notarization |
| GitHub Actions CI | ~Free | Public repo uses GitHub's free tier for macOS runners |
| Domain / hosting | ~$20/year | Project website and Sparkle appcast hosting |
| **Total recurring** | **~$120/year** | No server costs, no API costs |

## Comparison with Cloud-Based Alternatives

| Approach | Monthly Cost (typical) | Privacy |
|----------|----------------------|---------|
| VaulType (local) | $0 | 100% local, no data leaves device |
| OpenAI Whisper API | $6-60+ depending on usage | Audio sent to OpenAI servers |
| Google Speech-to-Text | $0-300+ depending on usage | Audio sent to Google servers |
| AWS Transcribe | $1-100+ depending on usage | Audio sent to AWS servers |

## Related Documentation

- [DEPLOYMENT_GUIDE.md](../deployment/DEPLOYMENT_GUIDE.md) — distribution and release process
- [../security/SECURITY.md](../security/SECURITY.md) — privacy guarantees and zero-network architecture
