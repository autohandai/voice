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

- Talk is now available only on Macs with Apple Silicon. On Intel Macs,
  Fn + Shift is ordinary dictation and Settings explains why.
- Talk "On this Mac" can run Ternary Bonsai 2 natively on MLX on Apple
  Silicon (PrismML's 2-bit Hadamard pack, 1.2 GB, pinned and checksum-
  verified). MLX is preferred when installed; llama.cpp remains the runtime on
  Intel and under Rosetta. Try it with `autohand-voice talk-local --runtime mlx`.
- Optional Qwen3-ASR 0.6B (MLX, 4-bit) dictation engine on Apple Silicon:
  Settings → Dictation Engine. Downloads 713 MB once from a pinned revision,
  checksum-verified; Parakeet stays the default and is never swapped silently.
- Talk can answer on this Mac: choose Settings → Talk → Answered By → On this
  Mac to use Ternary Bonsai 2 (2B) through llama.cpp. No account, nothing
  leaves the Mac; the model downloads once and is checksum-verified.
- Autohand Voice no longer reads Keychain at launch, so macOS stops asking for
  the login password every time an update starts. The Talk key is read when
  Talk first needs it.
- Launch at Login is re-applied at every launch, so it survives updates.
- Hands-free Talk: hold Command + Shift and press Fn (or use Fn + Shift with
  the Hands-Free recording mode) to talk with Fantail without holding keys.
  Voice sends each turn after a short pause, speaks the reply, then listens
  again; Escape or Fn ends the conversation and Copy Conversation copies the
  whole exchange.
- The recording pill, the Talk card and the menu bar icon now draw the real
  recent voice level instead of an animated wobble: flat in silence, moving
  with each word. The level meter was recalibrated so normal speech no longer
  pins the bars at full height.
- With the Flow look, the "Done" pill now hides about 1.4 seconds after the
  text is inserted instead of staying for 10 seconds. Classic is unchanged.
- Talk with Fantail: hold Fn + Shift to ask a question and hear the answer.
  Transcription and the Kokoro voice stay on the Mac; only the question text
  and recent conversation go to Autohand. Optional Autohand sign-in (browser
  device flow, Keychain), free-plan limits with an upgrade prompt, and a new
  Talk settings pane.
- The menu bar icon now shows a live waveform that follows the microphone
  while recording.
- Fn is hold-to-talk in every Recording Mode and starts capturing the
  moment it is pressed, so first words are no longer clipped; a quick Fn
  tap is discarded silently. Recording Mode applies to the shortcut.
- New Flow recording look, a slim pill whose bars follow the voice, is now
  the default; the previous design stays available as Classic.
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
