#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Autohand Voice"
APP_PATH="$REPO_ROOT/dist/$APP_NAME.app"
VERSION="${AUTOHAND_VOICE_VERSION:-$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleShortVersionString' \
        "$REPO_ROOT/Resources/Info.plist"
)}"
ARTIFACT_NAME="Autohand-Voice-$VERSION-universal"
DMG_PATH="$REPO_ROOT/dist/$ARTIFACT_NAME.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
CODESIGN_IDENTITY="${AUTOHAND_VOICE_CODESIGN_IDENTITY:--}"

if [[ "${AUTOHAND_VOICE_SKIP_APP_BUILD:-0}" != "1" ]]; then
    "$REPO_ROOT/scripts/build-app.sh"
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "Missing app bundle: $APP_PATH" >&2
    exit 1
fi

for executable in autohand-voice autohand-voice-stt; do
    executable_path="$APP_PATH/Contents/MacOS/$executable"
    architectures="$(lipo -archs "$executable_path")"
    if [[ "$architectures" != "x86_64 arm64" ]]; then
        echo "$executable must be universal (x86_64 arm64), found: $architectures" >&2
        exit 1
    fi
done

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

STAGING_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIRECTORY"' EXIT

ditto "$APP_PATH" "$STAGING_DIRECTORY/$APP_NAME.app"
ln -s /Applications "$STAGING_DIRECTORY/Applications"
cp \
    "$REPO_ROOT/Resources/Legal/THIRD-PARTY-NOTICES.txt" \
    "$STAGING_DIRECTORY/THIRD-PARTY-NOTICES.txt"
cp \
    "$REPO_ROOT/Resources/Legal/THIRD-PARTY-NOTICES.txt" \
    "$REPO_ROOT/dist/THIRD-PARTY-NOTICES.txt"

rm -f "$DMG_PATH" "$CHECKSUM_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIRECTORY" \
    -format UDZO \
    -ov \
    "$DMG_PATH"

if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
    codesign \
        --force \
        --sign "$CODESIGN_IDENTITY" \
        --timestamp \
        "$DMG_PATH"
fi

(
    cd "$REPO_ROOT/dist"
    shasum -a 256 "$(basename "$DMG_PATH")" \
        > "$(basename "$CHECKSUM_PATH")"
)

echo "Built $DMG_PATH"
echo "Checksum: $CHECKSUM_PATH"
