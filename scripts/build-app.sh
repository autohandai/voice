#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Autohand Voice"
APP_PATH="$REPO_ROOT/dist/$APP_NAME.app"
CONTENTS="$APP_PATH/Contents"

swift build -c release --product autohand-voice
swift build -c release --product autohand-voice-stt
BIN_PATH="$(swift build -c release --show-bin-path)"

rm -rf "$APP_PATH"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_PATH/autohand-voice" "$CONTENTS/MacOS/autohand-voice"
cp "$BIN_PATH/autohand-voice-stt" "$CONTENTS/MacOS/autohand-voice-stt"
cp "$REPO_ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

for bundle in "$BIN_PATH"/*.bundle; do
    if [[ -d "$bundle" ]]; then
        cp -R "$bundle" "$CONTENTS/Resources/"
    fi
done

codesign \
    --force \
    --deep \
    --sign - \
    --entitlements "$REPO_ROOT/Resources/AutohandVoice.entitlements" \
    "$APP_PATH"

echo "Built $APP_PATH"
