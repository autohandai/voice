# Autohand Voice Parity Architecture

Status: target architecture\
Companion product contract:
[`wispr-flow-parity-product-spec.md`](wispr-flow-parity-product-spec.md)

## 1. Architecture goal

Add the planned behavior without turning `VoiceSession` into a larger
stateful facade or exposing every system framework to every SwiftUI view.

The target is a small number of deep modules: each presents one compact
interface, owns its ordering and failure invariants, and is tested through the
same seam used by production callers. SwiftUI remains presentation. AppKit and
system frameworks remain adapters at seams where behavior actually varies.

## 2. Current baseline

The current package already has useful domain implementations:

- `AudioCapture` and `AudioInputDevice` for bounded capture and route health;
- `LocalSpeechRecognizer` for the only STT path;
- `Transcript` and `ProvisionalPreviewBuffer` for final/provisional separation;
- `TextInserter` for captured-target validation and commit;
- `InMemoryAudioRecovery` for bounded transient retry;
- `HistoryStore`, `VocabularyStore`, `AppProfileStore`, and
  `UsageInsightsStore` for owner-only local data;
- deterministic `DictationCommands`, `SpeechRefinement`, and
  `SmartFormatting`;
- `VoiceLifecyclePolicy`, `DiagnosticReport`, and `OperationalIssueStore`;
- SwiftUI settings and utility views hosted by AppKit window controllers; and
- one `@MainActor` `VoiceSession` that currently coordinates most runtime work.

The plan should deepen these modules or replace their interface deliberately.
It must not create new pass-through managers with no owned behavior.

## 3. Dependency rules

```text
SwiftUI/AppKit presentation
            |
            v
   DictationCoordinator  <---- InputBindingCoordinator
            |
   +--------+---------+-------------+-------------+
   |                  |             |             |
   v                  v             v             v
AudioSession    Recognition    Revision      TextCommit
   |                  |             |             |
   +------------------+-------------+-------------+
                      |
                      v
               LocalWorkspace
                      |
              +-------+-------+
              |               |
              v               v
         RecoveryVault   OptionalSync
```

Rules:

- `AutohandVoiceCore` owns domain types, policies, persistence, and testable
  in-process implementations.
- The `AutohandVoice` executable owns AppKit, SwiftUI, Accessibility, Core
  Audio, Carbon, event taps, notifications, Keychain, and workspace adapters.
- Views observe immutable presentation models and send intents. They do not
  capture audio, instantiate recognizers, write stores, or infer recovery.
- `autohand-voice-stt` uses the same Recognition interface and local model
  implementation as the app.
- A lower module never imports a view or window controller.
- Network code, if enabled later, cannot be imported by AudioSession,
  Recognition, Revision, or TextCommit.

## 4. Deep modules

### 4.1 DictationCoordinator

Purpose: own the full session state machine and guarantee one finalization and
at most one text commit.

Interface:

```swift
actor DictationCoordinator {
    func handle(_ intent: DictationIntent) async -> DictationSnapshot
    func snapshots() -> AsyncStream<DictationSnapshot>
}
```

Callers learn one intent vocabulary and one snapshot shape. Capture,
recognition, formatting, persistence, notification, and insertion ordering
remain implementation details.

Core intents:

- `start(origin:profile:)`
- `stop`
- `cancel`
- `selectLanguage`
- `selectStyle`
- `retryRecovery`
- `retryInsertion(target:)`
- `copyFinal`
- `discardRecovery`
- `handleLifecycleEvent`

State:

```text
idle
  -> starting(target, policy)
  -> recording(session)
  -> finalizing(session)
  -> revising(rawFinal)
  -> committing(revision, target)
  -> completed(result)

Any active state
  -> interrupted(recovery)
  -> recoverable(recovery)
  -> idle

Any state
  -> failed(category, recoverability)
```

Invariants:

- A session has one UUID and monotonic start time.
- `start` is rejected unless the prior state is idle or terminal.
- A stop/cancel/limit/lifecycle race resolves through one terminal transition.
- Provisional text can appear only in `recording`.
- Only a `RawFinalTranscript` may enter Revision.
- Only a `CommittedRevision` may enter TextCommit.
- Completion records exactly one insertion outcome.
- Cancellation never creates a final, revision, History item, or insertion.

Migration:

1. Extract the current transition policy from `VoiceSession` into pure tests.
2. Make `VoiceSession` a presentation adapter over coordinator snapshots.
3. Move side-effect ordering behind the coordinator interface.
4. Delete duplicated state from `VoiceSession` after parity tests pass.

### 4.2 AudioSession

Purpose: choose a ranked route, capture bounded audio, expose throttled meters,
handle route changes, and finalize one local audio artifact.

Interface:

```swift
actor AudioSession {
    func prepare(_ policy: AudioPolicy) async throws -> PreparedAudioRoute
    func start(_ route: PreparedAudioRoute) async throws -> AudioSessionID
    func events(for id: AudioSessionID) -> AsyncStream<AudioEvent>
    func stop(_ id: AudioSessionID) async throws -> FinalAudioArtifact
    func cancel(_ id: AudioSessionID) async
}
```

The interface hides AVFoundation/Core Audio device discovery, resampling,
clamshell detection, activity assertions, route handoff, metering, and spooling.

Implementation requirements:

- Real-time callbacks do no file I/O, model work, logging interpolation, or
  unbounded allocation.
- Meter streams use a newest-value buffer and UI updates are throttled.
- Capture resamples to the recognizer's documented format once.
- Ranked route resolution uses stable device IDs and returns a visible reason.
- A route handoff creates an explicit segment boundary.

Twenty-minute feasibility:

- Start with a measured spike against the pinned FluidAudio streaming/final
  decoder.
- Preferred implementation is a bounded encrypted chunk spool with sequential
  local final decoding.
- If authoritative final decoding requires contiguous Float32 input, the
  maximum allocation is approximately 76.8 MB at 16 kHz mono for 20 minutes;
  the implementation must preflight memory pressure and retain a fixed hard
  cap.
- Preview output is never reused as authoritative final text.
- The five-minute limit remains until accuracy, memory, cancellation, and
  recovery gates pass under the new cap.

System adapters:

- `AVAudioEngineCaptureAdapter` and a deterministic test adapter;
- `CoreAudioRouteAdapter` and a simulated route adapter;
- `ProcessActivityAdapter` and a no-op test adapter.

These are real seams because production and deterministic test behavior both
exist.

### 4.3 Recognition

Purpose: validate the selected local model, transcribe a finalized local audio
artifact, and emit provisional preview without permitting commit.

Interface:

```swift
actor Recognition {
    func validate(_ profile: RecognitionProfile) async throws -> ModelReceipt
    func preview(_ chunks: AsyncStream<AudioChunk>,
                 profile: RecognitionProfile) -> AsyncStream<ProvisionalText>
    func transcribe(_ artifact: FinalAudioArtifact,
                    profile: RecognitionProfile) async throws
        -> RawFinalTranscript
}
```

Invariants:

- The only production adapter is the pinned FluidAudio/CoreML implementation.
- Model profile and language are fixed for the session.
- Preview cancellation finishes before final decoding begins.
- A failure exposes a finite category and never chooses another engine.
- Model receipts include artifact version, checksum, language coverage, and
  validation time.

No generic "speech provider" port should be introduced. There is one product
engine, so a provider abstraction would be hypothetical indirection. Tests use
the Recognition interface with a local deterministic implementation owned by
the module.

### 4.4 Revision

Purpose: convert immutable raw final text into a reversible chain of local
revisions.

Interface:

```swift
actor Revision {
    func propose(raw: RawFinalTranscript,
                 policy: RevisionPolicy,
                 context: MinimalContext?) async -> RevisionResult
    func transform(input: RevisionInput,
                   transform: TransformID) async -> RevisionResult
    func undo(_ id: RevisionID) async throws -> TranscriptRevision
    func redo(_ id: RevisionID) async throws -> TranscriptRevision
}
```

Owned behavior:

- explicit dictation commands;
- Literal/Light/Medium deterministic refinement;
- dictionary priority and usage accounting;
- spacing, capitalization, and punctuation;
- app/style/temporary-override precedence;
- optional High/local Transform model;
- structured change sets and parent-child revision links.

Data model:

```swift
struct TranscriptRevision {
    let id: UUID
    let rootRawID: UUID
    let parentID: UUID?
    let text: String
    let kind: RevisionKind
    let policyVersion: String
    let modelReceipt: ModelReceipt?
    let changes: [BoundedTextChange]
    let createdAt: Date
}
```

Invariants:

- Raw final text is append-only until retention deletes the entire record.
- Deterministic cleanup produces the same output for the same versioned input.
- Local Transform failures return an unchanged revision result.
- A revision has maximum input, output, prompt, change-count, and depth limits.
- Context is memory-only and absent from the stored revision.

Local Transform model:

- Add no remote inference interface.
- Use a separate signed CoreML artifact, local validation, ANE execution where
  supported, cancellation, and explicit memory/disk budgets.
- Do not bundle or download it until model license, quality, and privacy review
  passes.
- Feature flag: `AUTOHAND_VOICE_LOCAL_TRANSFORMS`.

### 4.5 TextCommit

Purpose: resolve one insertion plan against the captured target, commit once,
and preserve host state.

Interface:

```swift
@MainActor
final class TextCommit {
    func captureTarget() throws -> TextTargetToken
    func commit(_ revision: CommittedRevision,
                to token: TextTargetToken,
                profile: CommitProfile) throws -> CommitReceipt
}
```

`TextTargetToken` contains only what is required to revalidate identity:
process ID, bundle identifier, Accessibility element identity/role, selection
metadata, and the minimum adjacent context allowed by policy.

Strategies are internal:

1. Accessibility replacement where the control supports it;
2. clipboard-preserving paste with pre- and post-event target validation;
3. terminal-safe Unicode event insertion only for tested profiles and with
   explicit Accessibility authorization.

Invariants:

- Target validation occurs immediately before every side effect.
- A strategy failure does not cascade to another strategy unless the next
  strategy is explicitly safe for the same validated target.
- Clipboard contents and types are restored exactly.
- Selection replacement participates in host Undo when the host supports it.
- Commit receipts contain no transcript text.

The external seam is macOS Accessibility/event delivery. Production and
in-memory target adapters share the same module interface.

### 4.6 InputBindingCoordinator

Purpose: own keyboard, pointer, menu, and Scratchpad triggers and reduce them to
`DictationIntent`.

Interface:

```swift
@MainActor
final class InputBindingCoordinator {
    func apply(_ configuration: InputConfiguration) throws
    var events: AsyncStream<InputIntent> { get }
}
```

Implementation:

- retain Carbon registered hot keys for normal keyboard bindings;
- add an optional CGEvent tap only for non-primary pointer buttons;
- request Input Monitoring only when pointer monitoring is enabled;
- preserve the prior working configuration when registration fails;
- treat synthesized Commit/Enter as a separate explicit binding.

Feature flag: `AUTOHAND_VOICE_MOUSE_FLOW`.

### 4.7 SensitiveContextPolicy

Purpose: make the allow/deny decision before microphone activation and provide
only the minimum context Revision or TextCommit may use.

Interface:

```swift
struct SensitiveContextPolicy {
    func decision(for target: TextTargetDescriptor,
                  profile: AppProfile) -> ContextDecision
}
```

This is pure in-process policy, so it needs no protocol or adapter.

Inputs:

- exact bundle identifier;
- Accessibility secure-field state and role;
- signed built-in sensitive-app rules;
- local user denylist;
- per-app context preference.

Outputs:

- deny capture with reason;
- allow with no context; or
- allow with a fixed context scalar limit.

It never receives window title, URL, document name, or field value.

Feature flag: `AUTOHAND_VOICE_MINIMAL_CONTEXT`.

### 4.8 RecoveryVault

Purpose: own bounded recoverability across transient failures and process exit.

Interface:

```swift
actor RecoveryVault {
    func stage(_ artifact: FinalAudioArtifact,
               metadata: RecoveryMetadata) async throws -> RecoveryID
    func list() async throws -> [RecoverySummary]
    func open(_ id: RecoveryID) async throws -> RecoveredAudioArtifact
    func resolve(_ id: RecoveryID, as: RecoveryResolution) async throws
    func purgeExpired(now: Date) async throws
}
```

Implementation:

- keep the current in-memory path for short transient failures;
- add AES-GCM encrypted chunk files for crash/quit recovery;
- generate a per-install symmetric key and store it in Keychain;
- write to a unique temporary path, fsync, atomically rename, then persist
  authenticated metadata;
- enforce item, byte, duration, and age caps before accepting a write;
- use owner-only directory and file permissions;
- delete ciphertext immediately after success/discard/expiry.

No audio filename, samples, or key material enters logs or diagnostics.

System seams:

- CryptoKit is in-process implementation;
- Keychain has production and isolated test adapters;
- filesystem uses temporary-directory stand-ins in tests, not a public port.

Feature flag: `AUTOHAND_VOICE_PERSISTENT_RECOVERY`.

### 4.9 LocalWorkspace

Purpose: provide one transactional local interface for History, revision
chains, Scratchpad, dictionary metadata, styles, and bounded search.

Interface:

```swift
actor LocalWorkspace {
    func apply(_ mutation: WorkspaceMutation) async throws -> WorkspaceReceipt
    func query(_ query: WorkspaceQuery) async throws -> WorkspacePage
    func enforceRetention(now: Date) async throws -> RetentionReport
    func erase(_ scope: ErasureScope) async throws -> ErasureReport
}
```

Storage:

- Use the system SQLite library through a small internal implementation for
  transactional metadata, full-text search, retention, and note versions.
- Store Scratchpad image blobs as content-addressed owner-only files with
  database references and independent byte caps.
- Keep recovery audio outside the workspace and under RecoveryVault ownership.
- Keep secrets and sync keys in Keychain, never SQLite.

Schema entities:

- `history_item`
- `transcript_revision`
- `dictionary_entry`
- `dictionary_usage`
- `style`
- `transform_template`
- `scratchpad_note`
- `scratchpad_version`
- `scratchpad_asset`
- `daily_metric`
- `operational_issue`
- `migration_ledger`

Migration:

1. Open read-only and validate the legacy JSON stores.
2. Import into a new SQLite file inside one transaction.
3. Compare counts and checksums for non-secret payloads.
4. Mark migration complete without deleting legacy files.
5. Read the new store behind an off-by-default flag.
6. After a release with rollback evidence, offer deletion of legacy stores.

Limits are centralized in a versioned `WorkspaceLimits` value and verified on
both mutation and load. No view supplies its own limit.

Feature flags:

- `AUTOHAND_VOICE_WORKSPACE_V2`
- `AUTOHAND_VOICE_SCRATCHPAD`
- `AUTOHAND_VOICE_ADVANCED_INSIGHTS`

### 4.10 NotificationPolicy

Purpose: turn domain events into coalesced in-app and system notifications
without hiding failures when system permission is denied.

Interface:

```swift
actor NotificationPolicy {
    func handle(_ event: ProductEvent,
                preferences: NotificationPreferences) async
        -> NotificationDisposition
}
```

Owned behavior:

- category mute policy;
- event coalescing and rate limits;
- action/deep-link identity;
- visible action acknowledgement;
- expired-item behavior;
- separation of system notification from mandatory in-app status.

The UNUserNotificationCenter adapter is a real external seam with production
and deterministic test adapters.

Feature flag: `AUTOHAND_VOICE_NOTIFICATIONS`.

### 4.11 ReliabilityLedger

Purpose: store redacted finite counters and latency buckets, evaluate local
service-level objectives, and export a safe report.

Interface:

```swift
actor ReliabilityLedger {
    func record(_ event: ReliabilityEvent) async
    func snapshot(_ interval: DateInterval) async -> ReliabilitySnapshot
    func exportRedacted() async throws -> Data
    func reset() async throws
}
```

Allowed fields:

- date bucket;
- app/model/policy schema versions;
- finite event category;
- bounded latency bucket;
- success/failure count;
- platform and supported-state booleans.

Forbidden fields:

- audio, transcript, revision, prompt, note, context, path, username,
  microphone name, bundle identifier, URL, credential, or arbitrary error text.

### 4.12 OptionalSync

Purpose: synchronize approved workspace records as end-to-end encrypted opaque
objects without affecting local dictation.

Interface:

```swift
actor OptionalSync {
    func configure(_ policy: SyncPolicy) async throws
    func enqueue(_ changes: [SyncChange]) async
    func reconcile() async -> SyncReport
    func revokeDevice(_ id: DeviceID) async throws
}
```

External port:

```swift
protocol EncryptedObjectTransport: Sendable {
    func exchange(_ request: OpaqueSyncRequest) async throws
        -> OpaqueSyncResponse
}
```

This port is justified only when there are two adapters: authenticated
production transport and an in-memory deterministic transport used for
conflict/offline tests. The server sees ciphertext, opaque object IDs, version
vectors, and bounded routing metadata.

Conflict policy:

- device-scoped monotonic counters, never wall-clock last-writer-wins;
- immutable revision objects;
- note conflicts retain both branches;
- deletes use authenticated tombstones with bounded retention;
- users can inspect and resolve unresolved note conflicts locally.

Network prohibition:

- AudioSession, Recognition, Revision, and TextCommit cannot import or call
  OptionalSync.
- The app works indefinitely with no account, token, or network.

Feature flag: `AUTOHAND_VOICE_ENCRYPTED_SYNC`.

### 4.13 AccountCapability

Purpose: expose authenticated entitlements and administrative links without
embedding an account/backend implementation in this repository.

Interface:

```swift
actor AccountCapability {
    func signIn() async throws -> AccountSnapshot
    func refreshEntitlements() async throws -> AccountSnapshot
    func signOut(deleteLocalData: Bool) async throws
    func openAdminResource(_ resource: AdminResource) async throws
}
```

The production adapter requires a separately owned, versioned API. A fake
adapter supports native UI tests, but mock evidence cannot release the feature.
Core local dictation has no entitlement check.

Feature flag: `AUTOHAND_VOICE_ACCOUNTS`.

## 5. Presentation models

Views receive purpose-built immutable values:

- `HUDPresentation`
- `MenuPresentation`
- `SettingsPresentation`
- `HistoryPresentation`
- `ScratchpadPresentation`
- `StatusPresentation`
- `RecoveryPresentation`

They never receive stores, recognizers, Accessibility elements, audio buffers,
Keychain handles, network clients, or mutable domain entities.

The HUD presentation has these finite modes:

```text
hidden
readyCompact
starting
recording
recordingWarning
finalizing
inserting
completed
recoverable
failed
```

Placement and opacity are preferences; state is coordinator-owned.

## 6. Persistence and privacy ledger

| Data | Default | Limit | Retention | Encryption | Sync |
| --- | --- | --- | --- | --- | --- |
| Preferences | on | 256 KB | until reset | owner-only file | selected fields only |
| Raw/final History | off | 500 items and 8 MB text | selected policy | owner-only SQLite | independently opt-in |
| Revision chains | follows History | 16 revisions/item | follows root | owner-only SQLite | follows History only |
| Dictionary | on | 5,000 entries | until delete/reset | owner-only SQLite | independently opt-in |
| Scratchpad | off until enabled | 1,000 notes, 100 versions/note, 500 MB assets | until delete/reset | owner-only SQLite/files | independently opt-in |
| Recovery audio | memory-only by default | 3 items, 25 minutes, 128 MB | 15 minutes default, 24 hours max | AES-GCM + Keychain | never |
| Usage insights | off | 366 daily rows | rolling year | owner-only SQLite | aggregates only, separate opt-in |
| Reliability ledger | on, redacted | 366 daily rows | rolling year | owner-only SQLite | never by default |
| Operational issues | on, finite categories | 30 days | rolling | owner-only SQLite | never |
| Sync credentials/keys | absent | one active account/install | until revoke/reset | Keychain | n/a |

Exact caps require performance validation before implementation. Any increase is
a schema/policy change with tests, not an unbounded view preference.

## 7. Error model

Replace arbitrary user-facing strings as state with a finite domain error:

```swift
enum VoiceFailureCategory {
    case unsupportedPlatform
    case permission(PermissionKind, PermissionState)
    case shortcut(ShortcutFailure)
    case pointer(PointerFailure)
    case microphone(MicrophoneFailure)
    case audioRoute(AudioRouteFailure)
    case capture(CaptureFailure)
    case model(ModelFailure)
    case recognition(RecognitionFailure)
    case revision(RevisionFailure)
    case target(TargetFailure)
    case insertion(InsertionFailure)
    case recovery(RecoveryFailure)
    case storage(StorageFailure)
    case notification(NotificationFailure)
    case sync(SyncFailure)
    case account(AccountFailure)
}
```

Every category defines:

- whether raw/final text or audio is recoverable;
- one primary remediation;
- safe diagnostic fields;
- whether retry is idempotent;
- whether the user may continue with literal/local behavior; and
- whether the event belongs in the redacted reliability ledger.

## 8. Concurrency and resource policy

- UI and macOS Accessibility/window work stays on `@MainActor`.
- Dictation orchestration, persistence, recovery, notifications, and sync are
  isolated actors.
- Real-time audio callbacks cross to actors through fixed-size buffers.
- Every `AsyncStream` declares a buffering policy and termination cleanup.
- Every task has one owner and cancellation path.
- Timers use `ContinuousClock` for session behavior and wall clock only for
  displayed dates/retention.
- Database work is serialized by LocalWorkspace.
- Sync never holds a database transaction across an await/network call.
- Keychain and encrypted-file work never runs on the audio callback.

## 9. Test architecture

The interface is the test surface.

### Pure/in-process

- transition reducer;
- route ranking policy;
- sensitive-context policy;
- cleanup/style precedence;
- dictionary ranking and normalization;
- retention and quota policy;
- error-to-remediation mapping.

### Local-substitutable

- LocalWorkspace against temporary SQLite/files;
- RecoveryVault against temporary files and isolated test keys;
- Recognition against generated samples and a deterministic local fake;
- encrypted sync conflict logic against the in-memory transport.

### System-adapter integration

- Core Audio route changes;
- AVAudioEngine capture;
- Carbon registration;
- optional pointer event tap;
- Accessibility target validation and insertion;
- system notifications and deep links;
- Service Management/wake;
- Keychain persistence;
- browser authentication callback.

### Evaluation corpus

Do not commit user recordings. Commit only the schema, generated fixtures,
expected transformations, license requirements, and checksum manifest. Run
accuracy evaluation against an approved local corpus outside Git and publish
only aggregate, privacy-reviewed results.

## 10. Architectural completion gates

- `VoiceSession` no longer owns duplicated domain state or persistence details.
- Each system side effect crosses one named seam.
- No network import exists in the audio, recognition, revision, or commit
  modules.
- A source-level test confirms `SpeechEngine` has only CoreML and diagnostics
  always report remote fallback disabled.
- Every store passes permission, corruption, size, migration, retention, and
  erase tests.
- Every feature flag defaults off until its package passes its release gate.
- A network-disabled real Apple Silicon dictation still succeeds after all
  optional features are compiled in.
