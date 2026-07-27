# Autohand Voice Product and App-Layer Roadmap

Market snapshot: 2026-07-27

## Objective

Make Autohand Voice the most trustworthy native dictation utility for Apple
Silicon Macs: fast to understand, dependable in every supported text field, and
private by construction.

This roadmap compares the current working tree with leading products and
defines 20 improvements worth implementing. It deliberately preserves the
product contract:

- speech recognition remains local;
- CoreML on the Apple Neural Engine remains the only STT path;
- no remote transcription, cleanup, sync, or silent fallback is introduced;
- provisional text is never inserted into another app;
- user text, selection, cursor, and clipboard state remain protected;
- audio, tasks, logs, history, and temporary data remain bounded.

## Current baseline

Autohand Voice already has a strong privacy and runtime foundation:

- native Swift and CoreML transcription with pinned FluidAudio;
- final-transcript-only insertion through Accessibility APIs;
- direct insertion that does not replace the clipboard;
- a registered Control-Option-Space global shortcut that does not require
  Input Monitoring;
- menu-bar state for ready, microphone startup, recording, local processing,
  and failure;
- direct and clipboard output modes;
- explicit permission links, pause/resume, sound feedback, and copy-last;
- bounded five-minute in-memory audio capture;
- CLI health checks, configuration, and audio-file transcription;
- no remote engine or automatic fallback.

The largest product gap is the app layer. The executable currently builds an
AppKit `NSStatusItem` menu directly and has no SwiftUI `App`, `MenuBarExtra`,
`Settings` scene, onboarding, history window, model manager, or accessible
recording overlay. Some stored preferences, notably launch at login, are not
wired to runtime behavior.

## Market benchmark

This is a representative benchmark of the major native and cross-platform
options visible in the market, not a claim that every small dictation utility
has been exhaustively catalogued.

| Product | Notable capabilities | Opportunity for Autohand Voice |
| --- | --- | --- |
| Apple Dictation and Voice Control | System integration, spoken editing commands, spelling mode, custom vocabulary, interactive tutorial, and VoiceOver interoperability | Match the native learnability and accessibility while offering a clearer local-model and failure contract |
| Wispr Flow | Context-aware formatting, custom dictionary, snippets, hands-free mode, scratchpad, history, retry, and visible interruption recovery | Deliver the reliability and recovery features without cloud storage or cursor-context collection |
| Superwhisper | Custom modes, context, file transcription, language selection, microphone configuration, local and cloud model choices | Offer focused local modes and file workflows without provider configuration or privacy ambiguity |
| VoiceInk | Offline dictation, custom vocabulary, language/model/hotkey controls, and visible recording animations | Match customization and feedback while retaining ANE-only execution and stronger state preservation |
| Spokenly | History, app-aware modes, word replacements, smart spacing/capitalization/paragraphs, file transcription, device controls, diagnostics, and VoiceOver improvements | Prioritize the same workflow polish with a smaller, auditable, local-only surface |
| MacWhisper | File transcription, rich editing/search/export, subtitles, meeting capture, and local models | Add a focused file-transcription window; do not expand into meeting capture until core dictation reliability is complete |
| Willow | Smart formatting, style matching, learned vocabulary, snippets, multilingual input, and noisy/quiet speech support | Build deterministic local formatting, vocabulary, and audio health rather than opaque cloud personalization |
| Typeless | Contextual tone, personal dictionary, translation, and local device history | Provide private per-app profiles and local history, but avoid remote rewriting and translation |
| Monologue | Local mode, local history controls, language selection, input-device selection, and recovery after audio changes or interruption | Treat device changes, sleep/wake, interruption, and recoverability as first-class product behavior |
| BetterDictation | Guided setup, external microphone selection, and text cleanup | Match its low-friction setup while keeping cleanup deterministic and local |

Primary product sources:

- [Apple Voice Control](https://support.apple.com/guide/mac-help/use-voice-control-commands-mh40719/mac)
- [Apple accessibility features](https://www.apple.com/accessibility/features/)
- [Wispr Flow updates](https://wisprflow.ai/whats-new)
- [Wispr Flow context awareness](https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness)
- [Superwhisper overview](https://superwhisper.com/docs/get-started/introduction)
- [VoiceInk features](https://www.voice-ink.com/)
- [Spokenly macOS releases](https://spokenly.app/releases/macos)
- [MacWhisper features](https://goodsnooze.gumroad.com/l/macwhisper)
- [Willow features](https://willowvoice.com/)
- [Typeless features](https://www.typeless.com/)
- [Monologue local processing](https://help.monologue.to/en/articles/14178204-how-do-i-switch-between-local-and-cloud-processing)
- [BetterDictation help](https://betterdictation.com/help)

## The 20 improvements

Current Phase A delivery:

- implemented: native SwiftUI settings window, guided first-run setup,
  contextual permission center, local-model preparation state,
  `SMAppService` launch-at-login control, redacted diagnostics, and an
  accessible nonactivating recording HUD;
- retained: the existing AppKit status item and Carbon registered hot key for
  runtime compatibility;
- implemented: remembered Core Audio microphone selection, system-default
  tracking, hot-plug refresh, bounded level metering, an eight-second local
  microphone test, and visible no-signal, clipping, and disconnect states;
- next: configurable recording modes and insertion recovery.

### 1. Native SwiftUI app shell and Settings scene

Priority: P0

Replace the menu-only product surface with a SwiftUI app shell that retains the
lightweight menu-bar workflow and adds a standard Settings window. Use
`MenuBarExtra` for common actions and a `Settings` scene for General, Audio,
Shortcut, Language, Vocabulary, Privacy, and Advanced panes. Keep AppKit only
where Carbon hot-key registration and Accessibility insertion require it.

Apple direction:

- use `Settings` so macOS owns Command-comma presentation and window lifecycle;
- use a window-style `MenuBarExtra` only if its richer status UI remains compact;
- use `@MainActor @Observable` app state owned by `@State`;
- use native controls, `Button`, `Form`, `TabView`, and semantic text styles.

Acceptance:

- every persisted preference is visible and editable in Settings;
- menu-bar recording remains usable when the Settings window is closed;
- keyboard-only and VoiceOver navigation reach every control;
- no duplicate runtime/session object is created by scene redraws.

### 2. Short, interactive onboarding and permission center

Priority: P0

Add an optional first-run flow that explains local processing, tests the
shortcut, shows live microphone level, and requests Microphone and Accessibility
permission only when their benefit is clear. The same checks remain available
later in a Permission Center.

Apple direction:

- keep onboarding fast, optional, and interactive;
- postpone nonessential customization;
- request private-resource access in context;
- show the exact system setting and a retry/check-again action after denial.

Acceptance:

- a new user can reach a successful test dictation without reading documentation;
- denied, restricted, and not-determined states have distinct guidance;
- relaunch is requested only when macOS actually requires it;
- onboarding never claims the model is offline-ready until model files load.

### 3. Accessible recording HUD

Priority: P0

Show a small, nonactivating floating HUD while starting, recording, processing,
or failed. Include the current state, elapsed time, input level, selected
microphone, and Stop/Cancel affordance. The menu-bar icon remains the quiet
default; users can disable the HUD.

Apple direction:

- use a SwiftUI panel hosted in a nonactivating AppKit panel where necessary;
- respect Reduce Motion, Increase Contrast, and Reduce Transparency;
- never communicate recording state by color or animation alone;
- provide VoiceOver labels and a stable keyboard escape action.

Acceptance:

- the HUD follows Spaces without stealing focus from the target text field;
- it never changes the frontmost app or insertion target;
- level updates are throttled and do not cause unbounded SwiftUI invalidations;
- processing and failure are visibly different from active recording.

### 4. Configurable shortcut and recording modes

Priority: P0

Status: implemented with local key capture, Carbon conflict rollback,
lifecycle re-registration, and hold, toggle, and hands-free modes.

Support user-defined registered shortcuts plus press-and-hold, toggle, and
hands-free modes. Detect registration conflicts and provide a safe reset. Keep
the current Control-Option-Space shortcut as the default.

Privacy boundary:

- prefer registered Carbon hot keys that do not require Input Monitoring;
- do not add modifier-only shortcuts if they require global event taps;
- explain why any future shortcut shape needs broader permission before enabling
  it.

Acceptance:

- invalid and conflicting shortcuts cannot be saved;
- key-down/key-up races cannot strand the session in recording state;
- wake, fast user switching, and relaunch re-register the chosen shortcut;
- Escape cancels hands-free recording without inserting text.

### 5. Microphone picker and audio health

Priority: P0

Status: implemented in the native Settings audio section and capture path.

Add a microphone picker with “System Default,” remembered device choice,
hot-plug handling, a level meter, and a test recording. Detect no signal,
clipping, disconnection, and another-app contention with actionable messages.

Apple direction:

- discover audio devices through AVFoundation and display `localizedName`;
- store stable device identifiers, not localized names;
- observe connection and disconnection notifications;
- fall back to System Default only after telling the user that their chosen
  device disappeared.

Acceptance:

- changing devices cannot corrupt or mix an active recording;
- unplugging a device produces a recoverable visible failure;
- the selected device is restored when it returns;
- audio buffers and meters remain bounded.

### 6. Model readiness and download manager

Priority: P0

Status: implemented with FluidAudio phase progress, explicit v2 English and v3
multilingual selection, targeted repair confirmation, storage measurement,
cancellation, failure classification, and CoreML load validation timestamps.

Move first-use model preparation out of the first real dictation. Show model
name, language coverage, download/compile progress, size, local readiness,
last validation, and a repair action. Allow explicit v2 English and v3
multilingual selection only after compatibility testing.

Acceptance:

- offline-ready status is verified by loading the selected local model;
- download, storage, checksum, compile, and load failures are distinct;
- cancellation cannot leave a model falsely marked ready;
- model repair never deletes unrelated caches or user data.

### 7. Insertion compatibility and recovery

Priority: P0

Status: implemented with pre-recording target and selection capture,
focus validation, clipboard-preserving fallback, and Retry Here, Copy, and
Discard recovery actions.

Build an insertion compatibility layer that records the target application and
selection state before recording, validates the focused element before commit,
and reports when focus moved. Offer explicit Copy, Retry Here, and Discard
actions after insertion failure.

Privacy boundary:

- inspect only the minimum Accessibility attributes needed for insertion;
- do not read surrounding document text by default;
- never use the clipboard as an invisible transport for direct insertion.

Acceptance:

- selected text is replaced only when the original target remains valid;
- focus changes never insert into an unintended app;
- a failed insertion leaves the final transcript recoverable in memory;
- successful insertion participates in the target app’s normal Undo behavior
  where the Accessibility control supports it.

### 8. In-memory failed-dictation recovery

Priority: P0

Status: implemented with a five-minute maximum sample cap, 15-minute
in-memory expiry, local transcription retry, and explicit discard.

Keep bounded audio samples in memory until transcription and insertion either
succeed or the user explicitly discards them. Permit retrying local
transcription after model or transient runtime failure. Do not write recovery
audio to disk.

Acceptance:

- a transient model-load failure can be retried without speaking again;
- recovery data is erased on success, discard, timeout, or process exit;
- the UI states exactly what remains recoverable;
- memory use remains capped by the five-minute recording limit.

### 9. Optional local text history

Priority: P1

Status: implemented as an opt-in resizable SwiftUI history window with local
search, copy, per-item deletion, confirmed delete-all, JSON export, retention
limits, and inserted versus insertion-failed outcomes.

Add an opt-in, text-only transcription history with search, copy, delete,
delete-all, and configurable retention. Default to off for existing users.
Store no audio and no surrounding cursor context.

Apple direction:

- present history in a resizable `Window` with a native `Table` or `List`;
- use stable item identity and locale-aware dates;
- add destructive confirmations and accessible empty states;
- expose export through `fileExporter`.

Acceptance:

- history is local, owner-only, bounded by count and age, and easy to erase;
- disabling history offers to remove existing entries;
- failures and successful insertions are distinguishable;
- search never sends text to a service or external process.

### 10. Local vocabulary and word replacements

Priority: P1

Status: implemented with deterministic longest-match replacement,
case preservation, final-transcript-only application, owner-only storage,
before/after testing, duplicate protection, and CSV/JSON import and export.

Add named vocabulary entries and deterministic word replacements for names,
brands, technical terms, and acronyms. Support CSV/JSON import and export.
Apply replacements to the final transcript before insertion and show the
before/after diff in a test view.

Acceptance:

- replacement order is deterministic and tested for overlapping phrases;
- word boundaries and case preservation are locale-aware;
- vocabulary remains local and owner-only;
- malformed imports report row-level errors without losing valid existing data.

### 11. Local dictation commands

Priority: P1

Status: implemented as an opt-in English grammar with an explicit `command`
prefix, punctuation and paragraph controls, literal mode, current-buffer
scratch, cancel-without-commit, and locale-specific fixtures.

Support a small explicit command grammar: new line, new paragraph, comma,
period, question mark, literal mode, scratch that, and cancel dictation.
Interpret commands in the provisional session buffer and commit only the final
result.

Acceptance:

- users can disable commands or choose literal dictation;
- ambiguous spoken phrases remain literal rather than being silently removed;
- “scratch that” affects only the current uncommitted dictation;
- command parsing has locale-specific XCTest fixtures.

### 12. Smart spacing, capitalization, and paragraphs

Priority: P1

Status: implemented as opt-in deterministic formatting using only the captured
selection and at most one adjacent character per side, with a native preview,
literal fallback for unknown context, and in-memory access to the prior text.

Add deterministic local formatting for mid-sentence insertion, leading/trailing
spaces, capitalization, terminal punctuation, and paragraph breaks. Avoid an
LLM cleanup dependency.

Privacy boundary:

- use only minimal target metadata by default, such as whether a selection
  exists and the immediately adjacent character when safely available;
- make any surrounding-text access explicit and independently disableable.

Acceptance:

- insertion at the start, middle, and end of text is covered by tests;
- code editors and terminals can disable prose formatting per app;
- formatting changes are previewable and reversible;
- user-spoken punctuation is not duplicated.

### 13. Per-app profiles

Priority: P1

Status: implemented with bounded owner-only storage, exact bundle-identifier
matching, global fallback for every override, native management for running or
manual apps, and visible active-profile state in Settings and the menu.

Let users bind settings to a frontmost application bundle identifier: output
mode, shortcut mode, language/model, command grammar, formatting, HUD visibility,
and sound feedback. Include a clear global fallback.

Acceptance:

- profiles match bundle identifiers rather than localized app names;
- deleting or renaming an app does not break global dictation;
- the active profile is visible before recording;
- profile selection does not read window or document contents.

### 14. Language and model profiles

Priority: P1

Status: implemented with the pinned runtime’s finite English v2 and
25-European-language v3 lists, per-language test phrases, compatible automatic
model selection, blocked active-session changes, and confirmed removal limited
to known model caches.

Expose the pinned Parakeet v3 multilingual coverage and the v2 English-focused
model as explicit local profiles. Provide language guidance and a test phrase
instead of promising unsupported automatic detection or 100+ languages.

Acceptance:

- supported languages come from the pinned runtime’s tested capability list;
- model switches are blocked during recording and processing;
- users can download, validate, and remove only known Autohand Voice models;
- the UI distinguishes language selection from translation, which is not
  provided.

### 15. Provisional live preview with final-only commit

Priority: P1

Status: implemented as an opt-in, bounded FluidAudio sliding-window session
shown only in the nonactivating HUD. Preview text is explicitly provisional,
cannot pass the final-transcript gate, and is cancelled and cleaned up before
the single authoritative final transcription and insertion.

Use FluidAudio’s local sliding-window/streaming support to show provisional text
inside the Autohand Voice HUD or scratchpad. Never stream provisional text into
the target app. On stop, run finalization and insert exactly one final
transcript.

Acceptance:

- provisional text is visually and accessibly labelled as provisional;
- only one final insertion event occurs;
- preview cancellation inserts nothing;
- streaming tasks and decoder state are cancelled and released predictably.

### 16. Native file-transcription window

Priority: P1

Status: implemented with a SwiftUI file importer, preflight audio validation,
explicit security-scoped access ownership, local progress and cancellation,
editable final text, copy, and plain-text or Markdown export.

Bring the existing CLI file transcription into the app with `fileImporter`,
progress, cancellation, editable final text, Copy, and plain-text/Markdown
export. Keep the scope to transcription; meeting capture, system audio,
speaker diarization, and cloud summaries are separate future products.

Acceptance:

- security-scoped file access is started and stopped correctly;
- unsupported formats fail before model work begins;
- cancellation releases file access and tasks;
- imported media and generated text are never uploaded.

### 17. Launch at login and lifecycle resilience

Priority: P1

Status: implemented with `SMAppService.mainApp` status-driven controls,
debounced wake restoration for one Carbon hot-key registration, recreated Core
Audio device observation, in-memory recovery for sleep-interrupted capture, and
explicit confirmation before quitting during a recording.

Wire the existing `launchAtLogin` preference through
`SMAppService.mainApp`. Restore hot-key registration and audio-device
observation after sleep/wake, and make termination during recording explicit.

Acceptance:

- the toggle reflects actual Service Management status, including approval
  required and denied states;
- no legacy login-item helper or shell script is introduced;
- wake does not create duplicate hot-key handlers;
- an interrupted dictation is either recoverable in memory or clearly reported.

### 18. Private usage insights

Priority: P2

Status: implemented as independently opt-in, owner-only daily aggregates
bounded to 366 rows, with monotonic duration inputs, a Swift Charts view,
accessible summary and table, a documented 40-WPM estimate, and full reset.

Provide an optional local dashboard for dictation count, words, recording time,
processing latency, insertion success, and estimated typing time saved. Store
aggregates rather than transcript content when history is off.

Apple direction:

- use Swift Charts with an accessible summary and data table;
- use locale-aware date and number formatting;
- explain the estimate and let users reset all statistics.

Acceptance:

- metrics collection is local and independently disableable;
- charts remain understandable with VoiceOver and without color;
- no transcript text is required for aggregate metrics;
- counters are bounded and resilient to clock changes.

### 19. Accessibility and localization baseline

Priority: P0 and continuous

Treat VoiceOver, Full Keyboard Access, Dynamic Type, Reduce Motion, increased
contrast, and localization as release requirements for every app-layer feature.
Create an English String Catalog now so future localization does not require a
UI rewrite.

Acceptance:

- every icon-only action has a label and hint where needed;
- state is never conveyed only through color, animation, or sound;
- layouts survive long localized strings and right-to-left direction;
- VoiceOver can complete onboarding, configure dictation, start/stop a test,
  recover a transcript, and erase history.

### 20. Diagnostics and privacy center

Priority: P0

Create a single screen for platform support, permissions, registered shortcut,
selected microphone, live signal, model readiness, disk use, app version,
recent bounded operational errors, and the invariant “Remote fallback:
disabled.” Add Copy Diagnostic Report with automatic redaction.

Acceptance:

- the report never includes transcript text, audio, file paths, usernames,
  focused-control contents, credentials, or environment values;
- each failing check has one clear remediation action;
- error logs have count and age bounds;
- CLI `check --json` and the app use the same diagnostic domain model.

## Recommended delivery order

### Phase A: trustworthy first run

Implement 1, 2, 5, 6, 19, and 20. These turn the current runtime into a product
that users can understand and repair without Terminal access.

### Phase B: dependable daily dictation

Implement 3, 4, 7, 8, and 17. These reduce lost dictations and unintended
insertion, which matter more than adding generative formatting.

### Phase C: accuracy and workflow

Implement 10, 11, 12, 13, 14, and 15. Keep all processing local and make
behavior previewable.

### Phase D: power-user surfaces

Implement 9, 16, and 18 after retention, deletion, accessibility, and export
contracts are tested.

## Features intentionally not recommended now

- Cloud transcription or remote cleanup: violates the product’s differentiator
  and failure contract.
- Silent fallback to another STT engine: violates the explicit single-engine
  contract.
- Account creation and cross-device cloud sync: adds privacy, security, and
  support cost before the local Mac experience is complete.
- Meeting recording and system-audio capture: materially expands consent,
  storage, diarization, and legal requirements.
- Agentic computer control: overlaps Apple Voice Control and greatly expands the
  Accessibility attack surface.
- Automatic reading of nearby cursor context: competitors use it for formatting,
  but it should remain an explicit future opt-in, not a default.
- Liquid Glass: the app targets macOS 14+, and no visual redesign requiring it
  was requested. Use stable native materials and controls with version-gated
  enhancements only when they add functional value.

## Apple implementation references

- [Settings scene](https://developer.apple.com/documentation/swiftui/settings)
- [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
- [Building and customizing the menu bar with SwiftUI](https://developer.apple.com/documentation/swiftui/building-and-customizing-the-menu-bar-with-swiftui)
- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)
- [Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)
- [Menus](https://developer.apple.com/design/human-interface-guidelines/menus)
- [SMAppService registration](https://developer.apple.com/documentation/servicemanagement/smappservice/register())
- [AVCaptureDevice](https://developer.apple.com/documentation/avfoundation/avcapturedevice)

## Release gate for every roadmap item

Each feature should follow the repository workflow:

1. add a failing XCTest for its domain behavior;
2. implement the smallest native change;
3. run focused tests and `swift test`;
4. run `swift build -c release`;
5. run `./.build/release/autohand-voice check --json`;
6. run `./scripts/build-app.sh`;
7. perform a real Apple Silicon smoke test for microphone, shortcut, menu bar,
   permission, model, or insertion behavior;
8. verify offline operation and confirm there is no remote or silent fallback.
