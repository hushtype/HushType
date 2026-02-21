Last Updated: 2026-02-13

# Legal Compliance — VaulType

> **VaulType** — Privacy-first, macOS-native speech-to-text. "Hush" (voice stays private) + "Type" (text appears at cursor). 100% local processing, zero network, no telemetry.

---

## Table of Contents

- [1. Project License: GPL-3.0](#1-project-license-gpl-30)
  - [1.1 What GPL-3.0 Means](#11-what-gpl-30-means)
  - [1.2 Why GPL-3.0 Was Chosen](#12-why-gpl-30-was-chosen)
  - [1.3 Implications for Users](#13-implications-for-users)
  - [1.4 Implications for Contributors](#14-implications-for-contributors)
  - [1.5 Copyleft Obligations](#15-copyleft-obligations)
- [2. Third-Party Licenses](#2-third-party-licenses)
  - [2.1 Dependency License Summary](#21-dependency-license-summary)
  - [2.2 License Compatibility Analysis](#22-license-compatibility-analysis)
  - [2.3 Transitive Dependencies](#23-transitive-dependencies)
- [3. AI Model Licensing](#3-ai-model-licensing)
  - [3.1 Supported Models and Their Licenses](#31-supported-models-and-their-licenses)
  - [3.2 Whisper Models (OpenAI)](#32-whisper-models-openai)
  - [3.3 Llama Models (Meta)](#33-llama-models-meta)
  - [3.4 Qwen Models (Alibaba)](#34-qwen-models-alibaba)
  - [3.5 Phi Models (Microsoft)](#35-phi-models-microsoft)
  - [3.6 User Responsibility](#36-user-responsibility)
- [4. Privacy Policy](#4-privacy-policy)
  - [4.1 Data Collection Statement](#41-data-collection-statement)
  - [4.2 Audio Data Handling](#42-audio-data-handling)
  - [4.3 Crash Reporting (Optional)](#43-crash-reporting-optional)
  - [4.4 Network Activity](#44-network-activity)
  - [4.5 User Accounts and Authentication](#45-user-accounts-and-authentication)
- [5. App Store Review Guidelines](#5-app-store-review-guidelines)
  - [5.1 Sandboxing Requirements](#51-sandboxing-requirements)
  - [5.2 Payment and Monetization](#52-payment-and-monetization)
  - [5.3 Content and Functionality](#53-content-and-functionality)
  - [5.4 Accessibility Requirements](#54-accessibility-requirements)
- [6. Accessibility Compliance](#6-accessibility-compliance)
  - [6.1 WCAG 2.1 AA Compliance Goals](#61-wcag-21-aa-compliance-goals)
  - [6.2 VoiceOver Support](#62-voiceover-support)
  - [6.3 Additional Accessibility Features](#63-additional-accessibility-features)
- [7. Open Source Attribution Requirements](#7-open-source-attribution-requirements)
  - [7.1 About Window Attribution](#71-about-window-attribution)
  - [7.2 Documentation Attribution](#72-documentation-attribution)
  - [7.3 Distribution Attribution](#73-distribution-attribution)
- [8. Export Compliance](#8-export-compliance)
  - [8.1 Encryption Usage Disclosure](#81-encryption-usage-disclosure)
  - [8.2 Classification](#82-classification)
  - [8.3 App Store Export Compliance](#83-app-store-export-compliance)
- [9. Data Protection](#9-data-protection)
  - [9.1 GDPR Considerations](#91-gdpr-considerations)
  - [9.2 CCPA Considerations](#92-ccpa-considerations)
  - [9.3 Other Jurisdictions](#93-other-jurisdictions)
  - [9.4 Why Data Protection Regulations Have Minimal Impact](#94-why-data-protection-regulations-have-minimal-impact)
- [10. Trademark Considerations](#10-trademark-considerations)
  - [10.1 VaulType Name](#101-vaultype-name)
  - [10.2 Avoiding Trademark Conflicts](#102-avoiding-trademark-conflicts)
  - [10.3 Third-Party Trademark Usage](#103-third-party-trademark-usage)
- [Related Documentation](#related-documentation)

---

## 1. Project License: GPL-3.0

VaulType is released under the **GNU General Public License v3.0 (GPL-3.0)**. The full license text is available in the `LICENSE` file at the root of the repository.

### 1.1 What GPL-3.0 Means

The GPL-3.0 is a strong copyleft free software license that guarantees end users the four essential freedoms:

| Freedom | Description |
|---------|-------------|
| **Freedom 0** | The freedom to run the program as you wish, for any purpose. |
| **Freedom 1** | The freedom to study how the program works, and change it so it does your computing as you wish. Access to source code is a precondition for this. |
| **Freedom 2** | The freedom to redistribute copies so you can help others. |
| **Freedom 3** | The freedom to distribute copies of your modified versions to others. By doing this you can give the whole community a chance to benefit from your changes. Access to source code is a precondition for this. |

### 1.2 Why GPL-3.0 Was Chosen

GPL-3.0 was selected for VaulType for the following reasons:

1. **Protecting User Privacy by Design** — A privacy-focused app should have verifiable source code. GPL-3.0 ensures that any distributed version of VaulType must include source code, allowing users and security researchers to verify that privacy claims are genuine.

2. **Ensuring Derivatives Remain Open Source** — Any fork or derivative of VaulType must also be released under GPL-3.0. This prevents a third party from taking VaulType's code, adding telemetry or data collection, and distributing it as a proprietary product.

3. **Protecting User Freedoms** — Users can inspect, modify, and redistribute VaulType. This aligns with the project's philosophy that users should have complete control over their tools, especially tools that handle sensitive data like voice recordings.

4. **Patent Protection** — GPL-3.0 includes an explicit patent grant, protecting contributors and users from patent litigation related to the covered code.

5. **Anti-Tivoization** — GPL-3.0 prevents hardware restrictions that would stop users from running modified versions of the software, preserving the practical exercise of software freedom.

> ℹ️ **Info**: GPL-3.0 is not the same as AGPL-3.0. Since VaulType is a desktop application with no server component, the standard GPL-3.0 is appropriate. AGPL would be relevant only if VaulType offered network-accessible services.

### 1.3 Implications for Users

- **You may use VaulType** for any purpose, personal or commercial, without restriction.
- **You may modify VaulType** to suit your needs. The source code is freely available.
- **You may redistribute VaulType** (original or modified) as long as you also distribute it under GPL-3.0 and include the source code.
- **You are not required to share modifications** you make for personal use only. The copyleft obligation triggers upon *distribution*.

### 1.4 Implications for Contributors

- **All contributions** to VaulType are licensed under GPL-3.0.
- **Contributors retain copyright** over their individual contributions but grant a license to distribute under GPL-3.0.
- **A Contributor License Agreement (CLA)** is not currently required, but contributors should be aware that their code will be distributed under GPL-3.0.
- **Contributors should not submit** code that is incompatible with GPL-3.0 (e.g., code under proprietary licenses or GPL-incompatible open-source licenses).

### 1.5 Copyleft Obligations

When distributing VaulType (original or modified), the following obligations apply:

| Obligation | Details |
|------------|---------|
| **Source Code** | You must provide the complete corresponding source code, or a written offer to provide it. |
| **License Preservation** | The distributed work must be licensed under GPL-3.0. You may not impose additional restrictions. |
| **Notice Preservation** | You must preserve all copyright notices, license notices, and warranty disclaimers. |
| **Modification Notices** | Modified files must carry prominent notices stating that you changed the files and the date of any change. |
| **Installation Information** | For User Products, you must provide Installation Information necessary for the user to install and run modified versions. |

> ⚠️ **Warning**: Linking GPL-3.0 code with proprietary code and distributing the combined work is not permitted under GPL-3.0. All code in the distributed binary must be under GPL-3.0-compatible licenses.

---

## 2. Third-Party Licenses

### 2.1 Dependency License Summary

The following table lists all third-party dependencies used by VaulType and their respective licenses:

| Dependency | Version | License | License Type | Usage in VaulType |
|------------|---------|---------|--------------|-------------------|
| **whisper.cpp** | Latest stable | MIT | Permissive | Core speech-to-text inference engine |
| **llama.cpp** | Latest stable | MIT | Permissive | Text post-processing and formatting via local LLMs |
| **Sparkle** | 2.x | MIT | Permissive | Auto-update framework for distributing updates |
| **Swift** | 5.9+ | Apache 2.0 | Permissive | Programming language and standard library |
| **SwiftUI** | macOS 14+ | Apple EULA | Proprietary (platform) | UI framework (bundled with macOS) |
| **AppKit** | macOS 14+ | Apple EULA | Proprietary (platform) | System integration (bundled with macOS) |
| **AVFoundation** | macOS 14+ | Apple EULA | Proprietary (platform) | Audio capture (bundled with macOS) |
| **CoreML** | macOS 14+ | Apple EULA | Proprietary (platform) | ML inference acceleration (bundled with macOS) |

> ℹ️ **Info**: Apple system frameworks (SwiftUI, AppKit, AVFoundation, CoreML) are part of macOS and are not distributed with VaulType. They are accessed via system APIs and do not create licensing obligations for VaulType's source distribution.

### 2.2 License Compatibility Analysis

All third-party dependencies must be compatible with VaulType's GPL-3.0 license. The following analysis confirms compatibility:

| License | GPL-3.0 Compatible? | Rationale |
|---------|---------------------|-----------|
| **MIT** | Yes | MIT is a permissive license. MIT-licensed code can be included in GPL-3.0 projects. The combined work is distributed under GPL-3.0, and the MIT license terms (attribution) are satisfied. |
| **Apache 2.0** | Yes | Apache 2.0 is compatible with GPL-3.0 (but not GPL-2.0). The patent grant in Apache 2.0 does not conflict with GPL-3.0's patent provisions. |
| **Apple EULA** | N/A (system library) | Apple frameworks are system libraries and are excluded from GPL-3.0's copyleft requirements under the "System Library Exception" (GPL-3.0, Section 1, definition of "System Library"). |

> 🔒 **Security**: Before adding any new dependency, verify that its license is compatible with GPL-3.0. Licenses that are **not** compatible include: GPL-2.0-only (without "or later"), CDDL, EPL-1.0, and most proprietary licenses. Consult the [FSF license compatibility list](https://www.gnu.org/licenses/license-list.html) when in doubt.

### 2.3 Transitive Dependencies

Transitive dependencies (dependencies of dependencies) must also be GPL-3.0 compatible. The current dependency tree is minimal:

- **whisper.cpp** — No additional runtime dependencies beyond system libraries (Accelerate.framework, Metal.framework).
- **llama.cpp** — No additional runtime dependencies beyond system libraries (Accelerate.framework, Metal.framework).
- **Sparkle** — Depends on system frameworks only (Foundation, AppKit, Security).

> 💡 **Tip**: Run a periodic audit of all transitive dependencies when updating any third-party library. Use the project's dependency management tooling to generate a full dependency tree and verify license compliance.

---

## 3. AI Model Licensing

VaulType supports downloading and running various AI models locally. Each model family has its own license terms. VaulType does **not** bundle any models — users download them separately during setup or configuration.

### 3.1 Supported Models and Their Licenses

| Model Family | Provider | License | Commercial Use | Redistribution | Conditions |
|-------------|----------|---------|----------------|----------------|------------|
| **Whisper** | OpenAI | MIT | Yes | Yes | Attribution required |
| **Llama 3.x** | Meta | Llama 3.x Community License | Yes (with conditions) | Yes (with conditions) | Monthly active users < 700M; acceptable use policy applies |
| **Qwen 2.x** | Alibaba Cloud | Apache 2.0 | Yes | Yes | Attribution required; patent grant included |
| **Phi-3/4** | Microsoft | MIT | Yes | Yes | Attribution required |

### 3.2 Whisper Models (OpenAI)

- **License**: MIT License
- **Source**: [github.com/openai/whisper](https://github.com/openai/whisper)
- **Compatibility**: Fully compatible with GPL-3.0 and all use cases.
- **Obligations**: Include the MIT license notice and copyright when redistributing the model files.
- **VaulType Usage**: Whisper models are the primary speech-to-text engine. Users download the model in GGML format for use with whisper.cpp.

> ℹ️ **Info**: The MIT license on Whisper models is one of the most permissive available. There are no restrictions on commercial use, modification, or redistribution beyond attribution.

### 3.3 Llama Models (Meta)

- **License**: Llama 3.x Community License Agreement
- **Source**: [llama.meta.com](https://llama.meta.com/)
- **Key Terms**:
  - **Commercial use** is permitted, provided the licensee (and its affiliates) had fewer than 700 million monthly active users in the preceding calendar month.
  - **Redistribution** is permitted, but redistributors must include a copy of the license and the Acceptable Use Policy.
  - **Acceptable Use Policy** prohibits specific harmful uses (e.g., weapons development, surveillance of individuals, generating disinformation).
  - **No sublicensing** — downstream recipients receive their license directly from Meta.

> ⚠️ **Warning**: The Llama Community License is **not** an open-source license by the OSI definition. It imposes use-based restrictions that go beyond traditional open-source licenses. VaulType does not redistribute Llama models; users must agree to Meta's license terms independently when downloading models.

- **VaulType's Approach**: VaulType provides tooling to download Llama models but does not bundle or redistribute them. Users must accept Meta's license terms during the download process. VaulType's GPL-3.0 license applies only to VaulType's own source code, not to downloaded model files.

### 3.4 Qwen Models (Alibaba)

- **License**: Apache 2.0
- **Source**: [github.com/QwenLM](https://github.com/QwenLM)
- **Compatibility**: Fully compatible with GPL-3.0 and all use cases.
- **Obligations**: Include the Apache 2.0 license notice, NOTICE file (if provided), and state any changes if redistributing modified model files.
- **Patent Grant**: Apache 2.0 includes an explicit patent license, providing additional legal protection for users.

### 3.5 Phi Models (Microsoft)

- **License**: MIT License
- **Source**: [huggingface.co/microsoft](https://huggingface.co/microsoft)
- **Compatibility**: Fully compatible with GPL-3.0 and all use cases.
- **Obligations**: Include the MIT license notice and copyright when redistributing model files.

### 3.6 User Responsibility

> ⚠️ **Warning**: Users are responsible for complying with the license terms of any AI model they download and use with VaulType. VaulType is a tool that runs models locally — it does not grant any license to the models themselves.

Key responsibilities for users:

1. **Read and accept** the license terms for each model before downloading.
2. **Comply with use-based restrictions** where applicable (e.g., Llama's Acceptable Use Policy).
3. **Verify commercial use rights** if using VaulType in a commercial context with models that have commercial restrictions.
4. **Retain license files** that accompany downloaded models; do not delete them.
5. **Do not redistribute models** without verifying that you comply with the model's redistribution terms.

---

## 4. Privacy Policy

### 4.1 Data Collection Statement

**VaulType does not collect, transmit, store, or process any user data on external servers.** This is a core architectural principle, not merely a policy choice.

| Data Category | Collected? | Transmitted? | Stored Externally? |
|---------------|-----------|--------------|---------------------|
| Audio/voice recordings | No (processed in memory, never saved to disk by default) | No | No |
| Transcribed text | No (delivered to cursor position, not retained) | No | No |
| Usage analytics | No | No | No |
| User accounts / credentials | N/A (no accounts exist) | N/A | N/A |
| Device identifiers | No | No | No |
| IP addresses | No | No | No |
| Crash reports | Only if user opts in (see [4.3](#43-crash-reporting-optional)) | Only if user opts in | Only if user opts in |

### 4.2 Audio Data Handling

VaulType processes audio data with the following guarantees:

1. **Audio capture** occurs through macOS system APIs (AVFoundation) and is processed entirely in local memory.
2. **Audio buffers** are used only for real-time inference by the local Whisper model and are released from memory immediately after transcription.
3. **No audio is written to disk** unless the user explicitly enables an audio logging/debug feature (if implemented, disabled by default).
4. **No audio is transmitted** over any network connection. VaulType has no networking code in its audio processing pipeline.
5. **Transcribed text** is inserted at the user's cursor position and is not retained, logged, or stored by VaulType.

> 🔒 **Security**: The entire speech-to-text pipeline runs in-process on the user's Mac. There is no intermediary server, API endpoint, cloud service, or external dependency involved in processing audio or generating text.

### 4.3 Crash Reporting (Optional)

VaulType may include optional crash reporting via Sentry (or a similar service). This feature:

- **Is disabled by default** and requires explicit user opt-in.
- **Presents a clear disclosure** explaining exactly what data is collected before the user enables it.
- **Collects only**: stack traces, OS version, app version, and device type (e.g., "Mac with Apple Silicon").
- **Does not collect**: audio data, transcribed text, user-generated content, personal identifiers, or IP addresses (Sentry is configured with IP address scrubbing enabled).
- **Can be disabled at any time** from the Settings window with immediate effect.

If crash reporting is enabled, the following disclosure is shown to the user:

> "VaulType can send anonymous crash reports to help us fix bugs. Crash reports include only technical information (stack traces, OS version, app version) and never include your audio, text, or personal data. You can disable this at any time in Settings."

### 4.4 Network Activity

VaulType's network activity is strictly limited to:

| Activity | Purpose | User Control |
|----------|---------|--------------|
| **Auto-updates (Sparkle)** | Checking for and downloading app updates from the official update server | Can be disabled in Settings |
| **Model downloads** | Downloading AI models during initial setup or when the user adds a new model | User-initiated only |
| **Crash reports** | Sending anonymous crash data (if opted in) | Opt-in only; can be disabled |

> 🔒 **Security**: VaulType does not make any network requests during normal operation (recording, transcribing, or typing). All inference is 100% local. Network activity occurs only for the three purposes listed above, all of which are user-initiated or user-controllable.

### 4.5 User Accounts and Authentication

VaulType does not implement user accounts, authentication, login, registration, or any form of identity management. There is no concept of a "user" in VaulType's data model. The app runs entirely as a local tool with no server-side component.

---

## 5. App Store Review Guidelines

This section documents compliance considerations for potential submission to the Mac App Store. Even if VaulType is initially distributed outside the App Store (via direct download with Sparkle updates), maintaining App Store compatibility is a design goal.

### 5.1 Sandboxing Requirements

The Mac App Store requires App Sandbox. VaulType requires the following entitlements:

| Entitlement | Purpose | Justification |
|-------------|---------|---------------|
| `com.apple.security.device.audio-input` | Microphone access | Required for speech-to-text functionality |
| `com.apple.security.accessibility` | Accessibility API access | Required to type text at the cursor position in other apps |
| `com.apple.security.network.client` | Outbound network | Required for auto-updates and model downloads |
| `com.apple.security.files.downloads.read-write` | Downloads folder access | Required for storing downloaded AI models |

> ⚠️ **Warning**: The Accessibility entitlement (`com.apple.security.accessibility`) is heavily scrutinized during App Store review. Apple requires a clear justification and may request a demo video showing why it is necessary. VaulType's use case (typing transcribed text at the cursor position in any application) is a legitimate use of this API.

**Sandboxing challenges**:
- The Accessibility API is essential for VaulType's core functionality but may conflict with App Sandbox restrictions.
- Model files may be large (several GB), and sandboxed storage limits could apply.
- If App Sandbox proves incompatible with VaulType's requirements, distribution via direct download (with notarization) is the fallback strategy.

### 5.2 Payment and Monetization

- **Initial release**: VaulType is free and open source. No in-app purchases, subscriptions, or paid features.
- **Future consideration**: If a paid tier is introduced, it must comply with Apple's App Store payment guidelines (using StoreKit for Mac App Store distribution).
- **No external payment links**: The Mac App Store version must not link to external payment mechanisms.

### 5.3 Content and Functionality

- **Minimum functionality**: VaulType must provide meaningful functionality to pass review (speech-to-text clearly qualifies).
- **No private API usage**: VaulType must use only public macOS APIs.
- **Accurate metadata**: App Store listing must accurately describe functionality and required permissions.
- **Age rating**: VaulType processes user-generated content (speech), so an appropriate age rating must be selected (likely 4+ as the app itself contains no objectionable content).

### 5.4 Accessibility Requirements

Apple's App Store Review Guidelines (Section 2.1) require apps to be accessible to users with disabilities. See [Section 6](#6-accessibility-compliance) for detailed compliance plans.

---

## 6. Accessibility Compliance

### 6.1 WCAG 2.1 AA Compliance Goals

VaulType aims to meet WCAG 2.1 Level AA compliance for all user-facing interfaces, particularly the Settings UI and any overlay/status windows. Key principles:

| WCAG Principle | Requirement | VaulType Implementation |
|----------------|-------------|------------------------|
| **Perceivable** | Text alternatives for non-text content; content adaptable to different presentations; distinguishable (color contrast >= 4.5:1) | All icons have text labels or accessibility descriptions; UI respects system font size and display settings; color contrast meets 4.5:1 minimum |
| **Operable** | Keyboard accessible; enough time; no seizure-inducing content; navigable | Full keyboard navigation in Settings; no time-limited interactions; no flashing content; clear focus indicators |
| **Understandable** | Readable; predictable; input assistance | Clear, plain-language labels; consistent navigation patterns; error prevention and helpful error messages |
| **Robust** | Compatible with assistive technologies | Full VoiceOver support; standard macOS accessibility APIs used throughout |

### 6.2 VoiceOver Support

VoiceOver is macOS's built-in screen reader. VaulType must provide full VoiceOver compatibility:

1. **All interactive elements** must have meaningful accessibility labels (`.accessibilityLabel()`).
2. **All status changes** (e.g., "Recording started", "Transcription complete") must be announced via accessibility notifications (`.accessibilityAddTraits(.updatesFrequently)` or `NSAccessibility.post()`).
3. **Custom controls** must expose their role, state, and value to the accessibility system.
4. **The recording indicator** (menu bar icon state change) must be perceivable by VoiceOver users.
5. **Settings panels** must be navigable in a logical order with VoiceOver.

> 💡 **Tip**: Test VoiceOver support regularly during development by enabling VoiceOver (Cmd+F5) and navigating the entire app without looking at the screen. Every interaction should be understandable through audio alone.

### 6.3 Additional Accessibility Features

| Feature | Description |
|---------|-------------|
| **System font size** | Respect macOS Dynamic Type / system font size preferences |
| **High contrast** | Support macOS Increase Contrast accessibility setting |
| **Reduced motion** | Respect macOS Reduce Motion preference; minimize animations |
| **Color independence** | Never rely on color alone to convey information; use shapes, labels, or patterns as secondary indicators |
| **Keyboard shortcuts** | All primary actions accessible via customizable keyboard shortcuts |

---

## 7. Open Source Attribution Requirements

### 7.1 About Window Attribution

VaulType's About window (or a dedicated "Acknowledgements" / "Open Source Licenses" section accessible from it) must display attribution for all third-party dependencies. The required format:

```
VaulType
Copyright (C) 2026 VaulType Contributors
Licensed under the GNU General Public License v3.0

---

This application uses the following open source software:

whisper.cpp
Copyright (c) 2023 Georgi Gerganov
MIT License

llama.cpp
Copyright (c) 2023 Georgi Gerganov
MIT License

Sparkle
Copyright (c) 2006-2013 Andy Matuschak
Copyright (c) 2013-2024 Sparkle Project
MIT License

Swift
Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
Apache License 2.0
```

> ℹ️ **Info**: The MIT License requires that "The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software." Displaying attribution in the About window satisfies this requirement for binary distributions.

### 7.2 Documentation Attribution

The project repository must include:

1. **`LICENSE`** — The full text of GPL-3.0.
2. **`THIRD_PARTY_LICENSES`** or **`NOTICES`** — The full license text of every third-party dependency.
3. **Individual license files** preserved in vendored dependency directories (e.g., `vendor/whisper.cpp/LICENSE`).

### 7.3 Distribution Attribution

When distributing VaulType (binary or source):

- The **GPL-3.0 license text** must be included in every distribution.
- The **third-party license texts** must be included (they are part of the source distribution and bundled into the app binary via the About window / Acknowledgements file).
- **DMG or installer** distributions should include a `LICENSE` file visible to the user before or during installation.
- **Source distributions** must include all license files as they exist in the repository.

---

## 8. Export Compliance

### 8.1 Encryption Usage Disclosure

VaulType's use of encryption is limited to:

| Encryption Use | Technology | Purpose | Custom Implementation? |
|----------------|-----------|---------|----------------------|
| **HTTPS for updates** | macOS TLS (via URLSession / Sparkle) | Secure download of app updates and AI models | No — uses system-provided TLS |
| **Code signing** | Apple codesign | Verifying app integrity | No — uses Apple's standard tooling |
| **Notarization** | Apple notarization service | macOS Gatekeeper compliance | No — uses Apple's standard tooling |

VaulType does **not**:
- Implement any custom cryptographic algorithms.
- Include any cryptographic libraries beyond what macOS provides.
- Encrypt user data (there is no user data to encrypt).
- Provide encryption as a feature to end users.
- Use encryption for authentication (there is no authentication).

### 8.2 Classification

Based on the above, VaulType qualifies for the following export control classification:

- **U.S. Export Administration Regulations (EAR)**: VaulType uses only standard operating system-provided encryption for HTTPS connections. This qualifies under the **EAR99** classification, meaning no export license is required.
- **BIS Encryption Registration**: Not required, as VaulType does not include custom encryption and relies solely on OS-level TLS.
- **Wassenaar Arrangement**: Not applicable, as VaulType does not implement or distribute cryptographic technology.

> ℹ️ **Info**: The use of HTTPS (via the operating system's built-in TLS implementation) for downloading updates and models does not trigger export control requirements in most jurisdictions. This is explicitly exempted under EAR Section 740.13(e) (publicly available encryption source code) and BIS guidance on mass-market software.

### 8.3 App Store Export Compliance

When submitting to the Mac App Store, Apple asks whether the app uses encryption. The correct responses for VaulType:

1. **"Does your app use encryption?"** — Yes (HTTPS is technically encryption).
2. **"Does your app qualify for any of the exemptions?"** — Yes, the app uses only standard OS-provided HTTPS/TLS.
3. **"Is your app exempt from EAR?"** — Yes, under the mass-market / publicly available exemption.

No additional export compliance documentation (e.g., CCATS filing) should be necessary.

---

## 9. Data Protection

### 9.1 GDPR Considerations

The **General Data Protection Regulation (EU)** applies to organizations that process personal data of individuals in the European Economic Area. Key analysis for VaulType:

| GDPR Concept | Applicability to VaulType |
|--------------|---------------------------|
| **Data Controller** | Not applicable — VaulType (the project) does not collect or process any personal data. The user's Mac processes data locally; the VaulType project has no access to it. |
| **Data Processor** | Not applicable — VaulType does not process data on behalf of any controller. |
| **Personal Data Processing** | Audio and text are processed locally on the user's device. This data never leaves the device and is never accessible to VaulType's developers. |
| **Right to Access** | Not applicable — no data is held by VaulType's developers or infrastructure. |
| **Right to Erasure** | Not applicable — uninstalling VaulType and deleting model files removes all traces. No external data exists to erase. |
| **Data Protection Impact Assessment** | Not required — no high-risk processing occurs. |

### 9.2 CCPA Considerations

The **California Consumer Privacy Act** applies to businesses that collect personal information of California residents. Analysis for VaulType:

- VaulType does not "collect" personal information as defined by CCPA.
- VaulType does not "sell" or "share" personal information.
- VaulType is not a "business" under CCPA (it is an open-source project, not a for-profit entity meeting CCPA thresholds).
- No CCPA-mandated disclosures (e.g., "Do Not Sell My Personal Information") are required.

### 9.3 Other Jurisdictions

The same logic applies to data protection regulations in other jurisdictions:

| Regulation | Jurisdiction | Applicability |
|------------|-------------|---------------|
| **PIPEDA** | Canada | Not applicable — no personal information is collected |
| **LGPD** | Brazil | Not applicable — no personal data is processed by the project |
| **POPIA** | South Africa | Not applicable — no personal information is processed by a responsible party |
| **APPI** | Japan | Not applicable — no personal information is handled |
| **Privacy Act 1988** | Australia | Not applicable — no personal information is collected or disclosed |

### 9.4 Why Data Protection Regulations Have Minimal Impact

> 🔒 **Security**: VaulType's architecture makes most data protection regulations inapplicable by design. Since all processing occurs on the user's local device and no data is transmitted to or accessible by the VaulType project, there is no "processing of personal data" by VaulType in the legal sense. This is an intentional architectural decision — privacy by design, not merely privacy by policy.

Key architectural guarantees:

1. **No server component** — There is no server that could receive, store, or process user data.
2. **No telemetry** — No usage data, analytics, or behavioral data is collected (unless the user explicitly opts into crash reporting, which collects only technical data).
3. **No user accounts** — There is no concept of a user identity in VaulType.
4. **No persistent audio storage** — Audio is processed in memory and discarded.
5. **No persistent text storage** — Transcribed text is delivered to the cursor and not retained.

> 💡 **Tip**: If VaulType is deployed within an organization (e.g., as part of an enterprise toolset), that organization may have its own data protection obligations regarding the audio content processed by VaulType on employee devices. Those obligations are the responsibility of the deploying organization, not the VaulType project.

---

## 10. Trademark Considerations

### 10.1 VaulType Name

- **"VaulType"** is the project name combining "Hush" (voice stays private) and "Type" (text appears at cursor).
- As of this writing, "VaulType" has not been registered as a trademark. Registration should be considered if the project gains significant adoption.
- The name should be used consistently in all official materials: **VaulType** (one word, capital H and T).

**Recommended trademark protection steps**:

1. Conduct a comprehensive trademark search (USPTO, EUIPO, and common law) before formal registration.
2. File a trademark application in relevant jurisdictions (at minimum, USPTO Class 9 — computer software).
3. Use the ™ symbol until registration is granted, then switch to ®.
4. Document first use in commerce and maintain evidence of continuous use.

### 10.2 Avoiding Trademark Conflicts

Before finalizing the VaulType name, the following searches should be conducted:

| Search Type | Source | Status |
|-------------|--------|--------|
| **USPTO TESS** | United States Patent and Trademark Office | Recommended |
| **EUIPO TMView** | European Union Intellectual Property Office | Recommended |
| **Common law search** | Web search, app stores, domain registrars | Recommended |
| **Domain availability** | vaultype.com, vaultype.app, vaultype.io | Recommended |

> ⚠️ **Warning**: Using a name that conflicts with an existing trademark could result in a cease-and-desist letter, forced rebranding, or legal action. Conduct thorough searches before investing heavily in branding.

### 10.3 Third-Party Trademark Usage

VaulType's documentation and marketing materials reference third-party trademarks. These must be used correctly:

| Trademark | Owner | Correct Usage |
|-----------|-------|---------------|
| **macOS**, **Mac**, **Apple Silicon**, **Metal** | Apple Inc. | Use as adjectives (e.g., "runs on macOS"), not as nouns. Include ™ or ® where appropriate in formal materials. |
| **Whisper** | OpenAI | Reference as "OpenAI Whisper" or "Whisper (by OpenAI)" to distinguish from other uses of the word. |
| **Llama** | Meta Platforms, Inc. | Reference as "Meta Llama" or "Llama (by Meta)" to distinguish from other uses. |
| **Qwen** | Alibaba Cloud | Reference as "Alibaba Qwen" or "Qwen (by Alibaba Cloud)". |
| **Phi** | Microsoft Corporation | Reference as "Microsoft Phi" or "Phi (by Microsoft)". |
| **Swift**, **SwiftUI** | Apple Inc. | Apple trademarks. Use as proper nouns. |
| **Sparkle** | Sparkle Project | Community project name. Use with attribution. |

> ℹ️ **Info**: All third-party trademarks mentioned in this document and in VaulType's materials are the property of their respective owners. VaulType is not affiliated with, endorsed by, or sponsored by any of the trademark owners listed above.

---

## Related Documentation

- [Security Policy](SECURITY.md) — Vulnerability reporting, security architecture, and threat model
- [Privacy Architecture](../architecture/PRIVACY.md) — Technical details of VaulType's privacy-preserving architecture
- [Contributing Guide](../../CONTRIBUTING.md) — How to contribute to VaulType, including license requirements for contributions
- [License (GPL-3.0)](../../LICENSE) — Full text of the GNU General Public License v3.0
- [Third-Party Licenses](../../THIRD_PARTY_LICENSES) — Full license texts for all third-party dependencies
- [Build & Distribution](../development/BUILD.md) — Build instructions including code signing and notarization
- [App Store Submission](../development/APP_STORE.md) — Detailed App Store submission checklist and requirements

---

*This document is provided for informational purposes and does not constitute legal advice. For specific legal questions regarding licensing, compliance, or trademark matters, consult a qualified attorney.*

*VaulType is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.*
