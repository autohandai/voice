#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$REPO_ROOT/dist/Autohand Voice.app"

if [[ ! -d "$APP_PATH" ]]; then
    "$REPO_ROOT/scripts/build-app.sh"
fi

open "$APP_PATH"
