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
- Microphone, Accessibility, and Input Monitoring permission

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
swift run autohand-voice
swift run autohand-voice transcribe recording.wav
swift run autohand-voice-stt check
```

## Use

Launch the app, hold Right Option, speak, then release. The menu bar icon shows
recording and local processing state. A final transcript is inserted into the
focused editable control. Provisional text is never committed.

The menu supports:

- pausing and resuming dictation;
- choosing direct cursor insertion or explicit clipboard output;
- changing the push-to-talk key;
- disabling sound feedback;
- copying the most recent final transcript.

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
autohand-voice config set ptt_key right_option
autohand-voice config set sounds off
autohand-voice config reset
```

The file and its parent directory are owner-only. The canonical environment
prefix remains `AUTOHAND_VOICE_` for future integrations, but the native app
does not read legacy upstream environment variables.

## Privacy and failure behavior

- Audio samples stay in memory and are bounded to five minutes.
- Speech recognition runs in the local CoreML process.
- No speech or cleanup request is sent to a remote endpoint.
- There is no silent engine fallback.
- Permission, microphone, model, and focused-control failures remain visible in
  the menu instead of discarding or inventing text.
- Direct insertion uses the focused accessibility element and does not replace
  the user's clipboard.

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
