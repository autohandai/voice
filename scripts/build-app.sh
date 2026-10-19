#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Autohand Voice"
APP_PATH="$REPO_ROOT/dist/$APP_NAME.app"
CONTENTS="$APP_PATH/Contents"
INFO_PLIST="$CONTENTS/Info.plist"
VERSION="${AUTOHAND_VOICE_VERSION:-$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleShortVersionString' \
        "$REPO_ROOT/Resources/Info.plist"
)}"
BUILD_NUMBER="${AUTOHAND_VOICE_BUILD_NUMBER:-1}"
CODESIGN_IDENTITY="${AUTOHAND_VOICE_CODESIGN_IDENTITY:--}"

# Universal by default so one installer runs on Apple Silicon and Intel Macs.
read -r -a ARCHS <<< "${AUTOHAND_VOICE_ARCHS:-arm64 x86_64}"
ARCH_ARGUMENTS=()
for arch in "${ARCHS[@]}"; do
    ARCH_ARGUMENTS+=(--arch "$arch")
done

swift build -c release "${ARCH_ARGUMENTS[@]}" --product autohand-voice
swift build -c release "${ARCH_ARGUMENTS[@]}" --product autohand-voice-stt
BIN_PATH="$(swift build -c release "${ARCH_ARGUMENTS[@]}" --show-bin-path)"

rm -rf "$APP_PATH"
mkdir -p \
    "$CONTENTS/MacOS" \
    "$CONTENTS/Resources/Brand" \
    "$CONTENTS/Resources/Legal"
cp "$BIN_PATH/autohand-voice" "$CONTENTS/MacOS/autohand-voice"
cp "$BIN_PATH/autohand-voice-stt" "$CONTENTS/MacOS/autohand-voice-stt"
cp "$REPO_ROOT/Resources/Info.plist" "$INFO_PLIST"
cp "$REPO_ROOT/Resources/Brand/"* "$CONTENTS/Resources/Brand/"
cp "$REPO_ROOT/Resources/Brand/autohand-voice.icns" "$CONTENTS/Resources/autohand-voice.icns"
cp "$REPO_ROOT/Resources/Legal/"* "$CONTENTS/Resources/Legal/"

/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $VERSION" \
    "$INFO_PLIST"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleVersion $BUILD_NUMBER" \
    "$INFO_PLIST"

xcrun xcstringstool compile \
    "$REPO_ROOT/Resources/Localizable.xcstrings" \
    --output-directory "$CONTENTS/Resources"

for bundle in "$BIN_PATH"/*.bundle; do
    if [[ -d "$bundle" ]]; then
        cp -R "$bundle" "$CONTENTS/Resources/"
    fi
done

# MLX GPU kernels for the optional Qwen3-ASR engine (Apple Silicon only).
# `swift build` does not compile mlx-swift's .metal sources, so the cached
# metallib is placed where MLX looks for a SwiftPM resource bundle:
# <main bundle resources>/mlx-swift_Cmlx.bundle/default.metallib. Both
# executables in Contents/MacOS resolve the app as their main bundle.
MLX_METALLIB="$("$REPO_ROOT/scripts/build-mlx-metallib.sh")"
MLX_BUNDLE="$CONTENTS/Resources/mlx-swift_Cmlx.bundle"
rm -rf "$MLX_BUNDLE"
mkdir -p "$MLX_BUNDLE"
cp "$MLX_METALLIB" "$MLX_BUNDLE/default.metallib"

SIGNING_ARGUMENTS=(
    --force \
    --sign "$CODESIGN_IDENTITY"
)

# Developer ID builds get the hardened runtime and a secure timestamp for
# notarization. A self-signed identity (AUTOHAND_VOICE_CODESIGN_SELF_SIGNED=1)
# only gives builds a stable signature, so macOS keeps Keychain, Accessibility
# and login-item approvals across updates; it is not notarized.
if [[ "$CODESIGN_IDENTITY" != "-" && "${AUTOHAND_VOICE_CODESIGN_SELF_SIGNED:-0}" != "1" ]]; then
    SIGNING_ARGUMENTS+=(--options runtime --timestamp)
fi

codesign \
    "${SIGNING_ARGUMENTS[@]}" \
    --identifier ai.autohand.voice.stt \
    "$CONTENTS/MacOS/autohand-voice-stt"

codesign \
    "${SIGNING_ARGUMENTS[@]}" \
    --identifier ai.autohand.voice \
    --entitlements "$REPO_ROOT/Resources/AutohandVoice.entitlements" \
    "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Built $APP_PATH (version $VERSION, build $BUILD_NUMBER)"
