# Contributing to Autohand Voice

Read [AGENTS.md](AGENTS.md) before changing the native runtime.

## Setup

```bash
git clone https://github.com/autohandai/voice.git
cd voice
swift test
swift build -c release
```

## Pull requests

- Keep one concern per pull request.
- Start behavioral fixes with a failing XCTest.
- Preserve the local-only engine and explicit failure behavior.
- Include the macOS version and Apple chip for native failures.
- Update docs with CLI, configuration, model, privacy, or installation changes.
- Preserve required MIT attribution.

## Validation

```bash
swift test
swift build -c release
./.build/release/autohand-voice check --json
./scripts/build-app.sh
```

Native interaction changes additionally require a real Apple Silicon smoke test.
