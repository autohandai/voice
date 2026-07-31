# Autohand Voice: Wispr Flow Feature-Parity Product Specification

Status: implementation contract\
Research snapshot: 2026-07-29\
Source ledger: [`wispr-flow-source-inventory.md`](wispr-flow-source-inventory.md)

## 1. Product outcome

Autohand Voice should provide the confidence, recoverability, customization,
and workflow range represented by the current Wispr Flow changelog while
remaining a distinctly native, local-first Mac product.

The successful user outcome is:

> I can start speaking from any supported Mac workflow, see unambiguous local
> recording state, recover every bounded final or interrupted dictation, shape
> the result without surrendering the raw text, and understand exactly what was
> stored or sent.

This specification covers every source family in the evidence inventory. It is
not permission to copy branding, prose, visual assets, or proprietary
implementation.

## 2. Product invariants

These are acceptance criteria for every feature:

1. Audio reaches only the native capture module and local
   `autohand-voice-stt` CoreML path.
2. Provisional text is never inserted, stored in history, transformed, or
   synchronized.
3. The recognized final transcript is immutable source material. Formatting
   and transforms produce revisions that always retain a reversible link to the
   raw final text.
4. Focus changes stop insertion. The user receives Retry Here, Copy, and
   Discard actions.
5. Clipboard operations are explicit or restore the exact prior clipboard.
6. All persisted stores are owner-only, bounded, versioned, and erasable.
7. Every networked capability is independently opt-in and visibly offline when
   unavailable. Local dictation never depends on it.
8. A missing model, permission, microphone, pointer binding, shortcut,
   notification permission, insertion target, or sync credential produces a
   specific failure with one next action.
9. State is conveyed through text and accessibility semantics, never color,
   sound, or motion alone.
10. Incomplete user-facing features remain behind an off-by-default
    `AUTOHAND_VOICE_` flag.

## 3. Primary journeys

### 3.1 Fast dictation

The user presses or holds the configured keyboard or pointer trigger. The
compact HUD appears at its remembered edge, shows the selected language,
microphone, input health, and timer, then inserts exactly one final result into
the captured target.

### 3.2 Long thought

The user starts a toggle or hands-free session. The HUD warns before the
20-minute hard limit. A stop, interruption, device loss, sleep, crash, or
process exit leaves a clear recoverable result without committing provisional
text.

### 3.3 Correct and refine

The user can preserve literal output, apply a cleanup level, select a named
style, or run an explicit local transform. The raw final text remains
available, and undo/redo never requires re-transcription.

### 3.4 Capture without switching apps

The user dictates directly into the floating Scratchpad or routes the next
dictation there. Notes remain local by default and may use separately gated
end-to-end encrypted sync when that control plane exists.

### 3.5 Repair a failure

The user sees a category-specific notification or History row, opens the
affected dictation, and retries local transcription or insertion. No retry
silently changes the model, language, microphone, or transform policy.

## 4. Feature specifications

### 4.1 Reliability, latency, and accuracy program

Source families:

- `WF-20260709-DESKTOP-01`
- `WF-20260624-DESKTOP-01`
- `WF-20260617-DESKTOP-01`
- `WF-20260610-DESKTOP-01`
- `WF-20260604-DESKTOP-01`
- `WF-20260424-DESKTOP-05`
- `WF-20260424-ANDROID-05`
- `WF-20260331-DESKTOP-09`
- `WF-20260331-ANDROID-06`

Decision: `quality`; extend the existing diagnostics, transcript fixtures,
audio preprocessing, lifecycle policy, and insertion tests.

Requirements:

- Define local service-level objectives for recording-start success,
  transcription completion, insertion completion, crash-free sessions, and
  p50/p95 stop-to-final latency.
- Record only bounded aggregate outcomes; never record audio, transcript text,
  filenames, focused contents, microphone names, or full error messages.
- Maintain a versioned offline evaluation manifest for every shipped model,
  supported language, audio preprocessing revision, cleanup level, and
  dictation-command grammar.
- Keep explicit protected slices for British English and Swiss German routing
  and for compressed/uncompressed audio preprocessing because these were named
  failure modes in the source release.
- Add regression slices for course correction, literal word preservation,
  spoken punctuation, repeated words, fillers, accents, quiet input, clipping,
  route changes, sleep/wake, rapid focus changes, and terminal insertion.
- A model or formatter release cannot ship if any protected slice regresses
  beyond its declared threshold even when the aggregate score improves.
- The app shows local runtime health and the most recent model validation. It
  must not imply that a vendor status page controls local transcription.
- Add a redacted export containing versions, finite failure categories,
  aggregate latency buckets, and pass/fail checks.
- Treat personalized acoustic/language models as a research item, not an
  implied cloud-training feature. Any future adaptation must train or adapt
  locally, disclose its storage and reset behavior, and pass the same
  versioned evaluation before it can affect recognition.

Acceptance:

- Deterministic benchmark runs produce a signed or checksummed report tied to
  the app, STT executable, model, and fixture-manifest versions.
- Network-disabled smoke tests complete a real dictation.
- Fault injection proves that capture, recognition, formatting, insertion,
  history, notifications, and sync failure independently.
- Crash and restart tests leave no unbounded tasks, logs, audio, or temporary
  files.
- Release notes report measured baselines and deltas rather than unsupported
  uptime or speed claims.

### 4.2 Movable, adaptive recording HUD

Source families:

- `WF-20260709-DESKTOP-02`
- `WF-20260424-ANDROID-01`
- `WF-20260424-ANDROID-03`
- `WF-20260424-ANDROID-04`

Decision: `extend` the current compact `RecordingHUDController`.

Requirements:

- Support bottom-center, left-edge, and right-edge anchors. Dragging changes
  the anchor only after a threshold so button clicks remain reliable.
- Bottom placement is horizontal; side placement uses a compact vertical
  layout. Pressing Escape during a drag restores the prior position.
- Persist anchor and edge-relative offset per display identity. Clamp to the
  visible frame on resolution, Dock, menu-bar, Stage Manager, or display
  changes.
- Preserve the current compact resting size. The HUD may expand only for
  provisional text, a warning, a recovery action, or a language menu.
- Offer Auto, Compact, and Dot idle forms plus 20–100 percent opacity. Auto
  shrinks after five inactive seconds but never during starting, recording,
  processing, warning, or failure.
- In Auto mode, a search-field target may use the Dot idle form without reading
  field contents. The opacity control exposes 20, 40, 60, 80, and 100 percent
  stops and defaults to 80 percent for new installs.
- Show an explicit Copy Final action for ten seconds after a successful
  dictation. It must not overwrite the clipboard without a click.
- Remember settings without moving focus or the insertion target.

Acceptance:

- Placement tests cover every edge, multiple displays, display removal,
  reduced visible frames, and oversize content.
- Dragging never activates the app or changes the frontmost text control.
- VoiceOver exposes state, elapsed time, input health, and every action.
- Reduce Motion removes decorative transitions; Increase Contrast and Reduce
  Transparency remain legible.

### 4.3 Session timer and 20-minute dictation

Source families:

- `WF-20260617-IOS-03`
- `WF-20260331-DESKTOP-02`
- `WF-20260331-ANDROID-05`

Decision: `extend` the bounded audio/session policy with a Mac-native timer.

Requirements:

- Show elapsed time for every session, regardless of keyboard, menu, mouse, or
  Scratchpad trigger.
- Raise accessible warnings at 15:00 and 19:00. At 20:00, stop capture and
  finalize automatically.
- Replace the current five-minute sample cap only after memory and streaming
  finalization tests prove a fixed upper bound for 20 minutes.
- Use a system activity assertion only while recording so display sleep does
  not hide an active session; never prevent system sleep indefinitely.
- If the app sleeps, loses its route, or reaches the limit, finalize or persist
  a recoverable interrupted session and explain which occurred.

Acceptance:

- A fake monotonic clock proves warning and hard-stop transitions without
  wall-clock dependence.
- Exactly one finalization begins at the limit.
- Memory remains within the documented cap for the worst supported sample rate.
- Cancel before or at the limit inserts nothing.

### 4.4 Automatic microphone priority and route continuity

Source families:

- `WF-20260624-DESKTOP-02`
- `WF-20260624-DESKTOP-03`
- `WF-20260501-DESKTOP-06`
- `WF-20260331-DESKTOP-07`

Decision: `extend` `AudioInputDevice`, `AudioCapture`, and audio settings.

Requirements:

- Let users order stable microphone device IDs. "System Default" remains a
  valid ranked choice.
- At rest, select the highest-ranked available device. Show the actual route
  before capture starts.
- During capture, a route loss performs a bounded handoff to the next available
  ranked route. Mark the handoff in session metadata; do not mix incompatible
  formats or silently discard the prefix.
- In clamshell mode, prefer a ranked external microphone. If the built-in
  microphone remains active, warn before capture and offer Open Audio Settings.
- Reordering applies immediately. During capture, changing the top-ranked route
  uses the same bounded handoff path as a disconnect; it never restarts the
  session or loses the recorded prefix.
- Distinguish unplugged, busy, muted/no-signal, denied, unsupported format, and
  Core Audio failure.

Acceptance:

- Device simulation covers connect, disconnect, reorder, default change,
  clamshell enter/exit, and mid-session format change.
- Failed handoff leaves recoverable audio and a specific error.
- The diagnostic report redacts device names while the local settings UI may
  display them.
- No route decision starts another recognizer or fallback STT engine.

### 4.5 Language selection, localization, and Canadian English

Source families:

- `WF-20260709-DESKTOP-03`
- `WF-20260610-DESKTOP-02`
- `WF-20260331-DESKTOP-01`

Decision: `extend` language profiles and localization.

Requirements:

- Put a language picker in the expanded HUD whenever two or more compatible
  languages are enabled.
- A language change is allowed only before capture or between sessions. The HUD
  always shows the active language.
- Add a one-time, dismissible Canadian English recommendation when macOS locale
  and supported model coverage justify it. Canadian spelling policy is a local
  formatting profile, not a false STT language claim.
- Accepting that recommendation disables conflicting English spelling variants
  for the active profile; dismissing it changes no language setting.
- Localize app chrome, settings, notifications, diagnostics, onboarding, and
  insights into German, Spanish, Italian, and Portuguese after the English
  catalog passes extraction and layout tests.
- Never promise automatic language detection unless the pinned model exposes a
  tested local mode.

Acceptance:

- Every enabled language is compatible with the selected local model.
- A mid-recording language mutation is rejected with no state corruption.
- Locale recommendation appears once, can be undone in settings, and never
  rewrites literal output when cleanup is off.
- Pseudolocalization, long-string, right-to-left layout, and VoiceOver audits
  pass even before all translations ship.

### 4.6 Dictionary priority and learning

Source families:

- `WF-20260331-DESKTOP-04`
- `WF-20260331-ANDROID-01`

Decision: `extend` `VocabularyStore` and deterministic replacement.

Requirements:

- Preserve add, edit, delete, search, import, export, case preservation, and
  longest-match behavior.
- Add an explicit starred flag. Starred entries win only when two valid rules
  compete; they may not replace unrelated recognized text.
- Track bounded local usage counts and last-used timestamps only when a rule
  actually changes a final transcript.
- Default sorting is starred then most-used, with alphabetical and newest
  alternatives.
- Auto-add suggestions are opt-in and local. Normalize apostrophe variants,
  Unicode composition, and case before duplicate detection.
- A suggestion never becomes an active rule without user confirmation.

Acceptance:

- Tests cover conflicting stars, ties, apostrophes, Unicode normalization,
  locale-sensitive boundaries, import migrations, counter saturation, and
  disabled learning.
- Raw final text remains available after every replacement.
- Dictionary contents and usage metadata are owner-only and independently
  erasable.

### 4.7 Context-aware continuation and sensitive-app protection

Source families:

- `WF-20260331-ANDROID-02`
- `WF-20260331-ANDROID-03`

Decision: `new`, off by default; add a minimum-context policy rather than
reading whole documents.

Requirements:

- Context access is an independent permission in Autohand Voice, not implied by
  Accessibility permission.
- The default policy reads no surrounding text. The opt-in policy may capture
  only selected text plus a bounded number of adjacent Unicode scalars required
  for continuation, spacing, capitalization, and repetition avoidance.
- Per-app profiles can disable context or classify an exact bundle identifier
  as sensitive.
- Ship a signed, updateable sensitive-app ruleset for financial, password,
  healthcare, and secret-management applications. Matching pauses dictation
  before audio capture and explains why.
- Users can add local bundle identifiers to the denylist. No window titles,
  URLs, document names, or field contents are stored for classification.

Acceptance:

- With context disabled, Accessibility reads no adjacent text attributes.
- The context snapshot is memory-only, bounded, cleared after commit/cancel,
  and absent from diagnostics/history.
- Sensitive-app detection is deterministic, visible, overrideable only through
  settings, and occurs before microphone start.
- Password and secure text fields always deny capture even if the app is not on
  the ruleset.

### 4.8 Cleanup levels, styles, and reversible revisions

Source families:

- `WF-20260624-DESKTOP-01`
- `WF-20260424-DESKTOP-02`
- `WF-20260331-DESKTOP-07`
- `WF-20260331-IOS-01`

Decision: `extend` deterministic formatting and app profiles; add a versioned
revision model.

Requirements:

- Provide four cleanup levels: Literal, Light, Medium, and High.
- Literal returns the normalized final transcript without filler removal,
  grammar edits, or rewrites.
- Light may remove high-confidence fillers/repetition and apply explicit
  vocabulary rules.
- Medium may apply local grammar, punctuation, and concision rules with a
  complete change set.
- High requires the explicit local Transform model described below; if that
  model is unavailable, remain at the raw final text and show the failure.
- Preserve raw, cleaned, and transformed revisions. Undo/redo is local,
  deterministic, and available from History and the post-dictation HUD.
- Styles bind cleanup, punctuation, vocabulary set, and transform preset to an
  exact app profile.
- The HUD offers a temporary style override that resets after 15 minutes of
  inactivity. It never mutates the stored default.

Acceptance:

- Every revision names its policy and model version and can reconstruct its
  parent raw final text.
- No level changes a word under protected literal-word fixtures unless an
  explicit vocabulary rule authorizes it.
- Per-app and temporary style precedence is deterministic and displayed before
  recording.
- Cleanup failure never blocks access to or insertion of the raw final text.

### 4.9 Local Transforms

Source family:

- `WF-20260501-DESKTOP-02`

Decision: `new`; local CoreML only and independently opt-in.

Requirements:

- A Transform accepts selected text or a final dictation revision and returns a
  proposed revision plus a structured change summary.
- Ship Polish and Prompt Builder presets. Users may create bounded named prompt
  templates only after the local text-transform model is installed and
  validated.
- Manual transforms operate on explicit selection. Automatic transforms may run
  after final recognition but before insertion only for profiles where the user
  enabled them.
- Selection capture and replacement use the same focus-safe commit gate as
  dictation.
- The interface shows the active local model, size, last validation, and the
  fact that no remote request occurs.
- Model absence, cancellation, out-of-memory, unsupported language, or safety
  rejection returns the untouched input.

Acceptance:

- Network instrumentation observes no transform traffic.
- A transform cannot receive provisional text or implicit surrounding text.
- Custom templates have character, count, and output limits.
- Golden fixtures and semantic-preservation review gates exist for every
  enabled language.
- Automatic transform is off by default and unavailable for secure or
  denylisted applications.

### 4.10 Terminal-safe insertion and native editing behavior

Source families:

- `WF-20260501-DESKTOP-03`
- `WF-20260617-IOS-04`
- `WF-20260501-ANDROID-02`
- `WF-20260331-ANDROID-06`

Decision: `extend` insertion compatibility and `preserve` native keyboard and
navigation behavior.

Requirements:

- Detect terminal-like targets by exact bundle identifier and Accessibility
  role/subrole, not by reading terminal contents.
- Insert multiline text through a target-specific strategy that keeps it
  visible and editable and avoids bracketed-paste collapse when the target
  exposes a safe alternative.
- Never synthesize Backspace behavior, replace system navigation, or install a
  global key event tap merely to mimic mobile keyboard features.
- Rapid focus changes invalidate the target token before any paste or direct
  insertion event.
- App navigation, Backspace acceleration, drawer behavior, and keyboard
  dismissal remain owned by macOS/host apps.

Acceptance:

- Real smoke tests cover Terminal, iTerm2, Warp, Claude Code, and Codex where
  installed, with short, long, and multiline text.
- Focus-switch tests prove text cannot land in the previous or next field.
- Existing clipboard, selection, cursor, Undo, Backspace, and host-app keyboard
  shortcuts remain intact.

### 4.11 Pointer and keyboard control

Source family:

- `WF-20260331-DESKTOP-03`
- `WF-20260331-DESKTOP-05`

Decision: `extend` the registered-shortcut module and add a pointer adapter.

Requirements:

- Bind any discoverable non-primary mouse button to Start/Stop, Hold to Talk,
  Cancel, or Commit/Enter. Never bind primary or secondary click.
- Pointer monitoring is separately opt-in and explains Input Monitoring
  permission before macOS prompts.
- Preserve fully rebindable keyboard Start/Stop, Cancel, and Commit actions.
- Detect conflicts within Autohand Voice and reject unsupported or reserved
  combinations without replacing the working binding.
- Offer a guided pointer setup only after a compatible extra button is observed.
- Support no more than four active input bindings, and show feature-specific
  binding rows only when their capability is enabled.
- A synthesized Enter occurs only after a successful final insertion and an
  additional explicit binding; it is never coupled by default.

Acceptance:

- Button-down/up races cannot strand recording.
- Disconnecting the pointing device restores keyboard control and reports the
  missing binding without cancelling recoverable audio.
- Cancel inserts and sends nothing.
- Permission denial leaves all registered Carbon shortcuts working.

### 4.12 Interruption, failure, and quit recovery

Source families:

- `WF-20260617-IOS-01`
- `WF-20260617-IOS-02`
- `WF-20260501-DESKTOP-05`
- `WF-20260331-DESKTOP-05`
- `WF-20260331-ANDROID-05`

Decision: `extend` in-memory recovery and add an encrypted, bounded,
crash-resilient recovery vault.

Requirements:

- Distinguish cancelled, interrupted, recognition-failed, transform-failed,
  insertion-failed, and expired outcomes.
- Preserve bounded audio for local transcription retry when capture produced
  valid samples but no final transcript.
- To recover after process exit, encrypt eligible recovery audio with a
  per-install Keychain key before atomic persistence. This is opt-in until its
  threat model and purge tests pass.
- Recovery audio expires after 15 minutes by default and at most 24 hours by
  policy. The store has byte, item, and duration caps.
- On next launch, show Recover and Discard before normal dictation. Never retry
  automatically with a different model or setting.
- Failed History rows use explicit labels and a dedicated retry action.
- Notifications may deep-link to the item but may not auto-copy it.
- A cancelled capture inserts nothing. If valid audio exists, expose a bounded
  short-lived Undo Cancel recovery item so an accidental Escape can be retried
  locally; never transcribe or insert it automatically.

Acceptance:

- Kill, crash, `Cmd-Q`, sleep, route loss, model failure, and insertion failure
  fixtures each produce exactly the documented outcome.
- Key loss, corruption, partial writes, expiry, and full-store conditions fail
  closed and are erasable.
- Successful retry deletes audio immediately; transcript retention then follows
  the independent History policy.
- A user can always copy a recovered final transcript without insertion.

### 4.13 History, copy actions, and local retention

Source families:

- `WF-20260424-DESKTOP-03`
- `WF-20260331-ANDROID-04`
- `WF-20260331-ANDROID-05`

Decision: `extend` `HistoryStore`.

Requirements:

- Offer local retention modes: Never, 24 Hours, 7 Days, 30 Days, 90 Days, and
  bounded Custom. Never is the default for new privacy-first installs unless
  onboarding explicitly enables History.
- A History item stores raw final text, reversible revision metadata, insertion
  outcome, language, timestamps, duration, and finite failure category. It
  stores no audio or surrounding context.
- Clicking a completed row selects it; Copy is a separate button with visible
  confirmation. Failed rows expose Retry rather than appearing empty.
- "Copy Last" is available in the menu and HUD only when a final transcript
  exists.
- Reset All Local Data requires confirmation, closes active sessions, deletes
  every owner-only store and recovery file, clears the Keychain recovery key,
  and reports failures. It does not pretend to sign out when no account exists.

Acceptance:

- Retention pruning runs at load and after append, tolerates clock changes, and
  enforces count/byte caps.
- Disabling History offers immediate deletion and cannot strand revisions.
- Clipboard tests prove no implicit copy or loss of prior clipboard contents.
- Secure reset tests enumerate and verify every current data location.

### 4.14 Scratchpad and Quick Dictation

Source families:

- `WF-20260501-DESKTOP-01`
- `WF-20260501-IOS-01`
- `WF-20260424-IOS-01`

Decision: `new`.

Requirements:

- Provide a nonactivating floating Scratchpad opened by a configurable
  shortcut, initially Option-S unless it conflicts.
- Support multiple tabs, a notes sidebar, plain and rich text, inline images,
  local search, and per-note version history.
- "Quick Dictation to Scratchpad" routes the next final transcript to a new or
  selected note without requiring a focused third-party field.
- Notes are local, owner-only, and bounded by item, version, image, and total
  byte quotas. Large images are rejected before copying.
- Scratchpad survives app restart. It remains fully useful without an account
  or network.
- Optional cross-device sync is separately gated through the encrypted sync
  specification. No sync claim ships until another first-party client passes
  conflict and recovery tests.

Acceptance:

- Opening, dictating, editing, and closing never steals focus unless the user
  explicitly activates the editor.
- Version history restores text and image references atomically.
- Conflicting shortcuts are detected without losing the previous binding.
- Local-only, offline, quota, corruption, and migration tests pass.

### 4.15 Insights and shareable summaries

Source family:

- `WF-20260424-DESKTOP-01`

Decision: `extend` local aggregate insights and add explicit opt-in advanced
views.

Requirements:

- Usage view includes words per minute, total dictated words, cleanup changes,
  vocabulary/snippet matches, app-category breakdown, and a daily streak
  heatmap.
- Voice view is generated locally after at least 2,000 retained words and may
  show most-corrected terms and active-time patterns. Archetype and catchphrase
  cards require explicit local text analysis and must label their deterministic
  method; they may not present an invented personality assessment as fact or
  run without the transcript retention needed to derive them.
- Generate accessible share cards locally. The user chooses a destination
  through the system share sheet; Autohand Voice does not post automatically.
- Comparison with other users and team leaderboards are `external` features:
  they require explicit aggregate upload, minimum cohort privacy, and a
  separately versioned control-plane contract.
- If enabled, the team leaderboard provides weekly and all-time ranges plus a
  top-three presentation, with an accessible ranked table that does not rely on
  a podium graphic.
- Insights remain independently opt-in and are deletable without deleting
  preferences or vocabulary.

Acceptance:

- Every metric documents its formula, source data, minimum sample, and
  retention.
- No chart or card requires transcript text unless the user enabled the
  corresponding local analysis.
- Local share-card generation works offline and contains no hidden metadata or
  raw transcripts.
- Team and cohort UI is absent when the external capability is unavailable.

### 4.16 Notifications, action confirmation, and status

Source families:

- `WF-20260617-IOS-01`
- `WF-20260501-DESKTOP-04`
- `WF-20260424-ANDROID-02`
- `WF-20260331-DESKTOP-06`

Decision: `new` notification policy, backed by existing diagnostics and menu
state.

Requirements:

- Define categories for failures, interrupted/recovered dictations, model
  readiness, permission changes, formatting reminders, feature education, and
  milestones. Users can mute each category independently.
- Critical active-session failures are always shown in the HUD/menu even when
  system notifications are muted.
- Notification actions acknowledge immediately with a checkmark/state change
  and are idempotent.
- A completed-dictation notification may offer an explicit Copy Last action.
  Copy occurs only after that action, reports success, and never runs merely
  because the notification was opened.
- Do not install a persistent notification. The menu-bar item remains the
  durable Mac status affordance.
- Provide a local Status view showing capture, model, shortcut, microphone,
  insertion, storage, and optional sync health. Link to an external incident
  page only for a capability that actually depends on it.
- Request notification permission in context, after explaining recovery value.

Acceptance:

- Notification denial does not hide in-app failures or block dictation.
- Duplicate event coalescing prevents repeated sounds and notification floods.
- Deep links resolve to an existing History/recovery item or show a clear
  expired state.
- Muting education or milestones never mutes operational failures inside the
  app.

### 4.17 Lifecycle, permission, and per-user isolation

Source families:

- `WF-20260702-ANDROID-01`
- `WF-20260424-ANDROID-05`
- `WF-20260331-DESKTOP-09`
- `WF-20260331-ANDROID-05`

Decision: `extend` lifecycle resilience with Mac-specific equivalents.

Requirements:

- Re-audit Microphone, Accessibility, Input Monitoring, and Notification
  authorization on activation, wake, and before the dependent action.
- Permission revocation changes state immediately and offers the exact System
  Settings destination; it never enters a silent broken loop.
- Recreate one status item, one hot-key registration, one pointer monitor, and
  one Core Audio observer after wake or process recovery.
- All application data remains in the current macOS user's Application Support
  directory with owner-only permissions. No settings leak between login
  accounts.
- HUD errors clear only when their underlying condition changes or the user
  acknowledges them.
- Add fault-injection and crash-loop guards for repeated startup failures.
- Android OEM battery, overlay, accessibility-service, navigation, shake, and
  Android-version details are captured as platform evidence but are not copied
  into the Mac runtime. Their Mac outcome is the lifecycle and permission
  recovery contract above.

Acceptance:

- Fast user switching and two local macOS accounts prove data isolation.
- Wake/revocation tests do not create duplicate handlers.
- Recovery after app relaunch is finite and cannot respawn indefinitely.
- The app reports unsupported Mac/platform state instead of attempting another
  engine.

### 4.18 Encrypted synchronization and data controls

Source family:

- `WF-20260617-DESKTOP-02`

Decision: `external` plus a native sync client; this is storage only.

Requirements:

- Separate controls for Local History, Recovery Audio, Notes Sync, History
  Sync, Vocabulary Sync, Transform Template Sync, and Diagnostic Sharing.
- Default every sync control off. Changing a local retention setting never
  enables network storage or training.
- Encrypt synchronized payloads on-device with keys unavailable to the storage
  provider. Authenticate metadata, support key rotation, and expose device
  revocation and remote-wipe status.
- Audio sync is not planned. If ever proposed, it requires a new threat model
  and explicit user authorization; it cannot inherit transcript-sync consent.
- Autohand Voice data is never used for model training. There is no training
  toggle that weakens this invariant.
- Dictionary, snippets, and transform templates follow their own sync toggles;
  they never bypass disabled sync because another product did so.
- Conflicts retain both versions until deterministic merge or user resolution.

Acceptance:

- With every sync control off, packet capture shows no user-data traffic.
- Offline edits converge after reconnect without data loss, duplication, or
  last-writer clock dependence.
- Revocation, invalid token, key loss, quota, server error, and corrupted
  ciphertext are visible and leave local data usable.
- The native feature remains hidden until the authenticated control plane and a
  second first-party client pass live end-to-end tests.

### 4.19 Account, billing, team, and compliance control plane

Source families:

- `WF-20260501-DESKTOP-07`
- `WF-20260501-DESKTOP-08`
- `WF-20260424-DESKTOP-04`
- `WF-20260331-DESKTOP-07`
- `WF-20260331-DESKTOP-08`

Decision: `external`; define native integration but do not add a web runtime to
this repository.

Requirements:

- Browser sign-in uses an ephemeral authorization session with PKCE, state,
  nonce, universal callback validation, and Keychain token storage.
- A Restore/Refresh Entitlements action reconciles signed server entitlements
  across devices without changing the local dictation data policy.
- Team invite links are scoped, expiring, revocable, auditable, and require
  authenticated acceptance. A valid accepted link adds the user without a
  second manual approval while still enforcing seat and domain policy.
- IT Admin is a non-dictating role that can manage seats, billing, policies,
  and aggregate team usage without transcript/audio access.
- HIPAA BAA status and downloadable documents come from the control plane with
  signed metadata. The native app must not imply compliance from a local
  checkbox.
- A verified BAA policy can force diagnostic sharing and every sync class off.
  It cannot disable or reroute local STT, and the native UI must explain the
  enforced settings.
- Sign Out revokes credentials and offers separately confirmed deletion of
  local data. It never deletes local transcripts as an unannounced side effect.

Acceptance:

- Authentication cancellation, callback spoofing, token expiry, device
  revocation, offline launch, and account switching are covered.
- Entitlements fail closed for paid network features while core local dictation
  remains available.
- Admin and team roles cannot retrieve transcript, audio, context, vocabulary,
  note, or transform contents.
- Completion requires live API, billing, email/link, audit, and document
  delivery proof in the control-plane repository.

### 4.20 Mobile interaction items with preserve-only Mac outcomes

Source families:

- `WF-20260702-IOS-01`
- `WF-20260617-IOS-04`
- `WF-20260501-ANDROID-01`
- `WF-20260501-ANDROID-02`
- `WF-20260424-ANDROID-02`
- `WF-20260331-ANDROID-05`

Decision: `adapt` or `preserve`.

Requirements:

- Host-app switchback becomes a stronger Mac focus invariant: Autohand Voice
  never activates itself during normal dictation and returns final text only to
  the captured valid target.
- Mobile keyboard Backspace behavior remains owned by the host app. Autohand
  Voice may expose Undo Revision and Retry, never a global Backspace handler.
- Shake-to-unsnooze has no Mac gesture equivalent. Resume remains an explicit
  menu, shortcut, or accessible HUD action with no accelerometer/pointer
  monitoring while paused.
- Mobile drawer/back navigation maps to standard macOS window commands, Escape
  dismissal, Command-W, and Full Keyboard Access.
- Persistent mobile notification removal maps to coalesced optional
  notifications plus a durable status item.
- Mobile keep-awake maps only to the bounded recording activity assertion in
  section 4.3.

Acceptance:

- The Mac app installs no gesture, back-button, or Backspace interception for
  these items.
- Focus, Undo, Escape, Command-W, clipboard, and full keyboard access smoke
  tests pass across supported surfaces.

## 5. Information architecture

### Menu bar

Keep the menu compact:

- Ready/Paused/Failure status
- Start or Stop Dictation
- Active language and style
- Copy Last
- Recover Last, when applicable
- Quick Dictation to Scratchpad
- Open Scratchpad
- History
- Status
- Settings
- Quit

### Settings

Use a native sidebar with these destinations:

1. General
2. Audio
3. Shortcuts & Pointer
4. Languages
5. Dictionary
6. Styles & Transforms
7. App Profiles
8. Scratchpad
9. History & Recovery
10. Notifications
11. Privacy & Sync
12. Models
13. Status & Diagnostics
14. Account & Team, only when compiled with the external capability

Avoid a card wall. Use open sections, semantic headings, inline status, and
containment only for selections, warnings, or reversible previews.

### Recording HUD

The compact sequence is:

```text
Ready -> Starting -> Recording -> Finalizing -> Inserting -> Done
                    |              |             |
                    +-> Interrupted+-> Recoverable+-> Retry/Copy/Discard
```

The HUD never becomes a settings dashboard. Language/style menus, warnings,
copy, and recovery expand in place only while relevant.

## 6. Accessibility and localization acceptance

- VoiceOver can start, stop, cancel, choose language/style, copy, retry,
  recover, and inspect privacy state.
- Full Keyboard Access can operate every view without a pointer.
- Every timer and progress surface has throttled accessible announcements.
- Reduce Motion, Reduce Transparency, Increase Contrast, and differentiated
  state symbols are supported.
- No action relies only on hover.
- Every new string enters the String Catalog in the same change as the feature.
- Layout tests cover German expansion, Portuguese wrapping, right-to-left
  direction, and large accessibility text.

## 7. Explicit non-goals

- Remote speech recognition or cleanup
- Silent model, microphone, route, transform, or insertion fallback
- Reading full documents, browser URLs, terminal contents, or password fields
- Automatic social posting
- Shipping an account/admin web runtime from this Swift repository
- Claiming cross-device sync before another first-party client exists
- Copying mobile-only keyboard or gesture mechanisms onto macOS
- Persisting provisional transcripts
