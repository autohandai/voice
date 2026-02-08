#!/usr/bin/env bash
# Dictate — Pre-flight check
# Run this before demos or screen recordings to verify everything works.
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; ISSUES=$((ISSUES+1)); }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }

ISSUES=0

echo ""
echo "🎤 Dictate Pre-flight Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# --- Python ---
echo "Runtime:"
if command -v python3 &>/dev/null; then
    PY_VER=$(python3 --version 2>&1)
    pass "Python: $PY_VER"
else
    fail "Python 3 not found"
fi

# --- macOS ---
if [[ "$(uname)" == "Darwin" ]]; then
    pass "macOS detected"
    CHIP=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "unknown")
    pass "Chip: $CHIP"
else
    fail "macOS required (menu bar app)"
fi

# --- Package ---
if python3 -c "import dictate" 2>/dev/null; then
    pass "dictate package importable"
else
    fail "dictate not installed — run: pip install -r requirements.txt"
fi

# --- Dependencies ---
echo ""
echo "Dependencies:"
for dep in rumps mlx_lm mlx_whisper numpy sounddevice; do
    if python3 -c "import $dep" 2>/dev/null; then
        pass "$dep"
    else
        fail "$dep missing"
    fi
done

# --- Optional: Parakeet ---
if python3 -c "import parakeet_mlx" 2>/dev/null; then
    pass "parakeet-mlx (fast English STT)"
else
    warn "parakeet-mlx not installed (optional: pip install parakeet-mlx)"
fi

# --- Accessibility ---
echo ""
echo "Permissions:"
# Can't check accessibility programmatically before launch, but we can note it
warn "Accessibility permission — macOS will prompt on first launch"
warn "Microphone permission — macOS will prompt on first launch"

# --- Whisper model ---
echo ""
echo "Models:"
WHISPER_PATH="$HOME/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-turbo"
if [ -d "$WHISPER_PATH" ]; then
    pass "Whisper Large V3 Turbo cached"
else
    warn "Whisper model not yet downloaded (~2GB, auto-downloads on first run)"
fi

# --- LLM models ---
for model_dir in "$HOME/.cache/huggingface/hub/models--mlx-community--Qwen2.5-"*; do
    if [ -d "$model_dir" ]; then
        model_name=$(basename "$model_dir" | sed 's/models--mlx-community--//')
        pass "LLM model cached: $model_name"
    fi
done

# --- Tests ---
echo ""
echo "Tests:"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d "$SCRIPT_DIR/tests" ]; then
    # Need to activate venv for test deps
    if [ -d "$SCRIPT_DIR/.venv" ]; then
        TEST_OUT=$(cd "$SCRIPT_DIR" && source .venv/bin/activate && python -m pytest tests/ -q 2>&1 | tail -1)
        if echo "$TEST_OUT" | grep -q "passed"; then
            pass "$TEST_OUT"
        else
            fail "Tests: $TEST_OUT"
        fi
    else
        warn "No .venv — run tests manually"
    fi
else
    warn "No tests directory found"
fi

# --- Audio devices ---
echo ""
echo "Audio:"
MIC_COUNT=$(python3 -c "
import sounddevice as sd
inputs = [d for d in sd.query_devices() if d['max_input_channels'] > 0]
print(len(inputs))
" 2>/dev/null || echo "0")
if [ "$MIC_COUNT" -gt 0 ]; then
    pass "$MIC_COUNT input device(s) found"
else
    fail "No input devices detected"
fi

# --- Summary ---
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}All checks passed. Ready to demo!${NC}"
    echo ""
    echo "Launch: python -m dictate"
else
    echo -e "${RED}$ISSUES issue(s) found. Fix before demo.${NC}"
fi
echo ""
