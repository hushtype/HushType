# HushType Privacy Verification Protocol

## Overview

### Purpose

This document defines a reproducible test protocol for verifying HushType's core privacy claim: **all speech-to-text transcription, LLM post-processing, voice command execution, and text injection happen 100% on-device with zero outbound network connections.**

The protocol is designed to be run before each release and by any contributor who modifies the audio pipeline, model inference code, or any service that touches user speech or transcribed text.

### Scope

- Core dictation pipeline (audio capture → whisper inference → LLM processing → text injection)
- Voice command execution
- Application startup and shutdown
- Sparkle update checks (expected, must be isolated to appcast URL only)
- Model registry refresh (expected, must be isolated to GitHub raw content only)
- Model file downloads (expected, must be isolated to huggingface.co and mirror URLs only)

### Privacy Architecture Summary

HushType uses two local C libraries bridged into Swift:

- **whisper.cpp** (`HushType/Services/Speech/WhisperContext.swift`) — performs speech-to-text inference entirely in-process using loaded GGUF/GGML model files
- **llama.cpp** (`HushType/Services/LLM/LlamaContext.swift`) — performs LLM text post-processing entirely in-process using loaded GGUF model files

Neither library opens network sockets. Both operate exclusively on memory buffers and local files.

The entitlements file (`HushType/HushType.entitlements`) grants the following capabilities:

- `com.apple.security.device.audio-input` — microphone access
- `com.apple.security.device.gpu` — Metal GPU acceleration
- `com.apple.security.automation.apple-events` — AppleScript for system commands
- `com.apple.security.cs.disable-library-validation` — C library loading
- `com.apple.security.cs.allow-jit` — llama.cpp JIT compilation
- `com.apple.security.cs.allow-unsigned-executable-memory` — whisper.cpp memory needs

Notably absent: `com.apple.security.network.client` and `com.apple.security.network.server`. The app does not declare outbound or inbound network entitlements at the sandbox level. Network access used by `URLSession` (for model downloads and registry refresh) operates under the default macOS app networking without a hardened sandbox network entitlement.

---

## Expected Network Connections

The following network connections are explicitly expected and must be the **only** connections HushType ever makes. Any connection not on this list is a privacy violation.

| Connection | Host | Trigger | Frequency | User-Initiated |
|---|---|---|---|---|
| Model file download | `huggingface.co` | User taps Download in Settings → Models | On demand only | Yes |
| Model file download (mirror) | Mirror URLs defined in model manifest | Fallback if primary fails | On demand only | Yes |
| Model registry manifest | `raw.githubusercontent.com` (repo: `hushtype/HushType`, path: `registry/models.json`) | App launch (once per `Constants.Registry.refreshIntervalSeconds`) | Periodic, configurable | No (background) |
| Sparkle update check | `harungungorer.github.io` (path: `/HushType/appcast.xml`) | Configured by `SUEnableAutomaticChecks` in `Info.plist` | Periodic (Sparkle default: 24 hours) | No (background) |
| Sparkle delta/release download | GitHub Releases CDN | User approves an update | On demand only | Yes |

### Connections That Must Never Occur

- Any connection during an active dictation session
- Any connection carrying audio data, transcribed text, or processed text
- Any connection to analytics, telemetry, or crash reporting services
- Any connection to third-party LLM APIs (OpenAI, Anthropic, etc.)
- Any connection not listed in the table above

---

## Test Environment Setup

### Prerequisites

- macOS 14.0 or later (Sonoma)
- HushType built in Debug or Release configuration
- At least one whisper model downloaded and loaded
- At least one LLM model downloaded and loaded (for LLM processing tests)
- Terminal access with administrator privileges (for `tcpdump`)

### Option A: nettop (Recommended for Quick Checks)

`nettop` provides a live, process-filtered view of network activity. Run it in a dedicated terminal window before launching HushType.

```bash
# Monitor HushType network connections in real time.
# Replace PID with the actual HushType process ID after launch.
sudo nettop -p <PID> -m tcp -d

# Or filter by process name (requires nettop 1.6+, macOS 14+):
sudo nettop -n HushType -m tcp
```

To find the PID after launch:

```bash
pgrep -x HushType
```

**Reading nettop output:** Each row is a connection. Columns show bytes in/out, state, and remote host. During core dictation, the list must be empty or show only loopback (127.0.0.1) entries.

### Option B: tcpdump (Recommended for Full Packet Capture)

`tcpdump` captures all packets at the network interface level, producing evidence suitable for audit.

```bash
# Capture all traffic from HushType to a pcap file.
# Run this before launching HushType.
sudo tcpdump -i en0 -w /tmp/hushtype-capture.pcap &
TCPDUMP_PID=$!

# ... run test scenario ...

# Stop capture and inspect.
kill $TCPDUMP_PID
tcpdump -r /tmp/hushtype-capture.pcap -nn | grep -v "127.0.0.1"
```

To filter by PID (requires macOS tcpdump with -E flag or `nettop` instead):

```bash
# List sockets owned by HushType:
lsof -i -n -P -p $(pgrep -x HushType)
```

### Option C: Little Snitch or Lulu (Recommended for Extended Monitoring)

For extended monitoring sessions or privacy audits, a third-party firewall provides the most comprehensive visibility:

- **Little Snitch** (paid): Rules-based firewall with per-process network logging. Create a "monitor-only" rule for HushType and inspect the connection log.
- **Lulu** (free, open source): Block-by-default firewall. Any unexpected connection attempt triggers a user alert.

Both tools can export connection logs for audit purposes.

### Option D: Network Link Conditioner (Offline Testing)

Apple's Network Link Conditioner (part of the Additional Tools for Xcode package) provides a system-wide network simulation. Use the "100% Loss" profile to simulate no connectivity.

Alternatively, disable WiFi and unplug Ethernet before running offline test scenarios.

```bash
# Disable WiFi from terminal:
networksetup -setairportpower en0 off

# Re-enable after testing:
networksetup -setairportpower en0 on
```

---

## Monitoring Script

Save this script as `scripts/monitor-privacy.sh` and run it alongside any test scenario. It polls active HushType connections every 2 seconds and logs any non-loopback entries.

```bash
#!/usr/bin/env bash
# monitor-privacy.sh — Log all HushType network connections to stdout and a file.
# Usage: ./scripts/monitor-privacy.sh [output_file]
#
# Run this in a separate terminal while executing test scenarios.
# Any line printed to stdout (other than the header) indicates an unexpected
# or expected network connection that must be reviewed.

set -euo pipefail

OUTPUT_FILE="${1:-/tmp/hushtype-privacy-$(date +%Y%m%d-%H%M%S).log}"
POLL_INTERVAL=2

echo "HushType Privacy Monitor"
echo "Output: $OUTPUT_FILE"
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "---"

{
  echo "# HushType Privacy Monitor Log"
  echo "# Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# Format: TIMESTAMP | PID | PROTO | LOCAL_ADDR | REMOTE_ADDR | STATE"
  echo ""
} > "$OUTPUT_FILE"

while true; do
  PID=$(pgrep -x HushType 2>/dev/null || true)

  if [ -z "$PID" ]; then
    echo "[$(date +%H:%M:%S)] HushType not running — waiting..."
    sleep "$POLL_INTERVAL"
    continue
  fi

  CONNECTIONS=$(lsof -i -n -P -p "$PID" 2>/dev/null \
    | grep -v "127.0.0.1" \
    | grep -v "LISTEN" \
    | grep -v "COMMAND" \
    | grep -E "TCP|UDP" \
    || true)

  if [ -n "$CONNECTIONS" ]; then
    TIMESTAMP="$(date +%H:%M:%S)"
    echo "$CONNECTIONS" | while IFS= read -r line; do
      ENTRY="[$TIMESTAMP] PID=$PID | $line"
      echo "$ENTRY"
      echo "$ENTRY" >> "$OUTPUT_FILE"
    done
  fi

  sleep "$POLL_INTERVAL"
done
```

Make the script executable:

```bash
chmod +x scripts/monitor-privacy.sh
```

Run it before each test scenario:

```bash
./scripts/monitor-privacy.sh /tmp/hushtype-test-$(date +%Y%m%d).log
```

---

## Test Scenarios

Each scenario includes: setup steps, monitoring commands, expected result, and a pass/fail criterion.

---

### Scenario 1: Core Dictation — Offline

**Purpose:** Verify that the core audio → whisper → text injection pipeline makes zero network connections.

**Setup:**
1. Disable WiFi: `networksetup -setairportpower en0 off`
2. Disconnect Ethernet if present.
3. Start the monitoring script in a separate terminal.
4. Launch HushType. Confirm the menu bar icon appears.
5. Confirm a whisper model is loaded (Settings → Models shows a model with a checkmark).

**Steps:**
1. Activate push-to-talk (default: fn key). Speak a short phrase (5–10 words).
2. Release the key. Observe text injection into the focused text field.
3. Repeat 5 times with varied phrases.

**Monitoring command:**
```bash
# After the 5 dictations, inspect lsof output:
lsof -i -n -P -p $(pgrep -x HushType) | grep -v "127.0.0.1"

# Expected output: empty (no entries)
```

**Expected Result:**
- All 5 dictations complete successfully.
- Transcribed text is injected into the target application.
- `lsof` output is empty (no active sockets).
- Console.app shows no network-related errors (filter by process: HushType).
- The monitoring script log contains no entries.

**Pass Criteria:**
- [ ] All 5 dictations produce correct output
- [ ] `lsof` returns no non-loopback connections
- [ ] No `NSURLError`, `URLError`, or network timeout errors in Console.app
- [ ] WiFi disabled state does not cause the app to hang or crash

---

### Scenario 2: LLM Processing — Offline

**Purpose:** Verify that all six LLM processing modes operate entirely offline with no network calls.

**Setup:**
1. Disable WiFi.
2. Start the monitoring script.
3. Confirm an LLM model is loaded (Settings → Processing shows model loaded).

**Steps:**
1. For each of the six processing modes, perform one dictation and verify output:
   - **Raw** — unprocessed transcription
   - **Clean** — grammar and punctuation corrected
   - **Structure** — formatted with headings or lists
   - **Prompt** — template-driven transformation
   - **Code** — code-formatted output
   - **Custom** — user-defined processing chain
2. Switch modes via Settings → Processing or voice prefix (e.g., "code mode: ").

**Monitoring command:**
```bash
# After all 6 modes tested:
lsof -i -n -P -p $(pgrep -x HushType) | grep -v "127.0.0.1"
```

**Expected Result:**
- All 6 modes produce transformed output.
- No network connections open at any point.
- LLM inference latency is within expected range for the loaded model.

**Pass Criteria:**
- [ ] All 6 processing modes return output without error
- [ ] `lsof` returns no non-loopback connections after any mode
- [ ] No network-related errors in system logs

---

### Scenario 3: Voice Commands — Offline

**Purpose:** Verify that all voice command categories execute without requiring network access.

**Setup:**
1. Disable WiFi.
2. Start the monitoring script.
3. Ensure Accessibility permission is granted (required for window management commands).

**Steps:**

Execute at least 5 of the following command categories:

```
"hey hushtype open safari"              # App management
"hey hushtype switch to finder"         # App switching
"hey hushtype maximize window"          # Window management
"hey hushtype set volume to 50"         # System control (AppleScript)
"hey hushtype new tab"                  # Workflow shortcut
"hey hushtype type hello world"         # Direct injection
```

**Monitoring command:**
```bash
lsof -i -n -P -p $(pgrep -x HushType) | grep -v "127.0.0.1"
```

**Expected Result:**
- Each command executes its intended action locally (app launches, window resizes, volume changes).
- No network connections at any point.

**Pass Criteria:**
- [ ] At least 5 voice commands execute successfully in offline mode
- [ ] AppleScript-based commands (volume, media keys) succeed
- [ ] AXUIElement-based commands (window tiling) succeed
- [ ] `lsof` returns no non-loopback connections

---

### Scenario 4: Application Startup — No Network

**Purpose:** Verify that HushType starts cleanly and reaches a fully operational state with no network available.

**Setup:**
1. Disable WiFi before launching the app.
2. Quit HushType if already running.
3. Start `tcpdump` capture.

**Steps:**
1. Launch HushType.
2. Wait 30 seconds for all startup services to initialize.
3. Confirm the menu bar icon is visible and interactive.
4. Open Settings and confirm all tabs render without loading spinners or errors.
5. Quit HushType normally.

**Monitoring command:**
```bash
# Start capture before launch:
sudo tcpdump -i en0 -w /tmp/hushtype-startup.pcap &

# After quit:
kill %1
tcpdump -r /tmp/hushtype-startup.pcap -nn | grep -v "127.0.0.1"
```

**Expected Result:**
- App starts without hanging during any initialization phase.
- Model registry refresh fails gracefully (logged as a warning, not a crash).
- Sparkle update check fails gracefully (no dialog, no crash).
- All UI is usable immediately.
- `tcpdump` capture may show failed connection attempts to `raw.githubusercontent.com` and `harungungorer.github.io` — these are expected and acceptable (they will fail immediately). They must not block the UI.

**Pass Criteria:**
- [ ] App reaches operational state within 10 seconds of launch
- [ ] No hang or timeout on the main thread during startup
- [ ] Settings window opens and all tabs are functional
- [ ] Any network errors are logged as warnings, not user-visible errors
- [ ] No crash on startup in offline mode

---

### Scenario 5: Model Download — Connection Monitoring

**Purpose:** Verify that model downloads connect exclusively to expected hosts (huggingface.co) and no other destinations.

**Setup:**
1. Enable WiFi.
2. Start `tcpdump` capture on the primary interface.
3. In Settings → Models, identify a model that is not yet downloaded.

**Steps:**
1. Start the packet capture:
   ```bash
   sudo tcpdump -i en0 -w /tmp/hushtype-download.pcap &
   ```
2. Initiate a model download from Settings → Models.
3. Wait for the download to complete (progress bar reaches 100%).
4. Stop the capture.

**Analysis:**
```bash
# Stop capture:
kill %1

# Extract unique remote hosts contacted:
tcpdump -r /tmp/hushtype-download.pcap -nn \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
  | sort -u

# Resolve those IPs to hostnames:
tcpdump -r /tmp/hushtype-download.pcap -n \
  | awk '{print $3}' \
  | sort -u
```

**Expected Hosts (Allowed):**
- `huggingface.co` and its CDN IPs
- `cdn-lfs.huggingface.co` (HuggingFace Large File Storage CDN)
- Mirror hosts defined in the model's `mirrorURLs` property (if primary fails)
- DNS resolvers (53/udp) — expected for hostname resolution

**Forbidden Hosts:**
- Any IP or hostname not associated with HuggingFace or the configured mirror
- `api.anthropic.com`, `api.openai.com`, `api.cohere.ai` or any LLM cloud provider
- Any analytics or telemetry endpoint

**Pass Criteria:**
- [ ] Download completes with correct SHA-256 checksum
- [ ] All TCP connections go exclusively to huggingface.co or declared mirror hosts
- [ ] No connections to any LLM API provider
- [ ] No connections carrying audio or text data
- [ ] After download completes, all network activity ceases

---

### Scenario 6: Sparkle Update Check — Connection Monitoring

**Purpose:** Verify that Sparkle's automatic update check connects only to the declared appcast URL and no other hosts.

**Background:**
`Info.plist` declares:
```xml
<key>SUFeedURL</key>
<string>https://harungungorer.github.io/HushType/appcast.xml</string>
<key>SUEnableAutomaticChecks</key>
<true/>
```

Sparkle checks this URL periodically (default interval: 24 hours). The check must not leak any identifying information beyond what Sparkle's standard user-agent sends.

**Setup:**
1. Enable WiFi.
2. Reset Sparkle's last-check timestamp to force an immediate check:
   ```bash
   defaults delete com.hushtype.app SULastCheckTime 2>/dev/null || true
   ```
3. Start `tcpdump` or the monitoring script.
4. Quit and relaunch HushType.

**Monitoring command:**
```bash
sudo tcpdump -i en0 host harungungorer.github.io -w /tmp/sparkle-check.pcap &

# After 60 seconds (enough time for Sparkle to check on launch):
kill %1
tcpdump -r /tmp/sparkle-check.pcap -A | grep -E "Host:|GET |User-Agent:"
```

**Expected Result:**
- One HTTPS GET request to `harungungorer.github.io/HushType/appcast.xml`
- Standard Sparkle user-agent (contains `HushType/` and macOS version)
- No request body (GET request carries no audio or text payload)
- No connections to any host other than `harungungorer.github.io` and its CDN

**Pass Criteria:**
- [ ] Only `harungungorer.github.io` is contacted during the update check
- [ ] Request is a standard GET with no sensitive payload
- [ ] If an update is available, the update prompt appears but does not auto-download
- [ ] If `harungungorer.github.io` is unreachable, Sparkle fails silently (no user-visible error, no crash)

---

### Scenario 7: DNS Leak Check

**Purpose:** Verify that HushType does not trigger unexpected DNS queries that could reveal user behavior to DNS resolvers.

**Background:**
Even if TCP connections are blocked or fail, DNS queries for unexpected hostnames indicate that HushType is attempting connections to undeclared hosts. DNS queries are a common privacy leak vector.

**Setup:**
1. Enable WiFi.
2. Install `dnsspy` or use `tcpdump` on port 53.

**Monitoring command:**
```bash
# Capture all DNS queries from the machine during the test:
sudo tcpdump -i en0 -n port 53 -w /tmp/hushtype-dns.pcap &
DNS_PID=$!

# Use HushType normally for 10 minutes:
# - 3 dictations
# - 2 LLM processing sessions
# - 3 voice commands
# - Leave app idle for 5 minutes

kill $DNS_PID

# Extract queried hostnames:
tcpdump -r /tmp/hushtype-dns.pcap -vv \
  | grep -oE '"[^"]+"' \
  | sort -u
```

**Expected DNS Queries (Allowed):**

| Hostname | Reason |
|---|---|
| `harungungorer.github.io` | Sparkle appcast check |
| `raw.githubusercontent.com` | Model registry manifest refresh |
| Apple system hostnames (e.g., `ocsp.apple.com`) | macOS certificate validation |

**Forbidden DNS Queries:**

Any hostname not in the allowed list above, especially:
- `api.openai.com`, `api.anthropic.com`
- `analytics.*.com`, `telemetry.*.com`, `stats.*.com`
- `huggingface.co` (should not appear unless user initiates a model download)

**Pass Criteria:**
- [ ] No DNS queries for undeclared hosts during 10 minutes of normal use
- [ ] No DNS queries carrying any user-identifiable information in the hostname
- [ ] Queries for Apple OCSP endpoints are acceptable (macOS certificate validation)

---

### Scenario 8: Extended Offline Use Session

**Purpose:** Verify stability and privacy compliance during a sustained 30-minute offline session representing realistic daily use.

**Setup:**
1. Disable WiFi.
2. Start the monitoring script with output to a timestamped log file.
3. Start Console.app filtered to process "HushType".

**Steps (30-minute session):**

| Time | Activity |
|---|---|
| 0:00 | Launch HushType |
| 0:01 | Perform 3 dictations in Raw mode |
| 0:05 | Switch to Clean mode, perform 3 dictations |
| 0:10 | Switch to Code mode, perform 2 dictations |
| 0:15 | Execute 3 voice commands (app switch, volume, maximize) |
| 0:20 | Open Settings, navigate all 10 tabs |
| 0:22 | Perform 3 more dictations while reviewing history tab |
| 0:25 | Leave app idle (no input) |
| 0:28 | Perform 2 final dictations |
| 0:30 | Quit HushType |

**Pass Criteria:**
- [ ] All dictations complete without error across the session
- [ ] No memory leak (Activity Monitor: memory usage stable, not growing unbounded)
- [ ] No network-related errors in Console.app log
- [ ] The monitoring script log file contains zero entries
- [ ] App quits cleanly (no crash on termination)

---

## Pass Criteria — Full Suite

The privacy verification protocol **passes** when all of the following are true:

### Mandatory Pass Conditions

1. **Zero unexpected outbound connections** — During any scenario that does not explicitly test model downloads or Sparkle, `lsof` and `tcpdump` show no non-loopback connections from HushType.

2. **Core pipeline is fully offline** — Scenarios 1, 2, and 3 (dictation, LLM processing, voice commands) pass 100% with WiFi disabled.

3. **Startup does not block on network** — Scenario 4 passes: app reaches operational state within 10 seconds with no network available.

4. **Model downloads stay on declared hosts** — Scenario 5 passes: all TCP connections during download go exclusively to `huggingface.co` or declared mirror URLs.

5. **Sparkle stays on declared host** — Scenario 6 passes: update check contacts only `harungungorer.github.io`.

6. **No undeclared DNS queries** — Scenario 7 passes: no DNS lookups for undeclared hostnames during 10 minutes of normal use.

7. **Extended offline session is error-free** — Scenario 8 passes: 30-minute offline session produces zero network-related log entries.

### Automatic Failure Conditions

Any of the following constitutes an automatic failure of the entire protocol:

- A connection from HushType to any host carrying audio or transcribed text
- A connection to any LLM cloud API (`openai.com`, `anthropic.com`, `cohere.ai`, etc.)
- A connection to any analytics, telemetry, or crash-reporting service
- The app crashing or hanging when network is unavailable
- Any dictation silently failing due to a network dependency

---

## Results Template

Copy this table for each test run. Fill in all fields.

### Test Run Metadata

| Field | Value |
|---|---|
| Date | |
| Tester | |
| HushType Version | |
| macOS Version | |
| Hardware | (e.g., MacBook Pro M3, 16GB) |
| Whisper Model Loaded | |
| LLM Model Loaded | |
| Network Monitoring Tool Used | |
| Log File Path | |

### Per-Scenario Results

| Scenario | Result | Notes |
|---|---|---|
| 1. Core Dictation (Offline) | PASS / FAIL / SKIP | |
| 2. LLM Processing (Offline) | PASS / FAIL / SKIP | |
| 3. Voice Commands (Offline) | PASS / FAIL / SKIP | |
| 4. Startup with No Network | PASS / FAIL / SKIP | |
| 5. Model Download Monitoring | PASS / FAIL / SKIP | |
| 6. Sparkle Update Check | PASS / FAIL / SKIP | |
| 7. DNS Leak Check | PASS / FAIL / SKIP | |
| 8. Extended Offline Session | PASS / FAIL / SKIP | |

### Overall Verdict

| Field | Value |
|---|---|
| Overall Result | PASS / FAIL |
| Unexpected Connections Found | YES / NO |
| Connection Details (if any) | |
| Regression from Previous Run | YES / NO / N/A |
| Issues Filed | (link to DevTrack tasks, if any) |
| Sign-Off | |

### Connection Log (if any unexpected connections found)

Paste the raw output of the monitoring script or `tcpdump` here. For each unexpected connection, include:

- Timestamp
- Remote host (IP and resolved hostname)
- Port
- Protocol (TCP/UDP)
- Bytes transferred
- Which scenario triggered it
- Assessment: known-safe / privacy violation / under investigation
