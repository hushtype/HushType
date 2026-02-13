# Docker Setup for CI/CD

> **Last Updated: 2026-02-13**

> **HushType** — Privacy-first, macOS-native speech-to-text application

---

> ⚠️ **Important**: HushType is a native macOS application. Docker is **not** used to
> run or deploy the app. This document covers Docker usage exclusively for CI/CD
> pipelines, linting, testing, and documentation generation.

---

## Table of Contents

- [1. Docker Usage for CI/CD Only](#1-docker-usage-for-cicd-only)
  - [1.1 Why HushType Cannot Run in Docker](#11-why-hushtype-cannot-run-in-docker)
  - [1.2 What Docker Is Used For](#12-what-docker-is-used-for)
  - [1.3 CI/CD Architecture Overview](#13-cicd-architecture-overview)
- [2. macOS Cross-Compilation Considerations](#2-macos-cross-compilation-considerations)
  - [2.1 Legal Considerations (macOS EULA)](#21-legal-considerations-macos-eula)
  - [2.2 What Can Be Done in Docker](#22-what-can-be-done-in-docker)
  - [2.3 What Cannot Be Done in Docker](#23-what-cannot-be-done-in-docker)
  - [2.4 Hybrid CI/CD Strategy](#24-hybrid-cicd-strategy)
- [3. CI/CD Docker Images for Linting and Testing](#3-cicd-docker-images-for-linting-and-testing)
  - [3.1 SwiftLint Container](#31-swiftlint-container)
  - [3.2 Swift Formatting Container](#32-swift-formatting-container)
  - [3.3 Documentation Generation Container](#33-documentation-generation-container)
  - [3.4 Markdown Linting Container](#34-markdown-linting-container)
  - [3.5 Docker Compose for All CI Services](#35-docker-compose-for-all-ci-services)
- [4. Model Testing in CI Environments](#4-model-testing-in-ci-environments)
  - [4.1 Testing Without Metal GPU](#41-testing-without-metal-gpu)
  - [4.2 CPU-Only Fallback Testing](#42-cpu-only-fallback-testing)
  - [4.3 Mock Model Testing](#43-mock-model-testing)
  - [4.4 Model Testing Docker Setup](#44-model-testing-docker-setup)
  - [4.5 Model Validation Pipeline](#45-model-validation-pipeline)
- [5. GitHub Actions Integration](#5-github-actions-integration)
  - [5.1 Workflow Overview](#51-workflow-overview)
  - [5.2 Lint and Format Workflow](#52-lint-and-format-workflow)
  - [5.3 Model Testing Workflow](#53-model-testing-workflow)
  - [5.4 Full CI Pipeline Workflow](#54-full-ci-pipeline-workflow)
- [6. Docker Image Management](#6-docker-image-management)
  - [6.1 Building and Pushing Images](#61-building-and-pushing-images)
  - [6.2 Image Versioning Strategy](#62-image-versioning-strategy)
  - [6.3 Image Security Scanning](#63-image-security-scanning)
- [7. Local Development with Docker](#7-local-development-with-docker)
  - [7.1 Running CI Checks Locally](#71-running-ci-checks-locally)
  - [7.2 Pre-Commit Hook Integration](#72-pre-commit-hook-integration)
- [8. Troubleshooting](#8-troubleshooting)
- [Related Documentation](#related-documentation)

---

## 1. Docker Usage for CI/CD Only

### 1.1 Why HushType Cannot Run in Docker

HushType is a native macOS application that relies on system-level APIs and hardware
features that are fundamentally incompatible with containerized environments:

| Dependency | Why It Requires macOS | Docker Compatibility |
|---|---|---|
| **Metal GPU** | whisper.cpp and llama.cpp use Metal for hardware-accelerated inference | :x: Not available in containers |
| **Accessibility APIs** | Text injection uses `AXUIElement` for inserting transcribed text | :x: Requires macOS window server |
| **Audio Input** | Core Audio captures microphone input for speech recognition | :x: No audio hardware in containers |
| **SwiftUI / AppKit** | Native UI framework requires macOS display server | :x: No GUI in containers |
| **Keychain Services** | Secure storage for user preferences and model credentials | :x: macOS-specific service |
| **macOS Sandbox** | App sandboxing and entitlements require macOS runtime | :x: macOS-only security model |

> :x: **Do not attempt to run HushType inside a Docker container.** The application
> requires native macOS hardware and system services that cannot be virtualized or
> emulated in any container runtime.

### 1.2 What Docker Is Used For

Docker serves HushType's CI/CD pipeline for tasks that do **not** require macOS-specific
APIs or hardware:

| Task | Docker Image | Purpose |
|---|---|---|
| **Swift Linting** | `hushtype/swiftlint` | Enforce code style and catch common issues |
| **Swift Formatting** | `hushtype/swift-format` | Verify consistent code formatting |
| **Markdown Linting** | `hushtype/markdownlint` | Validate documentation quality |
| **Documentation Generation** | `hushtype/docs-generator` | Build API docs and reference pages |
| **Model Validation** | `hushtype/model-test` | CPU-only inference testing for whisper.cpp / llama.cpp |
| **Dependency Auditing** | `hushtype/dependency-audit` | Check for vulnerable dependencies |

> :bulb: **Tip**: Running these tasks in Docker ensures reproducible CI environments
> regardless of the developer's local setup. Every contributor gets identical linting
> rules, formatting standards, and test configurations.

### 1.3 CI/CD Architecture Overview

The HushType CI/CD pipeline uses a hybrid approach:

```
+---------------------------------------------+
|              GitHub Actions CI               |
+---------------------------------------------+
|                                              |
|  +------------------+  +------------------+ |
|  | Docker Runners   |  | macOS Runners    | |
|  | (Linux amd64)    |  | (macos-14)       | |
|  +------------------+  +------------------+ |
|  | - SwiftLint      |  | - Xcode Build    | |
|  | - swift-format   |  | - Unit Tests     | |
|  | - markdownlint   |  | - UI Tests       | |
|  | - Doc generation |  | - Metal Tests    | |
|  | - CPU model tests|  | - Code Signing   | |
|  | - Dep auditing   |  | - Notarization   | |
|  +------------------+  +------------------+ |
|         |                      |             |
|         v                      v             |
|  +------------------------------------------+|
|  |          Artifact Collection              ||
|  +------------------------------------------+|
+---------------------------------------------+
```

> :information_source: **Note**: Docker-based tasks run on standard Linux runners, which
> are significantly cheaper and faster to provision than macOS runners. This hybrid
> approach keeps CI costs low while still performing full macOS builds and tests where
> needed. See `CI_CD.md` for the complete pipeline configuration.

---

## 2. macOS Cross-Compilation Considerations

### 2.1 Legal Considerations (macOS EULA)

> :lock: **Legal Warning**: Apple's macOS End User License Agreement (EULA) restricts
> running macOS in virtualized or containerized environments.

Key restrictions that affect Docker-based CI:

1. **macOS may only run on Apple hardware** — Apple's EULA permits macOS virtualization
   only on Apple-branded hardware. Running macOS inside Docker on non-Apple hardware
   (e.g., standard Linux cloud instances) violates the EULA.

2. **No macOS Docker images on Linux** — There are no legally distributable macOS Docker
   images for Linux hosts. Projects like `sickcodes/Docker-OSX` exist but are **not
   compliant** with Apple's licensing terms.

3. **Xcode license restrictions** — The Xcode license agreement requires that Xcode
   and its toolchain run on Apple hardware with macOS. Cross-compiling macOS binaries
   from Linux is not supported or permitted.

> :apple: **HushType's approach**: We use Docker exclusively for platform-independent
> CI tasks (linting, formatting, documentation, CPU-only model testing). All macOS-specific
> operations (building, signing, notarization, Metal-accelerated testing) run on GitHub
> Actions macOS runners, which use genuine Apple hardware.

For full legal compliance details, see `../security/LEGAL_COMPLIANCE.md`.

### 2.2 What Can Be Done in Docker

The following tasks are fully supported in Docker containers running on Linux:

| Task | Feasibility | Notes |
|---|---|---|
| SwiftLint analysis | :white_check_mark: Fully supported | Uses official Swift Linux toolchain |
| swift-format checks | :white_check_mark: Fully supported | Swift formatting is cross-platform |
| Markdown linting | :white_check_mark: Fully supported | Node.js-based, platform-independent |
| Documentation generation | :white_check_mark: Fully supported | Jazzy/DocC can parse Swift on Linux |
| whisper.cpp CPU inference | :white_check_mark: Fully supported | CPU fallback path works on Linux |
| llama.cpp CPU inference | :white_check_mark: Fully supported | CPU fallback path works on Linux |
| Dependency vulnerability scanning | :white_check_mark: Fully supported | Static analysis of Package.swift |
| JSON/YAML schema validation | :white_check_mark: Fully supported | Configuration file validation |
| Git hook enforcement | :white_check_mark: Fully supported | Commit message and branch checks |

### 2.3 What Cannot Be Done in Docker

The following tasks **require** native macOS and must run on macOS runners:

| Task | Reason | Alternative in Docker |
|---|---|---|
| Xcode project build | Requires Xcode toolchain on macOS | None — must use macOS runner |
| Unit tests with XCTest | XCTest requires macOS runtime | Limited: Swift Testing on Linux |
| UI tests with XCUITest | Requires macOS window server | None |
| Metal GPU inference tests | Requires Apple GPU hardware | CPU-only fallback testing |
| Code signing | Requires macOS Keychain and codesign | None |
| Notarization | Requires Apple notary service via Xcode | None |
| Accessibility API tests | Requires macOS Accessibility framework | Mock-based testing only |
| Core Audio tests | Requires audio hardware/subsystem | Mock-based testing only |

> :information_source: **Note**: The split between Docker and macOS runner tasks is defined
> in the GitHub Actions workflow files. See `CI_CD.md` for the complete workflow
> configuration and runner allocation strategy.

### 2.4 Hybrid CI/CD Strategy

HushType uses a two-track CI strategy to balance cost, speed, and completeness:

```
Pull Request Opened
        |
        v
+-------+--------+
|                 |
v                 v
Track A           Track B
(Docker/Linux)    (macOS Runner)
|                 |
|- SwiftLint      |- xcodebuild
|- swift-format   |- XCTest suite
|- markdownlint   |- UI tests
|- Doc build      |- Metal inference
|- CPU model      |- Code signing
|  validation     |- Integration tests
|- Dep audit      |
|                 |
v                 v
+-------+---------+
        |
        v
   All Checks Pass
        |
        v
   Ready to Merge
```

**Cost comparison** (approximate GitHub Actions pricing):

| Runner Type | Cost per Minute | Typical Job Duration | Cost per Run |
|---|---|---|---|
| Linux (Docker) | $0.008 | 3-5 minutes | ~$0.04 |
| macOS | $0.08 | 10-15 minutes | ~$1.00 |

> :bulb: **Tip**: By offloading linting, formatting, and CPU model tests to Docker/Linux
> runners, HushType saves approximately 70% on CI costs compared to running everything
> on macOS runners.

---

## 3. CI/CD Docker Images for Linting and Testing

### 3.1 SwiftLint Container

The SwiftLint container enforces HushType's Swift coding standards.

**Dockerfile** (`docker/swiftlint/Dockerfile`):

```dockerfile
# HushType SwiftLint CI Container
# Purpose: Enforce Swift code style and catch common issues
# Base: Official Swift image for Linux

FROM swift:5.9-jammy AS builder

# Install SwiftLint from source for Linux compatibility
ARG SWIFTLINT_VERSION=0.55.1
RUN apt-get update && apt-get install -y --no-install-recommends \
        libcurl4-openssl-dev \
        libxml2-dev \
        git \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --branch ${SWIFTLINT_VERSION} --depth 1 \
        https://github.com/realm/SwiftLint.git /tmp/SwiftLint \
    && cd /tmp/SwiftLint \
    && swift build -c release --static-swift-stdlib \
    && cp .build/release/swiftlint /usr/local/bin/ \
    && rm -rf /tmp/SwiftLint

# --- Runtime stage ---
FROM swift:5.9-jammy-slim

COPY --from=builder /usr/local/bin/swiftlint /usr/local/bin/swiftlint

# Create a non-root user for CI
RUN useradd --create-home --shell /bin/bash ciuser
USER ciuser
WORKDIR /workspace

LABEL org.opencontainers.image.title="HushType SwiftLint"
LABEL org.opencontainers.image.description="SwiftLint CI container for HushType"
LABEL org.opencontainers.image.source="https://github.com/hushtype/hushtype"

ENTRYPOINT ["swiftlint"]
CMD ["lint", "--strict", "--reporter", "github-actions-logging"]
```

**SwiftLint configuration** (`.swiftlint.yml`):

```yaml
# HushType SwiftLint Configuration
# See: https://realm.github.io/SwiftLint/rule-directory.html

included:
  - Sources
  - Tests

excluded:
  - Sources/Generated
  - .build
  - Packages

disabled_rules:
  - todo

opt_in_rules:
  - closure_end_indentation
  - closure_spacing
  - collection_alignment
  - contains_over_filter_count
  - contains_over_first_not_nil
  - discouraged_object_literal
  - empty_collection_literal
  - empty_count
  - empty_string
  - enum_case_associated_values_count
  - explicit_init
  - extension_access_modifier
  - fallthrough
  - fatal_error_message
  - file_name_no_space
  - first_where
  - flatmap_over_map_reduce
  - force_unwrapping
  - identical_operands
  - implicit_return
  - last_where
  - literal_expression_end_indentation
  - modifier_order
  - multiline_arguments
  - multiline_parameters
  - operator_usage_whitespace
  - overridden_super_call
  - pattern_matching_keywords
  - prefer_self_in_static_references
  - prefer_self_type_over_type_of_self
  - private_action
  - private_outlet
  - prohibited_super_call
  - reduce_into
  - redundant_nil_coalescing
  - redundant_type_annotation
  - sorted_first_last
  - toggle_bool
  - unavailable_function
  - unneeded_parentheses_in_closure_argument
  - unowned_variable_capture
  - vertical_parameter_alignment_on_call
  - yoda_condition

line_length:
  warning: 120
  error: 150
  ignores_comments: true
  ignores_urls: true

type_body_length:
  warning: 300
  error: 500

file_length:
  warning: 500
  error: 1000

function_body_length:
  warning: 50
  error: 100

identifier_name:
  min_length:
    warning: 2
    error: 1
  max_length:
    warning: 50
    error: 60
  excluded:
    - id
    - x
    - y
    - i
    - n

nesting:
  type_level:
    warning: 3
  function_level:
    warning: 3

reporter: "github-actions-logging"
```

**Usage in CI**:

```bash
# Run SwiftLint against the project source
docker run --rm \
    -v "$(pwd):/workspace:ro" \
    hushtype/swiftlint:latest \
    lint --strict --config /workspace/.swiftlint.yml
```

### 3.2 Swift Formatting Container

The Swift formatting container verifies that all source files conform to HushType's
formatting standards using `swift-format`.

**Dockerfile** (`docker/swift-format/Dockerfile`):

```dockerfile
# HushType Swift Format CI Container
# Purpose: Verify consistent Swift code formatting

FROM swift:5.9-jammy AS builder

ARG SWIFT_FORMAT_VERSION=509.0.0
RUN git clone --branch ${SWIFT_FORMAT_VERSION} --depth 1 \
        https://github.com/apple/swift-format.git /tmp/swift-format \
    && cd /tmp/swift-format \
    && swift build -c release --static-swift-stdlib \
    && cp .build/release/swift-format /usr/local/bin/ \
    && rm -rf /tmp/swift-format

# --- Runtime stage ---
FROM swift:5.9-jammy-slim

COPY --from=builder /usr/local/bin/swift-format /usr/local/bin/swift-format

RUN useradd --create-home --shell /bin/bash ciuser
USER ciuser
WORKDIR /workspace

LABEL org.opencontainers.image.title="HushType swift-format"
LABEL org.opencontainers.image.description="Swift formatting CI container for HushType"

ENTRYPOINT ["swift-format"]
CMD ["lint", "--strict", "--recursive", "Sources/", "Tests/"]
```

**Formatting configuration** (`.swift-format.json`):

```json
{
  "version": 1,
  "indentation": {
    "spaces": 4
  },
  "tabWidth": 4,
  "maximumBlankLines": 1,
  "lineLength": 120,
  "respectsExistingLineBreaks": true,
  "lineBreakBeforeControlFlowKeywords": false,
  "lineBreakBeforeEachArgument": true,
  "lineBreakBeforeEachGenericRequirement": true,
  "indentConditionalCompilationBlocks": true,
  "lineBreakAroundMultilineExpressionChainComponents": true,
  "prioritizeKeepingFunctionOutputTogether": true,
  "indentSwitchCaseLabels": false,
  "spacesAroundRangeFormationOperators": false,
  "multiElementCollectionTrailingCommas": true,
  "rules": {
    "AllPublicDeclarationsHaveDocumentation": true,
    "AlwaysUseLowerCamelCase": true,
    "AmbiguousTrailingClosureOverload": true,
    "BeginDocumentationCommentWithOneLineSummary": true,
    "DoNotUseSemicolons": true,
    "DontRepeatTypeInStaticProperties": true,
    "FileScopedDeclarationPrivacy": true,
    "FullyIndirectEnum": true,
    "GroupNumericLiterals": true,
    "IdentifiersMustBeASCII": true,
    "NeverForceUnwrap": true,
    "NeverUseForceTry": true,
    "NeverUseImplicitlyUnwrappedOptionals": true,
    "NoAccessLevelOnExtensionDeclaration": true,
    "NoBlockComments": true,
    "NoCasesWithOnlyFallthrough": true,
    "NoEmptyTrailingClosureParentheses": true,
    "NoLabelsInCasePatterns": true,
    "NoLeadingUnderscores": false,
    "NoParensAroundConditions": true,
    "NoVoidReturnOnFunctionSignature": true,
    "OneCasePerLine": true,
    "OneVariableDeclarationPerLine": true,
    "OnlyOneTrailingClosureArgument": true,
    "OrderedImports": true,
    "ReplaceForEachWithForLoop": true,
    "ReturnVoidInsteadOfEmptyTuple": true,
    "UseEarlyExits": true,
    "UseLetInEveryBoundCaseVariable": true,
    "UseShorthandTypeNames": true,
    "UseSingleLinePropertyGetter": true,
    "UseSynthesizedInitializer": true,
    "UseTripleSlashForDocumentationComments": true,
    "UseWhereClausesInForLoops": false,
    "ValidateDocumentationComments": true
  }
}
```

**Usage in CI**:

```bash
# Check formatting (non-destructive, exit code indicates violations)
docker run --rm \
    -v "$(pwd):/workspace:ro" \
    hushtype/swift-format:latest \
    lint --strict --recursive Sources/ Tests/

# Auto-format (destructive, modifies files in place)
docker run --rm \
    -v "$(pwd):/workspace" \
    hushtype/swift-format:latest \
    format --in-place --recursive Sources/ Tests/
```

### 3.3 Documentation Generation Container

This container generates API documentation from Swift source files and validates
that all public APIs are properly documented.

**Dockerfile** (`docker/docs-generator/Dockerfile`):

```dockerfile
# HushType Documentation Generator CI Container
# Purpose: Generate and validate API documentation

FROM swift:5.9-jammy

# Install documentation tooling
RUN apt-get update && apt-get install -y --no-install-recommends \
        ruby-full \
        build-essential \
        libsqlite3-dev \
        pkg-config \
        curl \
        git \
    && rm -rf /var/lib/apt/lists/*

# Install Jazzy for Swift documentation
RUN gem install jazzy --no-document

# Install swift-docc for DocC-based documentation
# DocC is included with the Swift 5.9 toolchain on Linux

RUN useradd --create-home --shell /bin/bash ciuser
USER ciuser
WORKDIR /workspace

LABEL org.opencontainers.image.title="HushType Docs Generator"
LABEL org.opencontainers.image.description="Documentation generation CI container for HushType"

COPY scripts/generate-docs.sh /usr/local/bin/generate-docs
USER root
RUN chmod +x /usr/local/bin/generate-docs
USER ciuser

ENTRYPOINT ["generate-docs"]
```

**Documentation generation script** (`docker/docs-generator/scripts/generate-docs.sh`):

```bash
#!/usr/bin/env bash
set -euo pipefail

# HushType Documentation Generator
# Generates API docs from Swift source files

WORKSPACE="${1:-/workspace}"
OUTPUT_DIR="${WORKSPACE}/docs-output"
COVERAGE_THRESHOLD="${DOC_COVERAGE_THRESHOLD:-90}"

echo "=== HushType Documentation Generator ==="
echo "Workspace: ${WORKSPACE}"
echo "Output: ${OUTPUT_DIR}"
echo "Coverage threshold: ${COVERAGE_THRESHOLD}%"

mkdir -p "${OUTPUT_DIR}"

# Step 1: Generate Jazzy documentation
echo ""
echo "--- Generating Jazzy documentation ---"
cd "${WORKSPACE}"

jazzy \
    --swift-build-tool spm \
    --module HushType \
    --output "${OUTPUT_DIR}/jazzy" \
    --min-acl public \
    --theme fullwidth \
    --author "HushType Contributors" \
    --github_url "https://github.com/hushtype/hushtype" \
    --readme "${WORKSPACE}/README.md" \
    2>&1 | tee "${OUTPUT_DIR}/jazzy-build.log"

# Step 2: Check documentation coverage
echo ""
echo "--- Checking documentation coverage ---"
COVERAGE=$(jazzy \
    --swift-build-tool spm \
    --module HushType \
    --min-acl public \
    2>&1 | grep -oP '\d+(?=% documentation coverage)' || echo "0")

echo "Documentation coverage: ${COVERAGE}%"

if [ "${COVERAGE}" -lt "${COVERAGE_THRESHOLD}" ]; then
    echo "ERROR: Documentation coverage ${COVERAGE}% is below threshold ${COVERAGE_THRESHOLD}%"
    exit 1
fi

echo ""
echo "=== Documentation generation complete ==="
echo "Output: ${OUTPUT_DIR}/jazzy"
echo "Coverage: ${COVERAGE}%"
```

### 3.4 Markdown Linting Container

The markdown linting container validates all documentation files, including this one.

**Dockerfile** (`docker/markdownlint/Dockerfile`):

```dockerfile
# HushType Markdown Lint CI Container
# Purpose: Validate documentation quality and consistency

FROM node:20-alpine

RUN npm install -g \
        markdownlint-cli2@0.13.0 \
        markdown-link-check@3.12.1 \
    && npm cache clean --force

RUN adduser -D ciuser
USER ciuser
WORKDIR /workspace

LABEL org.opencontainers.image.title="HushType Markdown Lint"
LABEL org.opencontainers.image.description="Markdown linting CI container for HushType"

COPY .markdownlint-cli2.yaml /home/ciuser/.markdownlint-cli2.yaml

ENTRYPOINT ["markdownlint-cli2"]
CMD ["**/*.md", "#node_modules", "#.build"]
```

**Markdown lint configuration** (`.markdownlint-cli2.yaml`):

```yaml
# HushType Markdown Lint Configuration
config:
  # MD001 - Heading levels should only increment by one level at a time
  MD001: true

  # MD003 - Heading style: ATX
  MD003:
    style: "atx"

  # MD009 - No trailing spaces
  MD009:
    br_spaces: 2

  # MD012 - No multiple consecutive blank lines
  MD012:
    maximum: 2

  # MD013 - Line length
  MD013:
    line_length: 120
    heading_line_length: 80
    tables: false
    code_blocks: false

  # MD024 - No duplicate headings
  MD024:
    siblings_only: true

  # MD033 - Allow inline HTML for callout boxes
  MD033:
    allowed_elements:
      - "details"
      - "summary"
      - "br"
      - "sub"
      - "sup"

  # MD036 - No emphasis used instead of a heading
  MD036: true

  # MD041 - First line should be a top-level heading
  MD041: true

  # MD046 - Code block style: fenced
  MD046:
    style: "fenced"

  # MD048 - Code fence style: backtick
  MD048:
    style: "backtick"

globs:
  - "docs/**/*.md"
  - "*.md"

ignores:
  - "node_modules/**"
  - ".build/**"
  - "docs-output/**"
```

**Usage in CI**:

```bash
# Lint all markdown files
docker run --rm \
    -v "$(pwd):/workspace:ro" \
    hushtype/markdownlint:latest

# Check for broken links in documentation
docker run --rm \
    -v "$(pwd):/workspace:ro" \
    --entrypoint markdown-link-check \
    hushtype/markdownlint:latest \
    --config /workspace/.markdown-link-check.json \
    /workspace/docs/**/*.md
```

### 3.5 Docker Compose for All CI Services

A single `docker-compose.yml` orchestrates all CI containers for local development
and testing.

**`docker/docker-compose.ci.yml`**:

```yaml
# HushType CI/CD Docker Compose Configuration
# Usage: docker compose -f docker/docker-compose.ci.yml run <service>

version: "3.9"

services:
  # -------------------------------------------------------
  # Swift Linting
  # -------------------------------------------------------
  swiftlint:
    build:
      context: ..
      dockerfile: docker/swiftlint/Dockerfile
    image: hushtype/swiftlint:latest
    volumes:
      - ..:/workspace:ro
    working_dir: /workspace
    command: ["lint", "--strict", "--config", ".swiftlint.yml"]

  # -------------------------------------------------------
  # Swift Formatting
  # -------------------------------------------------------
  swift-format:
    build:
      context: ..
      dockerfile: docker/swift-format/Dockerfile
    image: hushtype/swift-format:latest
    volumes:
      - ..:/workspace:ro
    working_dir: /workspace
    command: ["lint", "--strict", "--recursive", "Sources/", "Tests/"]

  swift-format-fix:
    build:
      context: ..
      dockerfile: docker/swift-format/Dockerfile
    image: hushtype/swift-format:latest
    volumes:
      - ..:/workspace
    working_dir: /workspace
    command: ["format", "--in-place", "--recursive", "Sources/", "Tests/"]
    profiles:
      - fix

  # -------------------------------------------------------
  # Markdown Linting
  # -------------------------------------------------------
  markdownlint:
    build:
      context: ..
      dockerfile: docker/markdownlint/Dockerfile
    image: hushtype/markdownlint:latest
    volumes:
      - ..:/workspace:ro
    working_dir: /workspace

  link-check:
    build:
      context: ..
      dockerfile: docker/markdownlint/Dockerfile
    image: hushtype/markdownlint:latest
    volumes:
      - ..:/workspace:ro
    working_dir: /workspace
    entrypoint: ["markdown-link-check"]
    command:
      - "--config"
      - ".markdown-link-check.json"
      - "--quiet"
      - "docs/"
    profiles:
      - full

  # -------------------------------------------------------
  # Documentation Generation
  # -------------------------------------------------------
  docs-generator:
    build:
      context: ..
      dockerfile: docker/docs-generator/Dockerfile
    image: hushtype/docs-generator:latest
    volumes:
      - ..:/workspace
    working_dir: /workspace
    environment:
      - DOC_COVERAGE_THRESHOLD=90

  # -------------------------------------------------------
  # Model Testing (CPU-only)
  # -------------------------------------------------------
  model-test:
    build:
      context: ..
      dockerfile: docker/model-test/Dockerfile
    image: hushtype/model-test:latest
    volumes:
      - ..:/workspace:ro
      - model-cache:/models
    working_dir: /workspace
    environment:
      - WHISPER_MODEL_PATH=/models/whisper-tiny.bin
      - LLAMA_MODEL_PATH=/models/llama-test.gguf
      - HUSHTYPE_FORCE_CPU=1
      - HUSHTYPE_TEST_MODE=1
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: "2.0"

  # -------------------------------------------------------
  # Dependency Auditing
  # -------------------------------------------------------
  dependency-audit:
    image: swift:5.9-jammy
    volumes:
      - ..:/workspace:ro
    working_dir: /workspace
    command: >
      bash -c "
        swift package show-dependencies --format json > /tmp/deps.json &&
        echo 'Dependency tree generated successfully' &&
        swift package audit
      "
    profiles:
      - security

volumes:
  model-cache:
    driver: local
```

**Running CI services locally**:

```bash
# Run all default checks
docker compose -f docker/docker-compose.ci.yml up --abort-on-container-exit

# Run individual services
docker compose -f docker/docker-compose.ci.yml run swiftlint
docker compose -f docker/docker-compose.ci.yml run swift-format
docker compose -f docker/docker-compose.ci.yml run markdownlint

# Run with auto-fix profile
docker compose -f docker/docker-compose.ci.yml --profile fix run swift-format-fix

# Run security audit
docker compose -f docker/docker-compose.ci.yml --profile security run dependency-audit

# Run everything including optional checks
docker compose -f docker/docker-compose.ci.yml --profile full --profile security up \
    --abort-on-container-exit
```

---

## 4. Model Testing in CI Environments

### 4.1 Testing Without Metal GPU

HushType's speech recognition (whisper.cpp) and text processing (llama.cpp) engines
are optimized for Metal GPU acceleration on macOS. In CI Docker containers running
on Linux, Metal is unavailable. The testing strategy addresses this limitation:

> :warning: **Important**: CI model tests validate correctness and regression detection,
> **not** performance benchmarks. Performance testing must be done on macOS runners
> with Metal GPU access. See `../testing/TESTING.md` for the full testing strategy.

**Testing matrix**:

| Test Category | Docker (CPU) | macOS Runner (Metal) |
|---|---|---|
| Model loading / initialization | :white_check_mark: | :white_check_mark: |
| Audio preprocessing pipeline | :white_check_mark: | :white_check_mark: |
| Transcription accuracy (tiny model) | :white_check_mark: | :white_check_mark: |
| Transcription accuracy (large model) | :x: Too slow | :white_check_mark: |
| LLM text processing | :white_check_mark: (small model) | :white_check_mark: |
| Inference latency benchmarks | :x: Not meaningful | :white_check_mark: |
| Memory usage profiling | :white_check_mark: Approximate | :white_check_mark: |
| Model format validation | :white_check_mark: | :white_check_mark: |
| Quantization verification | :white_check_mark: | :white_check_mark: |

### 4.2 CPU-Only Fallback Testing

HushType's inference engine includes a CPU fallback path used when Metal is unavailable.
The Docker CI environment exercises this path to ensure it remains functional.

**CPU fallback test configuration** (`Tests/ModelTests/CPUFallbackTests.swift`):

```swift
import XCTest
@testable import HushType

/// Tests for CPU-only inference fallback path.
///
/// These tests are designed to run in CI Docker containers where
/// Metal GPU is not available. They validate that the inference
/// engine correctly falls back to CPU computation.
final class CPUFallbackTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Force CPU-only mode (no Metal)
        ProcessInfo.processInfo.environment["HUSHTYPE_FORCE_CPU"] = "1"
    }

    func testWhisperCPUInference() throws {
        let config = WhisperConfig(
            modelPath: TestFixtures.whisperTinyModelPath,
            useGPU: false,
            threads: 2
        )

        let engine = try WhisperEngine(config: config)
        XCTAssertFalse(engine.isUsingMetal)
        XCTAssertEqual(engine.computeDevice, .cpu)

        // Test with a short audio sample (1 second of speech)
        let audioSamples = try TestFixtures.loadAudioSamples("hello_world_16khz")
        let result = try engine.transcribe(audioSamples)

        XCTAssertFalse(result.text.isEmpty)
        // CPU transcription of tiny model should complete within 10 seconds
        XCTAssertLessThan(result.processingTime, 10.0)
    }

    func testLlamaCPUInference() throws {
        let config = LlamaConfig(
            modelPath: TestFixtures.llamaTestModelPath,
            useGPU: false,
            threads: 2,
            contextSize: 512
        )

        let engine = try LlamaEngine(config: config)
        XCTAssertFalse(engine.isUsingMetal)

        let result = try engine.process(
            text: "fix the grammar: i goes to the store yesterday",
            task: .grammarCorrection
        )

        XCTAssertFalse(result.text.isEmpty)
        XCTAssertLessThan(result.processingTime, 30.0)
    }

    func testMetalUnavailableGracefulDegradation() throws {
        // Simulate Metal being unavailable (as in Docker)
        let config = WhisperConfig(
            modelPath: TestFixtures.whisperTinyModelPath,
            useGPU: true  // Request GPU, but it's unavailable
        )

        let engine = try WhisperEngine(config: config)

        // Engine should gracefully fall back to CPU
        XCTAssertFalse(engine.isUsingMetal)
        XCTAssertEqual(engine.computeDevice, .cpu)

        // Should still produce valid output
        let audioSamples = try TestFixtures.loadAudioSamples("hello_world_16khz")
        let result = try engine.transcribe(audioSamples)
        XCTAssertFalse(result.text.isEmpty)
    }
}
```

### 4.3 Mock Model Testing

For faster CI runs and tests that do not require actual model inference, HushType
provides mock model implementations:

**Mock inference engine** (`Tests/Mocks/MockWhisperEngine.swift`):

```swift
import Foundation
@testable import HushType

/// Mock WhisperEngine for CI testing without real model files.
///
/// Returns predetermined transcription results based on audio
/// characteristics, enabling fast unit tests that validate the
/// transcription pipeline without actual inference.
final class MockWhisperEngine: WhisperEngineProtocol {

    var isUsingMetal: Bool = false
    var computeDevice: ComputeDevice = .cpu

    /// Predefined responses for test scenarios
    private let mockResponses: [String: String] = [
        "hello_world": "Hello, world.",
        "quick_brown_fox": "The quick brown fox jumps over the lazy dog.",
        "silence": "",
        "noise": "[inaudible]",
        "multilingual": "Bonjour le monde."
    ]

    private let simulatedLatency: TimeInterval

    init(simulatedLatency: TimeInterval = 0.1) {
        self.simulatedLatency = simulatedLatency
    }

    func transcribe(_ samples: [Float]) throws -> TranscriptionResult {
        // Simulate processing time
        Thread.sleep(forTimeInterval: simulatedLatency)

        // Determine mock response based on sample characteristics
        let sampleKey = determineSampleType(samples)
        let text = mockResponses[sampleKey] ?? "Mock transcription result."

        return TranscriptionResult(
            text: text,
            segments: [
                TranscriptionSegment(
                    text: text,
                    startTime: 0.0,
                    endTime: Double(samples.count) / 16000.0,
                    confidence: 0.95
                )
            ],
            processingTime: simulatedLatency,
            modelUsed: "mock-tiny",
            computeDevice: .cpu
        )
    }

    private func determineSampleType(_ samples: [Float]) -> String {
        let maxAmplitude = samples.map { abs($0) }.max() ?? 0
        if maxAmplitude < 0.01 { return "silence" }
        if samples.count < 8000 { return "hello_world" }
        return "quick_brown_fox"
    }
}
```

**When to use mock vs. real models in CI**:

| Scenario | Use Mock | Use Real (CPU) |
|---|---|---|
| Unit tests for pipeline logic | :white_check_mark: | |
| Integration tests for transcription accuracy | | :white_check_mark: |
| UI component tests | :white_check_mark: | |
| Regression tests for known transcriptions | | :white_check_mark: |
| Performance regression detection | | :white_check_mark: (CPU baseline) |
| Error handling tests | :white_check_mark: | |
| Model loading and format validation | | :white_check_mark: |

### 4.4 Model Testing Docker Setup

**Dockerfile** (`docker/model-test/Dockerfile`):

```dockerfile
# HushType Model Testing CI Container
# Purpose: CPU-only inference testing for whisper.cpp and llama.cpp

FROM swift:5.9-jammy

# Install build dependencies for whisper.cpp and llama.cpp
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        git \
        curl \
        wget \
        libopenblas-dev \
        pkg-config \
        python3 \
        python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Build whisper.cpp for CPU-only (no Metal, no CUDA)
ARG WHISPER_CPP_VERSION=v1.6.2
RUN git clone --branch ${WHISPER_CPP_VERSION} --depth 1 \
        https://github.com/ggerganov/whisper.cpp.git /opt/whisper.cpp \
    && cd /opt/whisper.cpp \
    && cmake -B build \
        -DWHISPER_NO_METAL=ON \
        -DWHISPER_NO_CUDA=ON \
        -DWHISPER_OPENBLAS=ON \
        -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build --config Release -j$(nproc) \
    && cmake --install build

# Build llama.cpp for CPU-only (no Metal, no CUDA)
ARG LLAMA_CPP_VERSION=b2500
RUN git clone --branch ${LLAMA_CPP_VERSION} --depth 1 \
        https://github.com/ggerganov/llama.cpp.git /opt/llama.cpp \
    && cd /opt/llama.cpp \
    && cmake -B build \
        -DLLAMA_METAL=OFF \
        -DLLAMA_CUDA=OFF \
        -DLLAMA_BLAS=ON \
        -DLLAMA_BLAS_VENDOR=OpenBLAS \
        -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build --config Release -j$(nproc) \
    && cmake --install build

# Download tiny test models (small enough for CI)
RUN mkdir -p /models \
    && cd /opt/whisper.cpp \
    && bash models/download-ggml-model.sh tiny.en \
    && cp models/ggml-tiny.en.bin /models/whisper-tiny.bin

# Create non-root user
RUN useradd --create-home --shell /bin/bash ciuser \
    && chown -R ciuser:ciuser /models
USER ciuser
WORKDIR /workspace

# Environment variables for test configuration
ENV WHISPER_MODEL_PATH=/models/whisper-tiny.bin
ENV HUSHTYPE_FORCE_CPU=1
ENV HUSHTYPE_TEST_MODE=1

LABEL org.opencontainers.image.title="HushType Model Test"
LABEL org.opencontainers.image.description="CPU-only model testing container for HushType"

ENTRYPOINT ["swift", "test"]
CMD ["--filter", "ModelTests"]
```

**Model test runner script** (`docker/model-test/scripts/run-model-tests.sh`):

```bash
#!/usr/bin/env bash
set -euo pipefail

# HushType Model Test Runner
# Runs CPU-only model tests in Docker CI environment

echo "=== HushType Model Test Runner ==="
echo "Whisper model: ${WHISPER_MODEL_PATH}"
echo "Force CPU mode: ${HUSHTYPE_FORCE_CPU}"
echo "Test mode: ${HUSHTYPE_TEST_MODE}"
echo ""

# Verify model files exist
echo "--- Verifying model files ---"
if [ ! -f "${WHISPER_MODEL_PATH}" ]; then
    echo "ERROR: Whisper model not found at ${WHISPER_MODEL_PATH}"
    exit 1
fi
echo "Whisper model: $(du -h "${WHISPER_MODEL_PATH}" | cut -f1)"

if [ -n "${LLAMA_MODEL_PATH:-}" ] && [ -f "${LLAMA_MODEL_PATH}" ]; then
    echo "Llama model: $(du -h "${LLAMA_MODEL_PATH}" | cut -f1)"
fi

# Run model validation tests
echo ""
echo "--- Running model validation tests ---"
swift test \
    --filter "ModelValidationTests" \
    --parallel \
    2>&1

# Run CPU inference tests
echo ""
echo "--- Running CPU inference tests ---"
swift test \
    --filter "CPUFallbackTests" \
    --parallel \
    2>&1

# Run mock model tests (always fast)
echo ""
echo "--- Running mock model tests ---"
swift test \
    --filter "MockModelTests" \
    --parallel \
    2>&1

echo ""
echo "=== All model tests passed ==="
```

### 4.5 Model Validation Pipeline

The model validation pipeline checks that model files are correctly formatted and
compatible with HushType before they are bundled with the application:

```bash
#!/usr/bin/env bash
set -euo pipefail

# validate-models.sh
# Validates model files for format correctness and compatibility

MODEL_DIR="${1:-/models}"
RESULTS_FILE="/tmp/model-validation-results.json"

echo "=== Model Validation Pipeline ==="
echo "Model directory: ${MODEL_DIR}"

PASS=0
FAIL=0

validate_whisper_model() {
    local model_path="$1"
    local model_name
    model_name=$(basename "${model_path}")

    echo ""
    echo "--- Validating Whisper model: ${model_name} ---"

    # Check file exists and is non-empty
    if [ ! -s "${model_path}" ]; then
        echo "FAIL: Model file is empty or missing"
        ((FAIL++))
        return
    fi

    # Check GGML magic number (first 4 bytes)
    local magic
    magic=$(xxd -l 4 -p "${model_path}")
    if [ "${magic}" != "67676d6c" ] && [ "${magic}" != "67676d66" ]; then
        echo "FAIL: Invalid model format (magic: ${magic})"
        ((FAIL++))
        return
    fi

    # Run a minimal inference test
    if command -v whisper-cli &> /dev/null; then
        echo "Running minimal inference test..."
        timeout 30 whisper-cli \
            -m "${model_path}" \
            -f /opt/whisper.cpp/samples/jfk.wav \
            --no-timestamps \
            -t 2 \
            > /dev/null 2>&1

        if [ $? -eq 0 ]; then
            echo "PASS: Inference test succeeded"
            ((PASS++))
        else
            echo "FAIL: Inference test failed"
            ((FAIL++))
        fi
    else
        echo "SKIP: whisper-cli not available for inference test"
        ((PASS++))
    fi
}

# Validate all whisper models
for model in "${MODEL_DIR}"/whisper-*.bin; do
    [ -f "${model}" ] && validate_whisper_model "${model}"
done

echo ""
echo "=== Validation Complete ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"

if [ "${FAIL}" -gt 0 ]; then
    echo "ERROR: ${FAIL} model(s) failed validation"
    exit 1
fi
```

---

## 5. GitHub Actions Integration

### 5.1 Workflow Overview

HushType's GitHub Actions CI uses Docker containers for linting and model testing
on Linux runners, while reserving macOS runners for builds and platform-specific tests.

> :information_source: **Note**: For the complete CI/CD pipeline documentation, including
> deployment workflows, code signing, and release automation, see `CI_CD.md`.

### 5.2 Lint and Format Workflow

**`.github/workflows/lint.yml`**:

```yaml
# HushType Lint and Format CI
# Runs SwiftLint, swift-format, and markdownlint in Docker containers

name: Lint & Format

on:
  pull_request:
    branches: [main, develop]
    paths:
      - "Sources/**/*.swift"
      - "Tests/**/*.swift"
      - "docs/**/*.md"
      - "*.md"
      - ".swiftlint.yml"
      - ".swift-format.json"
  push:
    branches: [main]

concurrency:
  group: lint-${{ github.ref }}
  cancel-in-progress: true

jobs:
  swiftlint:
    name: SwiftLint
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/hushtype/swiftlint:latest
      credentials:
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Run SwiftLint
        run: |
          swiftlint lint \
            --strict \
            --config .swiftlint.yml \
            --reporter github-actions-logging

  swift-format:
    name: Swift Format
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/hushtype/swift-format:latest
      credentials:
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Check formatting
        run: |
          swift-format lint \
            --strict \
            --recursive \
            --configuration .swift-format.json \
            Sources/ Tests/

  markdownlint:
    name: Markdown Lint
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/hushtype/markdownlint:latest
      credentials:
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Lint markdown files
        run: markdownlint-cli2 "docs/**/*.md" "*.md"

      - name: Check links
        if: github.event_name == 'pull_request'
        run: |
          markdown-link-check \
            --config .markdown-link-check.json \
            --quiet \
            $(find docs -name '*.md' -type f)

  docs-coverage:
    name: Documentation Coverage
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/hushtype/docs-generator:latest
      credentials:
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Check documentation coverage
        run: generate-docs /workspace
        env:
          DOC_COVERAGE_THRESHOLD: "90"

      - name: Upload documentation artifacts
        if: github.ref == 'refs/heads/main'
        uses: actions/upload-artifact@v4
        with:
          name: api-docs
          path: docs-output/
          retention-days: 30
```

### 5.3 Model Testing Workflow

**`.github/workflows/model-tests.yml`**:

```yaml
# HushType Model Testing CI
# Runs CPU-only inference tests in Docker containers

name: Model Tests

on:
  pull_request:
    branches: [main, develop]
    paths:
      - "Sources/Whisper/**"
      - "Sources/Llama/**"
      - "Sources/Inference/**"
      - "Tests/ModelTests/**"
  push:
    branches: [main]
  schedule:
    # Run nightly to catch model regressions
    - cron: "0 3 * * *"

concurrency:
  group: model-tests-${{ github.ref }}
  cancel-in-progress: true

jobs:
  cpu-inference-tests:
    name: CPU Inference Tests
    runs-on: ubuntu-latest
    timeout-minutes: 30

    services:
      model-cache:
        image: ghcr.io/hushtype/model-cache:latest
        credentials:
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

    container:
      image: ghcr.io/hushtype/model-test:latest
      credentials:
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
      options: --memory=4g --cpus=2
      env:
        WHISPER_MODEL_PATH: /models/whisper-tiny.bin
        HUSHTYPE_FORCE_CPU: "1"
        HUSHTYPE_TEST_MODE: "1"

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Verify model files
        run: |
          echo "Checking model files..."
          ls -lh /models/
          echo "Whisper model size: $(du -h ${WHISPER_MODEL_PATH} | cut -f1)"

      - name: Run model validation tests
        run: |
          swift test \
            --filter "ModelValidationTests" \
            --parallel

      - name: Run CPU fallback tests
        run: |
          swift test \
            --filter "CPUFallbackTests" \
            --parallel

      - name: Run mock model tests
        run: |
          swift test \
            --filter "MockModelTests" \
            --parallel

      - name: Generate test report
        if: always()
        run: |
          swift test \
            --filter "ModelTests" \
            --parallel \
            2>&1 | tee test-results.log

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: model-test-results
          path: test-results.log
          retention-days: 14

  mock-model-tests:
    name: Mock Model Tests
    runs-on: ubuntu-latest
    timeout-minutes: 10
    container:
      image: swift:5.9-jammy

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Run mock tests
        run: |
          swift test \
            --filter "MockModelTests" \
            --parallel
        env:
          HUSHTYPE_TEST_MODE: "1"
          HUSHTYPE_USE_MOCK_MODELS: "1"
```

### 5.4 Full CI Pipeline Workflow

**`.github/workflows/ci.yml`** (Docker-related jobs only):

```yaml
# HushType Full CI Pipeline
# Combines Docker-based checks with macOS builds
# See CI_CD.md for complete documentation

name: CI

on:
  pull_request:
    branches: [main, develop]
  push:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  # =======================================================
  # Track A: Docker-based checks (Linux runners)
  # =======================================================

  lint:
    name: Lint & Format
    uses: ./.github/workflows/lint.yml
    secrets: inherit

  model-tests:
    name: Model Tests
    uses: ./.github/workflows/model-tests.yml
    secrets: inherit

  dependency-audit:
    name: Dependency Audit
    runs-on: ubuntu-latest
    container:
      image: swift:5.9-jammy
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Resolve dependencies
        run: swift package resolve

      - name: Audit dependencies
        run: |
          swift package show-dependencies --format json \
            > dependency-tree.json
          echo "Dependency tree generated"
          # Check for known vulnerabilities
          swift package audit 2>&1 || true

      - name: Upload dependency report
        uses: actions/upload-artifact@v4
        with:
          name: dependency-report
          path: dependency-tree.json
          retention-days: 7

  # =======================================================
  # Track B: macOS-specific builds (macOS runners)
  # These jobs do NOT use Docker
  # =======================================================

  build-macos:
    name: Build (macOS)
    runs-on: macos-14
    needs: [lint]
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.2.app

      - name: Build
        run: |
          xcodebuild build \
            -scheme HushType \
            -destination "platform=macOS,arch=arm64" \
            -configuration Debug \
            CODE_SIGNING_ALLOWED=NO

  test-macos:
    name: Tests (macOS)
    runs-on: macos-14
    needs: [build-macos]
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.2.app

      - name: Run tests
        run: |
          xcodebuild test \
            -scheme HushType \
            -destination "platform=macOS,arch=arm64" \
            -configuration Debug \
            CODE_SIGNING_ALLOWED=NO \
            -resultBundlePath TestResults.xcresult

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results-macos
          path: TestResults.xcresult
          retention-days: 14

  # =======================================================
  # Gate: All checks must pass
  # =======================================================

  ci-gate:
    name: CI Gate
    runs-on: ubuntu-latest
    needs:
      - lint
      - model-tests
      - dependency-audit
      - test-macos
    if: always()
    steps:
      - name: Check all jobs
        run: |
          if [[ "${{ needs.lint.result }}" != "success" ]] ||
             [[ "${{ needs.model-tests.result }}" != "success" ]] ||
             [[ "${{ needs.test-macos.result }}" != "success" ]]; then
            echo "One or more required checks failed"
            exit 1
          fi
          echo "All CI checks passed"
```

---

## 6. Docker Image Management

### 6.1 Building and Pushing Images

All HushType CI Docker images are stored in GitHub Container Registry (GHCR).

**Build and push script** (`docker/build-and-push.sh`):

```bash
#!/usr/bin/env bash
set -euo pipefail

# Build and push all HushType CI Docker images to GHCR

REGISTRY="ghcr.io/hushtype"
VERSION="${1:-latest}"

echo "=== Building HushType CI Images ==="
echo "Registry: ${REGISTRY}"
echo "Version: ${VERSION}"
echo ""

IMAGES=(
    "swiftlint:docker/swiftlint/Dockerfile"
    "swift-format:docker/swift-format/Dockerfile"
    "markdownlint:docker/markdownlint/Dockerfile"
    "docs-generator:docker/docs-generator/Dockerfile"
    "model-test:docker/model-test/Dockerfile"
)

for entry in "${IMAGES[@]}"; do
    IFS=':' read -r name dockerfile <<< "${entry}"

    echo "--- Building ${name}:${VERSION} ---"
    docker build \
        --tag "${REGISTRY}/${name}:${VERSION}" \
        --tag "${REGISTRY}/${name}:latest" \
        --file "${dockerfile}" \
        --label "org.opencontainers.image.version=${VERSION}" \
        --label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        .

    echo "--- Pushing ${name}:${VERSION} ---"
    docker push "${REGISTRY}/${name}:${VERSION}"
    docker push "${REGISTRY}/${name}:latest"

    echo ""
done

echo "=== All images built and pushed ==="
```

**GitHub Actions workflow for image building** (`.github/workflows/docker-images.yml`):

```yaml
# Build and push CI Docker images when Dockerfiles change

name: Docker Images

on:
  push:
    branches: [main]
    paths:
      - "docker/**"
  workflow_dispatch:

permissions:
  packages: write
  contents: read

jobs:
  build-images:
    name: Build CI Images
    runs-on: ubuntu-latest
    strategy:
      matrix:
        image:
          - name: swiftlint
            dockerfile: docker/swiftlint/Dockerfile
          - name: swift-format
            dockerfile: docker/swift-format/Dockerfile
          - name: markdownlint
            dockerfile: docker/markdownlint/Dockerfile
          - name: docs-generator
            dockerfile: docker/docs-generator/Dockerfile
          - name: model-test
            dockerfile: docker/model-test/Dockerfile

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/hushtype/${{ matrix.image.name }}
          tags: |
            type=sha
            type=raw,value=latest

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ${{ matrix.image.dockerfile }}
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

### 6.2 Image Versioning Strategy

HushType CI images follow a consistent versioning scheme:

| Tag Format | Example | Description |
|---|---|---|
| `latest` | `hushtype/swiftlint:latest` | Most recent build from `main` |
| `sha-<commit>` | `hushtype/swiftlint:sha-abc1234` | Pinned to specific commit |
| `v<semver>` | `hushtype/swiftlint:v1.2.0` | Tagged release version |
| `<tool-version>` | `hushtype/swiftlint:0.55.1` | Pinned to tool version |

> :bulb: **Tip**: For reproducible CI builds, pin to a specific `sha-` tag in your
> workflows rather than using `latest`. Update the pinned tag periodically after
> verifying the new image works correctly.

### 6.3 Image Security Scanning

All CI images are scanned for vulnerabilities before being pushed to the registry:

```yaml
# Added to docker-images.yml build job
      - name: Scan for vulnerabilities
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ghcr.io/hushtype/${{ matrix.image.name }}:latest
          format: "sarif"
          output: "trivy-results.sarif"
          severity: "CRITICAL,HIGH"

      - name: Upload scan results
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: "trivy-results.sarif"
```

---

## 7. Local Development with Docker

### 7.1 Running CI Checks Locally

Developers can run the same CI checks locally before pushing changes, ensuring
that PRs pass on the first attempt.

```bash
# Run all linting checks (same as CI)
docker compose -f docker/docker-compose.ci.yml run swiftlint
docker compose -f docker/docker-compose.ci.yml run swift-format
docker compose -f docker/docker-compose.ci.yml run markdownlint

# Run all checks in parallel
docker compose -f docker/docker-compose.ci.yml up \
    swiftlint swift-format markdownlint \
    --abort-on-container-exit

# Auto-fix formatting issues
docker compose -f docker/docker-compose.ci.yml --profile fix run swift-format-fix

# Run CPU model tests locally
docker compose -f docker/docker-compose.ci.yml run model-test

# Run everything
docker compose -f docker/docker-compose.ci.yml \
    --profile full --profile security up \
    --abort-on-container-exit
```

> :warning: **Note**: Running model tests locally requires downloading model files
> (approximately 75 MB for the tiny model). The first run will be slower as Docker
> downloads and caches the model files in a named volume.

### 7.2 Pre-Commit Hook Integration

Integrate Docker-based linting into Git pre-commit hooks for automatic checks:

**`.githooks/pre-commit`**:

```bash
#!/usr/bin/env bash
set -euo pipefail

# HushType Pre-Commit Hook
# Runs SwiftLint and swift-format checks via Docker

echo "Running pre-commit checks..."

# Get list of staged Swift files
STAGED_SWIFT_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.swift$' || true)
STAGED_MD_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.md$' || true)

if [ -n "${STAGED_SWIFT_FILES}" ]; then
    echo "Checking Swift files..."

    # Run SwiftLint on staged files only
    echo "${STAGED_SWIFT_FILES}" | xargs docker run --rm \
        -v "$(pwd):/workspace:ro" \
        hushtype/swiftlint:latest \
        lint --strict --config /workspace/.swiftlint.yml --path

    if [ $? -ne 0 ]; then
        echo "SwiftLint check failed. Please fix the issues above."
        exit 1
    fi

    # Run swift-format check on staged files only
    echo "${STAGED_SWIFT_FILES}" | xargs docker run --rm \
        -v "$(pwd):/workspace:ro" \
        hushtype/swift-format:latest \
        lint --strict --configuration /workspace/.swift-format.json

    if [ $? -ne 0 ]; then
        echo "swift-format check failed. Run 'make format' to fix."
        exit 1
    fi
fi

if [ -n "${STAGED_MD_FILES}" ]; then
    echo "Checking Markdown files..."

    docker run --rm \
        -v "$(pwd):/workspace:ro" \
        hushtype/markdownlint:latest \
        ${STAGED_MD_FILES}

    if [ $? -ne 0 ]; then
        echo "Markdown lint check failed. Please fix the issues above."
        exit 1
    fi
fi

echo "Pre-commit checks passed."
```

**Setup instructions**:

```bash
# Configure Git to use the custom hooks directory
git config core.hooksPath .githooks

# Make the hook executable
chmod +x .githooks/pre-commit

# Verify the hook is active
git hooks list
```

---

## 8. Troubleshooting

**Common issues and solutions**:

| Issue | Cause | Solution |
|---|---|---|
| SwiftLint fails with "unsupported platform" | Using macOS-compiled SwiftLint binary on Linux | Use the Docker image which builds SwiftLint from source for Linux |
| Model tests timeout | CPU inference is slow for larger models | Use `whisper-tiny` model in CI; set `timeout-minutes: 30` |
| Docker build fails on Apple Silicon Mac | Docker Desktop defaults to ARM64 | Add `--platform linux/amd64` to build commands |
| Model cache not persisting between runs | Docker volume not configured | Use named volumes in `docker-compose.ci.yml` |
| GHCR authentication fails | Missing or expired token | Re-authenticate with `docker login ghcr.io` |
| swift-format version mismatch | Local and CI versions differ | Pin versions in Dockerfiles and `.swift-format.json` |
| Out of memory during model tests | Default container memory too low | Set `--memory=4g` in container options |
| Markdown link check fails on internal links | Relative paths not resolved in Docker | Mount the full repo and use `--base /workspace` flag |

**Debugging Docker CI containers locally**:

```bash
# Run a container interactively for debugging
docker run -it --rm \
    -v "$(pwd):/workspace" \
    --entrypoint /bin/bash \
    hushtype/swiftlint:latest

# Check container logs
docker compose -f docker/docker-compose.ci.yml logs swiftlint

# Inspect a running container
docker compose -f docker/docker-compose.ci.yml exec model-test /bin/bash

# View resource usage of CI containers
docker stats
```

> :bulb: **Tip**: When debugging CI failures, replicate the exact Docker environment
> locally by using the same image tag that CI uses. Check the GitHub Actions log for
> the exact image reference (e.g., `ghcr.io/hushtype/swiftlint:sha-abc1234`).

---

## Related Documentation

| Document | Description |
|---|---|
| [`CI_CD.md`](CI_CD.md) | Complete CI/CD pipeline configuration and deployment workflows |
| [`DEPLOYMENT_GUIDE.md`](DEPLOYMENT_GUIDE.md) | macOS app deployment, code signing, and notarization |
| [`../testing/TESTING.md`](../testing/TESTING.md) | Full testing strategy including Metal GPU tests and UI tests |
| [`../security/LEGAL_COMPLIANCE.md`](../security/LEGAL_COMPLIANCE.md) | Legal compliance including macOS EULA considerations |
| [`../architecture/TECH_STACK.md`](../architecture/TECH_STACK.md) | Technology stack details for whisper.cpp and llama.cpp integration |
| [`../features/SPEECH_RECOGNITION.md`](../features/SPEECH_RECOGNITION.md) | Speech recognition engine architecture and model requirements |
| [`../features/LLM_PROCESSING.md`](../features/LLM_PROCESSING.md) | LLM processing pipeline and model management |
| [`../features/MODEL_MANAGEMENT.md`](../features/MODEL_MANAGEMENT.md) | Model download, caching, and validation |
| [`SCALING_GUIDE.md`](SCALING_GUIDE.md) | Infrastructure scaling considerations |
