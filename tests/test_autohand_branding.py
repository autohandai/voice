"""Public identity contract for Autohand Voice."""

from __future__ import annotations

import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_python_distribution_and_cli_are_canonical() -> None:
    project = tomllib.loads((ROOT / "pyproject.toml").read_text())["project"]

    assert project["name"] == "autohand-voice-mlx"
    assert project["version"] == "0.1.0"
    assert project["scripts"] == {"autohand-voice": "dictate.menubar_main:main"}
    assert project["urls"]["Repository"] == "https://github.com/autohandai/voice"


def test_runtime_uses_autohand_paths_and_environment(monkeypatch) -> None:
    from dictate.config import Config, OutputMode
    from dictate.presets import PREFS_DIR
    from dictate.transcribe import ANETranscriber

    monkeypatch.setenv("AUTOHAND_VOICE_OUTPUT_MODE", "clipboard")

    assert Config.from_env().output_mode is OutputMode.CLIPBOARD
    assert PREFS_DIR.parts[-1] == "Autohand Voice"
    assert ANETranscriber._BINARY_NAME == "autohand-voice-stt"


def test_readme_documents_the_branded_qwen_install() -> None:
    readme = (ROOT / "README.md").read_text()

    assert "# Autohand Voice" in readme
    assert "pip install 'autohand-voice-mlx[qwen3-asr]'" in readme
    assert "github.com/autohandai/voice" in readme
