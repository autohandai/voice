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

- The menu bar icon now shows a live waveform that follows the microphone
  while recording.
- Fn now follows the Recording Mode: in Toggle and Hands-Free, hold Fn to
  start, keep talking after letting go, and press Fn again to finish.
- Warn when macOS Dictation is on, since pressing Fn twice can also start
  Apple's Dictation, with a shortcut to Keyboard settings.
- Shipped a universal app that also runs on Intel Macs (CoreML on the CPU
  and GPU there), and updated FluidAudio to 0.15.8.
- Fixed microphone start failing with -10868 when the input and output devices
  run at different sample rates (#1).
- Fixed type-mode insertion silently doing nothing in Terminal, iTerm2, and the
  onboarding dictation test (#2); added standard Edit menu shortcuts to the
  app's own windows.
- Fixed onboarding getting stuck after a recording with no recognized speech:
  a failed attempt no longer blocks the next one, and audio with no words is
  erased instead of held for recovery.
- A recording where no sound reached the app now names the microphone and
  explains how to fix it, instead of reporting an empty transcript.
- Opening the app while it is already running now shows its window.
- Onboarding now shows the official Autohand logo.
- The recording HUD now renders at native resolution instead of being scaled
  down.

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
- Added opt-in owner-only text history with search, copy, retention controls,
  outcome status, JSON export, and confirmed deletion.
- Added owner-only local vocabulary with deterministic whole-word
  replacements, case preservation, before/after preview, and CSV/JSON
  import and export.
- Added opt-in English dictation commands with an explicit ambiguity-safe
  prefix, literal mode, scratch-current-buffer, and cancel-without-commit.
- Added opt-in cursor-aware smart spacing, sentence and paragraph
  capitalization, terminal punctuation, before/after preview, and an
  in-memory copy of the latest unformatted transcript.
- Added bounded owner-only per-app profiles with exact bundle-identifier
  matching, global fallback, native management UI, and visible active profile.
- Added explicit language profiles for the pinned English v2 and 25-language
  v3 models, localized test phrases, safe model/language compatibility,
  translation clarification, and confirmed known-cache removal.
