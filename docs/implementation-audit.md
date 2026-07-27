# Autohand Voice: 20-Feature Implementation Audit

Audit date: 2026-07-27

This ledger maps the 20 improvements in `docs/product-roadmap.md` to committed
implementation and automated evidence. The app remains native Swift, uses the
pinned CoreML speech recognizer locally, and has no remote speech or cleanup
fallback.

| # | Improvement | Commit | Primary implementation | Automated evidence |
|---:|---|---|---|---|
| 1 | Native SwiftUI app shell and settings | `3f56e30` | `AppSettingsView`, `AppSettingsModel`, `SettingsWindowController`, `MenuBarController` | `AppLayerPreferencesTests`, `PreferencesTests` |
| 2 | Guided onboarding and permission center | `3f56e30` | `GettingStartedView`, `PermissionCenterView`, `SystemCheck` | `AppLayerPreferencesTests`, `DiagnosticReportTests` |
| 3 | Accessible recording HUD | `3f56e30` | `RecordingHUDController`, `VoiceSession` | `AppLayerPreferencesTests`, `AccessibilityBaselineTests` |
| 4 | Configurable shortcut and recording modes | `4bb217e` | `RegisteredShortcut`, `HotKeyMonitor`, `VoiceSession` | `PreferencesTests` |
| 5 | Microphone picker and audio health | `c0e8442` | `AudioInputDevice`, `AudioCapture`, audio settings | `AudioCaptureTests`, `AppLayerPreferencesTests` |
| 6 | Model readiness and manager | `c17c79a` | `ModelManagement`, language/model settings | `ModelManagementTests` |
| 7 | Focus-safe insertion recovery | `b96efe5` | `TextInsertion`, recovery actions in `VoiceSession` | `TextInsertionTests` |
| 8 | In-memory failed-dictation recovery | `69acabf` | `InMemoryAudioRecovery`, `VoiceSession` | `AudioRecoveryTests` |
| 9 | Optional local text history | `0f320ed` | `HistoryStore`, `HistoryView` | `HistoryStoreTests` |
| 10 | Local vocabulary and replacements | `b06e805` | `Vocabulary`, `VocabularySettingsModel` | `VocabularyTests` |
| 11 | Local dictation commands | `3efe92c` | `DictationCommands`, finalization pipeline | `DictationCommandTests` |
| 12 | Deterministic smart formatting | `a9c4284` | `SmartFormatting`, formatting settings | `SmartFormattingTests` |
| 13 | Per-app profiles | `e2cfaae` | `AppProfiles`, `AppProfileSettingsModel` | `AppProfileTests` |
| 14 | Language and model profiles | `0a14308` | `ModelManagement`, language/model settings | `LanguageProfileTests` |
| 15 | Provisional preview, final-only commit | `b2b8b40` | `Transcript`, `LocalSpeechRecognizer`, HUD preview | `TranscriptTests` |
| 16 | Native file transcription | `b37cfb6` | `FileTranscription`, `FileTranscriptionView` | `FileTranscriptionTests` |
| 17 | Login and lifecycle resilience | `4faba21` | `LifecyclePolicy`, `SMAppService` integration | `LifecyclePolicyTests` |
| 18 | Private aggregate usage insights | `828a3e9` | `UsageInsights`, `UsageInsightsView` | `UsageInsightsTests` |
| 19 | Accessibility and localization baseline | `0701303` | `Localizable.xcstrings`, semantic/adaptive SwiftUI views | `AccessibilityBaselineTests` |
| 20 | Diagnostics and privacy center | `20ae48e` | `DiagnosticReport`, `OperationalIssues`, privacy settings | `DiagnosticReportTests`, `OperationalIssueTests` |

## Architecture decisions

- A single `VoiceSession` owns the runtime. SwiftUI settings and utility
  windows receive that shared instance rather than creating recognizers during
  view redraws.
- The existing AppKit status item and hosting windows are retained for stable
  menu-bar, nonactivating-panel, and Carbon hot-key behavior. Product settings
  and app-layer views are SwiftUI.
- Provisional transcripts are view-only. Only a final transcript can pass the
  commit gate.
- History, vocabulary, profiles, insights, preferences, and operational issue
  files are local, bounded, and owner-only.
- Diagnostic reports expose finite states and aggregate categories, not
  dictated text, audio, paths, environment values, focused content, or
  microphone names.

## Current release evidence

The exact `20ae48e` commit passed 105 XCTest cases with zero failures, built
both release executables, returned a successful local-only JSON health check,
packaged the signed `.app`, and launched the packaged native process on Apple
Silicon.

Live microphone dictation and Accessibility insertion remain environment
permission-dependent manual release checks. A denied permission is surfaced as
an unavailable diagnostic state; it never triggers remote or alternate-engine
fallback.
