#!/usr/bin/env bash
# Builds mlx-swift's Metal kernels into one mlx.metallib and prints its path.
#
# `swift build` compiles mlx-swift's C++ and Swift but not its .metal kernels,
# so MLX fails at runtime with "Failed to load the default metallib" unless a
# metallib is shipped next to the code. The result is cached under
# .build/mlx-metallib/<mlx-swift revision>/ so rebuilds are instant.
#
# Usage: scripts/build-mlx-metallib.sh   (prints the cached metallib path)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Must match mlx-swift's own deployment floor and the app's (macOS 14).
# fence.metal needs Metal 3.2 (macOS 15) and is only used with
# MLX_METAL_FAST_SYNCH; *_nax kernels need newer GPUs/SDKs. Both are skipped.
METAL_STD="metal3.1"
MIN_MACOS="14.0"

swift package resolve >/dev/null
MLX_DIR="$REPO_ROOT/.build/checkouts/mlx-swift"
KERNELS="$MLX_DIR/Source/Cmlx/mlx/mlx/backend/metal/kernels"
if [[ ! -d "$KERNELS" ]]; then
    echo "build-mlx-metallib: mlx-swift kernels not found at $KERNELS" >&2
    exit 1
fi

REVISION="$(grep -A6 '"identity" : "mlx-swift"' "$REPO_ROOT/Package.resolved" \
    | sed -n 's/.*"revision" : "\([0-9a-f]*\)".*/\1/p')"
if [[ -z "$REVISION" ]]; then
    echo "build-mlx-metallib: mlx-swift revision missing from Package.resolved" >&2
    exit 1
fi

METAL_VERSION="$(xcrun -sdk macosx metal --version 2>/dev/null | head -1 | shasum -a 256 | cut -c1-12)"
CACHE_DIR="$REPO_ROOT/.build/mlx-metallib/$REVISION-$METAL_STD-$MIN_MACOS-$METAL_VERSION"
OUTPUT="$CACHE_DIR/mlx.metallib"
if [[ -s "$OUTPUT" ]]; then
    echo "$OUTPUT"
    exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/autohand-voice-metallib.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

find "$KERNELS" -type f -name '*.metal' \
    ! -name '*_nax.metal' ! -name 'fence.metal' \
    | LC_ALL=C sort > "$WORK/sources.txt"
if [[ ! -s "$WORK/sources.txt" ]]; then
    echo "build-mlx-metallib: no kernels found" >&2
    exit 1
fi

echo "build-mlx-metallib: compiling $(wc -l < "$WORK/sources.txt" | tr -d ' ') kernels for mlx-swift $REVISION" >&2
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
export KERNELS MLX_DIR WORK METAL_STD MIN_MACOS
tr '\n' '\0' < "$WORK/sources.txt" | xargs -0 -P "$JOBS" -n 1 /bin/bash -c '
set -euo pipefail
src="$1"
air="$WORK/$(printf "%s" "${src#$KERNELS/}" | shasum -a 256 | cut -c1-16).air"
xcrun -sdk macosx metal -x metal -std="$METAL_STD" \
    -mmacosx-version-min="$MIN_MACOS" -fno-fast-math \
    -Wno-c++17-extensions -Wno-c++20-extensions \
    -c "$src" -I"$KERNELS" -I"$MLX_DIR/Source/Cmlx/mlx" -o "$air"
' _

AIRS=()
while IFS= read -r air; do
    AIRS+=("$air")
done < <(find "$WORK" -name '*.air' | LC_ALL=C sort)

mkdir -p "$CACHE_DIR"
xcrun -sdk macosx metallib "${AIRS[@]}" -o "$WORK/mlx.metallib"
mv -f "$WORK/mlx.metallib" "$OUTPUT"
echo "build-mlx-metallib: wrote $OUTPUT ($(du -h "$OUTPUT" | cut -f1))" >&2
echo "$OUTPUT"
