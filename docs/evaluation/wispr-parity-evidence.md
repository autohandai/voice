# Wispr-source parity implementation evidence

Status: local implementation substantially complete; release parity is not yet
claimable because native, offline, artifact, and external gates remain.

This report separates repository proof from evidence that XCTest cannot
replace. The canonical scope remains the 55 source families in
`docs/plans/wispr-flow-source-inventory.md`.

| Package | Repository implementation | Evidence still required |
| --- | --- | --- |
| WP0 | 55-family inventory, product contract, delivery ledger, and mechanical coverage verifier | None beyond final-document review |
| WP1 | Finite failures, bounded reliability ledger, fault injection, redacted diagnostics, offline evaluation schemas | Checksummed licensed benchmark run, network-disabled real dictation, crash/restart soak, measured release baseline |
| WP2 | One-session coordinator with explicit start, stop, cancel, retry, interruption, and duration-limit transitions | Real shortcut/menu/pointer/Scratchpad race smoke |
| WP3 | Ranked stable routes including System Default, immediate reorder handoff, clamshell policy, segmented format-safe capture, streaming 20-minute bounds, monotonic timer, recording-only activity assertion | Real plug/unplug, default change, clamshell, sleep/wake, format-change, and 20-minute Apple Silicon smoke |
| WP4 | Per-display anchors/offsets, thresholded edge changes, horizontal/vertical forms, Escape rollback, opacity/forms, language/style menus, warnings, completion, recovery, ten-second explicit Copy Final, HUD revision navigation, Canadian spelling recommendation | Multi-display, Dock/menu-bar, Spaces, Stage Manager, Reduce Transparency/Contrast, VoiceOver, and Full Keyboard Access smoke without focus change |
| WP5 | Four-binding cap, rebindable Start/Stop/Cancel/Commit keyboard paths, opt-in extra-button event tap, HID disconnect status, race reducer, explicit Enter gate, focus-safe terminal plans | Input Monitoring denial/revocation and device-removal smoke; real Terminal, iTerm2, Warp, Claude Code, and Codex short/long/multiline matrix where installed |
| WP6 | Immutable raw root, bounded revision chain/change sets, Literal/Light/Medium/High fail-closed policy, History and HUD undo/redo navigation, style precedence, ranked/starred vocabulary and confirmed local suggestions | Live History/HUD copy-and-reinsert usability review |
| WP7 | No-context default, 64-scalar cap, exact bundle policy, signed sensitive rules, secure-field hard deny | Real secure-field and representative sensitive-app smoke |
| WP8 | Incremental AES-GCM spool, Keychain key, restart recovery, corruption/key-loss/expiry/quota handling, Undo Cancel, independent retention, verified Reset All ledger | Forced process kill, Cmd-Q, sleep, and live Keychain recovery smoke |
| WP9 | Owner-only SQLite Workspace v2, migrations, bounded notes/versions/assets, local search, Scratchpad and Quick Dictation | Restart, quota, inline-image, accessibility, focus, and corruption smoke in packaged app |
| WP10 | Signed-manifest, deterministic `.mlmodelc` tree digest, bounded templates, fail-closed runner contract and feasibility gate | Licensed signed CoreML text model, ANE runner, golden semantic fixtures, memory/cancellation/offline/selection proof; feature remains off |
| WP11 | Category/coalescing/action policy, deep links, local finite Status, five-locale String Catalog, static-call-site/placeholder/pseudolocalization checks, advanced local metrics and metadata-audited share cards | Human linguistic review; long-string, right-to-left, VoiceOver, Full Keyboard Access, notification-denial, and system share-sheet smoke |
| WP12 | All-off data classes, zero-call test, bounded opaque AES-GCM objects, authenticated metadata, key rotation, tombstones, offline queue contract, conflict branches, release evidence gate | Reviewed auth/key/control plane, persistent transport integration, second first-party client, two-device conflict/revocation/reinstall/outage tests, packet captures; UI remains hidden |
| WP13 | S256 PKCE/state/nonce and exact callback validation, ThisDeviceOnly Keychain credential vault, account capability seam, finite member/admin boundary, BAA enforcement and separate sign-out deletion contract | Live auth, callback, token refresh/revocation, entitlements, billing, invite/email, roles, audit, BAA document delivery, legal/security approval; UI remains hidden |

## Publication boundary

The repository must not describe the initiative as shipped parity until:

1. `swift test`, both release executables, diagnostic JSON, and packaged app
   gates pass from the final source state;
2. the current Apple Silicon native/offline matrix above is recorded;
3. the Transform artifact gate is satisfied or remains explicitly unavailable;
4. WP12 and WP13 external evidence is produced by the separately owned
   control-plane and second-client work; and
5. no opt-in feature flag is lifted without its package-specific evidence.

Green automated tests establish code proof only. They do not establish live
microphone, accessibility, display, terminal, notification, network, Keychain,
provider, billing, email, legal, or second-client proof.

## Current automated validation

Run on an Apple Silicon Mac on 2026-07-30 from the final source state:

- `swift test`: 260 tests passed with zero failures.
- `swift build -c release`: both `autohand-voice` and
  `autohand-voice-stt` built as arm64 executables.
- `.build/release/autohand-voice check --json`: exited successfully,
  confirmed `supported: true`, `speechEngine: coreml`, and
  `remoteFallbackEnabled: false`. The live environment reported microphone
  permission denied, Accessibility unavailable, and model/shortcut not
  checked.
- `./scripts/build-app.sh`: built `dist/Autohand Voice.app`; strict deep
  signature verification passed, the app and helper are arm64, the minimum
  system version is macOS 14.0, and the microphone entitlement is present.
- Packaged localizations: English, German, Spanish, Italian, and Portuguese.
- `./scripts/verify-wispr-plan-coverage.sh`: all 55 source families covered.

This is repository and packaging proof, not the native/offline or external
release evidence listed in the table above.

## Current native smoke

Run against the packaged app on the same Apple Silicon Mac on 2026-07-30:

- The current packaged process launched, created its menu-bar status item,
  remained responsive, and showed no launch failure in its local process log.
- General, Formatting, Vocabulary, App Profiles, Language & Models, and
  Permissions rendered with accessible labels and keyboard-addressable
  controls.
- The packaged model pane reported Parakeet v3 ready offline with a current
  successful validation.
- The packaged app's permission pane reported Microphone and Accessibility
  authorized. The standalone CLI diagnostic has a separate executable
  identity and therefore reported that it did not hold those TCC grants.
- A user-observed eight-second microphone test showed live signal and stopped
  normally without transcription or persistence.
- A user-observed TextEdit smoke confirmed that provisional speech was not
  inserted, the final transcript was inserted exactly once after stop, and
  the pre-existing clipboard content remained unchanged.

This establishes a basic microphone/final-insertion smoke for the current
package. It does not replace the multi-device, multi-display, terminal,
permission-revocation, recovery, sleep/wake, notification, accessibility, or
long-session matrix still listed above.
