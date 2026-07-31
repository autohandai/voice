# Wispr Flow Parity Delivery Plan

Status: implementation sequence and traceability ledger\
Snapshot: 2026-07-29

## 1. How to read this plan

The source ID is the unit of coverage. "Baseline" describes evidence visible in
the current working tree, not a release claim. "Target" points to the product
spec section. A source family is complete only when all material bullets in the
source inventory pass the target acceptance criteria.

Baseline labels:

- `foundation`: a current module provides much of the outcome;
- `partial`: some user behavior exists but material requirements are missing;
- `absent`: no current user-facing behavior;
- `platform`: the source mechanism is mobile-only;
- `external`: requires an authenticated control plane outside this repository;
- `quality`: represented by tests/diagnostics rather than a standalone feature.

## 2. Current-state gap ledger

### July 9, 2026

| Source ID | Source feature | Baseline | Target decision | Primary target |
| --- | --- | --- | --- | --- |
| `WF-20260709-DESKTOP-01` | Reliability, latency, accuracy, cleanup regression | quality | quality | Product §4.1; `ReliabilityLedger` |
| `WF-20260709-DESKTOP-02` | Remembered left/right/bottom HUD placement | partial: fixed compact placement | extend | Product §4.2; HUD presentation |
| `WF-20260709-DESKTOP-03` | Canadian English recommendation and spelling | absent | extend | Product §4.5; Revision/Language |

### July 2, 2026

| Source ID | Source feature | Baseline | Target decision | Primary target |
| --- | --- | --- | --- | --- |
| `WF-20260702-ANDROID-01` | Overlay recovery, permission recovery, crash fixes, account isolation, bubble cleanup, OEM fixes | partial lifecycle foundation; Android details are platform-only | adapt/quality | Product §4.17 |
| `WF-20260702-IOS-01` | Automatic switchback to host app | foundation: nonactivating HUD and captured target | preserve/extend | Product §4.20; `TextCommit` |

### June 24, 2026

| Source ID | Source feature | Baseline | Target decision | Primary target |
| --- | --- | --- | --- | --- |
| `WF-20260624-DESKTOP-01` | Consistent course correction, literal word preservation, punctuation, evaluation | partial deterministic refinement | quality/extend | Product §§4.1, 4.8 |
| `WF-20260624-DESKTOP-02` | Ranked automatic microphones and live handoff | partial: one remembered device | extend | Product §4.4; `AudioSession` |
| `WF-20260624-DESKTOP-03` | Clamshell automatic route switching | absent | new | Product §4.4; `AudioSession` |

### June 17, 2026

| Source ID | Source feature | Baseline | Target decision | Primary target |
| --- | --- | --- | --- | --- |
| `WF-20260617-DESKTOP-01` | Infrastructure isolation, language/audio accuracy, model evaluation | local runtime has no server dependency; benchmark coverage is partial | quality/adapt | Product §4.1 |
| `WF-20260617-DESKTOP-02` | Independent training and cloud-storage controls | no training or sync; local retention exists | external/new | Product §4.18; `OptionalSync` |
| `WF-20260617-IOS-01` | Interruption notification and direct recovery | partial: in-app/in-memory recovery | extend | Product §§4.12, 4.16 |
| `WF-20260617-IOS-02` | One-tap retry for failed transcripts | partial | extend | Product §4.12 |
| `WF-20260617-IOS-03` | Always-visible live dictation timer | partial: compact HUD timer behavior not a documented invariant | extend | Product §4.3 |
| `WF-20260617-IOS-04` | Accelerating system-like Backspace | platform | preserve | Product §§4.10, 4.20 |

### June 10 and June 4, 2026

| Source ID | Source feature | Baseline | Target decision | Primary target |
| --- | --- | --- | --- | --- |
| `WF-20260610-DESKTOP-01` | Reliability transparency and incident status | partial local diagnostics | adapt/quality | Product §§4.1, 4.16 |
| `WF-20260610-DESKTOP-02` | Localized desktop application | partial: English String Catalog | extend | Product §4.5 |
| `WF-20260604-DESKTOP-01` | Failover, monitoring, on-call, accuracy rollback controls | server failover is non-applicable; local regression gates are partial | quality/adapt | Product §4.1 |

### May 1, 2026

| Source ID | Source feature | Baseline | Target decision | Primary target |
| --- | --- | --- | --- | --- |
| `WF-20260501-DESKTOP-01` | Floating rich-text Scratchpad, tabs, history, images | absent | new | Product §4.14; `LocalWorkspace` |
| `WF-20260501-DESKTOP-02` | Manual/automatic built-in and custom transforms | absent | new | Product §4.9; `Revision` |
| `WF-20260501-DESKTOP-03` | Visible, editable terminal dictation | partial insertion compatibility | extend | Product §4.10; `TextCommit` |
| `WF-20260501-DESKTOP-04` | Status page and incident subscription | partial local status; external incidents not applicable to local STT | adapt | Product §4.16 |
| `WF-20260501-DESKTOP-05` | Recover audio after quitting | partial: quit confirmation and in-memory recovery | extend | Product §4.12; `RecoveryVault` |
| `WF-20260501-DESKTOP-06` | Specific microphone failure messages and fixes | partial audio-health categories | extend | Product §4.4 |
| `WF-20260501-DESKTOP-07` | Refresh subscription status | external | external | Product §4.19 |
| `WF-20260501-DESKTOP-08` | Non-paid IT Admin seats | external | external | Product §4.19 |
| `WF-20260501-ANDROID-01` | Shake-to-unsnooze only while snoozed | platform | preserve explicit resume, no gesture monitor | Product §4.20 |
| `WF-20260501-ANDROID-02` | Predictable system back navigation | platform | preserve Mac navigation | Product §4.20 |
| `WF-20260501-IOS-01` | Scratchpad/Notes cross-device sync | absent/external | new/external | Product §§4.14, 4.18 |

### April 24, 2026

| Source ID | Source feature | Baseline | Target decision | Primary target |
| --- | --- | --- | --- | --- |
| `WF-20260424-DESKTOP-01` | Usage, voice-profile, share cards, team leaderboard | partial local aggregate insights | extend/external | Product §4.15 |
| `WF-20260424-DESKTOP-02` | Four cleanup levels and raw-text undo/redo | partial boolean deterministic formatting/raw copy | extend | Product §4.8; `Revision` |
| `WF-20260424-DESKTOP-03` | Normal, 24-hour, or no local transcript storage | partial configurable bounded retention | extend | Product §4.13; `LocalWorkspace` |
| `WF-20260424-DESKTOP-04` | Team invite links | external | external | Product §4.19 |
| `WF-20260424-DESKTOP-05` | Start-at-login, insertion, notification, responsiveness fixes | foundation/quality | quality | Product §§4.1, 4.17 |
| `WF-20260424-ANDROID-01` | Auto-shrinking bubble and compact/dot modes | partial compact HUD | adapt/extend | Product §4.2 |
| `WF-20260424-ANDROID-02` | Remove persistent foreground notification | platform | adapt | Product §§4.16, 4.20 |
| `WF-20260424-ANDROID-03` | Post-dictation copy action with timeout | partial Copy Last menu action | extend | Product §4.2 |
| `WF-20260424-ANDROID-04` | Adjustable overlay opacity | absent | extend | Product §4.2 |
| `WF-20260424-ANDROID-05` | Overlay responsiveness and background recovery | partial lifecycle foundation | adapt/quality | Product §4.17 |
| `WF-20260424-IOS-01` | Quick Dictation to Notes | absent | adapt/new | Product §4.14 |

### March 31, 2026

| Source ID | Source feature | Baseline | Target decision | Primary target |
| --- | --- | --- | --- | --- |
| `WF-20260331-DESKTOP-01` | Language picker in recording surface | language setting exists; HUD picker absent | extend | Product §4.5 |
| `WF-20260331-DESKTOP-02` | 20-minute sessions with warning | absent; current cap is five minutes | extend | Product §4.3; `AudioSession` |
| `WF-20260331-DESKTOP-03` | Non-primary mouse dictation and Enter binding | absent | new | Product §4.11 |
| `WF-20260331-DESKTOP-04` | Starred, usage-ranked, deduplicated dictionary | partial dictionary | extend | Product §4.6 |
| `WF-20260331-DESKTOP-05` | Rebind Cancel/Enter and retry dismissed/failed sessions | partial configurable start shortcut and in-memory retry | extend | Product §§4.11, 4.12 |
| `WF-20260331-DESKTOP-06` | Notification redesign, category mutes, action acknowledgement | absent | new | Product §4.16 |
| `WF-20260331-DESKTOP-07` | Browser sign-in, clamshell warning, and additional app/site Styles | mixed: external sign-in, absent warning, partial app profiles | external/new/extend | Product §§4.4, 4.8, 4.19 |
| `WF-20260331-DESKTOP-08` | HIPAA BAA visibility and download | external | external | Product §4.19 |
| `WF-20260331-DESKTOP-09` | Wake, start/stop, notification-sound, and UI stability | foundation/quality | quality | Product §§4.1, 4.17 |
| `WF-20260331-ANDROID-01` | Full custom dictionary management | foundation | extend quality and shared interface | Product §4.6 |
| `WF-20260331-ANDROID-02` | Context-aware continuation | absent | new, opt-in | Product §4.7 |
| `WF-20260331-ANDROID-03` | Automatic pause in financial apps | absent | new | Product §4.7 |
| `WF-20260331-ANDROID-04` | Secure sign-out and local purge | no account; store-specific deletion exists | adapt/new | Product §4.13 |
| `WF-20260331-ANDROID-05` | History/Copy Last, keep-awake, limit warning/save, failed-audio retry, and stopped-service warning | mixed: partial History/recovery/diagnostics; timer/activity assertion absent | adapt/extend | Product §§4.3, 4.12, 4.13, 4.17 |
| `WF-20260331-ANDROID-06` | Crash, wrong-target, waveform-start, and Accessibility stability fixes | partial quality suite | quality | Product §§4.1, 4.10 |
| `WF-20260331-IOS-01` | Default style plus temporary 15-minute override | partial app profiles, no temporary override | extend | Product §4.8 |

## 3. Feature flags

Flags are internal release gates, not marketing entitlements. Unknown or
malformed values resolve to off.

| Flag | Default | Lift gate |
| --- | --- | --- |
| `AUTOHAND_VOICE_HUD_EDGE_PLACEMENT` | off | placement/accessibility/multi-display smoke |
| `AUTOHAND_VOICE_LONG_DICTATION_20` | off | memory, accuracy, timer, interruption, and 20-minute real smoke |
| `AUTOHAND_VOICE_MOUSE_FLOW` | off | Input Monitoring disclosure and pointer race smoke |
| `AUTOHAND_VOICE_MINIMAL_CONTEXT` | off | privacy audit and secure-field/sensitive-app proof |
| `AUTOHAND_VOICE_LOCAL_TRANSFORMS` | off | signed local model, offline proof, semantic evaluation |
| `AUTOHAND_VOICE_PERSISTENT_RECOVERY` | off | threat model, Keychain, corruption, expiry, kill/relaunch proof |
| `AUTOHAND_VOICE_WORKSPACE_V2` | off | migration/rollback/erase and data-integrity proof |
| `AUTOHAND_VOICE_SCRATCHPAD` | off | workspace v2 plus editor/quota/accessibility proof |
| `AUTOHAND_VOICE_NOTIFICATIONS` | off | permission-denied and deep-link/idempotency proof |
| `AUTOHAND_VOICE_ADVANCED_INSIGHTS` | off | formula/privacy/share-card proof |
| `AUTOHAND_VOICE_ENCRYPTED_SYNC` | off | separate live control plane plus second-client conflict proof |
| `AUTOHAND_VOICE_ACCOUNTS` | off | live auth/entitlement/revocation proof |

When a flag protects schema-writing behavior, disabling it must retain
backward-readable data and must not destroy user content.

## 4. Work packages

Each package is intended to be independently reviewable and releasable where
its dependencies permit. File names are targets, not permission to perform a
large mechanical rewrite.

### WP0 — Freeze the contracts and build the coverage verifier

Source coverage: all IDs.

Deliver:

- commit this plan set;
- add a small docs verifier that extracts source IDs from the inventory and
  requires each to appear in this gap ledger and product spec;
- define `FeatureFlag` parsing with unknown/off behavior;
- add a release-evidence template separating automated, native smoke,
  deployment, and external-provider proof.

Tests:

- duplicate and missing source IDs fail;
- malformed flags resolve off;
- public identity and privacy invariants remain unchanged.

### WP1 — Reliability harness and finite failure model

Source coverage:

- `WF-20260709-DESKTOP-01`
- `WF-20260624-DESKTOP-01`
- `WF-20260617-DESKTOP-01`
- `WF-20260610-DESKTOP-01`
- `WF-20260604-DESKTOP-01`
- every `quality` row in the gap ledger

Deliver:

- `VoiceFailureCategory` and remediation mapping;
- `ReliabilityLedger` with bounded aggregates;
- deterministic fault injection at module interfaces;
- model/refinement evaluation manifest and report schema;
- safe app/CLI export.

Likely files:

- `Sources/AutohandVoiceCore/ReliabilityLedger.swift`
- `Sources/AutohandVoiceCore/VoiceFailureCategory.swift`
- `tests/AutohandVoiceCoreTests/ReliabilityLedgerTests.swift`
- `tests/AutohandVoiceCoreTests/VoiceFailureCategoryTests.swift`
- `docs/evaluation/`

Gate:

- no arbitrary messages or private content in the ledger;
- offline real dictation succeeds;
- baseline latency and success results are recorded without claiming an
  unsupported market comparison.

### WP2 — Coordinator extraction and session race proof

Source coverage:

- lifecycle, interruption, focus, and reliability families.

Deliver:

- pure transition tests for current `VoiceSession` behavior;
- `DictationCoordinator` with one-intent/one-snapshot interface;
- adapters from the current menu, HUD, shortcut, and onboarding;
- deletion of duplicated state only after behavioral parity.

Likely files:

- `Sources/AutohandVoiceCore/DictationCoordinator.swift`
- `tests/AutohandVoiceCoreTests/DictationCoordinatorTests.swift`
- `Sources/AutohandVoice/VoiceSession.swift`

Gate:

- start/stop/cancel/limit/sleep/quit races yield one terminal event;
- final-only commit and no-remote invariants remain source-tested;
- current user workflows pass before any new feature flag is enabled.

### WP3 — Ranked audio routes, clamshell handling, and long sessions

Source coverage:

- `WF-20260624-DESKTOP-02`
- `WF-20260624-DESKTOP-03`
- `WF-20260501-DESKTOP-06`
- `WF-20260331-DESKTOP-02`
- `WF-20260331-DESKTOP-07`
- `WF-20260331-ANDROID-05`

Deliver in order:

1. ranked route domain policy and settings migration;
2. clamshell detection/warning;
3. at-rest route changes;
4. mid-session handoff with explicit segment outcome;
5. monotonic timer and warnings;
6. measured 20-minute buffer/spool implementation.

Likely files:

- deepen `AudioInputDevice.swift` and `AudioCapture.swift`;
- add `AudioSession.swift`, `AudioRoutePolicy.swift`, and tests;
- extend audio settings and HUD presentation.

Gate:

- route simulation and real plug/unplug smoke;
- 20-minute real capture/finalization on Apple Silicon;
- fixed memory/disk/task bounds;
- permission, busy-device, no-signal, clipping, disconnect, and handoff
  failures are distinct.

### WP4 — HUD placement, adaptive form, and language/style controls

Source coverage:

- `WF-20260709-DESKTOP-02`
- `WF-20260709-DESKTOP-03`
- `WF-20260424-ANDROID-01`
- `WF-20260424-ANDROID-03`
- `WF-20260424-ANDROID-04`
- `WF-20260331-DESKTOP-01`
- `WF-20260331-IOS-01`

Deliver:

- placement/offset model per display;
- drag handling that cannot steal focus;
- compact/dot/auto and opacity preferences;
- timer, language, style, warning, completion, and recovery presentations;
- one-time Canadian spelling recommendation;
- temporary style override with monotonic inactivity expiry.

Gate:

- multi-display, Dock/menu-bar, Spaces, Stage Manager, and display-removal
  smoke;
- VoiceOver and Full Keyboard Access;
- no activation or insertion-target change.

### WP5 — Input bindings and terminal-safe commit

Source coverage:

- `WF-20260501-DESKTOP-03`
- `WF-20260331-DESKTOP-03`
- `WF-20260331-DESKTOP-05`
- mobile preserve-only interaction families

Deliver:

- `InputBindingCoordinator`;
- separate Start/Stop, Cancel, and Commit bindings;
- non-primary pointer adapter and guided setup;
- explicit target-specific insertion plans;
- terminal profile fixtures and focus-token hardening.

Gate:

- pointer permission denial preserves keyboard operation;
- button/key races terminate cleanly;
- real Terminal/iTerm2/Warp/Claude Code/Codex smoke where installed;
- clipboard, selection, cursor, Undo, Escape, and host shortcuts are preserved.

### WP6 — Revision chain, cleanup levels, and dictionary priority

Source coverage:

- `WF-20260624-DESKTOP-01`
- `WF-20260424-DESKTOP-02`
- `WF-20260331-DESKTOP-04`
- `WF-20260331-DESKTOP-07`
- `WF-20260331-ANDROID-01`
- `WF-20260331-IOS-01`

Deliver:

- immutable raw final/revision types;
- Literal/Light/Medium cleanup policies;
- undo/redo chain and structured change set;
- starred/usage-ranked dictionary with local suggestion review;
- style/app/temporary precedence.

Gate:

- current formatting/vocabulary behavior remains compatible at equivalent
  settings;
- protected literal words never change without an explicit rule;
- raw final text is always recoverable until retention erases the root.

### WP7 — Minimum context and sensitive-app policy

Source coverage:

- `WF-20260331-ANDROID-02`
- `WF-20260331-ANDROID-03`

Deliver:

- pure `SensitiveContextPolicy`;
- signed built-in ruleset and local denylist;
- secure-field hard deny;
- separately consented bounded context capture;
- app-profile controls and visible active policy.

Gate:

- Accessibility inspection shows no adjacent reads when disabled;
- captured context is memory-only and never appears in a store/report;
- financial/password/secret-manager smoke;
- policy decision completes before microphone activation.

### WP8 — Persistent recovery and retention controls

Source coverage:

- `WF-20260617-IOS-01`
- `WF-20260617-IOS-02`
- `WF-20260501-DESKTOP-05`
- `WF-20260424-DESKTOP-03`
- `WF-20260331-ANDROID-04`
- `WF-20260331-ANDROID-05`

Deliver:

- RecoveryVault threat model;
- encrypted crash-safe spool and Keychain key;
- launch-time Recover/Discard;
- explicit failed History states and retry;
- retention presets and complete Reset All Local Data ledger.

Gate:

- kill -9/relaunch, normal quit, crash, corruption, key loss, expiry, quota,
  retry, discard, and secure erase tests;
- no recovery audio in History, logs, exports, sync, or backups where excluded;
- live copy/retry/insertion proof.

### WP9 — Workspace v2 and Scratchpad

Source coverage:

- `WF-20260501-DESKTOP-01`
- `WF-20260424-IOS-01`
- local portion of `WF-20260501-IOS-01`

Deliver:

- transactional LocalWorkspace;
- legacy JSON import/verification/rollback;
- floating Scratchpad with tabs, sidebar, local search, rich text, bounded
  images, and version history;
- Quick Dictation route.

Gate:

- migration from representative valid, corrupt, oversized, and mixed legacy
  stores;
- local/offline editor and dictation smoke;
- asset quota, orphan cleanup, note restore, accessibility, and secure erase.

### WP10 — Local Transforms

Source coverage:

- `WF-20260501-DESKTOP-02`
- High cleanup in `WF-20260424-DESKTOP-02`

Deliver:

- model/license/size/performance feasibility record;
- signed local CoreML Transform model artifact contract;
- Polish and Prompt Builder presets;
- bounded custom templates;
- manual selection and profile-specific automatic flow.

Gate:

- network-disabled operation and network-traffic audit;
- supported-language golden fixtures and semantic-preservation evaluation;
- selection/focus/Undo smoke;
- memory pressure, cancellation, model absence, and failure return untouched
  input.

### WP11 — Notifications, local status, localization, and advanced insights

Source coverage:

- `WF-20260610-DESKTOP-02`
- `WF-20260501-DESKTOP-04`
- `WF-20260424-DESKTOP-01`
- `WF-20260424-ANDROID-02`
- `WF-20260331-DESKTOP-06`
- `WF-20260331-ANDROID-05`

Deliver:

- category policy, coalescing, deep links, and action acknowledgement;
- local status view driven by finite domain state;
- German, Spanish, Italian, and Portuguese localization;
- advanced local metrics, Voice view rules, and local share cards.

Gate:

- system-notification denied/muted state still surfaces in-app failures;
- duplicate suppression and expired deep-link behavior;
- pseudolocalization/VoiceOver/Full Keyboard Access;
- metric formula, privacy, reset, and image-metadata audit.

### WP12 — Encrypted sync

Source coverage:

- `WF-20260617-DESKTOP-02`
- sync portion of `WF-20260501-IOS-01`
- comparison/team portion of `WF-20260424-DESKTOP-01`

Dependencies:

- Workspace v2;
- a separately reviewed authentication/key/control-plane contract;
- a second first-party client.

Deliver:

- device keys and recovery design;
- E2EE opaque-object transport;
- offline queue, conflict branches, tombstones, revocation;
- per-data-class controls;
- hidden native UI until live gates pass.

Gate:

- packet capture with sync off and on;
- two-device concurrent edits, revoke, quota, token expiry, key loss, corrupt
  ciphertext, offline reinstall, and server outage;
- local dictation and local data remain available through every failure.

### WP13 — Accounts, billing, teams, and compliance

Source coverage:

- `WF-20260501-DESKTOP-07`
- `WF-20260501-DESKTOP-08`
- `WF-20260424-DESKTOP-04`
- `WF-20260331-DESKTOP-07`
- `WF-20260331-DESKTOP-08`

Dependencies:

- a separately owned control-plane repository and deployment;
- legal/security review.

Deliver:

- native browser sign-in/PKCE;
- entitlement refresh;
- account switching/sign-out;
- invite, admin, billing, team aggregate, and compliance-document links;
- no transcript/audio/content access in admin contracts.

Gate:

- native unit/UI tests are necessary but insufficient;
- require live auth callback, token revocation, entitlement, billing,
  invite/email, role authorization, audit event, and BAA download proof;
- core local dictation works offline and without an account.

## 5. Recommended release trains

### Train A — Trust and measurement

WP0–WP2. This creates traceability, finite errors, reproducible reliability
evidence, and a coordinator seam before behavior expands.

### Train B — Daily dictation control

WP3–WP5. Ranked audio, long sessions, a movable HUD, language/style controls,
pointer input, and terminal-safe insertion.

### Train C — Local intelligence

WP6–WP7. Reversible cleanup, dictionary priority, exact app styles, minimum
context, and sensitive-app protection.

### Train D — Never lose work

WP8–WP9. Encrypted recovery, retention, workspace migration, and Scratchpad.

### Train E — Refinement and communication

WP10–WP11. Local transforms, notifications, localization, status, and advanced
insights.

### Train F — Optional connected product

WP12–WP13. Encrypted sync and account/team capabilities. These are not allowed
to delay or weaken the complete local product.

At most one data-migration package and one native-interaction package should be
active concurrently. Do not combine a new local model, persistence migration,
and Accessibility insertion change in one release.

## 6. Required validation for every implementation package

```bash
swift test
swift build -c release
./.build/release/autohand-voice check --json
./scripts/build-app.sh
```

Also verify:

- both release executables exist and run;
- packaged `.app` signature and entitlements;
- network-disabled dictation;
- no remote fallback in the app and CLI diagnostic model;
- owner-only permissions and store limits;
- relevant data erase behavior; and
- a real Apple Silicon smoke test for any microphone, keyboard, pointer, menu
  bar, permission, notification, model, or insertion change.

## 7. Evidence report format

Every completed package reports four independent rows:

| Evidence class | Required statement |
| --- | --- |
| Automated | exact focused/full tests and result |
| Native | exact Mac model/OS, permissions, apps, and interaction exercised |
| Privacy/offline | network state, data locations inspected, remote fallback result |
| External | deployment/provider/API proof, or `not applicable` with reason |

Green XCTest output cannot stand in for the other three rows.

## 8. Initiative completion audit

Before declaring parity:

1. mechanically diff source IDs between inventory, product spec, and this
   ledger;
2. inspect every source family's material bullet, not just its heading;
3. require current evidence for every acceptance criterion;
4. verify mobile-only items received their preserve/adapt regression proof;
5. verify `external` items against live systems, not fake adapters;
6. run all repository validation at the exact final commit;
7. inspect the packaged app with networking disabled; and
8. confirm no feature flag is enabled by default without its documented lift
   gate.
