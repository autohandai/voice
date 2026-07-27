# Autohand Voice

Private, local voice input for Autohand on Apple Silicon.

Autohand Voice turns a push-to-talk shortcut into editable text using models that
run on your Mac. Audio and transcripts remain local by default.

## Platform

- macOS 14 or newer
- Apple Silicon (M1 or newer)
- Python 3.11+
- Microphone and Accessibility permissions

This repository is intentionally macOS and Apple Silicon specific. It is not the
Windows or Linux voice backend.

## Engines

| Engine | Role | Runtime |
|---|---|---|
| ANE / FluidAudio | Default | Parakeet through CoreML on Apple Neural Engine |
| Qwen3-ASR 0.6B | Optional multilingual engine | MLX |
| Parakeet MLX | GPU fallback | MLX |
| Whisper Large V3 Turbo | Compatibility fallback | MLX |

The default ANE engine keeps speech recognition off the GPU. Qwen3-ASR is
available for broader multilingual coverage.

## Install

```bash
git clone https://github.com/autohandai/voice.git
cd voice
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
cd swift-stt && swift build -c release && cd ..
autohand-voice
```

Install Qwen3-ASR support:

```bash
pip install 'autohand-voice-mlx[qwen3-asr]'
```

The first CoreML run downloads and compiles the selected FluidAudio model for
your Mac. Subsequent sessions reuse the local cache.

## Usage

```bash
autohand-voice
autohand-voice status
autohand-voice doctor
autohand-voice devices
autohand-voice config
autohand-voice config set stt ane
autohand-voice config set stt qwen3-asr
```

Hold the configured push-to-talk key, speak, then release. The result is typed
at the active cursor. The menu bar controls the microphone, language, writing
style, engine, and local model settings.

## Environment

Canonical settings use the `AUTOHAND_VOICE_` prefix:

```bash
AUTOHAND_VOICE_STT_ENGINE=ane
AUTOHAND_VOICE_INPUT_LANGUAGE=auto
AUTOHAND_VOICE_OUTPUT_MODE=type
AUTOHAND_VOICE_LLM_CLEANUP=true
```

Legacy upstream `DICTATE_` variables remain accepted during migration, but new
integrations must use `AUTOHAND_VOICE_`.

## Privacy boundary

- Speech recognition is local.
- Hugging Face telemetry is disabled.
- Models are downloaded once and cached locally.
- Remote cleanup endpoints are blocked by default.
- Enabling `AUTOHAND_VOICE_ALLOW_REMOTE_API=1` is an explicit privacy boundary
  change and may send text to the configured endpoint.

## Autohand integration

Autohand Code can activate Autohand Voice from its voice shortcut. The intended
integration contract is:

1. Detect `autohand-voice` and `autohand-voice-stt`.
2. Prompt for one-time installation when unavailable.
3. Start or focus the local voice service.
4. Stream partial text as non-destructive composer ghost text.
5. Commit only final text into the editable composer.
6. Fall back to Apple Speech when the model service is unavailable.

The standalone menu bar runtime is available in `0.1.0`. The streaming composer
service is specified in
[docs/autohand-composer-integration.md](docs/autohand-composer-integration.md)
and must be implemented before Autohand Code treats partial transcription as
available.

## Development

Read [AGENTS.md](AGENTS.md) before changing the runtime.

```bash
python -m pytest tests/ -q
ruff check <changed-python-files>
mypy dictate
cd swift-stt && swift build -c release
```

## Attribution

Autohand Voice is based on
[0xbrando/dictate](https://github.com/0xbrando/dictate), used under the MIT
License. The upstream README is retained in
[docs/upstream-readme.md](docs/upstream-readme.md), and upstream copyright
notices remain intact.

## License

MIT. See [LICENSE](LICENSE), [NOTICE.md](NOTICE.md), and
[LICENSES.md](LICENSES.md).
