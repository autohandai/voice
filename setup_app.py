"""py2app build configuration for Autohand Voice.app

Build a standalone macOS .app bundle:
    python setup_app.py py2app          # production build
    python setup_app.py py2app -A       # development build (symlinked)

Output: dist/Autohand Voice.app
"""

from setuptools import setup
from pathlib import Path

from dictate import __version__

ROOT = Path(__file__).resolve().parent
APP = [str(ROOT / "dictate" / "menubar_main.py")]
DATA_FILES = []
OPTIONS = {
    "argv_emulation": False,  # Must be False for menu bar apps
    "plist": {
        "CFBundleName": "Autohand Voice",
        "CFBundleDisplayName": "Autohand Voice",
        "CFBundleIdentifier": "ai.autohand.voice",
        "CFBundleVersion": __version__,
        "CFBundleShortVersionString": __version__,
        "LSUIElement": True,  # Menu bar only — no Dock icon
        "LSMinimumSystemVersion": "14.0",  # macOS Sonoma+ for MLX
        "NSMicrophoneUsageDescription": (
            "Autohand Voice needs microphone access for voice-to-text transcription. "
            "All processing happens locally on your device."
        ),
        "NSAppleEventsUsageDescription": (
            "Autohand Voice uses accessibility to type transcribed text "
            "into your active application."
        ),
    },
    "packages": [
        "dictate",
        "mlx",
        "mlx.core",
        "mlx.nn",
        "mlx_whisper",
        "mlx_lm",
        "numpy",
        "sounddevice",
        "pynput",
        "pyperclip",
        "huggingface_hub",
        "safetensors",
        "tokenizers",
        "transformers",
        "rumps",
        "dotenv",
    ],
    "includes": [
        "objc",
        "AppKit",
        "Foundation",
    ],
    "excludes": [
        "tkinter",
        "test",
        "unittest",
        "matplotlib",
        "scipy",
        "PIL",
        "IPython",
        "jupyter",
        "notebook",
        "pytest",
    ],
    "semi_standalone": False,
    "site_packages": True,
    "arch": "arm64",  # Apple Silicon only
}

ICON_FILE = ROOT / "assets" / "autohand-voice.icns"
if ICON_FILE.exists():
    OPTIONS["iconfile"] = str(ICON_FILE)

setup(
    app=APP,
    name="Autohand Voice",
    data_files=DATA_FILES,
    options={"py2app": OPTIONS},
    install_requires=[],
)
