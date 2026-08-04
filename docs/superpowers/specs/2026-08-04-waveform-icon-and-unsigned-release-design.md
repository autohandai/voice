# Waveform app icon + public unsigned DMG release

Date: 2026-08-04
Status: Approved

## Problem

Autohand Voice has no Apple Developer ID certificate, so the existing
`release-macos.yml` workflow (which intentionally refuses to publish
anything that isn't notarized) can never produce a public release. Meanwhile
the app also has no app icon at all — `assets/README.md` documents an
`autohand-voice.icns` as required, but it was never created and
`Resources/Info.plist` has no `CFBundleIconFile` key.

The goal: ship a simple waveform mark as the app icon, and make an unsigned,
ad-hoc-signed DMG publicly downloadable the way many indie macOS apps are
distributed outside the App Store (direct download, Gatekeeper right-click
"Open").

## Part 1 — App icon

A generator script, not a hand-designed static asset, so the icon stays
reproducible and reviewable as code — consistent with how
`StatusBarWaveformRenderer.swift` already draws the animated menu-bar icon
programmatically with AppKit.

- `scripts/generate-app-icon.swift`: standalone script (`swift
  scripts/generate-app-icon.swift`) that renders a 1024×1024 PNG to
  `assets/icon-1024.png`:
  - Plain white rounded-square background (simple rounded rect, ~18% corner
    radius), with a hairline light-gray edge so it's visible against white
    Finder/DMG backgrounds.
  - One continuous smooth sine-wave stroke, centered, ~2.5 cycles, rounded
    caps, colored `#1A1A1A` to match the existing
    `Resources/Brand/autohand-logo-*.svg` brand mark.
- `assets/icon-1024.png` → `Resources/Brand/autohand-voice.icns` via the
  sips/iconutil pipeline already documented in `assets/README.md`. Both the
  PNG and the `.icns` are committed so the build never depends on
  regenerating them.
- `Resources/Info.plist` gains `CFBundleIconFile = autohand-voice`.
- `scripts/build-app.sh` copies `autohand-voice.icns` into
  `Contents/Resources/` during bundling.

Out of scope: DMG background artwork (`dmg-background.png` in
`assets/README.md`) — it's documented but never wired into
`build-installer.sh`, and isn't part of this change.

## Part 2 — Public unsigned DMG

`docs/releasing.md` is explicit that tagged `v*` releases must be notarized
and the workflow "never publishes an unsigned or unnotarized tagged
release." That contract stays untouched for whenever a Developer ID cert
exists.

Instead, a new, separate workflow:

- `.github/workflows/unsigned-release.yml`
- Triggers: `push` to `main`, plus manual `workflow_dispatch`. Never
  `pull_request` — release-publish permissions must not be reachable from a
  fork's PR.
- Steps mirror `build-macos.yml`: `swift test`, build release executables,
  `autohand-voice check --json`, `scripts/build-app.sh`,
  `scripts/build-installer.sh`, signature/arch verification.
- Publishes to one rolling GitHub Release: tag `unsigned-latest`, marked as
  a pre-release, overwritten on each push to `main` so there's a single
  stable link to hand out.
- Release body states plainly: ad-hoc signed, not notarized, Gatekeeper
  will warn on first launch — right-click the app → Open (or `xattr -dr
  com.apple.quarantine`) to run it.
- Uploads the `.dmg`, its `.sha256`, and `THIRD-PARTY-NOTICES.txt`.
- Needs `permissions: contents: write` (only on this workflow, not the
  existing PR-triggered `build-macos.yml`).

README gets a short pointer to the `unsigned-latest` release as a download
option alongside the existing build-from-source instructions.

## Testing

- `swift test` continues to pass.
- `scripts/build-app.sh` produces a bundle containing
  `Contents/Resources/autohand-voice.icns` and an `Info.plist` with
  `CFBundleIconFile` set.
- `scripts/build-installer.sh` still produces a valid ad-hoc-signed DMG and
  checksum.
- New workflow YAML is validated by inspection (no secrets required, no
  behavior change to existing `build-macos.yml` / `release-macos.yml`).
