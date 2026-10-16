# Autohand Voice

Native, private voice input for Mac (Apple Silicon and Intel). Hold Fn, talk, let go —
your words land exactly where your cursor is, and nothing you say ever leaves
your Mac.

Autohand Voice is written entirely in Swift. It records through AVFoundation,
transcribes locally with FluidAudio and CoreML on the Apple Neural Engine, then
inserts only the final transcript at the active cursor through macOS
Accessibility APIs.

On first launch, required native onboarding explains the Autohand Voice
workflow and privacy boundary, prepares Microphone and Accessibility
permissions, validates the local speech model, and finishes with a real
end-to-end dictation into a focused test field. Company, brand, and privacy
policy links use the current public Autohand pages. The guided setup can be
reopened later from Settings → Getting Started.

![Autohand Voice demo](assets/voice-animation.gif)

## Highlights

- **Fully local, always** — recording, transcription, and text insertion all
  run on-device through FluidAudio and CoreML on the Apple Neural Engine.
  There is no remote transcription service and no silent cloud fallback.
- **Hold Fn and go** — long-press Fn to dictate, then release to insert.
  Toggle and hands-free recording modes are also available, plus a
  nonintrusive HUD that shows input level and processing state without
  stealing focus from the app you're typing into.
- **Shape the result, on your terms** — local Vocabulary replacements for
  names and jargon, opt-in Smart Formatting that trims filler words, and
  explicit voice commands ("command new paragraph") when you want them.
  Everything is literal by default.
- **App-aware, not content-aware** — App Profiles override output mode,
  language, model, and formatting per application, using only the frontmost
  bundle identifier — never window titles or document content.
- **25 languages for transcription, 5 for the UI** — Parakeet v2 and v3 models
  cover 25 European languages; the app itself is localized in English,
  German, Spanish, Italian, and Portuguese.
- **Private by construction** — optional local history and usage insights
  stay on-device, are bounded, and store no transcript text unless you
  explicitly turn history on.

## Quick start

```bash
gh release download --repo autohandai/voice --pattern '*.dmg' --output AutohandVoice.dmg
open AutohandVoice.dmg
```

Drag **Autohand Voice** into **Applications**, then launch it. Until a
Developer ID certificate is configured (see [Releasing](docs/releasing.md)),
every release is ad-hoc signed, not notarized — Gatekeeper will warn the
first time, so right-click the app and choose **Open**, or run `xattr -dr
com.apple.quarantine "/Applications/Autohand Voice.app"`.

No `gh` CLI handy? Grab the DMG directly from the
[latest release page](https://github.com/autohandai/voice/releases/latest).

Want the bleeding edge instead of a stable release? The
[nightly build](https://github.com/autohandai/voice/releases/tag/nightlybuild-latest)
rebuilds automatically from `main` on every push.

## Requirements

- macOS 14 or newer
- Apple Silicon (M1 or newer)
- Xcode 15.0 or newer
- Microphone and Accessibility permission

There is no Python runtime, MLX runtime, remote speech service, or automatic
cloud fallback.

## Build from source

```bash
git clone https://github.com/autohandai/voice.git
cd voice
swift test
./scripts/build-app.sh
open "dist/Autohand Voice.app"
```

To build the drag-to-Applications installer and its SHA-256 checksum:

```bash
./scripts/build-installer.sh
open dist/Autohand-Voice-0.1.0-universal.dmg
(cd dist && shasum -a 256 -c Autohand-Voice-0.1.0-universal.dmg.sha256)
```

Local builds use an ad-hoc signature. Tagged releases are published by the
private repository's release workflow the same way — ad-hoc signed, clearly
labeled unsigned — until a Developer ID Application certificate is
configured, at which point the same workflow instead submits the app and DMG
to Apple for notarization and staples the result. See
[Releasing](docs/releasing.md) for the required repository secrets and
versioning contract.

The first transcription downloads the pinned FluidAudio Parakeet model. The
model is compiled for CoreML and reused from the local cache on later launches.

For command-line development:

```bash
swift run autohand-voice check
swift run autohand-voice model-check --json
swift run autohand-voice
swift run autohand-voice transcribe recording.wav
swift run autohand-voice-stt check
```

## Use

Launch the app and hold Fn while you speak, then release it to finish.
Recording starts the moment Fn goes down; a press shorter than 0.4 seconds is
treated as a normal Fn tap and its audio is discarded, so short presses keep
their normal macOS behavior. The existing Accessibility permission is sufficient for
global Fn observation. Input Monitoring is an optional alternative, and
Control + Option + Space remains the registered fallback shortcut. The menu bar
icon shows recording and local processing state. A final transcript is inserted
into the focused editable control. Provisional text is never committed.
A nonactivating recording HUD shows starting, input level, local processing,
and failure state without taking focus from the target app; it can be disabled
in Settings. An opt-in live preview uses FluidAudio's local sliding-window
decoder and labels all changing text as provisional. Preview text never leaves
the HUD or reaches the target app; stopping runs one final transcription.
Settings also provides a remembered microphone picker, system-default tracking,
hot-plug recovery, bounded signal diagnostics, and a local microphone test.
Launch at Login uses macOS Service Management and reports when approval is
required in System Settings. After sleep or session unlock, the app restores
one hot-key registration and recreates its Core Audio device observation.
Sleep-interrupted captured audio remains available in memory for local retry;
quitting during capture requires explicit discard confirmation.

### Talk with Fantail (optional)

Hold **Fn + Shift**, ask a question, and let go. Your speech is transcribed on
this Mac, the text goes to Autohand's Fantail model, and the reply streams back
on screen and is spoken with the local Kokoro voice (`af_heart`). Hold Fn + Shift
again to follow up; the conversation is kept in memory for two minutes of
inactivity. Escape or Stop interrupts a reply; Insert types it at the cursor.

For a hands-free conversation, hold **Command + Shift** and press **Fn** (or set
Recording Mode to Hands-Free and use Fn + Shift). Voice listens, sends your turn
after a short pause, speaks the reply, then listens again; the microphone stays
closed while Fantail speaks. Press Escape or Fn to end it, then use **Copy
Conversation** on the card to copy the whole exchange. Listening stops by itself
after 30 seconds of silence.

Talk needs a free Autohand account (Settings → Talk → Sign In with Autohand,
using the same browser sign-in as the Autohand CLI). The API key is stored in
Keychain. When the free plan's limit is reached, Talk shows when it resets and
offers an upgrade. Turn Talk off in Settings → Talk.

The menu supports:

- pausing and resuming dictation;
- choosing direct cursor insertion or explicit clipboard output;
- recording with press-and-hold, toggle, or hands-free behavior;
- changing the registered shortcut without requiring Input Monitoring;
- enabling long-press Fn activation with explicit Input Monitoring status;
- disabling sound feedback;
- showing or hiding the recording HUD;
- enabling local provisional HUD preview;
- copying the most recent final transcript;
- opening optional local dictation history with search, export, and deletion;
- opening native Settings with Command + comma;
- opening a native About window with version, build, architecture, executable
  SHA-256 checksum, company, privacy, source, and selectable full license
  notices;
- transcribing a supported local audio file into editable final text.

On first launch, guided setup prepares Microphone and Accessibility permission,
validates the pinned local model, and requires a real dictation test. The
General pane controls audio input, output, sound feedback, and launch at login.
Privacy & Diagnostics shows the local runtime state and can copy a redacted
report that never includes audio, transcript text, file paths, or environment
values.

The model manager shows download and CoreML compilation progress, storage,
language coverage, and the last successful validation. It supports Parakeet v2
for English and v3 for multilingual dictation. Repair replaces only the
selected model cache. Language & Models exposes the pinned list of 25 European
languages with a local test phrase, clearly labels transcription as distinct
from translation, and can remove only a selected known model cache.

The Vocabulary pane supports local whole-word replacements for names, brands,
technical terms, and acronyms. It previews the deterministic result before
dictation, imports and exports JSON or CSV, and stores rules owner-only. Rules
are applied only to final transcripts before insertion. Rule count and import
size are bounded.

Optional English dictation commands are off by default. Enable them in General,
then use the explicit `command` prefix: “command new line,” “command new
paragraph,” “command comma,” “command period,” “command question mark,”
“command scratch that,” “command literal mode,” or “command cancel dictation.”
The prefix prevents ordinary phrases such as “a new line of products” from
being altered.

Smart Formatting is also opt-in. Its local refinement removes high-confidence
fillers such as “um” and “uh,” collapses accidental word or phrase repetition,
then applies Vocabulary replacements for names and technical terms. It uses
only the captured selection and at most one adjacent character on either side
to add deterministic spacing, capitalization, and optional terminal
punctuation. The Formatting pane previews the exact result, and the menu keeps
the most recent raw text available to copy in memory.

App Profiles can override output, recording mode, language, local model choice,
dictation commands, smart formatting, HUD visibility, provisional preview, and
sound feedback for an exact application bundle identifier. Unset values use
the global settings. Profiles never inspect window titles, document names, or
application content.

Transcribe Audio File opens a native importer for AAC, AIFF, CAF, FLAC, M4A,
MP3, and WAV audio. The selected file is validated before model work, its
security-scoped access is released on completion or cancellation, and the final
text can be edited, copied, or exported as plain text or Markdown. File audio
and generated text are never uploaded.

Private Usage Insights is independently opt-in. It stores at most 366 daily
aggregate rows—dictation count, word count, recording and processing time, and
insertion outcomes—with no transcript text. The native chart is paired with an
accessible summary and data table. Estimated time saved assumes 40 words per
minute and subtracts recording plus local processing time; all statistics can
be reset.

The native app ships one String Catalog with English, German, Spanish, Italian,
and Portuguese coverage. Static SwiftUI call sites are mechanically checked
against that catalog, including placeholder preservation and pseudolocalized
expansion. VoiceOver, Full Keyboard Access, Dynamic Type, Reduce Motion,
increased contrast, right-to-left layout, and long localized strings remain
release checks. Setup, microphone testing, transcript recovery, and destructive
history controls expose explicit labels and state instead of relying on color,
motion, or sound.

Privacy & Diagnostics uses the same diagnostic snapshot as
`autohand-voice check --json`. It shows platform and permission support,
shortcut registration, the selected microphone and live signal, model
readiness and disk use, app version, and the fixed invariant “Remote fallback:
Disabled.” Recent failures are stored for at most 30 days as bounded category
counts—never raw error messages—and the copied report automatically omits
transcripts, audio, paths, usernames, focused content, credentials, environment
values, and microphone names.

A separate reliability ledger stores at most 366 owner-only daily rows of
finite outcome counts and latency buckets. It never stores audio, transcript
or revision text, prompts, focused context, paths, usernames, microphone names,
bundle identifiers, URLs, credentials, environment values, or arbitrary error
messages. Inspect or export the same redacted schema from the CLI:

```bash
autohand-voice reliability show
autohand-voice reliability --json
autohand-voice reliability path
autohand-voice reliability export ./autohand-voice-reliability.json
autohand-voice reliability reset
```

## Configuration

Preferences are stored at:

```text
~/Library/Application Support/Autohand Voice/preferences.json
```

Use the menu or the native CLI:

```bash
autohand-voice config show
autohand-voice config set output type
autohand-voice config set output clipboard
autohand-voice config set ptt_key control_option_space
autohand-voice config set recording_mode press_and_hold
autohand-voice config set recording_mode toggle
autohand-voice config set recording_mode hands_free
autohand-voice config set function_key_long_press on
autohand-voice config set model v3
autohand-voice config set language en
autohand-voice config set sounds off
autohand-voice config set live_preview on
autohand-voice config reset
```

The file and its parent directory are owner-only. The canonical environment
prefix is `AUTOHAND_VOICE_`; the native app does not read legacy upstream
environment variables.

Incomplete or evidence-gated capabilities are explicit opt-ins for local
development. Missing, malformed, and unknown values are off:

```text
AUTOHAND_VOICE_HUD_EDGE_PLACEMENT
AUTOHAND_VOICE_LONG_DICTATION_20
AUTOHAND_VOICE_MOUSE_FLOW
AUTOHAND_VOICE_MINIMAL_CONTEXT
AUTOHAND_VOICE_LOCAL_TRANSFORMS
AUTOHAND_VOICE_PERSISTENT_RECOVERY
AUTOHAND_VOICE_WORKSPACE_V2
AUTOHAND_VOICE_SCRATCHPAD
AUTOHAND_VOICE_NOTIFICATIONS
AUTOHAND_VOICE_ADVANCED_INSIGHTS
AUTOHAND_VOICE_ENCRYPTED_SYNC
AUTOHAND_VOICE_ACCOUNTS
```

Use `1`, `true`, `yes`, or `on` to opt in. Scratchpad requires both
`WORKSPACE_V2` and `SCRATCHPAD`. Local Transforms still require a separately
licensed and signed CoreML artifact. Encrypted Sync and Accounts remain hidden
even with a local flag until their external control-plane, second-client,
security, legal, billing, and delivery gates pass; see
[connected-capabilities-gate.md](docs/evaluation/connected-capabilities-gate.md).

## Privacy and failure behavior

- Audio samples are bounded to five minutes by default. The separately gated
  20-minute mode uses the same fixed sample cap, streaming resampler, monotonic
  warnings, hard stop, and a recording-only system activity assertion.
- After a transient local transcription failure, bounded audio remains only in
  memory for up to 15 minutes and can be retried or explicitly discarded.
- Optional crash recovery writes incremental AES-GCM encrypted chunks with a
  per-install Keychain key, strict item/byte/duration quotas, and a maximum
  24-hour policy. Recovery is never retried automatically and can always be
  transcribed directly to the clipboard.
- Speech recognition runs in the local CoreML process.
- Dictation never sends speech, text, or cleanup requests to a remote endpoint.
- Talk is the only networked feature. It runs only when you hold Fn + Shift
  or start a hands-free conversation, and are signed in, sends only the final transcript text and the recent
  conversation (never audio) to Autohand, and speaks replies locally.
- There is no silent engine fallback.
- Permission, microphone, model, and focused-control failures remain visible in
  the menu instead of discarding or inventing text.
- The focused app and selection are captured before recording. If focus moves,
  the final transcript stays in memory with Retry Here, Copy, and Discard
  actions.
- Cursor insertion preserves and restores the user's clipboard.
- Text history is off by default. When enabled, it stores only final transcript
  text, timestamps, and insertion outcomes in an owner-only bounded JSON file.
- Vocabulary replacements are deterministic and local. A malformed vocabulary
  never discards recognized text or triggers a remote fallback.
- Dictation commands modify only the current uncommitted final transcript.
  Cancel commits nothing, and disabling commands preserves every phrase
  literally.
- Smart Formatting does not read surrounding paragraphs or call a cleanup
  service. Unknown cursor context remains literal.
- App Profiles are owner-only and bounded. Matching uses only the frontmost
  application’s bundle identifier.
- Ranked microphone routes use stable Core Audio device IDs, allow System
  Default at any rank, and perform a bounded segment handoff only when the user
  enables automatic handoff. Route metadata never starts another recognizer.
- Extra mouse buttons are separately opt-in, never include primary or secondary
  click, and leave the registered keyboard controls working after denial or
  device removal. Commit/Enter requires its own binding and a recent verified
  typed insertion.
- Canadian spelling is a reversible local cleanup policy shown once for
  English-speaking Canadian macOS users. It does not claim another STT
  language and never changes Literal or non-English output.

## Development

Read [AGENTS.md](AGENTS.md), then run:

```bash
swift test
swift build -c release
./.build/release/autohand-voice check --json
./scripts/build-app.sh
./scripts/build-installer.sh
```

Microphone, hot-key, cursor insertion, permission, or model changes also need a
real Apple Silicon smoke test.

## Contributors

- Autohand Evolve
- igorcosta

## Attribution and license

This work originated from the MIT-licensed Dictate project. Required upstream
copyright and license notices remain in [LICENSE](LICENSE) and
[NOTICE.md](NOTICE.md); they are legal attribution, not the current contributor
roster.

See [LICENSES.md](LICENSES.md) for the native dependency and model licenses.
