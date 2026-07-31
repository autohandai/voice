# Wispr Flow Source Inventory

Research date: 2026-07-29

## Scope

This file inventories the feature families currently represented on `https://wisprflow.ai/whats-new`, using Wispr first-party sources only:

- `https://wisprflow.ai/whats-new`
- `https://docs.wisprflow.ai/...`
- `https://wisprflow.ai/data-controls`
- `https://statuspage.incident.io/wispr-flow`

This is an evidence inventory, not an Autohand implementation plan.

## Method

- Read the current `What's new` page directly and pulled the underlying HTML to avoid Webflow truncation.
- Followed each changelog card to first-party help, product, privacy, admin, and security pages when those pages were readable.
- Marked `Source-backed` statements only when a first-party page explicitly said them.
- Marked `Inference` only when the changelog implied something but no clearer first-party detail was readable.

## ID convention

- Caller requested IDs in the format `WF-YYYYMMDD-{DESKTOP|ANDROID|IOS}-NN`.
- Some Wispr changelog cards are tagged `all-platforms`, not `desktop`.
- For those cards only, I assigned `DESKTOP` in the ID solely to satisfy the requested key format, and I explicitly note the real scope as `all-platforms`.

## Cross-cutting source facts

- Wispr documents repeatedly describe Flow as cloud-backed, not local-only. The security FAQ says Wispr Flow "runs entirely in the cloud" as multi-tenant SaaS and has no on-prem deployment.
- `Private Cloud Sync` and `Privacy Mode` are separate controls. Source-backed behavior:
  - `Private Cloud Sync` governs server-side storage and cross-device features.
  - `Privacy Mode` governs whether dictation data is used for model training.
- Wispr's own help says `Private Cloud Sync` is required for server-backed features including Wispr Notetaker, personalized speech models, meeting notes, and cross-device notes sync.
- Context Awareness is on by default on Mac and Windows, and Wispr says it can send app info, nearby text, screenshots, file names, and conversation context unless Privacy Mode is on.
- Wispr's Android setup docs explicitly say Flow requires an internet connection and does not work offline.

## Coverage boundary

- As of 2026-07-29, the public `What's new` page exposed dated entries from 2026-03-31 through 2026-07-09.
- I did not find a first-party older archive page from the same surface during this pass.

## Inventory

### 2026-07-09

#### `WF-20260709-DESKTOP-01` — Reliability and accuracy status update

- Card scope: `all-platforms` on `What's new`.
- Source-backed:
  - Wispr claimed 99.9% dictation uptime over the prior few weeks.
  - Wispr claimed dictation latency was down 30% since the start of the year.
  - Wispr claimed a recent accuracy regression was caused by Auto Cleanup being too aggressive for some users and that this was fixed.
- URLs:
  - `https://wisprflow.ai/whats-new`

#### `WF-20260709-DESKTOP-02` — Drag and dock the Flow Bar

- Card scope: desktop.
- Source-backed:
  - Flow Bar can be docked to bottom, left, or right.
  - Position persists across app launches and restarts.
  - Side docking reorients the bar vertically.
  - `Esc` cancels drag.
  - Rollout is gradual; not every account may see the drag-to-dock affordance yet.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/1790396454-move-and-dock-the-flow-bar-on-desktop`
  - `https://docs.wisprflow.ai/articles/3941699399-keyboard-and-screen-reader-accessibility-in-wispr-flow`

#### `WF-20260709-DESKTOP-03` — Canadian English prompt

- Card scope: desktop.
- Source-backed:
  - One-time prompt for English-speaking Canadian users.
  - Accepting the prompt switches conflicting English variants to Canadian English.
  - Desktop only.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/3191899797-use-flow-with-multiple-languages`

### 2026-07-02

#### `WF-20260702-ANDROID-01` — Android reliability and stability pass

- Card scope: Android `v2.0.9`.
- Source-backed:
  - Flow Bubble self-recovery.
  - Accessibility-permission recovery when Android revokes it in the background.
  - Crash fixes.
  - Per-account isolation for settings and onboarding on shared devices.
  - Bubble sizing, visibility, error, snooze, and shrink fixes.
  - Xiaomi and OnePlus battery/overlay fixes.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/2296441257-starting-your-first-dictation-on-android`
  - `https://docs.wisprflow.ai/articles/5002934560-why-is-the-wispr-bar-is-not-appearing-or-disappearing`

#### `WF-20260702-IOS-01` — Broader iOS auto-switchback coverage

- Card scope: iOS `v1.63`.
- Source-backed:
  - Auto-switchback returns users to the host app after dictation.
  - Wispr claims support across every supported iOS version, including the iOS 27 beta.
  - Newly named app coverage includes Claude, ChatGPT, Gemini, Grok, Perplexity, Kin, LinkedIn, and additional messaging/productivity apps.
- URLs:
  - `https://wisprflow.ai/whats-new`

### 2026-06-24

#### `WF-20260624-DESKTOP-01` — Consistent formatting model rollout

- Card scope: `all-platforms` on `What's new`.
- Source-backed:
  - Wispr attributed recent formatting inconsistency to some dictations being handled by older models.
  - Claimed fixes: cleaner course correction, fewer unwanted word substitutions, punctuation/corrections honoring user intent more consistently.
  - Wispr also claimed new A/B testing and benchmark expansion before future model rollouts.
- URLs:
  - `https://wisprflow.ai/whats-new`

#### `WF-20260624-DESKTOP-02` — Ranked microphone auto-selection

- Card scope: desktop `v1.5.751`.
- Source-backed:
  - Users rank microphones once.
  - Flow chooses the highest-ranked currently available input.
  - Mid-dictation unplug falls back to the next-ranked mic without manual switching.
  - Setting lives under `Settings > General > Microphone`.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/5096240724-navigating-the-wispr-flow-app-desktop-ios-and-android`

#### `WF-20260624-DESKTOP-03` — Clamshell microphone continuity

- Card scope: desktop `v1.5.751`.
- Source-backed:
  - Closing the laptop lid switches to the highest-ranked external microphone automatically.
  - Reopening switches back to the built-in mic.
  - Reordering microphones applies instantly without restarting dictation.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/1036674442-supported-devices-and-system-requirements`

### 2026-06-17

#### `WF-20260617-DESKTOP-01` — Infrastructure reliability remediation

- Card scope: desktop `v1.5.891`.
- Source-backed:
  - Wispr tied degraded service to rapid growth and infrastructure strain.
  - Claimed mitigations: scale-up, isolating demanding work to dedicated systems, tighter monitoring.
  - Accuracy fixes called out: UK English routing, Swiss German routing, audio-compression handling, stronger eval suite.
  - Wispr said personalized speech models are being built for the future.
- URLs:
  - `https://wisprflow.ai/whats-new`

#### `WF-20260617-DESKTOP-02` — Cloud Sync and split privacy controls

- Card scope: desktop `v1.5.891`, but the underlying settings affect multiple platforms.
- Source-backed:
  - New `Cloud Sync` setting introduced alongside `Privacy Mode`.
  - `Privacy Mode` still governs model training.
  - `Cloud Sync` governs whether transcripts, audio, and dictation history are stored on Wispr servers.
  - Existing Privacy Mode users were said to remain on effectively zero data retention unless they opt into Cloud Sync.
  - Dictionary, snippets, and custom prompts continue syncing regardless of Cloud Sync; Scratchpad cross-device sync requires Cloud Sync.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://wisprflow.ai/data-controls`
  - `https://docs.wisprflow.ai/articles/9609615338-private-cloud-sync-and-data-sharing-preferences-in-wispr-flow`
  - `https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq`

#### `WF-20260617-IOS-01` — Interrupted dictation preservation and notification

- Card scope: iOS `v1.62`.
- Source-backed:
  - Interruptions from calls, Siri, or the five-minute limit now notify the user that the transcript was saved.
  - Tapping the notification jumps to the transcript and auto-copies it.
  - Failed dictations can notify with tap-to-retry.
- URLs:
  - `https://wisprflow.ai/whats-new`

#### `WF-20260617-IOS-02` — One-tap retry for failed transcripts

- Card scope: iOS `v1.62`.
- Source-backed:
  - Failed transcripts are visually highlighted in orange.
  - Row tap or dedicated retry button triggers retry directly.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/2503460374-retry-failed-transcriptions`

#### `WF-20260617-IOS-03` — Always-on live dictation timer

- Card scope: iOS `v1.62`.
- Source-backed:
  - Dynamic Island and Lock Screen live activity timer now appears for every dictation, not only Action Button launches.
- URLs:
  - `https://wisprflow.ai/whats-new`

#### `WF-20260617-IOS-04` — Faster backspace behavior

- Card scope: iOS `v1.62`.
- Source-backed:
  - Single tap deletes one character on release.
  - Hold accelerates from character deletion to word deletion after about two seconds.
  - Wispr claims broad language coverage including CJK and Indic languages.
- URLs:
  - `https://wisprflow.ai/whats-new`

### 2026-06-10

#### `WF-20260610-DESKTOP-01` — Reliability incident report and recovery plan

- Card scope: desktop `v1.5.751`.
- Source-backed:
  - Wispr separated two prior weeks of issues into vendor/scaling outages and backend instability.
  - Claimed actions: engineering reprioritization to stability, reevaluating vendors, adding provider redundancy, testing rollback of a recent setting, and developing an upgraded speech-recognition model.
  - Wispr pointed users to the public status page and support page for ongoing incident visibility.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://statuspage.incident.io/wispr-flow`

#### `WF-20260610-DESKTOP-02` — Desktop Hub localization

- Card scope: desktop `v1.5.751`.
- Source-backed:
  - App language selection for English, German, Spanish, Italian, and Portuguese.
  - Settings, notifications, insights, and more adapt to the selected app language.
  - Setting path: `Settings > General > App language`.
- URLs:
  - `https://wisprflow.ai/whats-new`

### 2026-06-04

#### `WF-20260604-DESKTOP-01` — Reliability and accuracy remediation update

- Card scope: desktop `v1.5.619`.
- Source-backed:
  - Wispr attributed recent outages to infrastructure changes made while
    scaling capacity and said failover had not worked as planned.
  - Claimed mitigations included provider redundancy, health monitoring, and an
    on-call rotation.
  - Wispr said an Auto Cleanup rollback and an upgraded speech-recognition
    model were being tested for accuracy and latency.
  - Wispr described stronger pre-release internal tooling as longer-term work.
- URLs:
  - `https://wisprflow.ai/whats-new`

### 2026-05-01

#### `WF-20260501-DESKTOP-01` — Scratchpad beta

- Card scope: desktop `v1.5.113`.
- Source-backed:
  - Scratchpad replaces desktop Flow Notes.
  - Floating notepad launched by shortcut, default `Option + S` on Mac.
  - Desktop experience includes rich text, tabs, version history, notes sidebar, and image support.
  - Syncs with iPhone Notes/Scratchpad; Android not yet supported.
  - Beta with noted sync issues.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/9618237082-using-the-scratchpad-to-save-and-edit-notes`

#### `WF-20260501-DESKTOP-02` — Transforms beta

- Card scope: desktop `v1.5.113`.
- Source-backed:
  - Highlight text and rewrite it with AI anywhere Flow works.
  - Built-ins: `Polish` and `Prompt Engineer`.
  - Custom transforms supported.
  - Can run on demand or automatically after dictation.
  - Beta caveat: discoverability/activation still being worked on.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/8068950331-how-to-use-transforms-beta`
  - `https://docs.wisprflow.ai/articles/2719941210-how-to-configure-polish-shortcuts-and-custom-prompts`

#### `WF-20260501-DESKTOP-03` — Terminal paste visibility for Claude Code and Codex

- Card scope: desktop `v1.5.113`.
- Source-backed:
  - Long dictations into AI coding terminals are kept visible/editable instead of collapsing into pasted-line placeholders.
  - Claude Code and Codex are explicitly named.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/6478598909-using-flow-with-linux-wsl-and-terminal-applications`

#### `WF-20260501-DESKTOP-04` — Public status page access

- Card scope: desktop `v1.5.113`.
- Source-backed:
  - Users can check current incidents and subscribe for updates via Wispr's public status page.
  - In-app surfacing was described as future work.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://statuspage.incident.io/wispr-flow`

#### `WF-20260501-DESKTOP-05` — Recover dictations after app quit/restart

- Card scope: desktop `v1.5.113`.
- Source-backed:
  - Mid-dictation audio is automatically saved if the app quits or restarts.
  - Recovery path is reopening Flow, going to History, and clicking `Recover`.
- URLs:
  - `https://wisprflow.ai/whats-new`

#### `WF-20260501-DESKTOP-06` — Specific microphone error notifications

- Card scope: desktop `v1.5.113`.
- Source-backed:
  - Mic error notifications distinguish unplugged microphone, mic in use by another app, and system-permission block.
  - Notifications include suggested remediation.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/4351452717-troubleshooting-mic-issues`

#### `WF-20260501-DESKTOP-07` — Manual subscription refresh

- Card scope: desktop `v1.5.113`.
- Source-backed:
  - Settings now expose a sync button in `Plans & Billing` to refresh plan state after upgrading elsewhere.
- URLs:
  - `https://wisprflow.ai/whats-new`

#### `WF-20260501-DESKTOP-08` — Non-billable IT Admin seats

- Card scope: desktop/admin `v1.5.113`.
- Source-backed:
  - Enterprises can add non-paid IT Admin seats.
  - IT Admins manage settings, billing, and usage without a dictation license.
  - Admin portal docs say IT Admin is web/admin oriented and blocked from desktop dictation use.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/2277907847-how-do-i-use-the-admin-portal-to-manage-users-and-billing`
  - `https://docs.wisprflow.ai/articles/2458545840-faqs-for-flow-pro-team-and-flow-enterprise-plans`

#### `WF-20260501-ANDROID-01` — Smarter shake-to-unsnooze

- Card scope: Android `v1.88`.
- Source-backed:
  - Shake gesture only runs while snoozed.
  - Accelerometer stays off otherwise to reduce false triggers and battery use.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/3400534884-snooze-the-dictation-bubble`

#### `WF-20260501-ANDROID-02` — Smarter Android back navigation

- Card scope: Android `v1.88`.
- Source-backed:
  - Back button now closes drawers cleanly, dismisses keyboards before navigation, and returns predictably to Home.
- URLs:
  - `https://wisprflow.ai/whats-new`

#### `WF-20260501-IOS-01` — iPhone Scratchpad/Notes sync with desktop

- Card scope: iOS `v1.59`.
- Source-backed:
  - Notes now sync between desktop Scratchpad and iPhone.
  - iPhone remains plain text and still uses the `Notes` name at this point.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/9618237082-using-the-scratchpad-to-save-and-edit-notes`

### 2026-04-24

#### `WF-20260424-DESKTOP-01` — Insights tab

- Card scope: desktop `v1.5.55`.
- Source-backed:
  - Three views: `Your Usage`, `Your Voice`, `Leaderboard`.
  - Usage includes WPM, total words, cleaned-up words, dictionary/snippet replacements, top apps, streak heatmap.
  - Your Voice is a communication profile unlocking at 2,000 words.
  - Leaderboard is for enterprise teams with weekly/all-time views and a podium.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/5936327641-team-insights-measuring-the-impact-of-wispr-flow-rollout-admin-usage-page`

#### `WF-20260424-DESKTOP-02` — Auto Cleanup levels

- Card scope: desktop `v1.5.55`.
- Source-backed:
  - Replaces prior Smart Formatting toggle with levels `None`, `Light`, `Medium`, `High`.
  - Lives in the `Style` tab, not Settings.
  - Original/raw dictation remains reversible with `Undo AI edit`.
  - Help article currently exists but is not readable beyond a placeholder.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/4136931124-how-to-use-auto-cleanup-beta`
  - `https://docs.wisprflow.ai/articles/5373093536-how-do-i-use-smart-formatting-and-backtrack`

#### `WF-20260424-DESKTOP-03` — Local transcript storage policy

- Card scope: desktop `v1.5.55`.
- Source-backed:
  - Local-only storage options: store normally, auto-delete after 24 hours, or never store on-device.
  - Later privacy/admin docs confirm these policies are enforceable and affect transcript/polish/instruct history.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness`
  - `https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq`

#### `WF-20260424-DESKTOP-04` — Team invite links

- Card scope: desktop `v1.5.55`.
- Source-backed:
  - Team admins can generate a shareable join link.
  - Link is available from team settings and the admin portal.
  - Signup through the link adds the user automatically.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/2277907847-how-do-i-use-the-admin-portal-to-manage-users-and-billing`
  - `https://docs.wisprflow.ai/articles/2458545840-faqs-for-flow-pro-team-and-flow-enterprise-plans`

#### `WF-20260424-DESKTOP-05` — Desktop reliability improvements

- Card scope: desktop `v1.5.55`.
- Source-backed:
  - Windows `Start at login` reliability fix.
  - Additional text insertion, notification, and dictation responsiveness fixes.
- URLs:
  - `https://wisprflow.ai/whats-new`

#### `WF-20260424-ANDROID-01` — Bubble auto-shrink and search-field minimization

- Card scope: Android `v1.7.3`.
- Source-backed:
  - Bubble auto-shrinks after five seconds of inactivity.
  - Can shrink to compact icon or dot.
  - Can minimize in search fields.
  - Bubble size docs expose related toggles and defaults.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/8858845757-setup-wispr-flow-on-android-android-settings`
  - `https://docs.wisprflow.ai/articles/2296441257-starting-your-first-dictation-on-android`

#### `WF-20260424-ANDROID-02` — Cleaner Android notification tray

- Card scope: Android `v1.7.3`.
- Source-backed:
  - Persistent foreground notification removed.
- Caveat:
  - The `What's new` card links to a first-party article, but that link currently lands on an unrelated admin-portal article, so detailed first-party behavior for this item was not directly readable from the linked destination.
- URLs:
  - `https://wisprflow.ai/whats-new`

#### `WF-20260424-ANDROID-03` — Post-dictation copy button

- Card scope: Android `v1.7.3`.
- Source-backed:
  - Copy-to-clipboard button appears beside the bubble after dictation.
  - Auto-dismisses after roughly ten seconds.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/8858845757-setup-wispr-flow-on-android-android-settings`

#### `WF-20260424-ANDROID-04` — Bubble opacity control

- Card scope: Android `v1.7.3`.
- Source-backed:
  - Opacity slider from 20% to 100%.
  - Android setup docs specify five stops with 80% default.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/8858845757-setup-wispr-flow-on-android-android-settings`

#### `WF-20260424-ANDROID-05` — Android reliability improvements

- Card scope: Android `v1.7.3`.
- Source-backed:
  - Faster response when entering text fields.
  - Service auto-recovery after battery manager stops it.
  - Android 16 compatibility.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/6344532666-android-system-requirements`

#### `WF-20260424-IOS-01` — Action Button quick dictation to notes

- Card scope: iOS `v1.52`.
- Source-backed:
  - Built-in `Quick Dictation to Notes` shortcut can be bound to the Action Button.
  - Saves directly to Flow Notes.
  - Works even when stopping from Dynamic Island.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/4500510662-set-up-the-action-button-for-flow-on-iphone`

### 2026-03-31

#### `WF-20260331-DESKTOP-01` — Flow Bar language picker

- Card scope: desktop `v1.4.661`.
- Source-backed:
  - Manual language switching moved into the Flow Bar.
  - Requires multiple selected languages.
  - Best-results guidance favors manual selection over frequent auto-detect switching.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/3191899797-use-flow-with-multiple-languages`

#### `WF-20260331-DESKTOP-02` — 20-minute dictations

- Card scope: desktop `v1.4.661`.
- Source-backed:
  - Single-session desktop dictation limit raised to 20 minutes.
  - One-minute warning at 19 minutes.
  - Auto-submit at 20 minutes with transcript recovery affordances.
  - Applies to Basic and Pro on desktop.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/4841123325-longer-dictation-sessions-now-up-to-20-minutes`

#### `WF-20260331-DESKTOP-03` — Mouse Flow

- Card scope: desktop `v1.4.661`.
- Source-backed:
  - Non-primary mouse buttons can trigger dictation.
  - Mouse buttons can also bind Enter/send behavior.
  - Guided walkthrough appears when supported mouse hardware is present.
- Inference:
  - The help center page named in the changelog was not surfaced readably during this pass, but the shortcut system docs do confirm mouse-button binding rules.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/5298382595-route-dictation-directly-to-slack-email-or-calendar-with-keyboard-shortcuts`

#### `WF-20260331-DESKTOP-04` — Dictionary upgrades

- Card scope: desktop `v1.4.661`.
- Source-backed:
  - Star important words.
  - Usage-based ranking.
  - Smarter auto-add filtering for apostrophe variants.
  - Changelog also notes Android dictionary launch in the same month.
- URLs:
  - `https://wisprflow.ai/whats-new`

#### `WF-20260331-DESKTOP-05` — Shortcut and control upgrades

- Card scope: desktop `v1.4.661`.
- Source-backed:
  - Rebindable cancel shortcut.
  - Retry from Hub history after cancelled/error dictations.
  - Rebind Enter for dictation control/send behavior.
  - Shortcut system supports up to four bindings, mouse buttons, and conditional rows for advanced features.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/5298382595-route-dictation-directly-to-slack-email-or-calendar-with-keyboard-shortcuts`
  - `https://docs.wisprflow.ai/articles/2612050838-supported-unsupported-keyboard-hotkey-shortcuts`

#### `WF-20260331-DESKTOP-06` — Smarter notifications

- Card scope: desktop `v1.4.661`.
- Source-backed:
  - Redesigned notification UI.
  - Granular category muting.
  - Button-click confirmation checkmarks.
  - Help article also documents critical notifications that cannot be muted, enterprise-only categories, and per-device storage of notification prefs.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/2250194357-customize-notification-preferences-by-category`

#### `WF-20260331-DESKTOP-07` — Additional desktop app/site support bundle

- Card scope: desktop `v1.4.661`.
- Source-backed:
  - Browser-based sign-in for everyone.
  - Clamshell-mode microphone warning.
  - Additional Styles classification for Instagram, Discord, Signal, and LinkedIn.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/3152211871-setup-guide`
  - `https://docs.wisprflow.ai/articles/1036674442-supported-devices-and-system-requirements`

#### `WF-20260331-DESKTOP-08` — In-app HIPAA BAA visibility

- Card scope: desktop `v1.4.661`.
- Source-backed:
  - Enterprise HIPAA BAA users can view signing details and download the agreement from Settings.
  - Security docs say active BAA forces Privacy Mode on and Cloud Sync off.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq`

#### `WF-20260331-DESKTOP-09` — Desktop stability and reliability bundle

- Card scope: desktop `v1.4.661`.
- Source-backed:
  - Fewer duplicate notification sounds.
  - Better wake-from-sleep recovery.
  - Better dictation start/stop responsiveness.
  - Several Windows UI fixes.
- URLs:
  - `https://wisprflow.ai/whats-new`

#### `WF-20260331-ANDROID-01` — Android custom dictionary

- Card scope: Android `v1.4.1`.
- Source-backed:
  - Add, edit, delete, and search custom dictionary entries on Android.
  - Dictation prioritizes those words afterward.
- URLs:
  - `https://wisprflow.ai/whats-new`

#### `WF-20260331-ANDROID-02` — Android context-aware dictation

- Card scope: Android `v1.4.1`.
- Source-backed:
  - Reads surrounding text before transcribing.
  - Continues sentences naturally, matches prior tone, and avoids repetition.
- Caveat:
  - Help-center `Context Awareness` article is desktop-oriented (`Mac, Windows`) even though the changelog claims Android parity for surrounding-text behavior.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness`

#### `WF-20260331-ANDROID-03` — Banking app privacy protection

- Card scope: Android `v1.4.1`.
- Source-backed:
  - Dictation pauses automatically in 50+ banking and financial apps across multiple regions.
  - Related Android troubleshooting docs say banking/payment apps are intentionally excluded from bubble appearance.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/collections/7190508483-android`
  - `https://docs.wisprflow.ai/articles/5002934560-why-is-the-wispr-bar-is-not-appearing-or-disappearing`

#### `WF-20260331-ANDROID-04` — Secure sign-out

- Card scope: Android `v1.4.1`.
- Source-backed:
  - Sign-out adds confirmation and deletes local transcripts.
- URLs:
  - `https://wisprflow.ai/whats-new`

#### `WF-20260331-ANDROID-05` — Android quality-of-life bundle

- Card scope: Android `v1.4.1`.
- Source-backed:
  - Tap transcript to copy from history.
  - `Copy Last` action in the notification shade.
  - Keep screen on during dictation.
  - Warn/auto-save at five-minute session limit.
  - Retry failed transcriptions without redictating.
  - Home-screen warning card when background service stops.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/2296441257-starting-your-first-dictation-on-android`
  - `https://docs.wisprflow.ai/articles/2250194357-customize-notification-preferences-by-category`
  - `https://docs.wisprflow.ai/articles/6216145749-dictation-session-time-limits-on-android`

#### `WF-20260331-ANDROID-06` — Android stability and reliability bundle

- Card scope: Android `v1.4.1`.
- Source-backed:
  - Fixes for Samsung-default-browser crash scenario.
  - Wrong-target-field insertion fixes.
  - Waveform startup responsiveness fixes.
  - Accessibility framework fixes.
- URLs:
  - `https://wisprflow.ai/whats-new`

#### `WF-20260331-IOS-01` — Adapting to iOS 26.4

- Card scope: iOS `v1.46`.
- Source-backed:
  - Apple platform change broke prior quick-switchback behavior in many apps.
  - Apple platform change removed app-based automatic style switching.
  - Wispr response: app-level default style setting and keyboard style pill override.
  - Style override resets after 15 minutes of inactivity.
  - Available only for users with English, British English, or auto-detect language settings.
- URLs:
  - `https://wisprflow.ai/whats-new`
  - `https://docs.wisprflow.ai/articles/6269634092-adapting-to-ios-26-4`

## Coverage table

| Date | Version / platform card | IDs | Primary source URL | First-party details readable? |
| --- | --- | --- | --- | --- |
| 2026-07-09 | all-platforms, no version shown | `WF-20260709-DESKTOP-01` | `https://wisprflow.ai/whats-new` | Yes |
| 2026-07-09 | desktop, no version shown | `WF-20260709-DESKTOP-02`, `WF-20260709-DESKTOP-03` | `https://wisprflow.ai/whats-new` | Yes |
| 2026-07-02 | Android `v2.0.9` | `WF-20260702-ANDROID-01` | `https://wisprflow.ai/whats-new` | Yes |
| 2026-07-02 | iOS `v1.63` | `WF-20260702-IOS-01` | `https://wisprflow.ai/whats-new` | Partial |
| 2026-06-24 | all-platforms, no version shown | `WF-20260624-DESKTOP-01` | `https://wisprflow.ai/whats-new` | Yes |
| 2026-06-24 | desktop `v1.5.751` | `WF-20260624-DESKTOP-02`, `WF-20260624-DESKTOP-03` | `https://wisprflow.ai/whats-new` | Yes |
| 2026-06-17 | desktop `v1.5.891` | `WF-20260617-DESKTOP-01`, `WF-20260617-DESKTOP-02` | `https://wisprflow.ai/whats-new` | Yes |
| 2026-06-17 | iOS `v1.62` | `WF-20260617-IOS-01` to `WF-20260617-IOS-04` | `https://wisprflow.ai/whats-new` | Partial |
| 2026-06-10 | desktop `v1.5.751` | `WF-20260610-DESKTOP-01`, `WF-20260610-DESKTOP-02` | `https://wisprflow.ai/whats-new` | Partial |
| 2026-06-04 | desktop `v1.5.619` | `WF-20260604-DESKTOP-01` | `https://wisprflow.ai/whats-new` | Yes |
| 2026-05-01 | desktop `v1.5.113` | `WF-20260501-DESKTOP-01` to `WF-20260501-DESKTOP-08` | `https://wisprflow.ai/whats-new` | Yes |
| 2026-05-01 | Android `v1.88` | `WF-20260501-ANDROID-01`, `WF-20260501-ANDROID-02` | `https://wisprflow.ai/whats-new` | Partial |
| 2026-05-01 | iOS `v1.59` | `WF-20260501-IOS-01` | `https://wisprflow.ai/whats-new` | Yes |
| 2026-04-24 | desktop `v1.5.55` | `WF-20260424-DESKTOP-01` to `WF-20260424-DESKTOP-05` | `https://wisprflow.ai/whats-new` | Partial |
| 2026-04-24 | Android `v1.7.3` | `WF-20260424-ANDROID-01` to `WF-20260424-ANDROID-05` | `https://wisprflow.ai/whats-new` | Partial |
| 2026-04-24 | iOS `v1.52` | `WF-20260424-IOS-01` | `https://wisprflow.ai/whats-new` | Yes |
| 2026-03-31 | desktop `v1.4.661` | `WF-20260331-DESKTOP-01` to `WF-20260331-DESKTOP-09` | `https://wisprflow.ai/whats-new` | Partial |
| 2026-03-31 | Android `v1.4.1` | `WF-20260331-ANDROID-01` to `WF-20260331-ANDROID-06` | `https://wisprflow.ai/whats-new` | Partial |
| 2026-03-31 | iOS `v1.46` | `WF-20260331-IOS-01` | `https://wisprflow.ai/whats-new` | Yes |

## Unreadable or mismatched first-party sections

- `How to Use Auto Cleanup (Beta)` exists but currently renders as a placeholder saying the article is not available yet.
- Some changelog links currently point to unrelated first-party articles, so the destination URL cannot always be trusted as a semantic match.
  - Example: the April 24 Android `Cleaner notification tray` item linked to an admin-portal article during this pass.
- Some linked help topics were not independently discoverable/readable even though the changelog HTML preserved the feature description.
  - Example: `Set up Mouse Flow for faster dictation workflows`.
- The public `What's new` page is the authoritative source for the dated entry list, but some deeper help pages appear newer than the changelog entry and may reflect evolved behavior rather than the exact launch-day state.

## Totals

- Dated changelog entries captured: 9
- Version/platform cards captured: 19
- Stable feature-family IDs assigned: 55
