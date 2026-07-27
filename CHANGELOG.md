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
