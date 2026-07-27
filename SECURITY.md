# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| 1.x | Yes |

## Architecture

- Audio capture uses AVFoundation and is held in a bounded in-memory buffer.
- Speech recognition uses the pinned FluidAudio package and local CoreML models.
- No remote speech, cleanup, telemetry, analytics, or silent fallback exists.
- Direct text insertion requires macOS Accessibility permission and does not
  replace clipboard contents.
- Clipboard access occurs only when the user explicitly selects clipboard mode.
- Preferences and their directory are owner-only.

## Reporting a vulnerability

Do not open a public issue. Open a
[private security advisory](https://github.com/autohandai/voice/security/advisories/new)
with the impact, reproduction steps, and any suggested fix.

In scope: crafted-audio code execution, unsafe model loading, transcript or
clipboard disclosure, permission misuse, and privilege escalation.
