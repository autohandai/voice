# Autohand Composer Integration

Autohand Voice is a native local process for macOS 14+ on Apple Silicon.

## Current integration

Autohand Code may:

1. detect `autohand-voice` or `autohand-voice-stt`;
2. prompt before installing or downloading a model;
3. launch `Autohand Voice.app`;
4. use `autohand-voice-stt transcribe <audio-file>` for local final
   transcription.

The STT executable writes one bounded JSON object to standard output:

```json
{"duration_ms":120,"text":"Final words."}
```

Diagnostics and failures use standard error and a nonzero exit code.

## Composer contract

- Preserve the current composer value, selection, and cursor.
- Treat all in-progress recognition as provisional.
- Insert a final transcript once.
- Leave user-authored text unchanged on cancellation or failure.
- Never fall back to Apple Speech, a cloud API, or cleanup service silently.

The native app itself performs direct final insertion through the focused
Accessibility element. It does not expose a streaming partial-transcript
protocol yet; clients must not infer one from the final-transcription CLI.
