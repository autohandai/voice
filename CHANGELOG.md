# Changelog

## 1.0.0 - 2026-07-27

- Replaced the Python and MLX application runtime with a native Swift package.
- Added a native macOS menu bar app using AVFoundation audio capture.
- Made FluidAudio CoreML transcription on the Apple Neural Engine the only
  speech engine, with no remote or silent fallback.
- Added native cursor insertion that commits only final transcripts.
- Added native `autohand-voice` and `autohand-voice-stt` executables.
- Added owner-only JSON preferences and Swift unit tests for privacy,
  configuration, transcript, and audio contracts.
- Consolidated the contributor roster under Autohand Evolve and igorcosta while
  retaining required upstream MIT attribution.

## Unreleased

- Replaced the Input Monitoring-dependent modifier shortcut with a registered
  Control + Option + Space push-to-talk hotkey.
- Added legacy shortcut preference migration and explicit microphone and
  Accessibility recovery actions.
- Added a native SwiftUI Settings window with guided first-run setup,
  contextual permission requests, local-model readiness, launch-at-login
  control, and redacted privacy diagnostics.
- Added an optional nonactivating recording HUD with throttled local microphone
  level, processing/failure state, and accessible Stop and Dismiss actions.
- Added stable microphone selection, system-default and hot-plug tracking,
  bounded signal health diagnostics, and an eight-second local microphone test.
- Added conflict-checked custom registered shortcuts plus press-and-hold,
  toggle, and Escape-cancellable hands-free recording modes.
- Added focus-safe target and selection validation with explicit Retry Here,
  Copy, and Discard recovery for insertion failures.
- Added bounded in-memory audio recovery with local retry, explicit discard,
  and automatic 15-minute expiry after transcription failures.
- Added local model progress, v2/v3 selection, storage and validation status,
  cancellation, targeted repair, and actionable failure classification.
