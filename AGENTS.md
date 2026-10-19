# AGENTS.md

Autohand Voice is production software for macOS users who depend on reliable,
private voice input. Work as a critical staff-level Swift engineer.

## Product contract

- Target macOS 14+ on Apple Silicon and Intel, shipped as one universal app.
- Keep speech recognition local.
- CoreML (Parakeet via FluidAudio) is the default STT path: Neural Engine on
  Apple Silicon, CPU/GPU on Intel. Qwen3-ASR 0.6B on MLX is an opt-in
  alternative on Apple Silicon only; Intel reports it unavailable.
- Never silently fall back to remote speech, cleanup, or another engine. A
  chosen engine that cannot run fails visibly.
- Talk (Fn + Shift; Command + Shift + Fn for hands-free) answered by Fantail
  is the only networked feature: explicit, opt-in, signed in to Autohand. It
  sends final transcript text and recent conversation to the `fantail` model,
  never audio, and speaks replies with local Kokoro. Talk answered "On this
  Mac" runs Ternary Bonsai 2 (llama.cpp GGUF, or MLX on Apple Silicon) and
  sends nothing. Dictation must
  never use the network or fall back to Talk.
- Optional models (Bonsai GGUF, Bonsai MLX, Qwen3-ASR) download on request from pinned
  Hugging Face revisions and are checked against hardcoded SHA-256s before
  use. Never bundle or commit them.
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

The runtime is native Swift. Do not introduce Python, a web runtime, or a
remote inference dependency beyond the opt-in Talk feature above. The only
in-process ML runtimes are CoreML, MLX (mlx-swift, for Qwen3-ASR and the
Talk model's Apple Silicon runtime; its metallib is built by
`scripts/build-mlx-metallib.sh`) and llama.cpp (prebuilt xcframework, for the
local Talk model on every Mac). Do not read Keychain at launch. Preserve upstream legal attribution.

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
changes, also run a real smoke test (Apple Silicon, and Intel or Rosetta).

## Code standards

- Swift 5.9+ with explicit error propagation.
- Keep audio capture, recognition, normalization, and text insertion separate.
- Bound buffers, tasks, logs, and temporary files.
- Avoid dependencies without a clear native runtime or reliability benefit.
- Never commit models, caches, recordings, credentials, or secrets.
- Update docs with public CLI, configuration, engine, privacy, or install
  changes.
