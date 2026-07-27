# AGENTS.md

Autohand Voice is production software for macOS users who depend on reliable,
private voice input. Work as a critical staff-level Swift engineer.

## Product contract

- Target macOS 14+ on Apple Silicon only.
- Keep speech recognition local.
- Use CoreML on the Apple Neural Engine as the only STT path.
- Never silently fall back to remote speech, cleanup, or another engine.
- Preserve user typing, selection, clipboard, and cursor state.
- Treat partial transcripts as provisional and commit only final transcripts.
- Surface permission, model, microphone, hot-key, and insertion failures.

## Public identity

- Product: `Autohand Voice`
- CLI: `autohand-voice`
- STT executable: `autohand-voice-stt`
- Bundle ID: `ai.autohand.voice`
- Environment prefix: `AUTOHAND_VOICE_`
- Repository: `github.com/autohandai/voice`

The runtime is native Swift. Do not introduce Python, MLX, a web runtime, or a
remote inference dependency. Preserve upstream legal attribution.

## Engineering workflow

1. Inspect the implementation and existing tests.
2. Reproduce bugs with a failing XCTest.
3. Implement the smallest reliable change.
4. Run focused tests.
5. Run the full Swift suite.
6. Build both release executables.
7. Build the `.app`.
8. Verify privacy and failure behavior.

## Required validation

```bash
swift test
swift build -c release
./.build/release/autohand-voice check --json
./scripts/build-app.sh
```

For microphone, keyboard, menu bar, permission, model, or text insertion
changes, also run a real Apple Silicon smoke test.

## Code standards

- Swift 5.9+ with explicit error propagation.
- Keep audio capture, recognition, normalization, and text insertion separate.
- Bound buffers, tasks, logs, and temporary files.
- Avoid dependencies without a clear native runtime or reliability benefit.
- Never commit models, caches, recordings, credentials, or secrets.
- Update docs with public CLI, configuration, engine, privacy, or install
  changes.
