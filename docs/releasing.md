# Releasing Autohand Voice

Autohand Voice has three macOS workflows:

- `Build macOS` runs tests and required native checks on an Apple Silicon
  runner, builds both release executables, creates an ad-hoc-signed `.app`,
  packages a drag-to-Applications DMG, and uploads the DMG, SHA-256 checksum,
  and complete notices as workflow artifacts. Requires no secrets, but the
  artifact is only downloadable from the Actions run by someone signed into
  GitHub.
- `Unsigned Release` runs on every push to `main` (and manually via
  `workflow_dispatch`). It builds the same ad-hoc-signed DMG as `Build macOS`
  and publishes it publicly to a single rolling GitHub Release tagged
  `unsigned-latest`, overwriting the previous one each time. This is the
  channel to link to for anyone downloading and installing the app directly,
  the way many indie macOS apps are distributed outside the App Store. The
  release notes always state plainly that it is ad-hoc signed and not
  notarized, and that Gatekeeper requires right-click → Open (or `xattr -dr
  com.apple.quarantine`) on first launch. It requires no secrets either.
- `Release macOS` runs for version tags, requires a Developer ID Application
  certificate, signs the app and DMG with hardened runtime, notarizes and
  staples the DMG, then creates the private GitHub release.

The release workflow intentionally fails when signing or notarization
credentials are absent. It never publishes an unsigned or unnotarized tagged
release. `Unsigned Release` is a deliberately separate, always-available
channel so an unsigned build never has to masquerade as a notarized one —
once a Developer ID certificate exists, tagged `v*` releases remain the
notarized, canonical distribution and `unsigned-latest` keeps serving
untagged `main` builds.

## Repository secrets

Configure these Actions secrets in `autohandai/voice`:

| Secret | Value |
|---|---|
| `APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64` | Base64-encoded Developer ID Application `.p12` |
| `APPLE_DEVELOPER_ID_APPLICATION_P12_PASSWORD` | Password protecting the `.p12` |
| `APPLE_KEYCHAIN_PASSWORD` | Ephemeral CI keychain password |
| `APPLE_ID` | Apple ID used by `notarytool` |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for that Apple ID |
| `APPLE_TEAM_ID` | Apple Developer team identifier |

The workflow imports the certificate into a temporary keychain and deletes
that keychain even when a prior step fails.

## Version contract

Before tagging, update both:

- `Brand.version` in
  `Sources/AutohandVoiceCore/Brand.swift`
- `CFBundleShortVersionString` in `Resources/Info.plist`

The tag must be `v<Brand.version>`, for example `v1.0.0`. The release workflow
rejects a tag that does not match `Brand.version`. The GitHub run number
becomes `CFBundleVersion`.

## Local release-equivalent checks

```bash
swift test
swift build -c release
./.build/release/autohand-voice check --json
./scripts/build-app.sh
./scripts/build-installer.sh
codesign --verify --deep --strict --verbose=2 "dist/Autohand Voice.app"
(cd dist && shasum -a 256 -c Autohand-Voice-1.0.0-arm64.dmg.sha256)
```

Local artifacts are ad-hoc signed and are not a substitute for the notarized
tagged release. The downloaded model, caches, recordings, certificates, and
credentials must never be committed or uploaded as build artifacts.
