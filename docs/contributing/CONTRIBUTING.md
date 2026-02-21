Last Updated: 2026-02-13

# Contributing to VaulType

> How to contribute to VaulType — code, documentation, bug reports, and feature requests.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Environment](#development-environment)
- [Coding Standards](#coding-standards)
- [Pull Request Process](#pull-request-process)
- [Issue Reporting](#issue-reporting)
- [Feature Requests](#feature-requests)
- [Testing Requirements](#testing-requirements)
- [Documentation Requirements](#documentation-requirements)
- [How to Add a New Processing Mode](#how-to-add-a-new-processing-mode)
- [How to Add a New Voice Command](#how-to-add-a-new-voice-command)
- [Release Process](#release-process)
- [Community](#community)
- [Next Steps](#next-steps)

---

## Code of Conduct

VaulType follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating, you agree to:

- **Be respectful** — Treat everyone with kindness and empathy
- **Be constructive** — Focus on what's best for the project and community
- **Be inclusive** — Welcome people of all backgrounds and experience levels
- **No harassment** — Personal attacks, trolling, and discriminatory language are not tolerated

Report violations to the maintainers via email or GitHub issues.

---

## Getting Started

### Quick Contribution Checklist

1. Fork the repository
2. Clone your fork locally
3. Set up the development environment (see below)
4. Create a feature branch
5. Make changes and add tests
6. Run the test suite
7. Submit a pull request

### Types of Contributions

| Type | Description | Good First Issue? |
|------|-------------|-------------------|
| Bug fixes | Fix reported issues | Often yes |
| Documentation | Improve or add docs | Yes |
| Processing modes | Add new LLM modes | Yes |
| Voice commands | Add new commands | Yes |
| Translations | Add/improve i18n | Yes |
| Performance | Optimize inference | Usually no |
| Core features | New major features | Usually no |
| C bridging | whisper.cpp/llama.cpp updates | No |

Look for issues labeled [`good first issue`](https://github.com/vaultype/vaultype/labels/good%20first%20issue) to get started.

---

## Development Environment

### Prerequisites

| Tool | Version | Required |
|------|---------|----------|
| macOS | 14.0 (Sonoma)+ | Yes |
| Xcode | 15.0+ | Yes |
| CMake | 3.20+ | Yes |
| Git | 2.30+ | Yes |
| SwiftLint | Latest | Recommended |
| create-dmg | Latest | For packaging only |

### Setup

```bash
# Fork on GitHub, then:
git clone https://github.com/YOUR_USERNAME/vaultype.git
cd vaultype

# Add upstream remote
git remote add upstream https://github.com/vaultype/vaultype.git

# Install build tools
brew install cmake swiftlint

# Build C/C++ dependencies (whisper.cpp, llama.cpp)
./scripts/build-deps.sh

# Open in Xcode
open VaulType.xcodeproj

# Build and run (⌘R)
```

### Download Development Models

```bash
# Download Whisper tiny model for testing (~75MB)
./scripts/download-model.sh whisper-tiny

# (Optional) Download a small LLM for testing LLM features
./scripts/download-model.sh qwen2.5-0.5b-q4
```

> See [SETUP_GUIDE.md](../getting-started/SETUP_GUIDE.md) for detailed environment setup.

---

## Coding Standards

### Swift Style Guide

VaulType follows the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) with these project conventions:

**Enforced via SwiftLint:**

```yaml
# .swiftlint.yml
opt_in_rules:
  - closure_spacing
  - empty_count
  - explicit_init
  - fatal_error_message
  - first_where
  - implicitly_unwrapped_optional
  - modifier_order
  - multiline_arguments
  - multiline_parameters
  - operator_usage_whitespace
  - overridden_super_call
  - private_outlet
  - prohibited_super_call
  - redundant_nil_coalescing
  - sorted_imports
  - unneeded_parentheses_in_closure_argument
  - vertical_parameter_alignment_on_call

disabled_rules:
  - trailing_whitespace

line_length:
  warning: 120
  error: 150

type_body_length:
  warning: 300
  error: 500

function_body_length:
  warning: 50
  error: 100

identifier_name:
  min_length: 2
  max_length: 50
  excluded:
    - id
    - x
    - y
    - i

excluded:
  - vendor/
  - build/
  - .build/
```

### Key Conventions

```swift
// 1. Use async/await, not completion handlers
// GOOD
func transcribe(audio: [Float]) async throws -> String

// BAD
func transcribe(audio: [Float], completion: @escaping (Result<String, Error>) -> Void)

// 2. Use structured concurrency
// GOOD
let result = try await whisperService.transcribe(audio: audioData)

// BAD
Task.detached { ... }  // Avoid unless you have a specific reason

// 3. Use os_log, not print
// GOOD
Logger.whisper.info("Transcription completed in \(elapsed)ms")

// BAD
print("Transcription completed in \(elapsed)ms")

// 4. Use early returns
// GOOD
guard let model = selectedModel else {
    Logger.whisper.error("No model selected")
    return
}

// BAD
if let model = selectedModel {
    // deeply nested code...
}

// 5. Mark protocol conformances in extensions
// GOOD
extension WhisperService: TranscriptionService {
    func transcribe(...) { }
}

// BAD (don't put conformance in the main declaration for large protocols)
class WhisperService: TranscriptionService { ... }
```

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

**Types:**

| Type | Use For |
|------|---------|
| `feat` | New features |
| `fix` | Bug fixes |
| `perf` | Performance improvements |
| `refactor` | Code refactoring (no behavior change) |
| `test` | Adding or updating tests |
| `docs` | Documentation changes |
| `chore` | Build, CI, dependency updates |
| `style` | Formatting, SwiftLint fixes |

**Examples:**

```
feat(modes): add Email processing mode
fix(injection): restore clipboard after paste injection
perf(whisper): enable batch decoding for shorter latency
docs(api): add WhisperService API examples
test(parser): add voice command edge cases
chore(deps): bump whisper.cpp to v1.7.3
```

---

## Pull Request Process

### Before Submitting

1. **Sync with upstream:**
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Run the full lint and test suite:**
   ```bash
   swiftlint lint --strict
   xcodebuild test -scheme VaulType -destination "platform=macOS,arch=arm64"
   ```

3. **Check that your changes build in Release configuration:**
   ```bash
   xcodebuild build -scheme VaulType -configuration Release \
       CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
   ```

### PR Template

When creating a pull request, use this template:

```markdown
## Summary

Brief description of what this PR does and why.

## Changes

- [ ] Change 1
- [ ] Change 2
- [ ] Change 3

## Testing

- [ ] Unit tests added/updated
- [ ] Integration tests added/updated (if applicable)
- [ ] Manual testing performed (describe steps)

## Screenshots

(If applicable — for UI changes)

## Checklist

- [ ] Code follows project style guidelines
- [ ] SwiftLint passes with no warnings
- [ ] All existing tests pass
- [ ] New tests added for new functionality
- [ ] Documentation updated (if applicable)
- [ ] Commit messages follow Conventional Commits
- [ ] No sensitive data (API keys, credentials) in code
```

### Review Process

1. **Automated checks** — CI runs build, lint, and tests
2. **Code review** — At least one maintainer reviews the PR
3. **Feedback** — Address review comments
4. **Approval** — Maintainer approves
5. **Merge** — Squash-merged to `main` by a maintainer

### Review Criteria

| Area | What We Look For |
|------|-----------------|
| Correctness | Does it work as intended? Edge cases handled? |
| Tests | Are there adequate tests? Do they test the right things? |
| Performance | No unnecessary allocations, no main thread blocking |
| Memory | C bridging code properly frees resources |
| Thread safety | Proper use of actors, Sendable, @MainActor |
| Swift style | Follows project conventions and SwiftLint rules |
| Documentation | Public APIs documented, complex logic commented |
| Security | No hardcoded credentials, no unnecessary permissions |

---

## Issue Reporting

### Bug Report Template

```markdown
**Describe the bug**
A clear description of what the bug is.

**To Reproduce**
1. Go to '...'
2. Click on '...'
3. Speak '...'
4. See error

**Expected behavior**
What you expected to happen.

**Actual behavior**
What actually happened.

**Environment**
- VaulType version: [e.g., 0.1.0]
- macOS version: [e.g., 15.2]
- Mac model: [e.g., MacBook Pro M3, 16GB]
- Whisper model: [e.g., small]
- LLM model: [e.g., Qwen2.5-3B Q4]

**Diagnostics**
Attach the diagnostics export from Settings > Advanced > Export Diagnostics.

**Screenshots**
If applicable, add screenshots.

**Additional context**
Any other context about the problem.
```

### Security Vulnerabilities

> 🔒 **Do not report security vulnerabilities via public GitHub issues.** Email security@vaultype.app with details. See [SECURITY.md](../security/SECURITY.md) for the full responsible disclosure policy.

---

## Feature Requests

### Feature Request Template

```markdown
**Is your feature request related to a problem?**
A description of the problem. Example: "I'm frustrated when..."

**Describe the solution you'd like**
A clear description of what you want to happen.

**Describe alternatives you've considered**
Other solutions or features you've considered.

**Additional context**
Mockups, examples, or references.

**Target phase**
Which [roadmap phase](../reference/ROADMAP.md) does this fit into?
```

### Feature Prioritization

Features are prioritized based on:

1. **Alignment with roadmap** — Does it fit the current phase?
2. **User impact** — How many users would benefit?
3. **Implementation complexity** — How much effort is required?
4. **Privacy preservation** — Does it maintain the local-only philosophy?
5. **Maintainability** — Can it be maintained long-term?

---

## Testing Requirements

Every PR must include appropriate tests:

| Change Type | Required Tests |
|-------------|---------------|
| New processing mode | Unit test for template, integration test for LLM output |
| New voice command | Unit test for parsing, test for all phrase variations |
| Bug fix | Test that reproduces the bug and verifies the fix |
| UI change | UI test for the affected flow |
| C bridging change | Integration test with real model |
| Performance change | Benchmark test showing improvement |

### Running Tests

```bash
# Unit tests (fast, no model needed)
xcodebuild test -scheme VaulType -testPlan UnitTests \
    -destination "platform=macOS,arch=arm64" \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

# All tests including integration
xcodebuild test -scheme VaulType \
    -destination "platform=macOS,arch=arm64" \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

> See [TESTING.md](../testing/TESTING.md) for the full testing guide.

---

## Documentation Requirements

- **New feature** — Update or create relevant doc in `docs/features/`
- **New API** — Update [API_DOCUMENTATION.md](../api/API_DOCUMENTATION.md)
- **New setting** — Update relevant docs
- **Breaking change** — Update [CHANGELOG.md](../../CHANGELOG.md) and affected docs
- **New dependency** — Update [TECH_STACK.md](../architecture/TECH_STACK.md) and [LEGAL_COMPLIANCE.md](../security/LEGAL_COMPLIANCE.md)

---

## How to Add a New Processing Mode

1. Add a case to `ProcessingMode` enum
2. Create a prompt template JSON in `Resources/PromptTemplates/`
3. Register it in `LLMService.process()`
4. Add unit tests for the template
5. Verify it appears in the mode selector UI
6. Update docs in [LLM_PROCESSING.md](../features/LLM_PROCESSING.md)

> See the detailed walkthrough in [DEVELOPMENT_GUIDE.md](../getting-started/DEVELOPMENT_GUIDE.md#how-to-add-a-new-processing-mode).

---

## How to Add a New Voice Command

1. Define the command in `CommandRegistry`
2. Add regex patterns for natural language matching
3. Implement the handler
4. Add unit tests for parsing all phrase variations
5. Update docs in [VOICE_COMMANDS.md](../features/VOICE_COMMANDS.md)

> See the detailed walkthrough in [DEVELOPMENT_GUIDE.md](../getting-started/DEVELOPMENT_GUIDE.md#how-to-add-a-new-voice-command).

---

## Release Process

Releases are managed by maintainers. The process:

1. Update version in Xcode (CFBundleShortVersionString + CFBundleVersion)
2. Update CHANGELOG.md
3. Create a release tag: `git tag v0.X.0`
4. Push the tag: `git push origin v0.X.0`
5. CI automatically builds, signs, notarizes, and creates a GitHub Release

> See [DEPLOYMENT_GUIDE.md](../deployment/DEPLOYMENT_GUIDE.md) for the full release pipeline.

---

## Community

- **GitHub Issues** — Bug reports and feature requests
- **GitHub Discussions** — General questions and ideas
- **Pull Requests** — Code and documentation contributions

### Recognition

All contributors are recognized in:
- GitHub's contributor graph
- CHANGELOG.md release notes (for significant contributions)
- README.md acknowledgments (for major contributors)

---

## Next Steps

- [Development Guide](../getting-started/DEVELOPMENT_GUIDE.md) — Detailed development workflow
- [Setup Guide](../getting-started/SETUP_GUIDE.md) — Environment setup
- [Testing Guide](../testing/TESTING.md) — Testing practices
- [Architecture](../architecture/ARCHITECTURE.md) — System design
- [Roadmap](../reference/ROADMAP.md) — Feature planning
