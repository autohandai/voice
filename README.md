# Autohand Voice

Native, private voice input for Apple Silicon Macs.

Autohand Voice is written entirely in Swift. It records through AVFoundation,
transcribes locally with FluidAudio and CoreML on the Apple Neural Engine, then
inserts only the final transcript at the active cursor through macOS
Accessibility APIs.

## Requirements

- macOS 14 or newer
- Apple Silicon (M1 or newer)
- Xcode 15.0 or newer
- Microphone and Accessibility permission

There is no Python runtime, MLX runtime, remote speech service, or automatic
cloud fallback.

## Build and install

```bash
git clone https://github.com/autohandai/voice.git
cd voice
swift test
./scripts/build-app.sh
open "dist/Autohand Voice.app"
```

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

Launch the app and use Control + Option + Space, the default shortcut, to
dictate. The menu bar icon shows recording and local processing state. A final
transcript is inserted into the focused editable control. Provisional text is
never committed. The registered native shortcut does not require Input
Monitoring permission.
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

The menu supports:

- pausing and resuming dictation;
- choosing direct cursor insertion or explicit clipboard output;
- recording with press-and-hold, toggle, or hands-free behavior;
- changing the registered shortcut without requiring Input Monitoring;
- disabling sound feedback;
- showing or hiding the recording HUD;
- enabling local provisional HUD preview;
- copying the most recent final transcript;
- opening optional local dictation history with search, export, and deletion;
- opening native Settings with Command + comma.
- transcribing a supported local audio file into editable final text.

On first launch, Settings guides you through Microphone and Accessibility
permission and prepares the pinned local model before your first real
dictation. The General pane controls audio input, output, sound feedback, and
launch at login. Privacy & Diagnostics shows the local runtime state and can copy a
redacted report that never includes audio, transcript text, file paths, or
environment values.

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

Smart Formatting is also opt-in. It uses only the captured selection and at
most one adjacent character on either side to add deterministic spacing,
capitalization, and optional terminal punctuation. The Formatting pane previews
the exact result, and the menu keeps the most recent pre-formatting text
available to copy in memory.

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
autohand-voice config set model v3
autohand-voice config set language en
autohand-voice config set sounds off
autohand-voice config set live_preview on
autohand-voice config reset
```

The file and its parent directory are owner-only. The canonical environment
prefix remains `AUTOHAND_VOICE_` for future integrations, but the native app
does not read legacy upstream environment variables.

## Privacy and failure behavior

- Audio samples stay in memory and are bounded to five minutes.
- After a transient local transcription failure, bounded audio remains only in
  memory for up to 15 minutes and can be retried or explicitly discarded.
- Speech recognition runs in the local CoreML process.
- No speech or cleanup request is sent to a remote endpoint.
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

## Development

Read [AGENTS.md](AGENTS.md), then run:

```bash
swift test
swift build -c release
./.build/release/autohand-voice check --json
./scripts/build-app.sh
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
