# AGENTS.md

Autohand Voice is production software for macOS users who depend on reliable,
private voice input. Work as a critical staff-level Python and Swift engineer.

## Product contract

- Target macOS 14+ on Apple Silicon only.
- Keep speech recognition local by default.
- Use CoreML on the Apple Neural Engine as the default STT path.
- Keep Qwen3-ASR optional through `autohand-voice-mlx[qwen3-asr]`.
- Never silently fall back to a remote speech or cleanup service.
- Preserve user typing and cursor state; partial transcripts are provisional.
- Commit only final transcripts into editable text.
- Surface permission, model, microphone, and helper failures clearly.

## Public identity

- Product: `Autohand Voice`
- Python distribution: `autohand-voice-mlx`
- CLI: `autohand-voice`
- Swift helper: `autohand-voice-stt`
- Bundle ID: `ai.autohand.voice`
- Environment prefix: `AUTOHAND_VOICE_`
- Repository: `github.com/autohandai/voice`

The internal Python package remains `dictate` for source compatibility with the
MIT-licensed upstream project. Do not expose that internal name in new user
interfaces or documentation. Preserve upstream attribution and license notices.

## Engineering workflow

1. Inspect the implementation and existing tests.
2. Reproduce bugs with a failing test.
3. Implement the smallest reliable change.
4. Run focused tests.
5. Run the full Python suite.
6. Lint every changed Python file.
7. Build the Swift helper for runtime changes.
8. Verify privacy and fallback behavior.

## Required validation

```bash
python -m pytest tests/ -q
ruff check <changed-python-files>
mypy dictate
cd swift-stt && swift build -c release
```

For microphone, keyboard, menu bar, permission, or model changes, also run a
real Apple Silicon smoke test. Automated tests do not replace native runtime
proof.

## Code standards

- Python 3.11+ with type hints on public interfaces.
- Swift 5.9+ with explicit error propagation.
- Keep audio capture, recognition, cleanup, and text insertion as separate
  boundaries.
- Bound buffers, subprocess waits, logs, and temporary files.
- Keep temporary audio owner-only and remove it after processing.
- Avoid new dependencies without a clear runtime or reliability benefit.
- Never commit models, generated caches, recordings, credentials, or secrets.
- Update documentation with every public CLI, configuration, engine, privacy,
  or installation change.

## Compatibility

Canonical Autohand names take precedence. Legacy upstream environment variables
and helper discovery may remain as migration fallbacks, but they must not appear
as the primary user contract.
