"""Canonical public identity for Autohand Voice."""

from pathlib import Path

PRODUCT_NAME = "Autohand Voice"
CLI_NAME = "autohand-voice"
PACKAGE_NAME = "autohand-voice-mlx"
GITHUB_REPOSITORY = "https://github.com/autohandai/voice"
GITHUB_GIT_URL = f"{GITHUB_REPOSITORY}.git"
APP_BUNDLE_ID = "ai.autohand.voice"
ANE_HELPER_NAME = "autohand-voice-stt"

APP_SUPPORT_DIR = Path.home() / "Library" / "Application Support" / PRODUCT_NAME
LOG_DIR = Path.home() / "Library" / "Logs" / PRODUCT_NAME
