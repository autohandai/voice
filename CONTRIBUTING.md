# Contributing to Autohand Voice

Read [AGENTS.md](AGENTS.md) before making changes.

## Setup

```bash
git clone https://github.com/autohandai/voice.git
cd voice
python3 -m venv .venv
source .venv/bin/activate
pip install -e '.[dev]'
```

Build the CoreML/ANE helper:

```bash
cd swift-stt
swift build -c release
```

## Pull requests

- Keep one concern per pull request.
- Start behavioral fixes with a failing test.
- Preserve local-only defaults and explicit privacy boundaries.
- Include macOS version and Apple chip details for native failures.
- Update public documentation with CLI, configuration, model, or workflow
  changes.
- Preserve the upstream MIT attribution.

## Validation

```bash
python -m pytest tests/ -q
ruff check <changed-python-files>
mypy dictate
cd swift-stt && swift build -c release
```

The upstream contribution guide is retained at
[docs/upstream-contributing.md](docs/upstream-contributing.md).
