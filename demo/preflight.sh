#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
    echo "Autohand Voice requires Apple Silicon macOS." >&2
    exit 1
fi

swift test
swift build -c release
./.build/release/autohand-voice check
./scripts/build-app.sh

echo "Native preflight passed. Permission and live transcription still require an interactive smoke test."
